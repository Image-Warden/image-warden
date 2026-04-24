# image-warden
Quarantine pipeline for container auto-updates. Stages new images from upstream repositories into a local one, holds them for a configurable cooling-off period, scans for vulnerabilities, and promotes to production only after the quarantine expires and security scans come back clean.
