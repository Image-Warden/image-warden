FROM docker.io/library/debian:bookworm-slim

ARG TRIVY_MAJOR=0
ARG GRYPE_MAJOR=0
ARG GRYPE_VERSION=0.96.0
ARG IMAGE_WARDEN_UID=10001
ARG IMAGE_WARDEN_GID=10001

# XDG_DATA_HOME is intentionally omitted. The scripts should use the
# image-warden user's normal ~/.local/share/image-warden install path.
ENV XDG_CONFIG_HOME=/config \
    XDG_STATE_HOME=/state \
    XDG_CACHE_HOME=/cache \
    TRIVY_CACHE_DIR=/cache/trivy \
    GRYPE_DB_CACHE_DIR=/cache/grype/db

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        tar \
        gnupg \
        jq \
        skopeo \
        util-linux \
    && install -d -m 0755 /etc/apt/keyrings \
    && curl -fsSL https://aquasecurity.github.io/trivy-repo/deb/public.key -o /tmp/trivy.key \
    && gpg --dearmor -o /etc/apt/keyrings/trivy.gpg /tmp/trivy.key \
    && rm -f /tmp/trivy.key \
    && echo "deb [signed-by=/etc/apt/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" \
        > /etc/apt/sources.list.d/trivy.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends trivy \
    && dpkg_arch="$(dpkg --print-architecture)" \
    && case "${dpkg_arch}" in \
        amd64) grype_arch="linux_amd64" ;; \
        arm64) grype_arch="linux_arm64" ;; \
        *) echo "Unsupported architecture for Grype: ${dpkg_arch}" >&2; exit 1 ;; \
    esac \
    && curl -fsSL \
        "https://github.com/anchore/grype/releases/download/v${GRYPE_VERSION}/grype_${GRYPE_VERSION}_${grype_arch}.tar.gz" \
        -o /tmp/grype.tar.gz \
    && tar -xzf /tmp/grype.tar.gz -C /usr/local/bin grype \
    && rm -f /tmp/grype.tar.gz \
    && trivy --version | awk -v major="${TRIVY_MAJOR}" 'NR == 1 { split($2, v, "."); if (v[1] != major) exit 1 }' \
    && grype version -o json | jq -e --arg major "${GRYPE_MAJOR}" '.version | split(".")[0] == $major' >/dev/null \
    && groupadd --gid "${IMAGE_WARDEN_GID}" image-warden \
    && useradd \
        --uid "${IMAGE_WARDEN_UID}" \
        --gid "${IMAGE_WARDEN_GID}" \
        --create-home \
        --home-dir /home/image-warden \
        --shell /usr/sbin/nologin \
        image-warden \
    && install -d -o image-warden -g image-warden \
        /config/image-warden \
        /state/image-warden \
        /cache \
        /home/image-warden/.local/share/image-warden/bin \
        /home/image-warden/.local/share/image-warden/lib \
    && rm -rf /var/lib/apt/lists/*

COPY --chown=image-warden:image-warden bin/ /home/image-warden/.local/share/image-warden/bin/
COPY --chown=image-warden:image-warden lib/ /home/image-warden/.local/share/image-warden/lib/
COPY --chown=image-warden:image-warden config/image-warden.conf.example /config/image-warden/image-warden.conf.example
COPY --chown=image-warden:image-warden config/secrets.example /config/image-warden/secrets.example

RUN chmod 0755 /home/image-warden/.local/share/image-warden/bin/iw-* \
    && for script in /home/image-warden/.local/share/image-warden/bin/iw-*; do \
        ln -s "${script}" "/usr/local/bin/$(basename "${script}")"; \
    done

USER image-warden:image-warden
WORKDIR /home/image-warden

VOLUME ["/config", "/state", "/cache"]

CMD ["iw-stage", "--help"]
