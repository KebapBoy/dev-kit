# AGENTS.md

Instructions for AI coding agents (and humans) working on this repository. How to use dev-kit is in [README.md](README.md).

## Project

dev-kit holds what a family of small self-hosted projects shares: things that must be the same everywhere are taken from here, not copied. It has no app of its own.

## Architecture

- **The devcontainer feature** (`src/dev-kit/`) follows the [devcontainer feature spec](https://containers.dev/implementors/features/): `devcontainer-feature.json` declares options, environment, the shared volume and the VS Code extension; `install.sh` runs as root while the image is built and installs everything. The `dev-kit` command is a bash dispatcher; each command is `lib/<command>.sh` with a function `cmd_<command>`, installed to `/usr/local/lib/dev-kit/`. It also runs from the source tree (`src/dev-kit/bin/dev-kit` finds `../lib`), which is how the host uses `dev-kit job`.
- Nothing in this repository knows a real installation. Everything specific to one (URLs, webhook secrets, the MCP servers someone uses) comes at runtime from configuration on the host, outside of git: Claude Code reads the MCP servers and policies from `/etc/claude-code`, mounted from `~/.config/dev-kit/claude-code/`; `deploy` reads `/etc/dev-kit/deploy.env`, which the repository's devcontainer mounts from `~/.config/dev-kit/<repository>/etc/`. Settings files are parsed as `KEY=VALUE` data, never sourced.
- **The host side** (`host/dev-kit-host`) runs from `initializeCommand` of a devcontainer whose configuration lives on the host (`~/.config/dev-kit/<repository>/`) and whose code lives in a Docker volume. It must never run on the host, or build from, what the container can write: the devcontainer is built from the host's copies of `devcontainer.json` and `Dockerfile`, the volume is read only in throwaway containers (no capabilities, `no-new-privileges`, no network except for the clone, size and time limits), it never clones while a container uses the volume, what it shows from the volume goes through `cat -v`, and `push` copies only refs and objects out of the volume into a fresh repository, shows everything that is new on the remote (also what only a tag brings) and pushes exactly that, after asking.
- Secrets never appear in a command line (other processes can read those), and neither does what stands for them: `deploy` computes its HMAC with `printf` (a builtin) and `openssl dgst` on stdin, not with `openssl -hmac <key>`, and hands the signature header to curl through a file descriptor. Error messages never print a line of a settings file.

## Layout

| Path                                          | Purpose                                     |
| --------------------------------------------- | ------------------------------------------- |
| `src/dev-kit/devcontainer-feature.json`       | The feature: options, `CLAUDE_CONFIG_DIR`, the volume `dev-kit-claude`, the entrypoint, the VS Code extension |
| `src/dev-kit/install.sh`                      | Installs packages, just, Docker (option `docker`), Claude Code, the configuration directory and `dev-kit` (POSIX sh: runs before bash exists on Alpine) |
| `src/dev-kit/docker-init.sh`                  | The feature's entrypoint: starts `dockerd` at every container start if Docker is installed (through sudo for the group `docker`) |
| `src/dev-kit/bin/dev-kit`                     | The `dev-kit` command: dispatches to `lib/<command>.sh` |
| `src/dev-kit/lib/`                            | `common.sh` (helpers) and one file per command: `release.sh`, `deploy.sh`, `fork-sync.sh`, `job.sh` |
| `host/dev-kit-host`                           | The host side of a devcontainer: `prepare` (CLAUDE.md copy, clone into the volume `<name>-workspace`, deploy key for fetching, warning when the repository's `devcontainer.json` or `Dockerfile` differs from the host's copy), `diff`, `show`, and `push` with confirmation |
| `test/host.sh`                                | Test of `dev-kit-host` against a throwaway repository (`just test`; volume and container `dev-kit-test-*`) |
| `test/dev-kit/`                               | Feature tests: `test.sh` and one script per scenario in `scenarios.json` (Debian, Alpine, without just, Docker under Sysbox with root and with a user without sudo as container user; every scenario keeps the user's UID with `updateRemoteUserUID: false`, so a run as root does not turn it into root); `commands.sh` tests the commands, `docker.sh` the option `docker`, both without network |
| `examples/<stack>/`                           | Reference files for new repositories per stack (`node-sveltekit`, `python-uv`, `go`, `php`); `examples/README.md` explains them |
| `config.example/`                             | Examples of what stays on the host: `claude-code/` (managed Claude Code settings and MCP servers, mounted at `/etc/claude-code`) and `deploy.env` (deploy settings of a repository) |
| `.github/workflows/check.yaml`                | On pull requests, release tags (from `publish.yaml`) and by hand: `just check` and the feature tests |
| `.github/workflows/publish.yaml`              | On a tag `v<x.y.z>`: the checks of `check.yaml`, then publishes the feature to `ghcr.io/<owner>/dev-kit/dev-kit` with the version from the tag and creates the GitHub release |
| `.github/install-just.sh`                     | Installs the just release of the feature in the workflows |
| `.github/install-sysbox.sh`                   | Installs Sysbox (pinned, checksum verified) for the feature tests in the workflows |
| `VERSION`                                     | The version of dev-kit                      |
| `justfile`                                    | Development commands (see below)            |
| `.editorconfig`                               | Indentation, line endings and charset       |
| `README.md`, `AGENTS.md`, `CHANGELOG.md`      | Documentation                               |

## Development

Development needs only Docker and just: the tools run in containers with fixed versions.

| Command      | Does                                                                                           |
| ------------ | ---------------------------------------------------------------------------------------------- |
| `just check` | shfmt and shellcheck on every script, actionlint on the workflows, the compose files of the examples |
| `just fmt`   | Format every script with shfmt                                                                 |
| `just test`  | Test `dev-kit-host`, build the feature in every test scenario and run its tests (uses the real `dev-kit-claude` volume; the tests only create and remove a file in it; removes the images the run builds; the scenarios with Docker need [Sysbox](https://github.com/nestybox/sysbox) on the host) |

### Releasing

dev-kit releases itself with its own command: `dev-kit release <x.y.z> -m <summary>` (version source `VERSION`), then `dev-kit release --push`. The tag starts `publish.yaml`, which runs the checks of `check.yaml` on the tag, checks that tag and `VERSION` match, writes the version into `devcontainer-feature.json` (it stays `0.0.0` in git), publishes the feature and creates a GitHub release with the changelog section of the version and a link to the package; repositories use it as `ghcr.io/kebapboy/dev-kit/dev-kit:<major>`. Published from this public repository, the package was public right away; should a new package be private, make it public once in its settings on GitHub. There is no approval step: only the owner pushes tags, from the host. `dev-kit release` runs `just check` before it tags; the feature tests run on the tag, so run `just test` before releasing a change to the feature or the commands (or start `check` by hand in the Actions tab). If the checks on the tag fail, nothing is published: fix it and release the next patch version.

## Conventions

- This repository is public. Use `example.com`, `192.0.2.x` and generic names (`myapp`) in code, docs, tests and commit messages. Never commit real domains, IP addresses, user or host names, stack IDs, tokens or secrets.
- Scripts: `install.sh` is POSIX sh, everything else bash with `set -euo pipefail`. shfmt with `-i 4 -bn -ci -sr` (`just fmt`), shellcheck clean. Every download is pinned and its checksum verified (Claude Code's own installer verifies what it downloads).
- The feature must work on Debian (apt) and Alpine (apk) images and for any remote user with UID 1000; nothing may assume a user name or home directory.
- Docker in a devcontainer only under Sysbox (`"runArgs": ["--runtime=sysbox-runc"]`), never privileged: no `--privileged`, no feature `docker-in-docker`, no `"privileged": true` in the feature.
- The examples are the same in every stack wherever the stacks allow it: change one, change all, and keep `examples/README.md` in step. They are not complete apps; to try a change, copy an example to a scratch directory, add a minimal app (an empty `composer.json`, `uv init --package`, a `main.go`, …) and build the `dev` and `app` targets.
- GitHub Actions are pinned to a commit SHA with the version as a comment; workflows get only the permissions they need.
- Identifiers, comments and docs in English. 4 spaces everywhere (also JSON, YAML, Markdown), tabs only where Go requires them.

## With every change

1. Add the change to `CHANGELOG.md` ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/)) under `## [Unreleased]`. A release turns that section into `## [x.y.z] - YYYY-MM-DD` under [Semantic Versioning](https://semver.org/spec/v2.0.0.html), sets `VERSION`, is committed as `chore: release x.y.z` and tagged `v<x.y.z>`. MAJOR for changes that need action from repositories using dev-kit, MINOR for new features, PATCH for fixes.
2. Update `README.md` when features, requirements or configuration change, and this file when the layout or the conventions change.
3. Check: `just check`, and `just test` for changes to the feature or the commands.
4. Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/): `feat` (MINOR), `fix` (PATCH), `perf` (PATCH), `docs`, `refactor`, `test`, `ci` or `chore` (no release); `!` after the type plus a `BREAKING CHANGE:` footer for MAJOR. Imperative, lower-case subject up to 72 characters; the body says what changes for the user and why.
