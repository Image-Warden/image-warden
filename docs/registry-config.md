# Registry configuration

## Minimal config.yml

Create this file at for example
`~/.local/share/image-warden/registry/config.yml`. Reference it in the `staging-registry.container` volume mount or `staging-registry.compose.yml`.

```yaml
version: 0.1

storage:
  filesystem:
    rootdirectory: /var/lib/registry
  delete:
    enabled: true          # required for iw-cleanup garbage collection

http:
  addr: :5000

log:
  level: warn
  formatter: text
```

> **`storage.delete.enabled: true` is required.**  
> Without it, the registry rejects manifest DELETE requests and `iw-cleanup` cannot remove redundant tags or run garbage collection.

## Insecure registry (plain HTTP)

When `LOCAL_REGISTRY_TLS_VERIFY=false` (the default), the registry runs over plain HTTP. Clients need to be told to allow this:

for **Podman / skopeo**  
Add to `/etc/containers/registries.conf` or
`~/.config/containers/registries.conf`:

```toml
[[registry]]
location = "localhost:5000"
insecure = true
```

for **Docker**  
Add to `/etc/docker/daemon.json`:

```json
{
  "insecure-registries": ["localhost:5000"]
}
```

For a LAN registry (e.g. `192.168.1.10:5000`), replace `localhost:5000` with the actual address.