external_url 'https://${gitlab_hostname}'
gitlab_rails['gitlab_shell_ssh_port'] = 2222

# Disable integrated Let's Encrypt / ACME (using platform certs or external management)
letsencrypt['enable'] = false
letsencrypt['auto_renew'] = false

# Disable HTTPS redirect for health probe endpoints (Container Apps probes use HTTP)
nginx['redirect_http_to_https'] = false

# NFS storage configuration
gitlab_rails['shared_path'] = '/var/opt/gitlab/gitlab-rails/shared'
gitaly['storage'] = [
  { 'name' => 'default', 'path' => '/var/opt/gitlab/git-data' }
]

# External PostgreSQL database
postgresql['enable'] = false
gitlab_rails['db_adapter'] = 'postgresql'
gitlab_rails['db_encoding'] = 'unicode'
gitlab_rails['db_host'] = '${postgresql_host}'
gitlab_rails['db_database'] = '${postgresql_database}'
gitlab_rails['db_username'] = ENV['GITLAB_DB_USERNAME']
gitlab_rails['db_password'] = ENV['GITLAB_DB_PASSWORD']
gitlab_rails['db_sslmode'] = 'require'

# Disable services not needed in containerized environment
prometheus_monitoring['enable'] = false

# Container-optimized settings
puma['worker_processes'] = 2
sidekiq['max_concurrency'] = 10
