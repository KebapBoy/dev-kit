#!/bin/bash
# justVersion "none": no just, everything else is there
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "just is not installed" bash -c "! command -v just"
check "claude runs" claude --version
check "dev-kit shows its help" bash -c "dev-kit help | grep -q 'Usage: dev-kit'"

reportResults
