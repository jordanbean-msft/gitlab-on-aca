# CRITICAL: Use HTTP for Container Apps (platform handles TLS termination)
# external_url must be HTTP, not HTTPS, or nginx will expect HTTPS traffic
external_url 'http://${gitlab_hostname}'
gitlab_rails['gitlab_shell_ssh_port'] = 2222

# Disable integrated Let's Encrypt / ACME (using platform certs or external management)
letsencrypt['enable'] = false
letsencrypt['auto_renew'] = false

# Disable HTTPS redirect (Container Apps handles TLS termination at ingress)
nginx['redirect_http_to_https'] = false

# CRITICAL: Configure nginx to listen on all interfaces (0.0.0.0) for Container Apps probes
# Explicitly configure HTTP (not HTTPS) on port 8080
nginx['listen_addresses'] = ['0.0.0.0']
nginx['listen_port'] = 8080
nginx['listen_https'] = false

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
logrotate['enable'] = false

# Container-optimized settings
puma['worker_processes'] = 2
sidekiq['max_concurrency'] = 10

# CRITICAL: Bind Puma to TCP on 0.0.0.0:8080 (not Unix socket or loopback)
# Omnibus uses puma['socket'] and puma['bind'] separately - must disable socket explicitly
puma['enable'] = true
# CRITICAL: Set empty string for socket to disable Unix socket completely
# Setting nil doesn't work - Omnibus treats it as "use default"
puma['socket'] = ''
# CRITICAL: Set empty string for listen to disable loopback binding
puma['listen'] = ''
# Set our TCP binding on all interfaces
puma['bind'] = 'tcp://0.0.0.0:8080'
# Enable debug logging
puma['log_level'] = 'debug'
puma['per_worker_max_memory_mb'] = 2048
# Configure workhorse to use HTTP backend instead of Unix socket (NFS volume cannot host sockets)
gitlab_workhorse['auth_socket'] = nil
gitlab_workhorse['auth_backend'] = 'http://127.0.0.1:8080'
# CRITICAL: Must use 'network' and 'listen_addr' separately for TCP binding
gitlab_workhorse['listen_network'] = 'tcp'
gitlab_workhorse['listen_addr'] = '0.0.0.0:8181'
gitlab_workhorse['log_format'] = 'json'
gitlab_workhorse['log_level'] = 'debug'

# Redis configuration - use TCP instead of Unix sockets (NFS doesn't support sockets)
redis['enable'] = true
redis['bind'] = '127.0.0.1'
redis['port'] = 6379
gitlab_rails['redis_socket'] = nil
gitlab_rails['redis_host'] = '127.0.0.1'
gitlab_rails['redis_port'] = 6379
