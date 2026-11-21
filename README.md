# dev-kit

Shared tooling for a family of small self-hosted projects: what every repository needs in the same way comes from here instead of being copied into each one.

- **A devcontainer feature** that brings Claude Code, git, ssh-keygen and [just](https://just.systems) into any devcontainer, with one Claude Code configuration shared by all of them: sign in once, set up MCP servers once.

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

## License

[MIT](LICENSE)
