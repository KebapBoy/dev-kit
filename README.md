# dev-kit

Shared tooling for a family of small self-hosted projects: what every repository needs in the same way comes from here instead of being copied into each one.

- **A devcontainer feature** that brings Claude Code, git, ssh-keygen and [just](https://just.systems) into any devcontainer, with one Claude Code configuration shared by all of them: sign in once, set up MCP servers once, with MCP servers and policies kept on the host.
- **The `dev-kit` command**, installed by the feature: releases from the changelog, deploys of a release to a [Dockhand](https://github.com/Finsys/dockhand) git stack through its webhook, and a look at what upstream has for a fork.
- **[Examples](examples/README.md)** for new repositories in Node/SvelteKit, Python/uv, Go and PHP: Dockerfile, compose files for a demo and for a Dockhand installation, devcontainer, `justfile`, editor and linter settings, all wired up with the feature and the `dev-kit` command.

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

**Once**, in any devcontainer with the feature, sign in: run `claude`.

### Managed settings from the host

Claude Code also reads managed settings from `/etc/claude-code/`: they win over the settings in the volume and in a repository, and nothing in Claude Code can change them. Keep them on the host, outside of git, in `~/.config/dev-kit/claude-code/`; every devcontainer mounts that directory read-only at `/etc/claude-code` (see below). Examples: [config.example/claude-code/](config.example/claude-code/).

- `managed-mcp.json`: the MCP servers of every devcontainer. While it exists, Claude Code uses only these: no server can be added in the volume or by a repository. Sign in to a server with OAuth once, with `/mcp` in any devcontainer; the token stays in the volume.
- `managed-settings.json`: policies, e.g. `allowManagedHooksOnly` (hooks from the volume or a repository do not run) and `disableClaudeAiConnectors` (the connectors of your claude.ai account stay out of devcontainers).

Which servers you use and where they are stays on your host.

### All devcontainers are one trust domain

Code that runs in any devcontainer with the feature as the remote user (a dependency's install script, a test, Claude Code steered by a prompt injection) can read the shared sign-in, the OAuth tokens of the MCP servers and the history of every workspace, and can change the settings in the volume. The managed settings stop it from adding hooks or MCP servers that would then run in every other devcontainer, but only while the container is not privileged: a privileged container (as with the feature `docker-in-docker`) can remount what is read-only and reach the host. So:

- Open only code you trust in a devcontainer with the feature; review what you merge from someone else first (for a fork: what upstream changed, including `.devcontainer/`, whose `initializeCommand` runs on the host).
- Use only MCP servers whose tokens may be in every devcontainer: nothing with write access to infrastructure.
- Treat the working tree on the host as written by the container: whatever the host runs from it, code in the container can change. Mount `.devcontainer` read-only (see below), open the repository directly in the container, and do not run git, just or compose on the host in that tree: `.git/config` and `.git/hooks` can run commands for git, and a `justfile` or `compose.yaml` for the others. Look at them with `cat` if you need to.

### Files from the host

A feature cannot run anything on the host, so the repository's `devcontainer.json` brings in what lives there. `initializeCommand` runs on the host before the container starts: it copies your user-level `~/.claude/CLAUDE.md` (or an empty file, so the repository works for everyone) to `~/.config/dev-kit/CLAUDE.md`, and creates `~/.config/dev-kit/claude-code/` if it is missing, because a bind mount fails without its source. Both are mounted read-only. The copy stays out of the workspace on purpose: code in the container can write the workspace, and a symbolic link it leaves there would make the host's `cp` overwrite any file of yours.

For the same reason the repository's `.devcontainer` is mounted read-only over itself: code in the container then cannot change what `initializeCommand` runs on the host, or the mounts and options of the next container.

```jsonc
"initializeCommand": "mkdir -p ~/.config/dev-kit/claude-code && { cp ~/.claude/CLAUDE.md ~/.config/dev-kit/CLAUDE.md 2>/dev/null || : > ~/.config/dev-kit/CLAUDE.md; }",
"mounts": [
    "source=${localWorkspaceFolder}/.devcontainer,target=${containerWorkspaceFolder}/.devcontainer,type=bind,readonly",
    "source=${localEnv:HOME}/.config/dev-kit/CLAUDE.md,target=/var/lib/dev-kit/claude/CLAUDE.md,type=bind,readonly",
    "source=${localEnv:HOME}/.config/dev-kit/claude-code,target=/etc/claude-code,type=bind,readonly"
]
```

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
"initializeCommand": "mkdir -p ~/.config/dev-kit/claude-code ~/.config/dev-kit/myapp && { cp ~/.claude/CLAUDE.md ~/.config/dev-kit/CLAUDE.md 2>/dev/null || : > ~/.config/dev-kit/CLAUDE.md; }",
"mounts": [
    "source=${localWorkspaceFolder}/.devcontainer,target=${containerWorkspaceFolder}/.devcontainer,type=bind,readonly",
    "source=${localEnv:HOME}/.config/dev-kit/CLAUDE.md,target=/var/lib/dev-kit/claude/CLAUDE.md,type=bind,readonly",
    "source=${localEnv:HOME}/.config/dev-kit/claude-code,target=/etc/claude-code,type=bind,readonly",
    "source=${localEnv:HOME}/.config/dev-kit/myapp,target=/etc/dev-kit,type=bind,readonly"
]
```

In Dockhand, turn on the webhook of the git stack and give it a long random secret. The webhook URL must be reachable from the devcontainer: Dockhand is usually behind a reverse proxy with single sign-on, so let exactly the path `/api/git/stacks/<id>/webhook` through without it, for POST only and only from your own network; the signature protects it. The webhook has no replay protection: whoever sees a signed request can send it again and redeploy `main`, so use https.

### Forks

A fork keeps the original repository as the remote `upstream` and takes its changes by merging. `dev-kit fork-sync` shows what there is to take, without changing anything but the refs of upstream (branches in `upstream/*`, tags in `refs/upstream-tags/*`, so they never mix with the fork's own):

```text
$ dev-kit fork-sync
upstream:              https://github.com/example/myapp.git (main)
upstream/main:         1a2b3c4 2026-11-20 Add search
last merged release:   v2.3.0 (merge base 5d6e7f8 2026-10-02)
own commits:           4
new upstream commits:  12

New upstream releases:
  v2.4.0

New upstream commits (without merges, newest first, at most 30):
  ...

Merging upstream/main into HEAD conflicts in:
  src/config.ts
To merge and resolve them: git merge upstream/main
result: conflicts
```

The merge is tried in memory (`git merge-tree`, git 2.38 or newer). `--to v2.4.0` tries a release instead of the branch, `--branch` picks another upstream branch. What upstream wrote (commit subjects, tag names) is shown without control characters, and the upstream URL without credentials. The last line is `result: up-to-date`, `result: clean` or `result: conflicts`.

## License

[MIT](LICENSE)
