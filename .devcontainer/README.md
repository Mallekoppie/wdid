# Development container

A reproducible toolchain for developing **wdid** in VS Code (or the
`devcontainer` CLI) on Bazzite / Fedora with **rootless Podman**.

## What's inside

| Tool | Version | Why |
|------|---------|-----|
| Go | 1.26 (base image) | builds `cmd/wdid` |
| protoc | 27.3 | `make proto` |
| protoc-gen-go / protoc-gen-go-grpc | 1.36.11 / 1.2.0 | Go stubs |
| Dart + Flutter | stable channel (`/opt/flutter`) | `make buildweb`, Dart stubs |
| protoc-gen-dart | 25.1.0 | Dart stubs |
| podman + `docker` shim | (client only) | drive the **host** engine |
| make, jq, openssl, curl, socat... | | Makefile targets |

## How it talks to the host engine

The container does **not** run its own container engine. Instead:

* the host's rootless podman socket is bind-mounted at `/run/host-podman.sock`;
* `DOCKER_HOST` / `CONTAINER_HOST` point at it;
* a `/usr/local/bin/docker` shim forwards to `podman`.

`runArgs` includes `--userns=keep-id` so the container user (uid 1000) matches the
host user that owns both the bind-mounted workspace and the socket. Without it the
socket mount fails with `permission denied`.

This lets you run `make docker-build`, `docker ps`, etc. **inside** the container
while the images are actually built by the host's podman.

> The wdid server itself runs fine inside the container. Nothing in this project
> needs `kind`; if the deployment story grows into a cluster later, run cluster
> tooling on the host.

## First run

The `postCreateCommand` (`.devcontainer/post-create.sh`) checks the toolchain,
`go mod download`, `make proto` and `flutter pub get`. Each step is best-effort so
a flaky network does not block opening the repo.

```bash
make proto        # Go stubs (and Dart when web/pubspec.yaml exists)
make buildweb     # Flutter web app -> cmd/wdid/dist
make all          # build the server
make test         # go test + flutter test
```

## Common tasks

```bash
make all                       # build the server
make test                      # go test + flutter test
make lint                      # go vet + flutter analyze
make fmt                       # format the Go and Dart sources
make docker-build              # build the image via the host engine
```

Forwarded port: 8080 (web UI and gRPC-Web share it). If you change the listen
address in the platform config or the Makefile, update `forwardPorts` in
`devcontainer.json` too.

## Regenerating the image

```bash
podman build --format docker \
  -f .devcontainer/Dockerfile \
  -t wdid-dev \
  .
```

Then in VS Code: **Dev Containers: Rebuild Container**.
