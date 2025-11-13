locals {
  # Probe profile selection locals (bootstrap vs steady-state)
  # NOTE: Provider limits failure_count_threshold to 1-30. We maximize window by combining a higher interval with max threshold (30) in bootstrap mode.
  # Effective grace periods (approx):
  #   Startup: 30 (fail thresh) * 30s interval = ~15 min before restart
  #   Readiness: 30 * 15s = ~7.5 min continuous failures (traffic withheld only)
  # Adjust after initial converge by disabling bootstrap mode (var.use_bootstrap_probes = false).
  # Extend startup grace: GitLab Omnibus can exceed 10 minutes on first boot
  startup_initial_delay       = 30
  startup_interval_seconds    = var.use_bootstrap_probes ? 45 : 15
  startup_failure_threshold   = var.use_bootstrap_probes ? 30 : 12

  # Delay liveness to avoid premature restarts while Puma/Workhorse settle
  liveness_initial_delay      = 60  # Max allowed by Azure
  liveness_interval_seconds   = 45
  liveness_failure_threshold  = var.use_bootstrap_probes ? 20 : 5

  # Allow readiness to wait for DB migrations & asset compilation
  readiness_initial_delay     = var.use_bootstrap_probes ? 60 : 20
  readiness_interval_seconds  = var.use_bootstrap_probes ? 30 : 15
  readiness_failure_threshold = var.use_bootstrap_probes ? 30 : 8
}

resource "azurerm_container_app" "main" {
  name                         = var.name
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.environment_id
  revision_mode                = "Single"
  workload_profile_name        = var.workload_profile_name
  tags                         = var.tags
  # Ensure environment storage (NFS) exists before creating the app
  depends_on = [azurerm_container_app_environment_storage.shares]

  identity {
    type         = "UserAssigned"
    identity_ids = var.identity_ids
  }

  registry {
    server   = var.registry_server
    identity = var.registry_identity_id
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    # Probe profile applied using top-level locals

    container {
      name   = "gitlab"
      image  = var.image
      cpu    = var.cpu
      memory = var.memory

      env {
        name = "GITLAB_OMNIBUS_CONFIG"
        # Load config from external template for readability & reuse
        value = templatefile("${path.module}/gitlab-omnibus-config.tpl", {
          gitlab_hostname     = var.gitlab_hostname
          postgresql_host     = var.postgresql_host
          postgresql_database = var.postgresql_database
        })
      }

      env {
        name        = "GITLAB_ROOT_PASSWORD"
        secret_name = "gitlab-root-password"
      }

      env {
        name        = "GITLAB_DB_USERNAME"
        secret_name = "postgresql-admin-username"
      }

      env {
        name        = "GITLAB_DB_PASSWORD"
        secret_name = "postgresql-admin-password"
      }

      env {
        name        = "GITLAB_SHARED_RUNNERS_REGISTRATION_TOKEN"
        secret_name = "gitlab-runner-token"
      }

      dynamic "volume_mounts" {
        for_each = var.file_shares
        content {
          name = volume_mounts.value.name
          path = volume_mounts.value.path
        }
      }

      # Startup probe (gates liveness & readiness during long first converge)
      startup_probe {
        transport               = "HTTP"
        path                    = "/-/health"
        port                    = var.target_port
        initial_delay           = local.startup_initial_delay
        interval_seconds        = local.startup_interval_seconds
        timeout                 = 5
        failure_count_threshold = local.startup_failure_threshold
      }

      # Liveness probe (avoid restarts during bootstrap; tighter later)
      liveness_probe {
        transport               = "HTTP"
        path                    = "/-/liveness"
        port                    = var.target_port
        initial_delay           = local.liveness_initial_delay
        interval_seconds        = local.liveness_interval_seconds
        timeout                 = 5
        failure_count_threshold = local.liveness_failure_threshold
      }

      # Readiness probe (traffic gating)
      readiness_probe {
        transport               = "HTTP"
        path                    = "/-/readiness"
        port                    = var.target_port
        initial_delay           = local.readiness_initial_delay
        interval_seconds        = local.readiness_interval_seconds
        timeout                 = 5
        failure_count_threshold = local.readiness_failure_threshold
      }
    }

    dynamic "volume" {
      for_each = var.file_shares
      content {
        name         = volume.value.name
        storage_type = "NfsAzureFile"
        storage_name = volume.value.name
      }
    }
  }

  secret {
    name                = "gitlab-root-password"
    key_vault_secret_id = var.key_vault_secret_id_password
    identity            = var.identity_ids[0]
  }

  secret {
    name                = "gitlab-runner-token"
    key_vault_secret_id = var.key_vault_secret_id_token
    identity            = var.identity_ids[0]
  }

  secret {
    name                = "postgresql-admin-password"
    key_vault_secret_id = var.key_vault_secret_id_db_password
    identity            = var.identity_ids[0]
  }

  secret {
    name                = "postgresql-admin-username"
    key_vault_secret_id = var.key_vault_secret_id_db_username
    identity            = var.identity_ids[0]
  }

  ingress {
    external_enabled = var.external_enabled
    target_port      = var.target_port
    transport        = "http"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}

# Container App Environment Storage resources for each Azure Files share
# For NFS: only nfs_server_url, share_name, and access_mode are required
# Do NOT provide account_name (conflicts with nfs_server_url)
# NFS share_name format: /<storageAccountName>/<fileShareName>
resource "azurerm_container_app_environment_storage" "shares" {
  for_each = { for share in var.file_shares : share.name => share }

  name                         = each.value.name
  container_app_environment_id = var.environment_id
  share_name                   = "/${var.storage_account_name}/${each.value.name}"
  access_mode                  = "ReadWrite"
  nfs_server_url               = "${var.storage_account_name}.file.core.windows.net"
}

# Diagnostic Settings for Container App
# Note: Container Apps only support metrics; logs are sent to Log Analytics via the environment
resource "azurerm_monitor_diagnostic_setting" "containerapp" {
  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_container_app.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
