resource "azurerm_container_app" "main" {
  name                         = var.name
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.environment_id
  revision_mode                = "Single"
  tags                         = var.tags

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
          git_data_dirs({ "default" => { "path" => "/var/opt/gitlab/git-data" } })

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
    }

    dynamic "volume" {
      for_each = var.file_shares
      content {
        name         = volume.value.name
        storage_type = "AzureFile"
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
resource "azurerm_container_app_environment_storage" "shares" {
  for_each = { for share in var.file_shares : share.name => share }

  name                         = each.value.name
  container_app_environment_id = var.environment_id
  account_name                 = var.storage_account_name
  share_name                   = each.value.name
  access_mode                  = "ReadWrite"
  access_key                   = var.storage_account_key
}
