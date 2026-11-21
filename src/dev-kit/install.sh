#!/bin/sh
# Installs the dev-kit feature (runs as root while the devcontainer image is built):
# packages, just, Claude Code for the remote user, the shared configuration directory and the
# dev-kit command, and with the option docker the Docker Engine. Works on Debian/Ubuntu (apt) and
# Alpine (apk).
set -eu

CLAUDE_CHANNEL="${CLAUDECHANNEL:-stable}"
JUST_VERSION="${JUSTVERSION:-1.59.0}"
DOCKER="${DOCKER:-false}"
REMOTE_USER="${_REMOTE_USER:-root}"
CONTAINER_USER="${_CONTAINER_USER:-root}"
CONFIG_DIR=/var/lib/dev-kit/claude
FEATURE_DIR=$(cd "$(dirname "$0")" && pwd)

# Checksums of the default just release (from its SHA256SUMS), pinned here. Another version is only
# checked against the SHA256SUMS of the same release, which guards against a broken download, not
# against a tampered release.
JUST_DEFAULT=1.59.0

just_default_sha256() {
    case "$1" in
        x86_64) echo 409044617b6f06517c1035e55ca38c8c856ff8b650e41bc2aa1ef82d5903a23e ;;
        aarch64) echo 23871b1702bfd550fb5f901778fd4290ecf2ee034a45a889fbe96d89b188086d ;;
    esac
}

# Docker from Docker's apt repository (Debian/Ubuntu): pinned versions and the checksum of the key
# that signs the repository (the same file for Debian and Ubuntu). On Alpine, Docker comes from
# the Alpine release.
DOCKER_ENGINE_VERSION=29.9.3
DOCKER_BUILDX_VERSION=0.38.1
DOCKER_COMPOSE_VERSION=5.7.0
CONTAINERD_VERSION=2.4.2-3
DOCKER_KEY_SHA256=1500c1f56fa9e26b9b8f42452a553675796ade0807cdce11975eb98170b3a570

log() {
    echo "dev-kit: $*"
}

fail() {
    echo "dev-kit: $*" >&2
    exit 1
}

case "$CLAUDE_CHANNEL" in
    stable | latest) ;;
    *) fail "claudeChannel must be stable or latest, not '$CLAUDE_CHANNEL'" ;;
esac
case "$DOCKER" in
    true | false) ;;
    *) fail "docker must be true or false, not '$DOCKER'" ;;
esac

