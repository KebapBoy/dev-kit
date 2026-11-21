#!/bin/bash
# Default test of the feature (devcontainer features test): everything is installed and the shared
# configuration directory belongs to the remote user.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "claude runs" claude --version
check "just runs" just --version
check "git runs" git --version
check "ssh-keygen exists" bash -c "command -v ssh-keygen"
check "openssl runs" openssl version
check "ripgrep runs" rg --version
check "dev-kit shows its help" bash -c "dev-kit help | grep -q 'Usage: dev-kit'"
check "dev-kit knows its version" bash -c "dev-kit version | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'"
check "CLAUDE_CONFIG_DIR is set" test "$CLAUDE_CONFIG_DIR" = /var/lib/dev-kit/claude
check "the configuration directory is writable" bash -c "touch \"\$CLAUDE_CONFIG_DIR/.test\" && rm \"\$CLAUDE_CONFIG_DIR/.test\""

reportResults
