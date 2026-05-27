# Manual Rollback

Image-Warden does not perform automatic rollback.

Rollback policy is operationally risky: a previous candidate may have been
blocked by a scanner, force-released, cleaned up, or superseded by another
candidate. Instead, use `iw-history` to inspect what happened and then promote a
specific tag manually after review.

## Find Recent Releases

Show the release history for one image:

```bash
iw-history --image nginx --event released
```

Show scanner blocks and forced releases around the same image:

```bash
iw-history --image nginx --event scan_blocked
iw-history --image nginx --event scanner_gate_ignored
iw-history --image nginx --event force_release_requested
```

Show skipped candidates:

```bash
iw-history --image nginx --event candidate_removed
```

Candidate removals include a `reason` field in JSON output. For example,
`already_released` means Image-Warden found that the configured production tag
already points at the candidate digest and removed the candidate from the queue.
`missing_from_registry` means the staged tag no longer existed in the local
registry when release checked it.

Filter for one removal reason:

```bash
iw-history --image nginx --event candidate_removed --json \
  | jq 'select(.reason == "already_released")'
```

Filter by command source or broad category:

```bash
iw-history --source iw-release
iw-history --category scan
iw-history --image nginx --source iw-release --category release
```

Raw JSON output is useful for scripts or deeper inspection:

```bash
iw-history --image nginx --json
```

Human-readable `iw-history` output uses local time by default. Use `--utc` if
you want the text timeline to match the UTC timestamps stored in `events.log`.

`iw-history` reads one JSONL event log file into memory. If your installation
rotates `events.log`, inspect an older uncompressed log explicitly:

```bash
iw-history --event-log ~/.local/state/image-warden/events.log.1 --image nginx
```

Compressed rotated logs are not read automatically. Decompress them first or
copy the relevant JSONL lines into a temporary file.

## Promote An Older Local Tag

After selecting a previous tag from history, copy it over the configured
production tag.

For the default local registry over HTTP:

```bash
skopeo copy \
  --src-tls-verify=false \
  --dest-tls-verify=false \
  docker://127.0.0.1:5000/nginx:latest_20260517-1935_501b8add \
  docker://127.0.0.1:5000/nginx:production
```

If the image uses a custom production tag, replace `production` with that tag:

```bash
skopeo copy \
  --src-tls-verify=false \
  --dest-tls-verify=false \
  docker://127.0.0.1:5000/nginx:stable_20260517-1935_501b8add \
  docker://127.0.0.1:5000/nginx:stable
```

For TLS-enabled registries, use `--src-tls-verify=true` and
`--dest-tls-verify=true`.

## Restart The Workload

Image-Warden only changes tags in the registry. Your runtime still has to pull
and restart the workload.

Docker Compose:

```bash
docker compose pull nginx
docker compose up -d nginx
```

Podman Compose:

```bash
podman compose pull nginx
podman compose up -d nginx
```

Single Docker container:

```bash
docker pull 127.0.0.1:5000/nginx:production
docker stop nginx
docker rm nginx
# Recreate with your normal docker run command.
```

Single Podman container:

```bash
podman pull 127.0.0.1:5000/nginx:production
podman restart nginx
```

## Caveats

- `iw-cleanup` may have already deleted older staging tags depending on
  `KEEP_IMAGES`.
- A previous tag may have been force-released with `--ignore-scanner`.
- A previous tag may have been blocked by Trivy or Grype.
- If `production_tag` is configured per image, rollback must copy to that tag,
  not necessarily `production`.
- If the image is multi-arch, make sure the tag you promote is the platform you
  actually run.