# git and ssh-keygen (SSH-signed commits through the forwarded agent), curl for the installers and
# for deploy, openssl for the webhook signature, ripgrep for Claude Code (USE_BUILTIN_RIPGREP=0,
# so it works the same on glibc and musl), bash for the dev-kit command
if command -v apt-get > /dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends bash ca-certificates curl git openssh-client \
        openssl ripgrep
    rm -rf /var/lib/apt/lists/*
elif command -v apk > /dev/null; then
    # libgcc and libstdc++: the musl build of Claude Code needs them
    apk add --no-cache bash ca-certificates curl git libgcc libstdc++ openssh-client openssl \
        ripgrep
else
    fail "needs apt-get or apk"
fi

install_just() {
    case "$(uname -m)" in
        x86_64 | amd64) arch=x86_64 ;;
        aarch64 | arm64) arch=aarch64 ;;
        *) fail "just: unsupported architecture $(uname -m)" ;;
    esac
    name="just-$JUST_VERSION-$arch-unknown-linux-musl.tar.gz"
    url="https://github.com/casey/just/releases/download/$JUST_VERSION"
    tmp=$(mktemp -d)
    curl -fsSL -o "$tmp/$name" "$url/$name"
    if [ "$JUST_VERSION" = "$JUST_DEFAULT" ]; then
        sum=$(just_default_sha256 "$arch")
    else
        sum=$(curl -fsSL "$url/SHA256SUMS" | awk -v n="$name" '$2 == n { print $1 }')
        [ -n "$sum" ] || fail "just: no checksum for $name"
    fi
    echo "$sum  $tmp/$name" | sha256sum -c - > /dev/null || fail "just: checksum mismatch for $name"
    tar -xzf "$tmp/$name" -C "$tmp" just
    install -m 0755 "$tmp/just" /usr/local/bin/just
    rm -rf "$tmp"
    log "just $JUST_VERSION installed"
}

if [ "$JUST_VERSION" != "none" ]; then
    install_just
fi

# The full version of a package in the apt repository that starts with $2 (without epoch), e.g.
# 29.9.3 for 5:29.9.3-1~debian.13~trixie, or 2.4.2-3 for 2.4.2-3~debian.13~trixie
apt_version() {
    apt-cache madison "$1" | awk -v v="$2" '
        { s = $3; sub(/^[0-9]+:/, "", s) }
        index(s, v "-") == 1 || index(s, v "~") == 1 { print $3; exit }'
}

# Docker Engine, CLI, Buildx and Compose; dockerd is started by docker-init.sh (the feature's
# entrypoint). sudo lets the group docker run exactly that script as root: being in the group
# already means root in the container, so this adds no privilege.
install_docker() {
    if command -v apt-get > /dev/null; then
        # shellcheck source=/dev/null
        . /etc/os-release
        case "${ID:-}" in
            debian | ubuntu) ;;
            *) fail "docker: Docker's apt repository has no packages for ${ID:-this system}" ;;
        esac
        install -d -m 0755 /etc/apt/keyrings
        curl -fsSL -o /etc/apt/keyrings/docker.asc "https://download.docker.com/linux/$ID/gpg"
        echo "$DOCKER_KEY_SHA256  /etc/apt/keyrings/docker.asc" | sha256sum -c - > /dev/null \
            || fail "docker: checksum mismatch for the key of Docker's apt repository"
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc]" \
            "https://download.docker.com/linux/$ID $VERSION_CODENAME stable" \
            > /etc/apt/sources.list.d/docker.list
        apt-get update
        engine=$(apt_version docker-ce "$DOCKER_ENGINE_VERSION")
        cli=$(apt_version docker-ce-cli "$DOCKER_ENGINE_VERSION")
        buildx=$(apt_version docker-buildx-plugin "$DOCKER_BUILDX_VERSION")
        compose=$(apt_version docker-compose-plugin "$DOCKER_COMPOSE_VERSION")
        containerd=$(apt_version containerd.io "$CONTAINERD_VERSION")
        [ -n "$engine" ] && [ -n "$cli" ] && [ -n "$buildx" ] && [ -n "$compose" ] && [ -n "$containerd" ] \
            || fail "docker: the pinned versions are not in Docker's apt repository for $ID $VERSION_CODENAME"
        apt-get install -y --no-install-recommends "docker-ce=$engine" "docker-ce-cli=$cli" \
            "docker-buildx-plugin=$buildx" "docker-compose-plugin=$compose" "containerd.io=$containerd" sudo
        rm -rf /var/lib/apt/lists/*
    else
        apk add --no-cache docker docker-cli-buildx docker-cli-compose sudo
    fi
    for user in "$REMOTE_USER" "$CONTAINER_USER"; do
        if [ "$user" != root ] && id "$user" > /dev/null 2>&1; then
            if command -v usermod > /dev/null; then
                usermod -aG docker "$user"
            else
                addgroup "$user" docker
            fi
        fi
    done
    echo '%docker ALL=(root) NOPASSWD: /usr/local/share/dev-kit/docker-init.sh ""' \
        > /etc/sudoers.d/dev-kit-docker
    chmod 0440 /etc/sudoers.d/dev-kit-docker
    mkdir -p /usr/local/share/dev-kit
    : > /usr/local/share/dev-kit/docker-enabled
    log "Docker $(dockerd --version | sed 's/^Docker version \([^,]*\).*/\1/') installed"
}

if [ "$DOCKER" = true ]; then
    install_docker
fi

# Claude Code: native installer as the remote user (it installs to ~/.local and updates itself
# there); /usr/local/bin/claude makes it available whatever that user's PATH is
user_home=$(awk -F: -v u="$REMOTE_USER" '$1 == u { print $6 }' /etc/passwd)
user_id=$(awk -F: -v u="$REMOTE_USER" '$1 == u { print $3 ":" $4 }' /etc/passwd)
[ -n "$user_home" ] || fail "remote user '$REMOTE_USER' does not exist"
installer=$(mktemp)
curl -fsSL -o "$installer" https://claude.ai/install.sh
chmod 0755 "$installer"
if [ "$REMOTE_USER" = "root" ]; then
    bash "$installer" "$CLAUDE_CHANNEL"
else
    su "$REMOTE_USER" -s /bin/sh -c "bash '$installer' '$CLAUDE_CHANNEL'"
fi
rm -f "$installer"
ln -sf "$user_home/.local/bin/claude" /usr/local/bin/claude
log "Claude Code installed for $REMOTE_USER ($CLAUDE_CHANNEL)"

# The shared configuration: the volume dev-kit-claude is mounted here. Docker fills a new, empty
# volume from the image, so the directory must already belong to the remote user.
mkdir -p "$CONFIG_DIR"
chown "$user_id" "$CONFIG_DIR"
chmod 0700 "$CONFIG_DIR"

# The dev-kit command
version=$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$FEATURE_DIR/devcontainer-feature.json" | head -n 1)
mkdir -p /usr/local/lib/dev-kit
cp "$FEATURE_DIR"/lib/*.sh /usr/local/lib/dev-kit/
echo "$version" > /usr/local/lib/dev-kit/VERSION
install -m 0755 "$FEATURE_DIR/bin/dev-kit" /usr/local/bin/dev-kit
install -D -m 0755 "$FEATURE_DIR/docker-init.sh" /usr/local/share/dev-kit/docker-init.sh
log "dev-kit $version installed"
