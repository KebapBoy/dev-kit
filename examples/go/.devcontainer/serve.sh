#!/bin/sh
# Dev server of the devcontainer: the app from the working tree at http://localhost:8000.
# Started by postStartCommand, log in /tmp/serve.log. Settings come from .env.
set -eu

cd "$(dirname "$0")/.."
exec just serve
