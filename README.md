# dev-kit

Shared tooling for a family of small self-hosted projects: what every repository needs in the same way comes from here instead of being copied into each one.

- **A devcontainer feature** that brings Claude Code, git, ssh-keygen and [just](https://just.systems) into any devcontainer, with one Claude Code configuration shared by all of them: sign in once, set up MCP servers once.
- **The `dev-kit` command**, installed by the feature: releases from the changelog, and deploys of a release to a [Dockhand](https://github.com/Finsys/dockhand) git stack through its webhook.

## The devcontainer feature

Add it to `.devcontainer/devcontainer.json`:

```jsonc
"features": {
    "ghcr.io/kebapboy/dev-kit/dev-kit:1": {}
}
```

It installs:

- **Claude Code** with the native installer (it updates itself), for the container's remote user, plus the VS Code extension `anthropic.claude-code`.
- **git** and **openssh-client**: `ssh-keygen` signs commits with the SSH key of the agent VS Code forwards into the container.
- **just** (a pinned release, checksum verified), **curl**, **openssl** and **ripgrep**.

It works on Debian- and Alpine-based images.

| Option          | Default  | Meaning                                                     |
| --------------- | -------- | ----------------------------------------------------------- |
| `claudeChannel` | `stable` | Release channel of Claude Code: `stable` or `latest`        |
| `justVersion`   | `1.59.0` | Version of just, or `none` to leave it out (only the default has a pinned checksum; another version is checked against the checksums of its own release) |

### One Claude Code configuration for all devcontainers

The feature mounts the Docker volume `dev-kit-claude` at `/var/lib/dev-kit/claude` and points `CLAUDE_CONFIG_DIR` there. Every devcontainer with the feature shares it: the sign-in, settings, user-level MCP servers and the history of each workspace. Rebuilding a container keeps all of it.

The volume is separate from `~/.claude` on the host on purpose: tokens that Claude Code on the host holds for its own MCP servers never reach a container.

**All devcontainers with the feature are one trust domain.** Code that runs in any of them as the remote user (a dependency's install script, a test, Claude Code steered by a prompt injection) can read the shared sign-in, the OAuth tokens of the shared MCP servers and the history of every workspace, and can change the shared settings, for example add a hook or an MCP server that then runs in every other devcontainer. So:

- Open only code you trust in a devcontainer with the feature; review what you merge from someone else first (for a fork: what upstream changed, including `.devcontainer/`, whose `initializeCommand` runs on the host).
- Add only MCP servers at user scope whose tokens may be in every devcontainer: nothing with write access to infrastructure.
- Settings in the volume are preferences, not a boundary: any code in a devcontainer can change them.

**Once**, in any devcontainer with the feature:

```sh
claude                 # sign in
# MCP servers for every devcontainer, e.g. one over HTTP with OAuth (sign in with /mcp)
claude mcp add --scope user --transport http notes https://mcp.example.com/mcp
```

If you add a server this way that you also have as a connector on claude.ai, Claude Code loads both. To use only your own servers in devcontainers, turn the claude.ai connectors off in the shared `settings.json` (in Claude Code: `/config`, or edit `$CLAUDE_CONFIG_DIR/settings.json`):

```json
{
    "disableClaudeAiConnectors": true
}
```

### Your CLAUDE.md in the container

A feature cannot run anything on the host, so the repository copies your user-level `~/.claude/CLAUDE.md` itself: `initializeCommand` runs on the host before the container starts and copies it (or an empty file, so the repository works for everyone) to the ignored `.devcontainer/host/`, from where it is mounted read-only into the shared configuration:

```jsonc
"initializeCommand": "mkdir -p .devcontainer/host && { cp ~/.claude/CLAUDE.md .devcontainer/host/CLAUDE.md 2>/dev/null || : > .devcontainer/host/CLAUDE.md; }",
"mounts": [
    "source=${localWorkspaceFolder}/.devcontainer/host/CLAUDE.md,target=/var/lib/dev-kit/claude/CLAUDE.md,type=bind,readonly"
]
```

Add `.devcontainer/host/` to `.gitignore`.

## The dev-kit command

`dev-kit help` lists the commands, `dev-kit help <command>` explains one.

### Releases

A repository keeps its changes under `## [Unreleased]` in `CHANGELOG.md` ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/)) and its version in exactly one place: `VERSION`, `package.json` or `pyproject.toml` in the top directory, or else a `version.go` with `Version = "x.y.z"` (the only one in the repository).

```sh
dev-kit release 1.4.0 -m "Shared playlists and a faster search"
dev-kit release --push
```

The first command works on `main` and pushes nothing. It checks that the working tree is clean, that 1.4.0 is greater than the current version, that there are entries under `[Unreleased]` and that `just check` passes (if the repository has that recipe; skip it with `--no-check`). Then it:

1. turns `## [Unreleased]` into `## [1.4.0] - <today>` above the entries and updates the compare links at the bottom, if there are any,
2. sets the version (through npm for `package.json`, so `package-lock.json` follows, and through uv for `pyproject.toml`, so `uv.lock` follows),
3. commits `chore: release 1.4.0` with the summary as body and tags `v1.4.0`, both signed if git has a signing key.

`dev-kit release --push` pushes `main` and the release tag on `HEAD` in one atomic push.

### Deploys

`dev-kit deploy` deploys a released `main` to the repository's Dockhand git stack, which follows `main` with auto-update off, so only this command (or someone in Dockhand) deploys:

1. It fetches `origin` and refuses unless `origin/main` carries a release tag `v<x.y.z>` that is on `origin` too. Forks, which deploy `main` without releases, use `dev-kit deploy --fork`. This check is a guardrail of the command, not of Dockhand: the webhook deploys whatever `main` is when Dockhand pulls it.
2. It calls the stack's webhook: a POST signed with HMAC-SHA256 in `X-Hub-Signature-256`, like a GitHub webhook. The secret never leaves the container, and neither the secret nor the signature appears in a command line. Dockhand pulls `main`, builds and starts the stack, and answers when it is done.
3. It waits until the app's health URL answers with the new version in its body (for `--fork`: until it answers at all).

The container needs no Dockhand token: the webhook can only redeploy that one stack.

**Settings** live on the host, outside of git, one directory per repository: `~/.config/dev-kit/<repository>/deploy.env` (see [config.example/deploy.env](config.example/deploy.env)). It is read as `KEY=VALUE` data, nothing in it runs. The repository's `devcontainer.json` mounts that directory read-only at `/etc/dev-kit`, so a container sees only the settings of its own repository. Because a bind mount fails without its source, `initializeCommand` creates the directory first:

```jsonc
"initializeCommand": "mkdir -p .devcontainer/host ~/.config/dev-kit/myapp && { cp ~/.claude/CLAUDE.md .devcontainer/host/CLAUDE.md 2>/dev/null || : > .devcontainer/host/CLAUDE.md; }",
"mounts": [
    "source=${localWorkspaceFolder}/.devcontainer/host/CLAUDE.md,target=/var/lib/dev-kit/claude/CLAUDE.md,type=bind,readonly",
    "source=${localEnv:HOME}/.config/dev-kit/myapp,target=/etc/dev-kit,type=bind,readonly"
]
```

In Dockhand, turn on the webhook of the git stack and give it a long random secret. The webhook URL must be reachable from the devcontainer: Dockhand is usually behind a reverse proxy with single sign-on, so let exactly the path `/api/git/stacks/<id>/webhook` through without it, for POST only and only from your own network; the signature protects it. The webhook has no replay protection: whoever sees a signed request can send it again and redeploy `main`, so use https.

## License

[MIT](LICENSE)
