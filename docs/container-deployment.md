# Container Deployment

Image-Warden can run as an on-demand job container while the registry remains a separate long-running service. This keeps scheduling, registry lifecycle, and release policy explicit.

The container deployment supports Docker, Podman Compose, and Podman Quadlet examples. It does not replace the native host install path.

## Layout

One practical host layout:

```text
/opt/image-warden/
  compose.yaml
  config/
    image-warden.conf
    secrets
  registry/
    config.yml
  data/
    registry/
    state/
    cache/
```

The Image-Warden container uses:

```text
/config/image-warden   config and secrets
/state/image-warden    digests, candidate queue, events.log, lock
/cache                 scanner reports and scanner databases
```

The same state mount must be shared by all Image-Warden job containers. The global `flock` lock is stored in the mounted state directory, so parallel jobs using the same state mount contend correctly. Jobs using different state mounts do not protect each other.

## Build

From the repository root:

```bash
docker build -t localhost/image-warden:local .
```

Podman:

```bash
podman build -t localhost/image-warden:local .
```

The image is Debian-based and includes `skopeo`, `jq`, `curl`, `flock`, Trivy, and Grype. Scanner major versions are checked at build time. Grype is downloaded from a pinned release tarball, controlled by the `GRYPE_VERSION` build argument.

## Compose

Copy the example and edit paths:

```bash
cp deploy/compose.yaml.example /opt/image-warden/compose.yaml
mkdir -p /opt/image-warden/registry
cp deploy/registry/config.yml /opt/image-warden/registry/config.yml
```

If the compose file is no longer inside the repository `deploy/` directory, set the build context to the directory containing the Dockerfile:

```bash
export IMAGE_WARDEN_BUILD_CONTEXT=/path/to/image-warden
```

Use this registry address in the config when Image-Warden runs inside the compose network:

```bash
LOCAL_REGISTRY="registry:5000"
LOCAL_REGISTRY_TLS_VERIFY=false
REGISTRY_CONTAINER_NAME="staging-registry"
CONTAINER_RUNTIME="docker"
```

For Podman Compose, change `CONTAINER_RUNTIME="docker"` to `CONTAINER_RUNTIME="podman"`.

The compose example expects this host layout beside the compose file:

```text
config/image-warden.conf
config/secrets
registry/config.yml
data/registry/
data/state/
data/cache/
```

Start the registry:

```bash
docker compose -f /opt/image-warden/compose.yaml up -d registry
```

Run jobs on demand:

```bash
docker compose -f /opt/image-warden/compose.yaml run --rm image-warden iw-stage
docker compose -f /opt/image-warden/compose.yaml run --rm image-warden iw-release
docker compose -f /opt/image-warden/compose.yaml run --rm image-warden iw-cleanup
docker compose -f /opt/image-warden/compose.yaml run --rm image-warden iw-history --image nginx
```

Podman Compose uses the same file:

```bash
podman compose -f /opt/image-warden/compose.yaml up -d registry
podman compose -f /opt/image-warden/compose.yaml run --rm image-warden iw-stage
```

Scheduling is kept outside of the container on purpose. Use host cron or systemd timers that call `docker compose run --rm ...` or `podman compose run --rm ...`.

If `IMAGE_RELEASE_HOOK` is configured, the path must exist inside the Image-Warden container. Mount the hook script into the container and point the config at that container path. The hook runs once per promoted image. Hook failures are recorded in `events.log` but do not undo the already-promoted registry tag.

## Podman Quadlet

Podman users can use the examples in `deploy/podman/` instead of Compose.

Build the image:

```bash
podman build -t localhost/image-warden:local .
```

Copy and edit the job files:

```bash
mkdir -p ~/.config/containers/systemd
cp deploy/podman/image-warden-*.container ~/.config/containers/systemd/
cp deploy/podman/image-warden-*.timer ~/.config/containers/systemd/
```

Then reload and enable timers:

```bash
systemctl --user daemon-reload
systemctl --user enable --now image-warden-stage.timer
systemctl --user enable --now image-warden-release.timer
systemctl --user enable --now image-warden-cleanup.timer
```

The existing `systemd/staging-registry.container` remains the registry Quadlet example. Use the same registry name in `LOCAL_REGISTRY` that the Image-Warden job containers can reach.

The job examples use `Network=host` for the simple localhost registry case. If you use a dedicated Podman network, replace that with the shared network used by the registry container.

## Registry Naming

Registry names are namespace-sensitive.

Inside Compose, `registry:5000` usually resolves to the registry service. On the host, consumers often pull from `127.0.0.1:5000`. These are not the same reference.

Image-Warden promotes whatever `LOCAL_REGISTRY` names. Make sure consumers can pull that same reference, or publish/retag accordingly.

For rootless Podman, `localhost:5000` inside a container is the container's own network namespace. Use a Podman network alias, `host.containers.internal`, or host networking when appropriate.

## Scanner Cache

Trivy and Grype download vulnerability databases. If `/cache` is not persistent, every `--rm` job container may download fresh databases.

The example sets:

```bash
XDG_CACHE_HOME=/cache
TRIVY_CACHE_DIR=/cache/trivy
GRYPE_DB_CACHE_DIR=/cache/grype/db
```

Mount `/cache` read-write and include it in backup/restore decisions if you want fast warm starts. It does not need the same retention guarantees as state or registry data.

## Cleanup And Registry GC

`iw-cleanup` deletes old timestamp tags through the registry HTTP API and then runs registry garbage collection with:

```bash
${CONTAINER_RUNTIME} exec ${REGISTRY_CONTAINER_NAME} /bin/registry garbage-collect /etc/distribution/config.yml --delete-untagged=false
```

Inside an Image-Warden job container, GC only works if the selected container runtime client and socket are available. The first container deployment path does not hide that requirement.

Compose may prefix container names unless `container_name` is set. The example sets:

```yaml
container_name: staging-registry
```

so this config works:

```bash
REGISTRY_CONTAINER_NAME="staging-registry"
```

For registry v3, the config path is `/etc/distribution/config.yml`. Older
registry v2 examples often used `/etc/docker/registry/config.yml`.

## Event Log Rotation

`events.log` lives in the mounted state directory. `iw-history` reads one JSONL file into memory, so rotate long-running logs.

Example:

```conf
/opt/image-warden/data/state/events.log {
    monthly
    rotate 24
    compress
    missingok
    notifempty
    copytruncate
}
```

Compressed rotated logs are not searched automatically. Decompress older logs or pass an uncompressed file with:

```bash
iw-history --event-log /path/to/events.log.1
```

## Backups

Back up:

- registry data
- Image-Warden config and secrets
- Image-Warden state, especially candidates and `events.log`

Cache is optional. It only affects scanner DB warm-up and retained reports.

## Smoke Checks

After building:

```bash
docker run --rm localhost/image-warden:local iw-stage --help
docker run --rm localhost/image-warden:local iw-config --help
docker run --rm localhost/image-warden:local iw-history --help
```

Podman:

```bash
podman run --rm localhost/image-warden:local iw-stage --help
podman run --rm localhost/image-warden:local iw-config --help
podman run --rm localhost/image-warden:local iw-history --help
```

These smoke tests only check that the packaged scripts start and can read their help output. Use the same pattern for other commands, for example `iw-stage`, `iw-release`, `iw-cleanup`, `iw-scan`, and `iw-history`.
