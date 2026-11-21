#!/bin/sh
# Entrypoint of the dev-kit feature, run at every start of the container as the container user:
# starts dockerd if the feature installed Docker (option docker, marked by $ENABLED), and does
# nothing otherwise, also when the image has Docker from elsewhere.
# dockerd needs root, so another user runs this script again through sudo; the feature allows
# exactly that, without arguments, for the group docker. Docker inside a devcontainer needs the
# runtime sysbox-runc ("runArgs": ["--runtime=sysbox-runc"]); without it dockerd does not start.
set -u

SELF=/usr/local/share/dev-kit/docker-init.sh
ENABLED=/usr/local/share/dev-kit/docker-enabled
LOG=/var/log/dockerd.log

[ -e "$ENABLED" ] || exit 0

if [ "$(id -u)" != 0 ]; then
    exec sudo -n "$SELF"
fi

# As root, take nothing from the caller's environment
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root
unset DOCKER_HOST DOCKER_CONFIG DOCKER_CONTEXT

if docker info > /dev/null 2>&1; then
    exit 0
fi

# cgroup v2: dockerd can only hand controllers to its containers if no process is left in the
# root cgroup, so move them all to a child (as Docker's own dind script does)
if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
    {
        mkdir -p /sys/fs/cgroup/init
        xargs -rn1 < /sys/fs/cgroup/cgroup.procs > /sys/fs/cgroup/init/cgroup.procs
        sed -e 's/ / +/g' -e 's/^/+/' < /sys/fs/cgroup/cgroup.controllers \
            > /sys/fs/cgroup/cgroup.subtree_control
    } 2> /dev/null || :
fi

# Left over from the last run when the container restarts
rm -f /var/run/docker.pid

setsid dockerd > "$LOG" 2>&1 < /dev/null &

i=0
while [ "$i" -lt 30 ]; do
    if docker info > /dev/null 2>&1; then
        exit 0
    fi
    i=$((i + 1))
    sleep 1
done
echo "dev-kit: dockerd did not start, see $LOG. Docker in a devcontainer needs the runtime sysbox-runc." >&2
exit 1
