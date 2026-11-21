# AGENTS.md

Instructions for AI coding agents (and humans) working on this repository. How to use dev-kit is in [README.md](README.md).

## Project

dev-kit holds what a family of small self-hosted projects shares: things that must be the same everywhere are taken from here, not copied. It has no app of its own.

## Architecture

- **The devcontainer feature** (`src/dev-kit/`) follows the [devcontainer feature spec](https://containers.dev/implementors/features/): `devcontainer-feature.json` declares options, environment, the shared volume and the VS Code extension; `install.sh` runs as root while the image is built and installs everything. The `dev-kit` command is a bash dispatcher; each command is `lib/<command>.sh` with a function `cmd_<command>`, installed to `/usr/local/lib/dev-kit/`.
- Nothing in this repository knows a real installation. Everything specific to one (URLs, webhook secrets, the MCP servers someone uses) comes at runtime from configuration on the host, outside of git: `deploy` reads `/etc/dev-kit/deploy.env`, which the repository's devcontainer mounts from `~/.config/dev-kit/<repository>/`. Settings files are parsed as `KEY=VALUE` data, never sourced.
- Secrets never appear in a command line (other processes can read those), and neither does what stands for them: `deploy` computes its HMAC with `printf` (a builtin) and `openssl dgst` on stdin, not with `openssl -hmac <key>`, and hands the signature header to curl through a file descriptor. Error messages never print a line of a settings file.

## Layout

| Path                                          | Purpose                                     |
| --------------------------------------------- | ------------------------------------------- |
| `src/dev-kit/devcontainer-feature.json`       | The feature: options, `CLAUDE_CONFIG_DIR`, the volume `dev-kit-claude`, the VS Code extension |
| `src/dev-kit/install.sh`                      | Installs packages, just, Claude Code, the configuration directory and `dev-kit` (POSIX sh: runs before bash exists on Alpine) |
| `src/dev-kit/bin/dev-kit`                     | The `dev-kit` command: dispatches to `lib/<command>.sh` |
| `src/dev-kit/lib/`                            | `common.sh` (helpers) and one file per command: `release.sh`, `deploy.sh`, `fork-sync.sh` |
| `test/dev-kit/`                               | Feature tests: `test.sh` and one script per scenario in `scenarios.json` (Debian, Alpine, without just); `commands.sh` tests the commands in throwaway repositories, without network |
| `examples/<stack>/`                           | Reference files for new repositories per stack (`node-sveltekit`, `python-uv`, `go`, `php`); `examples/README.md` explains them |
| `config.example/deploy.env`                   | Example of the deploy settings a repository keeps on the host |
| `.github/workflows/check.yaml`                | On every push and pull request: `just check` and the feature tests |
| `.github/workflows/publish.yaml`              | On a tag `v<x.y.z>`: publishes the feature to `ghcr.io/<owner>/dev-kit/dev-kit` with the version from the tag |
| `.github/install-just.sh`                     | Installs the just release of the feature in the workflows |
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
| `just test`  | Build the feature in every test scenario and run its tests (uses the real `dev-kit-claude` volume; the tests only create and remove a file in it) |

### Releasing

dev-kit releases itself with its own command: `dev-kit release <x.y.z> -m <summary>` (version source `VERSION`), then `dev-kit release --push`. The tag starts `publish.yaml`, which waits for approval in the environment `release` (set a required reviewer in the repository settings, so a pushed tag alone publishes nothing), checks that tag and `VERSION` match, writes the version into `devcontainer-feature.json` (it stays `0.0.0` in git) and publishes the feature; repositories use it as `ghcr.io/kebapboy/dev-kit/dev-kit:<major>`. A new package on ghcr.io is private: after the first publish, make it public once in the package settings on GitHub.

## Conventions

- This repository is public. Use `example.com`, `192.0.2.x` and generic names (`myapp`) in code, docs, tests and commit messages. Never commit real domains, IP addresses, user or host names, stack IDs, tokens or secrets.
- Scripts: `install.sh` is POSIX sh, everything else bash with `set -euo pipefail`. shfmt with `-i 4 -bn -ci -sr` (`just fmt`), shellcheck clean. Every download is pinned and its checksum verified (Claude Code's own installer verifies what it downloads).
- The feature must work on Debian (apt) and Alpine (apk) images and for any remote user with UID 1000; nothing may assume a user name or home directory.
- The examples are the same in every stack wherever the stacks allow it: change one, change all, and keep `examples/README.md` in step. They are not complete apps; to try a change, copy an example to a scratch directory, add a minimal app (an empty `composer.json`, `uv init --package`, a `main.go`, …) and build the `dev` and `app` targets.
- GitHub Actions are pinned to a commit SHA with the version as a comment; workflows get only the permissions they need.
- Identifiers, comments and docs in English. 4 spaces everywhere (also JSON, YAML, Markdown), tabs only where Go requires them.

## With every change

1. Add the change to `CHANGELOG.md` ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/)) under `## [Unreleased]`. A release turns that section into `## [x.y.z] - YYYY-MM-DD` under [Semantic Versioning](https://semver.org/spec/v2.0.0.html), sets `VERSION`, is committed as `chore: release x.y.z` and tagged `v<x.y.z>`. MAJOR for changes that need action from repositories using dev-kit, MINOR for new features, PATCH for fixes.
2. Update `README.md` when features, requirements or configuration change, and this file when the layout or the conventions change.
3. Check: `just check`, and `just test` for changes to the feature or the commands.
4. Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/): `feat` (MINOR), `fix` (PATCH), `perf` (PATCH), `docs`, `refactor`, `test`, `ci` or `chore` (no release); `!` after the type plus a `BREAKING CHANGE:` footer for MAJOR. Imperative, lower-case subject up to 72 characters; the body says what changes for the user and why.
