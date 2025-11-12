resource "azurerm_container_app" "main" {
  name                         = var.name
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.environment_id
  revision_mode                = "Single"
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

    container {
      name   = "gitlab"
      image  = var.image
      cpu    = var.cpu
      memory = var.memory

      env {
        name  = "GITLAB_OMNIBUS_CONFIG"
        value = <<-EOT
          external_url 'https://${var.gitlab_hostname}'
          gitlab_rails['gitlab_shell_ssh_port'] = 2222

          # NFS storage configuration
          gitlab_rails['shared_path'] = '/var/opt/gitlab/gitlab-rails/shared'
          gitaly['storage'] = [
            { 'name' => 'default', 'path' => '/var/opt/gitlab/git-data' }
          ]

          # External PostgreSQL database
          postgresql['enable'] = false
          gitlab_rails['db_adapter'] = 'postgresql'
          gitlab_rails['db_encoding'] = 'unicode'
          gitlab_rails['db_host'] = '${var.postgresql_host}'
          gitlab_rails['db_database'] = '${var.postgresql_database}'
          gitlab_rails['db_username'] = ENV['GITLAB_DB_USERNAME']
          gitlab_rails['db_password'] = ENV['GITLAB_DB_PASSWORD']
          gitlab_rails['db_sslmode'] = 'require'

          # Disable services not needed in containerized environment
          prometheus_monitoring['enable'] = false

          # Container-optimized settings
          puma['worker_processes'] = 2
          sidekiq['max_concurrency'] = 10
        EOT
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

      # Startup probe: GitLab can take 10+ minutes on first boot
      # 30 failures × 30 seconds = 15 minutes max startup time
      startup_probe {
        transport               = "HTTP"
        path                    = "/-/readiness"
        port                    = var.target_port
        initial_delay           = 10
        interval_seconds        = 30
        timeout                 = 5
        failure_count_threshold = 30
      }

      # Liveness probe: Check if GitLab is still running
      # Less aggressive than startup - only restart if truly dead
      liveness_probe {
        transport               = "HTTP"
        path                    = "/-/liveness"
        port                    = var.target_port
        initial_delay           = 0
        interval_seconds        = 30
        timeout                 = 5
        failure_count_threshold = 3
      }

      # Readiness probe: Check if GitLab can accept traffic
      # Used for load balancing decisions
      readiness_probe {
        transport               = "HTTP"
        path                    = "/-/readiness"
        port                    = var.target_port
        initial_delay           = 5
        interval_seconds        = 10
        timeout                 = 5
        failure_count_threshold = 3
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
