#!/bin/sh
# Dev server of the devcontainer: the working tree with hot reload at http://localhost:5173.
# Started by postStartCommand, log in /tmp/serve.log. Settings come from .env.
set -eu

cd "$(dirname "$0")/.."
exec just serve
