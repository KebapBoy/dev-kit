# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Publishing no longer waits for approval in the GitHub environment `release`: pushing the release tag, which only the owner does from the host, is the approval. The checks still run on the tag first.
- The checks no longer run on every push to `main`, only on pull requests, on release tags and when started by hand.
- The GitHub release links to the published package.

### Fixed

- The Node/SvelteKit example answers `/healthz` with `Response.json` instead of the `json` helper of SvelteKit, which is deprecated in SvelteKit 3.
- `dev-kit deploy` no longer fails when a proxy in front of Dockhand gives up waiting for the webhook (504, or 524 from Cloudflare after 100 seconds) while Dockhand keeps deploying: it says so and waits until `DEPLOY_HEALTH_URL` reports the release. Without a health URL, and for `--fork`, it cannot tell whether the deploy succeeds and fails asking you to check the stack in Dockhand.
- `dev-kit release` no longer counts a `package.json` or `pyproject.toml` without a version as a version source, so a PHP or Go app whose `package.json` only holds development tools (Prettier, ESLint) next to `VERSION` can be released instead of failing with "more than one version source".

## [1.0.1] - 2026-11-22

### Changed

- Publishing runs the checks on the release tag first, and after publishing creates a GitHub release with the changelog section of the version.

### Fixed

- `dev-kit release` stops when the repository has a `justfile` but `just` is not installed, instead of releasing without running `just check`.

## [1.0.0] - 2026-11-22

### Added

- Devcontainer feature `ghcr.io/kebapboy/dev-kit/dev-kit`: Claude Code (native installer, channel `stable` or `latest`) with the VS Code extension, git, ssh-keygen for signed commits, just, curl, openssl and ripgrep, on Debian- and Alpine-based images. All devcontainers with the feature share one Claude Code configuration in the volume `dev-kit-claude`, so you sign in and set up MCP servers once.
- `dev-kit release <x.y.z> -m <summary>` turns `[Unreleased]` in the changelog into a release: it checks the repository (clean tree on `main`, a greater version, entries to release, `just check`), sets the version in `VERSION`, `package.json`, `pyproject.toml` or `version.go`, commits `chore: release x.y.z` and tags `v<x.y.z>`, signed if git has a key. `dev-kit release --push` pushes the release commit and its tag together.
- `dev-kit deploy` deploys the release on `origin/main` through the signed webhook of the repository's Dockhand git stack and waits until the app reports the new version; `--fork` deploys `main` of a fork without a release. Its settings come from `~/.config/dev-kit/<repository>/etc/deploy.env` on the host, mounted read-only into the devcontainer, so the container needs no Dockhand token.
- `dev-kit fork-sync` fetches `upstream` of a fork and shows the upstream releases and commits it does not have yet, and whether merging them (or a given release with `--to`) would conflict, without touching the working tree.
- `dev-kit job` runs a long command (build, test suite) in the background with its output in a log file, and `dev-kit job wait` waits for it in steps of at most 240 seconds and returns at once when it is done, with its exit code and the end of the log. An AI agent that waits this way calls a tool before its prompt cache expires, so a long build no longer costs a new write of the whole conversation. `stop` ends the command with everything it started, `list` shows all jobs. The example managed settings set the lifetime of the prompt cache for every devcontainer.
- Examples for new repositories in Node/SvelteKit, Python/uv, Go and PHP: Dockerfile with the stages `base`, `build`, `dev` and `app`, a demo and a Dockhand installation as compose files, a devcontainer with the feature, a `justfile` (`check`, `fmt`, `serve`, `demo`, `release`, `deploy`), editor and linter settings, and a `/healthz` that reports the version.
- Managed Claude Code settings from the host: repositories mount `~/.config/dev-kit/claude-code/` read-only at `/etc/claude-code`, so the MCP servers of every devcontainer (`managed-mcp.json`) and policies such as `allowManagedHooksOnly` (`managed-settings.json`) stay on the host, and code in a devcontainer cannot add hooks or MCP servers for all the others.
- Option `docker` of the feature: Docker Engine, CLI, Buildx and Compose in the devcontainer, with `dockerd` started with the container and the remote user in the group `docker`. It needs the runtime `sysbox-runc` (Sysbox on the host), which runs Docker inside without a privileged container. The examples use it for `just demo` instead of the privileged feature `docker-in-docker`.
- Publishing waits for approval in the GitHub environment `release`, so a pushed release tag alone publishes nothing.
- `host/dev-kit-host` keeps the host apart from the code, which root in a devcontainer can write: the code lives in the Docker volume `<repository>-workspace`, and the devcontainer is built from copies of the repository's `devcontainer.json` and `Dockerfile` in `~/.config/dev-kit/<repository>/` on the host, which no container mounts. Run from `initializeCommand`, it copies your `CLAUDE.md`, clones the repository into the volume (never while a container uses it), reads the volume only in throwaway containers without privileges, warns when the repository's files differ from the host's copies (`diff`, `show`), and pushes branches and tags from the volume after showing every new commit and the files it changes, and asking (`push`), so the devcontainer itself can sign commits but not push; it fetches with a read-only deploy key that `prepare` creates. The examples use it.
