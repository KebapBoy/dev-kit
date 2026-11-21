#!/bin/bash
# Checks of the option docker, for the scenarios docker-* (they run with the runtime sysbox-runc).
# With DEV_KIT_TEST_SUDO=narrow the container user has no root and no sudo of its own. Builds an
# image from scratch, so it needs no network.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

# Builds an image from scratch with one file, creates a container and copies the file back out
build_and_create() {
    local dir id
    dir=$(mktemp -d)
    echo dev-kit > "$dir/file"
    printf 'FROM scratch\nCOPY file /file\nCMD ["/file"]\n' > "$dir/Dockerfile"
    docker build -q -t dev-kit-test "$dir" > /dev/null
    id=$(docker create dev-kit-test)
    docker cp "$id:/file" "$dir/copy"
    docker rm "$id" > /dev/null
    docker rmi dev-kit-test > /dev/null
    cmp "$dir/file" "$dir/copy"
}

# The container counts as started before its entrypoint has started dockerd
wait_for_dockerd() {
    for _ in $(seq 60); do
        docker info > /dev/null 2>&1 && return 0
        sleep 1
    done
    return 1
}

check "dockerd answers within a minute" wait_for_dockerd
check "the remote user is in the group docker" bash -c "id -nG | tr ' ' '\n' | grep -qx docker"
check "docker runs" docker version
check "buildx runs" docker buildx version
check "compose runs" docker compose version
check "starting dockerd again changes nothing" /usr/local/share/dev-kit/docker-init.sh
check "an image builds and a container is created" build_and_create
if [[ "${DEV_KIT_TEST_SUDO:-}" == narrow ]]; then
    check "the container runs as a user other than root" \
        test "$(awk '/^Uid:/ { print $2 }' /proc/1/status)" != 0
    check "sudo allows nothing else" bash -c '! sudo -n true 2> /dev/null'
    check "sudo refuses docker-init.sh with arguments" \
        bash -c '! sudo -n /usr/local/share/dev-kit/docker-init.sh x 2> /dev/null'
fi
check "claude runs" claude --version
check "dev-kit shows its help" bash -c "dev-kit help | grep -q 'Usage: dev-kit'"

reportResults
