# myapp as a container. Stage "dev" is the devcontainer, the last stage "app" the image that runs
# the app (the default target).
FROM golang:1.27.3-trixie AS go

# Debian with CA certificates and time zones, for the devcontainer and the app
FROM debian:trixie-20261027-slim AS base
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/*

# The static binary
FROM go AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY cmd ./cmd
COPY internal ./internal
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /myapp ./cmd/myapp

# Devcontainer: user dev (UID 1000) with Go, gopls, golangci-lint, Delve (the debugger of
# .vscode/launch.json) and gcc (for the race detector). Claude Code, git, just and dev-kit come from
# the dev-kit feature (.devcontainer/devcontainer.json).
FROM base AS dev
RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 1000 --shell /bin/bash dev
COPY --from=go /usr/local/go /usr/local/go
ENV PATH=/home/dev/go/bin:/usr/local/go/bin:$PATH
USER dev
RUN go install golang.org/x/tools/gopls@v0.24.0 \
    && go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.15.0 \
    && go install github.com/go-delve/delve/cmd/dlv@v1.27.2 \
    && go clean -cache -modcache

# The app: user myapp (UID 1000), state in /data. VERSION labels the image when a build sets it
# (CI); the binary reports the version from internal/version at /healthz, and checks its own
# /healthz with -healthcheck (the image has no curl).
FROM base AS app
ARG VERSION=dev
LABEL org.opencontainers.image.title=myapp \
    org.opencontainers.image.source=https://github.com/example/myapp \
    org.opencontainers.image.version=$VERSION
RUN useradd --uid 1000 --no-create-home --shell /usr/sbin/nologin myapp \
    && mkdir /data \
    && chown myapp:myapp /data
COPY --from=build /myapp /usr/local/bin/myapp
ENV MYAPP_DATA_DIR=/data MYAPP_ADDR=:8000
USER myapp
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s CMD ["myapp", "-healthcheck"]
CMD ["myapp"]
