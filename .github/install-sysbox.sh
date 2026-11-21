#!/bin/sh
# Installs Sysbox on the runner for the GitHub workflows, so the feature tests can start the
# scenarios with "docker": true under the runtime sysbox-runc. The package restarts Docker, which
# is fine on a fresh runner without containers.
set -eu

version=0.7.1
# From the release page https://github.com/nestybox/sysbox/releases/tag/v0.7.1, section "Checksums"
sum=9d6d5484f980d0a17f86c492c1262015c2afb66280bdb97215b79fde6a0261c5
deb="sysbox-ce_$version.linux_amd64.deb"
tmp=$(mktemp -d)
curl -fsSL -o "$tmp/$deb" "https://github.com/nestybox/sysbox/releases/download/v$version/$deb"
echo "$sum  $tmp/$deb" | sha256sum -c -
chmod 0755 "$tmp"
chmod 0644 "$tmp/$deb"
sudo apt-get update -q
sudo apt-get install -y -q "$tmp/$deb"
rm -rf "$tmp"
docker info --format '{{json .Runtimes}}' | grep -q sysbox-runc
