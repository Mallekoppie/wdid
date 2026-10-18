# wdid development container image.
#
# Mirrors the ChaosGenerator dev container: the Microsoft Go devcontainer image
# (Debian bookworm) already provides Go, git and a non-root `vscode` user. On
# top of that we add:
#   * protoc + the Go and Dart protobuf plugins
#   * the Dart/Flutter SDK (for the web UI)
#   * make, openssl, jq and friends used by the Makefile
#   * the podman client plus a `docker` shim so builds use the HOST engine
#
# The host's Podman socket is mounted at runtime (see devcontainer.json); this
# image only ships the clients, it does not run a nested container engine.

ARG GO_VERSION=1.27
FROM mcr.microsoft.com/devcontainers/go:dev-${GO_VERSION}

ARG FLUTTER_CHANNEL=stable
ARG PROTOC_VERSION=27.3

USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# --- Base tooling ------------------------------------------------------------
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get install -y --no-install-recommends \
        make \
        openssl \
        jq \
        curl \
        ca-certificates \
        unzip \
        zip \
        xz-utils \
        git \
        procps \
        netcat-openbsd \
        socat \
        gnupg \
        podman \
        libglu1-mesa \
        libgtk-3-0 \
        libnss3 \
        libasound2 \
    && rm -rf /var/lib/apt/lists/*

# A `docker` shim so tools that invoke `docker` (image builds, scripts)
# transparently use the mounted host Podman socket. DOCKER_HOST is provided via
# devcontainer.json containerEnv, so the shim simply forwards to podman.
RUN printf '%s\n' \
        '#!/bin/sh' \
        'exec podman "$@"' \
        > /usr/local/bin/docker \
    && chmod 0755 /usr/local/bin/docker

# --- protoc ------------------------------------------------------------------
ARG TARGETARCH
RUN ARCH="${TARGETARCH:-amd64}" \
    && case "${ARCH}" in \
         amd64) PARCH=x86_64 ;; \
         arm64) PARCH=aarch_64 ;; \
         *) echo "unsupported arch ${ARCH}" && exit 1 ;; \
       esac \
    && curl -fsSL -o /tmp/protoc.zip \
        "https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/protoc-${PROTOC_VERSION}-linux-${PARCH}.zip" \
    && unzip -q /tmp/protoc.zip -d /usr/local \
    && rm /tmp/protoc.zip \
    && chmod +x /usr/local/bin/protoc \
    && protoc --version

# --- Dart + Flutter SDK ------------------------------------------------------
# Cloned at a pinned channel, then run once as the vscode user to warm the cache.
RUN git clone --depth 1 -b "${FLUTTER_CHANNEL}" https://github.com/flutter/flutter.git /opt/flutter \
    && chown -R vscode:vscode /opt/flutter \
    && git config --global --add safe.directory /opt/flutter

# --- Go protobuf / Connect plugins -------------------------------------------
# The base image sets GOPATH=/go, so `go install` places these in /go/bin,
# which is already on PATH for both interactive and login shells.
USER vscode
ENV PUB_CACHE="/home/vscode/.pub-cache"
ENV PATH="/go/bin:/home/vscode/.pub-cache/bin:/opt/flutter/bin:${PATH}"
RUN go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.36.12 \
    && go install connectrpc.com/connect/cmd/protoc-gen-connect-go@v1.21.1

# --- Dart protoc plugin + Flutter bootstrap ----------------------------------
# `flutter --version` triggers first-run downloads; give it a warm cache so the
# first build inside the container is not painfully slow.
RUN flutter --version \
    && flutter config --no-analytics \
    && flutter precache --web \
    && dart pub global activate protoc_plugin 25.1.0

# A login shell (`bash -lc`, which VS Code dev containers and postCreateCommand
# use) resets PATH from /etc/profile and would otherwise drop the Flutter and
# pub-cache directories. Register them in profile.d so every shell - interactive,
# login or remote - sees dart, flutter and protoc-gen-dart. Also makes the
# mounted host podman socket group-accessible to vscode.
USER root
RUN printf '%s\n' \
        'export PUB_CACHE="/home/vscode/.pub-cache"' \
        'export PATH="/go/bin:/home/vscode/.pub-cache/bin:/opt/flutter/bin:$PATH"' \
        > /etc/profile.d/00-devcontainer-path.sh \
    && chmod 0644 /etc/profile.d/00-devcontainer-path.sh \
    && groupadd -f podman-host \
    && usermod -aG podman-host vscode || true

# The workspace is bind-mounted from the host, so its files are owned by the
# host user rather than `vscode`. Tell git to trust it, otherwise `go build`
# fails with "error obtaining VCS status" (dubious ownership).
USER vscode
RUN git config --global --add safe.directory '*' \
    && git config --global --add safe.directory /workspaces/wdid

WORKDIR /workspaces

# Keep the container alive when used outside VS Code as well.
CMD ["sleep", "infinity"]
