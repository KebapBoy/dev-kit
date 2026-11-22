#!/bin/sh
# Installs the same just release as the feature (version and checksum from src/dev-kit/install.sh)
# to /usr/local/bin, for the GitHub workflows and for hosts that run dev-kit release or the checks
set -eu

cd "$(dirname "$0")/.."
version=$(sed -n 's/^JUST_DEFAULT=//p' src/dev-kit/install.sh)
sum=$(sed -n '/^just_default_sha256()/,/^}/s/^ *x86_64) echo \([0-9a-f]*\) ;;$/\1/p' src/dev-kit/install.sh)
name="just-$version-x86_64-unknown-linux-musl.tar.gz"
tmp=$(mktemp -d)
curl -fsSL -o "$tmp/$name" "https://github.com/casey/just/releases/download/$version/$name"
echo "$sum  $tmp/$name" | sha256sum -c -
tar -xzf "$tmp/$name" -C "$tmp" just
sudo install -m 0755 "$tmp/just" /usr/local/bin/just
rm -rf "$tmp"
just --version
