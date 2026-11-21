# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Devcontainer feature `ghcr.io/kebapboy/dev-kit/dev-kit`: Claude Code (native installer, channel `stable` or `latest`) with the VS Code extension, git, ssh-keygen for signed commits, just, curl, openssl and ripgrep, on Debian- and Alpine-based images. All devcontainers with the feature share one Claude Code configuration in the volume `dev-kit-claude`, so you sign in and set up MCP servers once.
- `dev-kit release <x.y.z> -m <summary>` turns `[Unreleased]` in the changelog into a release: it checks the repository (clean tree on `main`, a greater version, entries to release, `just check`), sets the version in `VERSION`, `package.json`, `pyproject.toml` or `version.go`, commits `chore: release x.y.z` and tags `v<x.y.z>`, signed if git has a key. `dev-kit release --push` pushes the release commit and its tag together.
- `dev-kit deploy` deploys the release on `origin/main` through the signed webhook of the repository's Dockhand git stack and waits until the app reports the new version; `--fork` deploys `main` of a fork without a release. Its settings come from `~/.config/dev-kit/<repository>/deploy.env` on the host, mounted read-only into the devcontainer, so the container needs no Dockhand token.
- `dev-kit fork-sync` fetches `upstream` of a fork and shows the upstream releases and commits it does not have yet, and whether merging them (or a given release with `--to`) would conflict, without touching the working tree.
- Examples for new repositories in Node/SvelteKit, Python/uv, Go and PHP: Dockerfile with the stages `base`, `build`, `dev` and `app`, a demo and a Dockhand installation as compose files, a devcontainer with the feature, a `justfile` (`check`, `fmt`, `serve`, `demo`, `release`, `deploy`), editor and linter settings, and a `/healthz` that reports the version.
- Managed Claude Code settings from the host: repositories mount `~/.config/dev-kit/claude-code/` read-only at `/etc/claude-code`, so the MCP servers of every devcontainer (`managed-mcp.json`) and policies such as `allowManagedHooksOnly` (`managed-settings.json`) stay on the host, and code in a devcontainer cannot add hooks or MCP servers for all the others. The examples do it, keep the copy of your `CLAUDE.md` outside the workspace, and mount their `.devcontainer` read-only, so code in a devcontainer cannot change what runs on the host.
