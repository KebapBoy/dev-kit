# myapp as a container. Stage "dev" is the devcontainer, the last stage "app" the image that runs
# the app (the default target).
FROM node:26.13.0-trixie-slim AS base
ENV NPM_CONFIG_UPDATE_NOTIFIER=false NPM_CONFIG_FUND=false

# The production build: adapter-node writes build/, then the devDependencies go
FROM base AS build
WORKDIR /app
COPY package.json package-lock.json .npmrc ./
RUN npm ci
COPY . .
RUN npm run build \
    && npm prune --omit=dev

# Devcontainer: the same Node with user dev (UID 1000; the image's user node renamed). Claude Code,
# git, just and dev-kit come from the dev-kit feature (.devcontainer/devcontainer.json).
FROM base AS dev
RUN usermod --login dev --move-home --home /home/dev node \
    && groupmod --new-name dev node
USER dev

# The app: user myapp (UID 1000), state in /data. VERSION labels the image when a build sets it
# (CI); the app itself reports the version from package.json at /healthz.
FROM base AS app
ARG VERSION=dev
LABEL org.opencontainers.image.title=myapp \
    org.opencontainers.image.source=https://github.com/example/myapp \
    org.opencontainers.image.version=$VERSION
RUN usermod --login myapp --home /nonexistent node \
    && groupmod --new-name myapp node \
    && mkdir /data \
    && chown myapp:myapp /data
WORKDIR /app
COPY --from=build /app/package.json ./
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/build ./build
ENV NODE_ENV=production HOST=0.0.0.0 PORT=3000 DATA_DIR=/data
USER myapp
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
    CMD ["node", "-e", "fetch('http://127.0.0.1:3000/healthz').then((r) => process.exit(r.ok ? 0 : 1), () => process.exit(1))"]
CMD ["node", "build"]
