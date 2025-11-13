---
applyTo: "infra/modules/container-app/**"
---

# GitLab Container App Instructions

## Image Configuration

- **Image**: `gitlab/gitlab-ee:latest` (official GitLab Enterprise Edition)
- **Source**: Imported into private ACR using `azapi_resource_action` (Container Registry `importImage`)
- **Reference**: `<acr_login_server>/gitlab/gitlab-ee:latest` (never pull directly from Docker Hub)
- **Import Action**: Use ARM `importImage` with `Force` mode for idempotency

## Port Configuration

GitLab listens on internal port **8080** (not 80).

ALL configurations MUST use port 8080:
- `target_port = 8080`
- All health probe ports: 8080

## Health Probes

Bootstrap mode configuration (high thresholds for 10-15 min initialization):

```hcl
startup_probe {
  path                = "/-/health"  # NOT /-/startup (causes 302 redirects)
  port                = 8080
  transport           = "HTTP"
  failure_count_threshold = 30
}

readiness_probe {
  path                = "/-/readiness"
  port                = 8080
  transport           = "HTTP"
  failure_count_threshold = 30
}

liveness_probe {
  path                = "/-/liveness"
  port                = 8080
  transport           = "HTTP"
  failure_count_threshold = 30
}
```

## Omnibus Configuration

Critical settings (must remain as configured):

```ruby
external_url 'https://${gitlab_hostname}'

# REQUIRED: Let's Encrypt disabled (use platform-managed certs)
letsencrypt['enable'] = false
letsencrypt['auto_renew'] = false

# REQUIRED: No HTTPS redirect (allows HTTP health probes to return 200)
nginx['redirect_http_to_https'] = false

# GitLab Shell SSH port
gitlab_rails['gitlab_shell_ssh_port'] = 2222
```

**CRITICAL**:
- `nginx['redirect_http_to_https'] = false` is REQUIRED for Azure Container Apps HTTP health probes
- Do NOT enable unless Azure supports HTTPS probe endpoints
- Do NOT add custom nginx server blocks for redirects without accounting for probes

## Certificate Management

- **Let's Encrypt**: Disabled inside container
- **Platform Domains**: Use managed certificate automatically provided
- **Custom Domains**: Bind managed/bring-your-own cert at Container App layer (not Omnibus ACME)
- ACME HTTP-01 validation will fail through platform ingress

## Storage Mounts

Three primary mount paths:

1. `/etc/gitlab` - Configuration
2. `/var/opt/gitlab` - Data/repositories
3. `/var/log/gitlab` - Logs

All use NFS Azure Files with:
- `storage_type = "NfsAzureFile"`
- Premium FileStorage tier
- Private endpoint access only

## Common Issues and Solutions

### ActivationFailed with 301/302 or 502 Probe Logs

**Cause**: Wrong probe path (`/-/startup`), HTTPS redirect enabled, or probes hitting port 80

**Fix**:
- Use `/-/health` for startup probe
- Ensure `nginx['redirect_http_to_https'] = false`
- Verify all probes use port 8080

### Persistent 503 Externally (Probes Pass)

**Cause**: Application still converging internal services (Sidekiq, migrations)

**Fix**:
- Allow bootstrap window (10-15 min)
- Verify readiness internally: `curl http://localhost:8080/-/readiness` via `az containerapp exec`
- Check Sidekiq/Puma logs

### ACME/Let's Encrypt Errors

**Cause**: Built-in LE enabled on platform domain

**Fix**: Keep LE disabled; use platform/custom domain cert

### Slow Initialization

**Expected**: 10-15 min on first start for background migrations, asset compilation

**Fix**: Bootstrap probe thresholds intentionally high (failure_count_threshold = 30)

## Resource Sizing

Single replica only (GitLab EE design limitation):
- CPU: 4.0 cores
- Memory: 8Gi
- Replicas: 1

## Ingress Configuration

- External ingress enabled
- HTTPS exposed externally
- Internal health probes remain HTTP on port 8080
- Platform handles TLS termination

## Configuration Reference

Official GitLab Docker assets: https://gitlab.com/gitlab-org/omnibus-gitlab/-/tree/master/docker/assets

## Probe Troubleshooting Quick Reference

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| Startup probe 301/302 to `/users/sign_in` | Using `/-/startup` path | Change to `/-/health` |
| Readiness 502 | App not ready or wrong port (80) | Ensure port 8080 + wait for init |
| All probes fail after enabling HTTPS redirect | `nginx['redirect_http_to_https'] = true` | Set to `false` |
| ACME errors in logs | Built-in LE enabled | Keep LE disabled |
| External 503 while probes OK | Internal services warming up | Allow bootstrap; check logs |
