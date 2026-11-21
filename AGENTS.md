# AGENTS.md

Instructions for AI coding agents (and humans) working on this repository. How to use dev-kit is in [README.md](README.md).

## Project

dev-kit holds what a family of small self-hosted projects shares: things that must be the same everywhere are taken from here, not copied. It has no app of its own.

## Architecture

- Nothing in this repository knows a real installation. Everything specific to one (URLs, webhook secrets, the MCP servers someone uses) comes at runtime from configuration on the host, outside of git.

## Layout

| Path                                          | Purpose                                     |
| --------------------------------------------- | ------------------------------------------- |
| `VERSION`                                     | The version of dev-kit                      |
| `justfile`                                    | Development commands (see below)            |
| `.editorconfig`                               | Indentation, line endings and charset       |
| `README.md`, `AGENTS.md`, `CHANGELOG.md`      | Documentation                               |

## Development

| Command      | Does                                  |
| ------------ | ------------------------------------- |
| `just check` | All checks                            |

## Conventions

- This repository is public. Use `example.com`, `192.0.2.x` and generic names (`myapp`) in code, docs, tests and commit messages. Never commit real domains, IP addresses, user or host names, stack IDs, tokens or secrets.
- Identifiers, comments and docs in English. 4 spaces everywhere (also JSON, YAML, Markdown), tabs only where Go requires them.

## With every change

1. Add the change to `CHANGELOG.md` ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/)) under `## [Unreleased]`. A release turns that section into `## [x.y.z] - YYYY-MM-DD` under [Semantic Versioning](https://semver.org/spec/v2.0.0.html), sets `VERSION`, is committed as `chore: release x.y.z` and tagged `v<x.y.z>`. MAJOR for changes that need action from repositories using dev-kit, MINOR for new features, PATCH for fixes.
2. Update `README.md` when features, requirements or configuration change, and this file when the layout or the conventions change.
3. Check: `just check`.
4. Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/): `feat` (MINOR), `fix` (PATCH), `perf` (PATCH), `docs`, `refactor`, `test`, `ci` or `chore` (no release); `!` after the type plus a `BREAKING CHANGE:` footer for MAJOR. Imperative, lower-case subject up to 72 characters; the body says what changes for the user and why.
