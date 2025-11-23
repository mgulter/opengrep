###############################################################################
# Lightweight Dockerfile for Opengrep
# Downloads pre-built standalone binary from GitHub Releases
###############################################################################

FROM python:3.11-alpine

WORKDIR /app

# Install runtime dependencies
RUN apk upgrade --no-cache && \
    apk add --no-cache \
        git \
        git-lfs \
        openssh \
        bash \
        jq \
        curl

# Download and install pre-built opengrep binary from GitHub Releases
# The binary is standalone and includes both core engine and CLI
ARG VERSION=latest
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ] || [ "$ARCH" = "amd64" ]; then \
        DIST="opengrep_musllinux_x86"; \
    elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then \
        DIST="opengrep_musllinux_aarch64"; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    if [ "$VERSION" = "latest" ]; then \
        VERSION=$(curl -s https://api.github.com/repos/opengrep/opengrep/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'); \
    fi && \
    echo "Downloading Opengrep ${VERSION} for ${DIST}..." && \
    curl --fail --location --progress-bar \
        "https://github.com/opengrep/opengrep/releases/download/${VERSION}/${DIST}" \
        -o /usr/local/bin/opengrep && \
    chmod +x /usr/local/bin/opengrep && \
    /usr/local/bin/opengrep --version

# Create symlinks for different command names
RUN ln -s opengrep /usr/local/bin/semgrep && \
    ln -s opengrep /usr/local/bin/semgrep-core && \
    ln -s opengrep /usr/local/bin/osemgrep

# Set environment variables
ENV SEMGREP_IN_DOCKER=1 \
    SEMGREP_USER_AGENT_APPEND="Docker"

# Create non-root user
RUN adduser -D -u 1000 -h /home/semgrep semgrep && \
    mkdir -p /src && \
    chown semgrep:semgrep /src

# Configure git safe directory
RUN printf "[safe]\\n\\tdirectory = /src" > /root/.gitconfig && \
    printf "[safe]\\n\\tdirectory = /src" > /home/semgrep/.gitconfig && \
    chown semgrep:semgrep /home/semgrep/.gitconfig

WORKDIR /src

# Default command
CMD ["opengrep", "--help"]

# Metadata
LABEL maintainer="opengrep" \
      description="Opengrep - Fast static analysis tool" \
      version="latest"
