# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Devcontainer feature `ghcr.io/kebapboy/dev-kit/dev-kit`: Claude Code (native installer, channel `stable` or `latest`) with the VS Code extension, git, ssh-keygen for signed commits, just, curl, openssl and ripgrep, on Debian- and Alpine-based images. All devcontainers with the feature share one Claude Code configuration in the volume `dev-kit-claude`, so you sign in and set up MCP servers once.
