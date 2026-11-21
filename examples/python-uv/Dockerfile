# myapp as a container. Stage "dev" is the devcontainer, the last stage "app" the image that runs
# the app (the default target).
FROM astral/uv:0.13.6-python3.13-trixie-slim AS base
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PYTHON_DOWNLOADS=never

# The environment with the app and its dependencies, without dev dependencies, in /app/.venv
FROM base AS build
WORKDIR /app
COPY pyproject.toml uv.lock README.md ./
RUN uv sync --locked --no-dev --no-install-project
COPY src ./src
RUN uv sync --locked --no-dev --no-editable

# Devcontainer: the same Python and uv with user dev (UID 1000). Claude Code, git, just and dev-kit
# come from the dev-kit feature (.devcontainer/devcontainer.json). The environment lives outside
# the workspace (UV_PROJECT_ENVIRONMENT), so a .venv from elsewhere never gets in the way.
FROM base AS dev
RUN useradd --create-home --uid 1000 --shell /bin/bash dev
ENV UV_PROJECT_ENVIRONMENT=/home/dev/.venv
USER dev

# The app: user myapp (UID 1000), state in /data. VERSION labels the image when a build sets it
# (CI); the app itself reports the version from its package metadata at /healthz.
FROM base AS app
ARG VERSION=dev
LABEL org.opencontainers.image.title=myapp \
    org.opencontainers.image.source=https://github.com/example/myapp \
    org.opencontainers.image.version=$VERSION
RUN useradd --uid 1000 --no-create-home --shell /usr/sbin/nologin myapp \
    && mkdir /data \
    && chown myapp:myapp /data
COPY --from=build /app/.venv /app/.venv
ENV PATH=/app/.venv/bin:$PATH MYAPP_DATA_DIR=/data MYAPP_HOST=0.0.0.0 MYAPP_PORT=8000
USER myapp
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=3)"]
CMD ["myapp"]
