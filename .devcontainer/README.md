# Development container

A reproducible toolchain for developing **wdid** in VS Code (or the
`devcontainer` CLI) on Bazzite / Fedora with **rootless Podman**.

## What's inside

| Tool | Version | Why |
|------|---------|-----|
| Go | 1.27 (base image) | builds `cmd/wdid` and goslow |
| protoc | 27.3 | `make proto` |
| protoc-gen-go / protoc-gen-connect-go | 1.36.12 / 1.21.1 | Go message + Connect stubs |
| Dart + Flutter | stable channel (`/opt/flutter`) | `make buildweb`, Dart stubs |
| protoc-gen-dart | 25.1.0 | Dart stubs |
| Node.js | LTS (devcontainer feature) | required by Claude Code |
| Claude Code | latest (devcontainer feature) | `claude` CLI + VS Code extension |
| gh (GitHub CLI) | 2.103.2 (devcontainer feature) | `gh issue` / `gh pr` against this repo |
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

## Claude Code

Claude Code is installed by the official dev container feature:

```json
"features": {
  "ghcr.io/devcontainers/features/node:1": {},
  "ghcr.io/anthropics/devcontainer-features/claude-code:1.0": {}
}
```

The Go base image ships nvm but does not install a Node version, so the Node
feature comes first — without it, the Claude feature's NodeSource fallback fails
on Debian trixie (Debian's `nodejs` package no longer pulls in `npm`). The
Claude feature then installs the `claude` CLI globally and adds the Claude Code
VS Code extension, so the tool works both from the integrated terminal and from
the extension panel.

### Host environment

`remoteEnv` copies these variables from the host into terminals, tasks and
extensions in the container:

* `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`
* `ANTHROPIC_BASE_URL`, `ANTHROPIC_CUSTOM_HEADERS`, `ANTHROPIC_MODEL`
* `ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU,FABLE}_MODEL`
* `GH_TOKEN`, `GITHUB_TOKEN` (the GitHub CLI, see below)
* the existing `COPILOT_*` settings

Export them on the host before opening or rebuilding the container, e.g.
`export ANTHROPIC_API_KEY=...`. Unset variables arrive as empty strings and are
ignored by Claude Code. To forward another variable, add
`"NAME": "${localEnv:NAME}"` to `remoteEnv` and rebuild.

### Authentication and persistence

If no API key or token is forwarded, run `claude` in the container and complete
the browser sign-in. If the callback does not reach the container, copy the code
shown in the browser back into the terminal. Authentication, settings and
session history live under `/home/vscode/.claude`, which is the named volume
`claude-code-config-<id>`, so they survive **Dev Containers: Rebuild Container**.
`CLAUDE_CONFIG_DIR` points at that volume so `~/.claude.json` is persisted too.

## GitHub CLI

The [GitHub CLI](https://cli.github.com/) is installed by the official dev
container feature, pinned so rebuilds are reproducible (bump the version
deliberately):

```json
"ghcr.io/devcontainers/features/github-cli:1": { "version": "2.103.2" }
```

Authenticate one of two ways:

* **Token (non-interactive, good for agents):** export `GH_TOKEN` (or
  `GITHUB_TOKEN`) on the host before opening the container; `remoteEnv` forwards
  it into terminals, tasks and extensions.
* **Interactive:** run `gh auth login`. The credential is stored in
  `~/.config/gh`, which is the named volume `gh-config-<id>`, so it survives
  **Dev Containers: Rebuild Container**.

Then, from any terminal in the container:

```bash
gh auth status                 # which account (or token) is active
gh issue list                  # issues on github.com/Mallekoppie/wdid
gh issue view 42
gh issue comment 42 --body "..."
gh pr list
```

The repository remote is HTTPS. To let plain `git push` reuse the `gh`
credential instead of prompting, run `gh auth setup-git` once (it writes the
credential helper into git config).

## First run

The `postCreateCommand` (`.devcontainer/post-create.sh`) checks the toolchain,
the GitHub CLI login, `go mod download`, `make proto` and `flutter pub get`. Each
step is best-effort so a flaky network does not block opening the repo.

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

Forwarded port: 8080 is the single application origin for native gRPC,
gRPC-Web, and the embedded web UI. If you change the listen address in the
platform config or the Makefile, update `forwardPorts` in `devcontainer.json`
too.

## Regenerating the image

```bash
podman build --format docker \
  -f .devcontainer/Dockerfile \
  -t wdid-dev \
  .
```

Then in VS Code: **Dev Containers: Rebuild Container**.
