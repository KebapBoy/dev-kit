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
| `.devcontainer/devcontainer.json` | Built from the `Dockerfile` (target `dev`) with the dev-kit feature, your `CLAUDE.md`, the managed Claude Code settings, the repository's deploy settings and its own `.devcontainer` mounted read-only, Docker inside for `just demo` (see below)                               |
| `.devcontainer/serve.sh`          | Started by `postStartCommand`: runs `just serve`, log in `/tmp/serve.log`                                                                                                                                            |
| `justfile`                        | `check`, `fmt`, `serve`, `demo`, plus `release` and `deploy` through dev-kit                                                                                                                                         |
| `.editorconfig`                   | UTF-8, LF, 4 spaces (tabs only for Go)                                                                                                                                                                               |
| `.dockerignore`                   | An allowlist: everything is left out except what the image needs                                                                                                                                                     |
| `.env.example`                    | Every setting with a comment and an example value                                                                                                                                                                    |
| `.gitignore`                      | What the stack's tools leave behind, and `.env`                                                                                                                                                                      |
| Linter configuration              | `eslint.config.js` and `prettier.config.js`, `ruff.toml` and `mypy.ini`, `.golangci.yml`, `.php-cs-fixer.dist.php` and `phpstan.neon`                                                                                |
| `/healthz`                        | One file that answers `{"status": "ok", "version": "x.y.z"}` with the version from the version source, which `dev-kit deploy` waits for                                                                            |

`VERSION` labels the image (`org.opencontainers.image.version`) only when a build passes it, as a CI build does; a build on deploy leaves it at `dev`. The version the app reports always comes from its version source.

**Docker inside the devcontainer** (the feature `docker-in-docker`, for `just demo`) runs the container privileged and lets its user start privileged containers: any code in the devcontainer can then reach the host as root, including its files and its Docker. Keep it only in devcontainers for code you trust, or leave it out and run `just demo` on the host.

## Starting a new app

- **node-sveltekit:** `npx sv create` with TypeScript, Prettier, ESLint and Vitest, and `@sveltejs/adapter-node` in `svelte.config.js`. The `justfile` expects the npm scripts `check`, `lint`, `format` and `test` that `sv create` writes.
- **python-uv:** `uv init --package myapp`, then `uv add --dev ruff mypy pytest`. The package needs an entry point `myapp` that starts the server on `MYAPP_HOST`:`MYAPP_PORT`.
- **go:** `go mod init example.com/myapp`; the binary is `cmd/myapp`, needs to listen on `MYAPP_ADDR` and to check its own `/healthz` when started with `-healthcheck` (the image has no curl).
- **php:** a `composer.json` (also without dependencies: the image installs from `composer.lock`), then `composer require --dev phpstan/phpstan friendsofphp/php-cs-fixer phpunit/phpunit`. `public/index.php` is the front controller for nginx in the image and for PHP's built-in server in the devcontainer.

Then put the deploy settings on the host as `~/.config/dev-kit/myapp/deploy.env` (see [../config.example/deploy.env](../config.example/deploy.env)); the managed Claude Code settings in `~/.config/dev-kit/claude-code/` are the same for every repository (see [../config.example/claude-code/](../config.example/claude-code/)).
