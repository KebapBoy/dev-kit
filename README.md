# dev-kit

Shared tooling for a family of small self-hosted projects: what every repository needs in the same way comes from here instead of being copied into each one.

- **A devcontainer feature** that brings Claude Code, git, ssh-keygen and [just](https://just.systems) into any devcontainer, with one Claude Code configuration shared by all of them: sign in once, set up MCP servers once, with MCP servers and policies kept on the host. Optionally Docker inside, for containers run with [Sysbox](https://github.com/nestybox/sysbox).
- **The `dev-kit` command**, installed by the feature: releases from the changelog, deploys of a release to a [Dockhand](https://github.com/Finsys/dockhand) git stack through its webhook, a look at what upstream has for a fork, and long commands in the background for AI agents that wait for them in short steps.
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
- With the option `docker`: **Docker Engine, CLI, Buildx and Compose** (see [Docker inside the devcontainer](#docker-inside-the-devcontainer)).

It works on Debian- and Alpine-based images.

| Option          | Default  | Meaning                                                     |
| --------------- | -------- | ----------------------------------------------------------- |
| `claudeChannel` | `stable` | Release channel of Claude Code: `stable` or `latest`        |
| `justVersion`   | `1.59.0` | Version of just, or `none` to leave it out (only the default has a pinned checksum; another version is checked against the checksums of its own release) |
| `docker`        | `false`  | Docker inside the container; needs the runtime `sysbox-runc` (see below)               |

### One Claude Code configuration for all devcontainers

The feature mounts the Docker volume `dev-kit-claude` at `/var/lib/dev-kit/claude` and points `CLAUDE_CONFIG_DIR` there. Every devcontainer with the feature shares it: the sign-in, settings, user-level MCP servers and the history of each workspace. Rebuilding a container keeps all of it.

The volume is separate from `~/.claude` on the host on purpose: tokens that Claude Code on the host holds for its own MCP servers never reach a container.

**Once**, in any devcontainer with the feature, sign in: run `claude`.

### Managed settings from the host

Claude Code also reads managed settings from `/etc/claude-code/`: they win over the settings in the volume and in a repository, and nothing in Claude Code can change them. Keep them on the host, outside of git, in `~/.config/dev-kit/claude-code/`; every devcontainer mounts that directory read-only at `/etc/claude-code` (see below). Examples: [config.example/claude-code/](config.example/claude-code/).

- `managed-mcp.json`: the MCP servers of every devcontainer. While it exists, Claude Code uses only these: no server can be added in the volume or by a repository. Sign in to a server with OAuth once, with `/mcp` in any devcontainer; the token stays in the volume.
- `managed-settings.json`: policies, e.g. `allowManagedHooksOnly` (hooks from the volume or a repository do not run) and `disableClaudeAiConnectors` (the connectors of your claude.ai account stay out of devcontainers). Settings that should be the same in every devcontainer belong here too, such as how long the prompt cache lives (`promptCacheTtl`, `subagentPromptCacheTtl`, see [Long commands and the prompt cache](#long-commands-and-the-prompt-cache)): the settings of Claude Code on the host do not reach the volume.

Which servers you use and where they are stays on your host.

### Docker inside the devcontainer

With `"docker": true` the feature installs Docker Engine, CLI, Buildx and Compose (on Debian and Ubuntu pinned versions from Docker's apt repository, on Alpine those of the Alpine release), adds the remote user to the group `docker` and starts `dockerd` with the container. That is enough for `docker build`, `docker compose up` and a demo of the app in the devcontainer.

It works only when the container runs with [Sysbox](https://github.com/nestybox/sysbox), a container runtime that has to be installed on the host:

```jsonc
"runArgs": ["--runtime=sysbox-runc"],
"features": {
    "ghcr.io/kebapboy/dev-kit/dev-kit:1": { "docker": true }
}
```

`dockerd` starts in the background while the container comes up, so it may take a few seconds before `docker` answers. Without Sysbox, `dockerd` does not start (its log is `/var/log/dockerd.log`). Do not make the container privileged instead, and do not use the feature `docker-in-docker`, which does: a privileged container gives every process in it root on the host.

Under Sysbox the container stays unprivileged: root in it cannot reach the host's processes, devices or kernel settings, and neither can the containers started inside. Being in the group `docker` means root in the devcontainer, so the feature also lets that group run `dockerd`'s start script through sudo, and nothing else.

What root in such a container can still do, or reach:

- **Files on mounts:** Sysbox mounts the workspace and volumes with ID mapping, so a file keeps its owner between host and container, and root in the container writes there as root of the host. It can leave a setuid-root program in the workspace or in the shared volume `dev-kit-claude`. Both are Docker volumes, so such a program never reaches a directory the host runs things from, and `dev-kit-host` reads the volume only in containers without new privileges (see [Files from the host](#files-from-the-host)); in another devcontainer that mounts the same volume, it gives root in that container.
- **What lies under a mount:** a read-only mount inside a writable one, such as a read-only `.devcontainer` over a workspace mounted from the host, protects nothing: root can mount the writable one a second time without the mounts inside it (also through `docker run --mount …,bind-recursive=disabled`) and write underneath. Only a mount of its own, like `/etc/claude-code`, stays read-only.
- **One user mapping for all:** Sysbox CE maps root of every container to the same host user.
- **The network of the devcontainer:** containers started inside reach what the devcontainer reaches, including the host's published ports and the local network. Ports they publish open only inside the devcontainer; VS Code forwards them from there.

Images and build cache of the inner Docker live on the host in Sysbox's own directory and are removed with the container: after a rebuild of the devcontainer, `docker compose up --build` starts from scratch.

### All devcontainers are one trust domain

Code that runs in any devcontainer with the feature as the remote user (a dependency's install script, a test, Claude Code steered by a prompt injection) can read the shared sign-in, the OAuth tokens of the MCP servers and the history of every workspace, and can change the settings in the volume. The managed settings stop it from adding hooks or MCP servers that would then run in every other devcontainer: they are mounted read-only, and nothing in the container can make them writable. They do not cover everything in the volume, though: other settings there also run commands or set the environment in every devcontainer (e.g. `statusLine`, `apiKeyHelper`, `env`), and skills, agents and memory there reach every workspace.

That holds for root in the container too, so for Docker inside it, as long as the container is not privileged. Run Docker inside only with Sysbox (see above). By default, though, Sysbox lets root in a container unmount what was mounted at its start: in that one container it would then see the empty directory underneath instead of the managed settings (in all other containers they still apply). Start `sysbox-fs` with `--allow-immutable-unmounts=false` to forbid that, e.g. with a systemd drop-in for `sysbox-fs.service`; root then can neither unmount nor remount them. In a container whose code is already hostile, the managed settings protect nothing anyway (root can mount something else over them, and the remote user owns Claude Code's own files); what they protect are the other devcontainers. So:

- Open only code you trust in a devcontainer with the feature; review what you merge from someone else first (for a fork: what upstream changed).
- Use only MCP servers whose tokens may be in every devcontainer: nothing with write access to infrastructure.
- Give devcontainers no key that can push. VS Code forwards your SSH agent into every devcontainer; with a key in it that can push, code in any of them could push to all your repositories, including a release tag that publishes a new version of a feature every devcontainer uses. Keep only your signing key in that agent and push from the host (see [Signing in the devcontainer, pushing from the host](#signing-in-the-devcontainer-pushing-from-the-host)).
- Keep the code away from the host: whatever the host runs from a working tree, code in the container can change (`.git/config` and `.git/hooks` run commands for git, a `justfile` or `compose.yaml` for just and compose, and `devcontainer.json` and the `Dockerfile` decide how the host builds and starts the next container). So the code lives in a Docker volume, and the devcontainer's configuration in a folder on the host that no container mounts (see below).

### Files from the host

Whatever the host builds or starts from files the container can write, code in the container can change, and with it how the next container starts: `runArgs` and `mounts` in `devcontainer.json`, but also an image label `devcontainer.metadata` in the `Dockerfile`, which the devcontainer CLI merges into the configuration (mounts, `privileged`, capabilities). A devcontainer is therefore split in two:

- **The code** lives in a Docker volume, `<repository>-workspace`, mounted as the workspace. It is never on the host's file system.
- **The configuration** lives in a folder on the host, `~/.config/dev-kit/<repository>/`, which you open in VS Code ("Reopen in Container"): copies of the repository's `.devcontainer/devcontainer.json` and `Dockerfile` that you have read. The devcontainer is built from these copies (stage `dev`, with nothing but `.devcontainer/` as build context), and no container mounts the folder.

```text
~/.config/dev-kit/
├── bin/dev-kit-host                    the host side, from this repository
├── CLAUDE.md                           copy of ~/.claude/CLAUDE.md          → /var/lib/dev-kit/claude/CLAUDE.md
├── claude-code/                        managed Claude Code settings          → /etc/claude-code
└── myapp/                              the folder you open in VS Code
    ├── .devcontainer/devcontainer.json the repository's, copied after reading it
    ├── .devcontainer/Dockerfile        the repository's, copied after reading it
    ├── repository                      where dev-kit-host push pushes to
    └── etc/                            for myapp's container only           → /etc/dev-kit
        ├── deploy.env                  deploy settings
        ├── deploy-key, known_hosts     read-only deploy key and host keys for git fetch
```

The arrows are read-only mounts of their own, which hold even against root in the container; besides them and the volumes, dev-kit gives a container nothing from the host (VS Code adds its own, see below). Every devcontainer can read your `CLAUDE.md`.

A feature cannot run anything on the host, so `initializeCommand` calls [host/dev-kit-host](host/dev-kit-host) before the container starts:

```jsonc
"initializeCommand": "~/.config/dev-kit/bin/dev-kit-host prepare myapp git@github.com:example/myapp.git",
"build": { "dockerfile": "Dockerfile", "context": ".", "target": "dev" },
"workspaceMount": "source=myapp-workspace,target=/workspaces/myapp,type=volume",
"workspaceFolder": "/workspaces/myapp",
"mounts": [
    "source=${localEnv:HOME}/.config/dev-kit/CLAUDE.md,target=/var/lib/dev-kit/claude/CLAUDE.md,type=bind,readonly",
    "source=${localEnv:HOME}/.config/dev-kit/claude-code,target=/etc/claude-code,type=bind,readonly",
    "source=${localWorkspaceFolder}/etc,target=/etc/dev-kit,type=bind,readonly"
]
```

`dev-kit-host prepare <name> <repository>`, run in the host folder:

1. copies your `~/.claude/CLAUDE.md` (or an empty file, so the repository works for everyone) to `~/.config/dev-kit/CLAUDE.md`, and creates `~/.config/dev-kit/claude-code/` and `etc/` if they are missing, because a bind mount fails without its source,
2. clones the repository into the volume `<name>-workspace` if it holds none yet, with your SSH agent and only the host keys in your `~/.ssh/known_hosts` (a path on the host works too); it refuses while a container uses the volume, which could otherwise put hooks into the clone,
3. records the repository in `repository` for `dev-kit-host push` (and refuses to start if `initializeCommand` names another one than recorded: delete `repository` if the repository moved), and for an SSH repository creates the key `etc/deploy-key` if it is missing (add `etc/deploy-key.pub` to the repository as a read-only deploy key) and copies the server's host keys from your `~/.ssh/known_hosts` to `etc/known_hosts`,
4. warns if the repository's `.devcontainer/devcontainer.json` or `Dockerfile` differs from the copy here.

It reads the volume only in throwaway containers (`alpine/git`, pinned by digest) as UID 1000, without capabilities (except the one that hands a fresh volume to UID 1000) or new privileges (a setuid program left in the volume does nothing), without network except for cloning and pushing, and at most 1 MiB of a file within 20 seconds. Nothing from the volume runs on the host, and the host builds nothing from it.

**Setting up a repository:** take `host/dev-kit-host` from a release of dev-kit you have read and put it at `~/.config/dev-kit/bin/dev-kit-host` (executable). Copy the repository's `.devcontainer/devcontainer.json` and `Dockerfile` to `~/.config/dev-kit/<repository>/.devcontainer/`, read them (including the repository URL in `initializeCommand`: it is where `push` pushes to), then open that folder in VS Code and reopen it in the container. The names `bin` and `claude-code` are taken; two host folders with the same name share one volume.

**When the repository changes one of the two files:** `prepare` warns at the next start. In the host folder, `dev-kit-host diff myapp` shows the changes and `dev-kit-host show myapp devcontainer.json` (or `Dockerfile`) the repository's file, both with control characters made visible; read them and copy what you want into the copies here (`dev-kit-host show --raw myapp Dockerfile > .devcontainer/Dockerfile` takes a file over unchanged). That is the one moment code from the container reaches the host, so take your time: a `Dockerfile` decides as much about the next container as `devcontainer.json` does, and its `FROM` and `ARG` lines most quietly, since the base image's own `devcontainer.metadata` label comes with it.

**Keep the `devcontainer-lock.json`** that VS Code writes next to the copy: it pins every feature to the digest it was first built with, so a new release of a feature reaches the devcontainer only when you update the lock file (VS Code: "Dev Containers: Upgrade Lock File"), after reading what changed.

**The volume holds the only copy of what you have not pushed** (commits, branches, stashes, `.env`, test data). Push work in progress to a branch (`dev-kit-host push myapp wip`), keep test data that matters as sample data in the repository, and never clean up with `docker volume prune`.

**What VS Code adds:** it forwards your SSH agent into the container and the container's ports to your machine, copies your `~/.gitconfig` in, offers git credentials from the host, can open URLs from the container in your browser, and runs extensions there that work with what the container holds. Treat VS Code's connection as a convenience, not as a security boundary, and keep the agent free of keys that can push (next section).

### Signing in the devcontainer, pushing from the host

The devcontainer commits and signs; only you push, from the host, after seeing what goes out:

- **The forwarded agent holds only your signing key.** VS Code forwards the agent in `SSH_AUTH_SOCK` of your login shell. Put the key you sign commits with there, and your key for logging in to GitHub into an agent of its own, which ssh on the host uses for github.com:

    ```text
    # ~/.ssh/config
    Host github.com
        IdentityFile ~/.ssh/id_ed25519
        IdentitiesOnly yes
        AddKeysToAgent yes
        IdentityAgent ${XDG_RUNTIME_DIR}/ssh-auth-agent
    ```

    Register the signing key at GitHub as a signing key only, not for authentication. Then the container signs, but GitHub does not let it in.
- **git in the container fetches with a read-only deploy key**, `etc/deploy-key`, which only that container sees (`GIT_SSH_COMMAND` in `remoteEnv` of the examples). Do not give it write access: the container also holds the deploy webhook's secret, and a `main` it pushed itself would be deployed with whatever its `deploy/compose.yaml` asks for.
- **`dev-kit-host push myapp main v1.4.0`**, in the host folder, pushes branches and tags from the volume to the repository in `repository`: a throwaway container without network takes the refs over into a fresh repository on a volume of its own (nothing of the volume's git configuration or hooks applies; a name that is both a branch and a tag, or a tag that is no commit, is refused), another one shows every commit that is on no branch or tag of the remote yet, for each branch and each tag (a tag can bring commits that are on no branch: it warns about those), and the files they change, marking those that decide how the code is built, run or deployed (`.github/`, `.devcontainer/`, `deploy/`, `Dockerfile`, `justfile`, compose files). After you answer `y` it pushes exactly that, atomically, with the agent ssh on the host uses for that server. `--yes` skips the question. Read the files it marks in the volume's diff before you answer: a signed commit says only that the devcontainer signed it.

## The dev-kit command

`dev-kit help` lists the commands, `dev-kit help <command>` explains one.

### Releases

A repository keeps its changes under `## [Unreleased]` in `CHANGELOG.md` ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/)) and its version in exactly one place: `VERSION`, `package.json` or `pyproject.toml` in the top directory, or else a `version.go` with `Version = "x.y.z"` (the only one in the repository).

```sh
dev-kit release 1.4.0 -m "Shared playlists and a faster search"
dev-kit release --push
```

The first command works on `main` and pushes nothing. It checks that the working tree is clean, that 1.4.0 is greater than the current version, that there are entries under `[Unreleased]` and that `just check` passes (if the repository has that recipe; skip it with `--no-check`). If the repository has a `justfile` but `just` is not installed, it stops rather than release unchecked. Then it:

1. turns `## [Unreleased]` into `## [1.4.0] - <today>` above the entries and updates the compare links at the bottom, if there are any,
2. sets the version (through npm for `package.json`, so `package-lock.json` follows, and through uv for `pyproject.toml`, so `uv.lock` follows),
3. commits `chore: release 1.4.0` with the summary as body and tags `v1.4.0`, both signed if git has a signing key.

`dev-kit release --push` pushes `main` and the release tag on `HEAD` in one atomic push. A devcontainer that cannot push (see [Signing in the devcontainer, pushing from the host](#signing-in-the-devcontainer-pushing-from-the-host)) leaves that to the host: `dev-kit-host push myapp main v1.4.0`.

### Deploys

`dev-kit deploy` deploys a released `main` to the repository's Dockhand git stack, which follows `main` with auto-update off, so only this command (or someone in Dockhand) deploys:

1. It fetches `origin` and refuses unless `origin/main` carries a release tag `v<x.y.z>` that is on `origin` too. Forks, which deploy `main` without releases, use `dev-kit deploy --fork`. This check is a guardrail of the command, not of Dockhand: the webhook deploys whatever `main` is when Dockhand pulls it.
2. It calls the stack's webhook: a POST signed with HMAC-SHA256 in `X-Hub-Signature-256`, like a GitHub webhook. The secret never leaves the container, and neither the secret nor the signature appears in a command line. Dockhand pulls `main`, builds and starts the stack, and answers when it is done.
3. It waits until the app's health URL answers with the new version in its body (for `--fork`: until it answers at all).

The container needs no Dockhand token: the webhook can only redeploy that one stack.

**Settings** live on the host, outside of git, in the folder `etc/` of the repository's host folder: `~/.config/dev-kit/<repository>/etc/deploy.env` (see [config.example/deploy.env](config.example/deploy.env) and [Files from the host](#files-from-the-host)). It is read as `KEY=VALUE` data, nothing in it runs. The devcontainer mounts only that folder, read-only, at `/etc/dev-kit`, so a container sees only the settings of its own repository.

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

### Long commands and the prompt cache

Claude Code caches the conversation for a few minutes (5 by default, optionally an hour at a higher price per written token). A build or test suite that runs longer than that, as one tool call in the foreground, lets the cache expire: the next request writes the whole conversation again. `dev-kit job` runs such a command in the background instead and lets the agent wait for it in steps that are shorter than the cache's lifetime:

```text
$ dev-kit job start check 'just check'
started check, log: /tmp/dev-kit-jobs-1000/check.log
$ dev-kit job wait check
RUNNING check 240s 1834 lines
ok   tests/test_api.py::test_search
$ dev-kit job wait check
DONE check exit=0 391s
...the last 20 lines of the log
```

`wait` returns as soon as the command is done, and otherwise after `--max` seconds (default 240); each return is a tool call that keeps the cache warm. While the command runs it prints only two lines of the log, so the waiting adds little to the conversation; once it is done, the last 20 lines (`--lines`), and it exits with the command's exit code. Done means the exit code was written: a command that prints "DONE" itself cannot fool it. Running means a process of the job still holds its lock (`flock`), so a stale pid file after a crash or a container restart never makes an unrelated process count as the job. What `wait` shows from the log comes without control characters. `dev-kit job stop` ends the command with everything it started (TERM, after 10 seconds KILL), `dev-kit job list` shows all jobs and their logs.

Every wait reads the cached conversation once (a tenth of the normal price) and replaces a new write of all of it when the cache would have expired. That pays off for commands up to about 40 minutes; for longer ones, let the cache expire once.

Tell the agent in your `CLAUDE.md`, which every devcontainer gets from the host. The main agent and general-purpose subagents follow it; Claude Code's Explore subagents do not get `CLAUDE.md` and wait in the foreground. For example:

```markdown
## Long-running commands
- Commands that may run longer than 2 minutes (builds, test suites, installs, image pulls):
  `dev-kit job start <name> '<command>'`, then `dev-kit job wait <name>` with a Bash timeout of
  270000 ms, again and again right after each RUNNING, without other tool calls in between.
- On DONE, look at the log (`grep`, `tail`) instead of printing all of it.
- Commands that will run longer than 40 minutes: run them in the background and wait for the
  notification instead.
```

On the host, `src/dev-kit/bin/dev-kit` runs from a clone of this repository (`ln -s ~/git-repos/dev-kit/src/dev-kit/bin/dev-kit ~/.local/bin/dev-kit`, or any directory in `PATH`).

## License

[MIT](LICENSE)
