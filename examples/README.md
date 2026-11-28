# Examples

Reference files for a new repository, one directory per stack. They are not complete apps: create the app with the stack's own tool first, then copy these files in and replace `myapp`, `example/myapp` and `example.com` with your own names.

| Stack            | Base image                     | Checks (`just check`)                         | Version source                 | App port |
| ---------------- | ------------------------------ | --------------------------------------------- | ------------------------------ | -------- |
| `node-sveltekit` | `node:26.13.0-trixie-slim`     | svelte-check, Prettier, ESLint, Vitest        | `package.json`                 | 3000     |
| `python-uv`      | `astral/uv:0.13.6-python3.13`  | Ruff (lint and format), mypy, pytest          | `pyproject.toml`               | 8000     |
| `go`             | `golang:1.27.3`, Debian slim   | golangci-lint (fmt and run), `go test -race`  | `internal/version/version.go`  | 8000     |
| `php`            | `alpine:3.24` with PHP 8.5     | PHP-CS-Fixer, PHPStan, PHPUnit                | `VERSION`                      | 8080     |

The versions were current when the files were written; take the newest that have been out for at least two weeks.

## What every example has

| File                              | Purpose                                                                                                                                                                                                              |
| --------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Dockerfile`                      | Named stages `base` → `build` → `dev` → `app`; `app` is last, so it is the default target. `dev` and `app` run as UID 1000 (`dev`, and a user named after the app), state lives in `/data`, `HEALTHCHECK` on `/healthz` |
| `compose.yaml`                    | The demo: the image with the sample data from `docs/sample/` (copied into a volume once), ports only on `127.0.0.1` (`just demo`)                                                                                    |
| `deploy/compose.yaml`             | The installation as a Dockhand git stack behind a reverse proxy: required settings as `${VAR:?}`, the proxy network as `${MYAPP_PROXY_NETWORK:-proxy}`, no published ports, read-only with no capabilities   |
| `.devcontainer/devcontainer.json` | The template of the host's copy (see below): the stage `dev` of the host's copy of the `Dockerfile`, the code in a Docker volume, the dev-kit feature, your `CLAUDE.md`, the managed Claude Code settings and the repository's deploy settings mounted read-only, Docker inside for `just demo`; `postCreateCommand` only copies `.env.example` to `.env` |
| `.vscode/launch.json`             | Run and Debug (F5) in the devcontainer: starts the app from the working tree with the stack's debugger (js-debug, debugpy, Delve, Xdebug), after the task `install`. Nothing starts or installs when the container starts |
| `.vscode/tasks.json`              | The task `install` (`just install`), which every debug session runs first |
| `justfile`                        | `install` (the dependencies, which `check`, `fmt` and `serve` install first), `check`, `fmt`, `serve`, `demo`, plus `release` and `deploy` through dev-kit (the release is pushed on the host with `dev-kit-host push`)                                                                           |
| `.editorconfig`                   | UTF-8, LF, 4 spaces (tabs only for Go)                                                                                                                                                                               |
| `.dockerignore`                   | An allowlist: everything is left out except what the image needs                                                                                                                                                     |
| `.env.example`                    | Every setting with a comment and an example value                                                                                                                                                                    |
| `.gitignore`                      | What the stack's tools leave behind, and `.env`                                                                                                                                                                      |
| Linter configuration              | `eslint.config.js` and `prettier.config.js`, `ruff.toml` and `mypy.ini`, `.golangci.yml`, `.php-cs-fixer.dist.php` and `phpstan.neon`                                                                                |
| `/healthz`                        | One file that answers `{"status": "ok", "version": "x.y.z"}` with the version from the version source, which `dev-kit deploy` waits for                                                                            |

`VERSION` labels the image (`org.opencontainers.image.version`) only when a build passes it, as a CI build does; a build on deploy leaves it at `dev`. The version the app reports always comes from its version source.

**Docker inside the devcontainer** (for `just demo`) comes from the feature's option `docker` and needs [Sysbox](https://github.com/nestybox/sysbox) on the host: `"runArgs": ["--runtime=sysbox-runc"]` starts the devcontainer with it. Sysbox runs Docker in the container without making it privileged; root in the container, and every container started inside, runs as an unprivileged user on the host (on mounts, though, it writes files as root of the host; see the README). Without Sysbox, remove both lines and run `just demo` on the host; never use the feature `docker-in-docker` or `--privileged` instead, as those give the devcontainer root on the host. See [Docker inside the devcontainer](../README.md#docker-inside-the-devcontainer).

## Starting a new app

- **node-sveltekit:** `npx sv create` with TypeScript, Prettier, ESLint and Vitest, and `@sveltejs/adapter-node` in `svelte.config.js`. The `justfile` expects the npm scripts `check`, `lint`, `format` and `test` that `sv create` writes.
- **python-uv:** `uv init --package myapp`, then `uv add --dev ruff mypy pytest`. The package needs an entry point `myapp` that starts the server on `MYAPP_HOST`:`MYAPP_PORT`.
- **go:** `go mod init example.com/myapp`; the binary is `cmd/myapp`, needs to listen on `MYAPP_ADDR` and to check its own `/healthz` when started with `-healthcheck` (the image has no curl).
- **php:** a `composer.json` (also without dependencies: the image installs from `composer.lock`), then `composer require --dev phpstan/phpstan friendsofphp/php-cs-fixer phpunit/phpunit`. `public/index.php` is the front controller for nginx in the image and for PHP's built-in server in the devcontainer.

Replace `git@github.com:example/myapp.git` in `.devcontainer/devcontainer.json` with your repository and push it. On the host, copy that file and the `Dockerfile` to `~/.config/dev-kit/myapp/.devcontainer/`, put the deploy settings in `~/.config/dev-kit/myapp/etc/deploy.env` (see [../config.example/deploy.env](../config.example/deploy.env)), and open `~/.config/dev-kit/myapp` in VS Code: `dev-kit-host` clones the repository into the volume `myapp-workspace`, creates `etc/deploy-key` (add `etc/deploy-key.pub` to the repository as a read-only deploy key, so git can fetch in the devcontainer), and the devcontainer is built from the host's copies; push from the host with `dev-kit-host push myapp main` (see [Files from the host](../README.md#files-from-the-host) and [Signing in the devcontainer, pushing from the host](../README.md#signing-in-the-devcontainer-pushing-from-the-host)). The managed Claude Code settings in `~/.config/dev-kit/claude-code/` are the same for every repository (see [../config.example/claude-code/](../config.example/claude-code/)).
