#!/usr/bin/env bash
# Tests of host/dev-kit-host against a throwaway repository, with HOME in a temp directory. Needs
# Docker; creates and removes the volume dev-kit-test-workspace, the container dev-kit-test-holder
# and the volumes of push labelled dev-kit-host.push=dev-kit-test.
# shellcheck disable=SC2016 # commands for bash -c and the container, expanded there
set -euo pipefail

script=$(cd "$(dirname "$0")/.." && pwd)/host/dev-kit-host
image="alpine/git:v2.52.0@sha256:4a0e72d49596a1f5d3701aeedafdadc5c0da4062be4657c7bdc4017387f591cc"
tmp=$(mktemp -d)
failed=0

cleanup() {
    docker rm -f -v dev-kit-test-holder > /dev/null 2>&1 || :
    docker volume rm -f dev-kit-test-workspace > /dev/null 2>&1 || :
    push_volumes | xargs -r docker volume rm -f > /dev/null 2>&1 || :
    rm -rf "$tmp"
}
cleanup_and_report() {
    cleanup
    ((failed == 0)) || echo "test/host.sh: $failed check(s) failed" >&2
}
trap cleanup_and_report EXIT
docker rm -f -v dev-kit-test-holder > /dev/null 2>&1 || :
docker volume rm -f dev-kit-test-workspace > /dev/null 2>&1 || :

push_volumes() {
    docker volume ls -q --filter label=dev-kit-host.push=dev-kit-test
}

check() {
    local name=$1
    shift
    if "$@" > "$tmp/out" 2>&1; then
        echo "ok: $name"
    else
        echo "FAILED: $name" >&2
        sed 's/^/    /' "$tmp/out" >&2
        failed=$((failed + 1))
    fi
}

# Runs a command in the volume as the devcontainer user
in_volume() {
    docker run --rm --user 1000:1000 -v dev-kit-test-workspace:/src -w /src --entrypoint sh "$image" -c "$1"
}

prepare() {
    "$script" prepare dev-kit-test "$repo" > "$tmp/prepare.log" 2>&1 || {
        cat "$tmp/prepare.log"
        return 1
    }
}

export HOME="$tmp/home"
mkdir -p "$HOME/.claude" "$tmp/host/.devcontainer"
echo "# my rules" > "$HOME/.claude/CLAUDE.md"

# The repository (bare, to push to), with a devcontainer.json holding an escape character; the host
# copies both files
src="$tmp/src"
repo="$tmp/repo.git"
mkdir -p "$src/.devcontainer"
printf 'FROM scratch AS dev\n' > "$src/Dockerfile"
printf '{ "name": "test\033[31m" }\n' > "$src/.devcontainer/devcontainer.json"
git -C "$src" init -q -b main
git -C "$src" add -A
git -C "$src" -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false commit -qm test
git clone -q --bare "$src" "$repo"
cp "$src/.devcontainer/devcontainer.json" "$tmp/host/.devcontainer/devcontainer.json"
cp "$src/Dockerfile" "$tmp/host/.devcontainer/Dockerfile"
cd "$tmp/host"

first_run() {
    prepare && grep -q 'cloning' "$tmp/prepare.log" && ! grep -q 'warning' "$tmp/prepare.log" \
        && grep -q "recording the layout 'root'" "$tmp/prepare.log"
}
check "prepare clones without a warning" first_run
check "CLAUDE.md is copied" grep -qx '# my rules' "$HOME/.config/dev-kit/CLAUDE.md"
check "claude-code and etc exist" test -d "$HOME/.config/dev-kit/claude-code" -a -d etc
check "the clone belongs to UID 1000" in_volume 'test "$(stat -c %u . .git Dockerfile)" = "1000
1000
1000"'
check "the clone has no hooks" in_volume 'test -z "$(ls -A .git/hooks 2> /dev/null)"'
check "origin is the repository" in_volume "test \"\$(git remote get-url origin)\" = '$repo'"
second_run() {
    prepare && ! grep -q 'cloning' "$tmp/prepare.log"
}
check "a second prepare does not clone again" second_run
check "prepare records the repository" grep -qx "$repo" repository
moved() {
    ! "$script" prepare dev-kit-test /elsewhere > "$tmp/prepare.log" 2>&1 \
        && grep -q 'records another repository' "$tmp/prepare.log" && grep -qx "$repo" repository
}
check "prepare refuses another repository than the recorded one" moved

# push takes branches and tags from the volume to the recorded repository, whatever the volume's
# configuration says, and without its hooks
in_volume 'git -c user.name=test -c user.email=test@example.com commit -q --allow-empty -m "pushed commit" \
    && git tag v9.9.9 && git remote set-url origin /elsewhere \
    && mkdir -p .git/hooks && printf "#!/bin/sh\necho HOOKED\n" > .git/hooks/pre-push && chmod +x .git/hooks/pre-push'
pushes() {
    "$script" push --yes dev-kit-test main v9.9.9 > "$tmp/push.log" 2>&1 || {
        cat "$tmp/push.log"
        return 1
    }
    grep -q 'pushed commit' "$tmp/push.log" && ! grep -q HOOKED "$tmp/push.log" \
        && [[ $(git -C "$repo" log -1 --format=%s main) == "pushed commit" ]] \
        && git -C "$repo" rev-parse -q --verify refs/tags/v9.9.9 > /dev/null
}
check "push --yes pushes a branch and a tag to the recorded repository" pushes
check "push leaves no volume behind" test -z "$(push_volumes)"
asks() {
    local out
    out=$("$script" push dev-kit-test main < /dev/null 2>&1) && return 1
    [[ $out == *'needs a terminal'* ]]
}
check "push without --yes needs a terminal to ask" asks
check "push refuses a ref the volume does not have" bash -c '! "$1" push --yes dev-kit-test nothing' _ "$script"
check "push refuses an invalid ref" bash -c '! "$1" push --yes dev-kit-test ../x' _ "$script"

# push shows every commit it brings, also those only a tag brings, and the files they change
commit='git -c user.name=test -c user.email=test@example.com commit -q'
in_volume "$commit --allow-empty -m 'on main' && git checkout -q -b side && $commit --allow-empty -m 'hidden one' \
    && echo x > Dockerfile.side && git add Dockerfile.side && $commit -m 'hidden two' \
    && git -c user.name=test -c user.email=test@example.com tag -a -m release v9.9.10 \
    && git checkout -q main && git branch -q -D side"
shows_tag() {
    "$script" push --yes dev-kit-test main v9.9.10 > "$tmp/push.log" 2>&1 || {
        cat "$tmp/push.log"
        return 1
    }
    grep -q 'WARNING: the tag brings commits' "$tmp/push.log" && grep -q 'hidden one' "$tmp/push.log" \
        && grep -q 'hidden two' "$tmp/push.log" && grep -q '^  ! Dockerfile.side$' "$tmp/push.log" \
        && grep -q 'annotated by test: release' "$tmp/push.log" && grep -q '^  1 new commit(s):' "$tmp/push.log"
}
check "push shows the commits only a tag brings, and the files they change" shows_tag
in_volume "git checkout -q -b many && for i in \$(seq 25); do $commit --allow-empty -m \"many \$i\"; done \
    && git checkout -q main"
shows_all() {
    "$script" push --yes dev-kit-test many > "$tmp/push.log" 2>&1 || {
        cat "$tmp/push.log"
        return 1
    }
    grep -q '^branch many (new on the remote):' "$tmp/push.log" && grep -q '^  25 new commit(s):' "$tmp/push.log" \
        && grep -Eq 'many 1 +test' "$tmp/push.log" && grep -Eq 'many 25 +test' "$tmp/push.log" \
        && ! grep -q 'on main' "$tmp/push.log"
}
check "push shows every new commit of a new branch, and none the remote has" shows_all
refuses() {
    local setup=$1 ref=$2 message=$3
    in_volume "$setup"
    ! "$script" push --yes dev-kit-test "$ref" > "$tmp/push.log" 2>&1 && grep -q "$message" "$tmp/push.log"
}
check "push refuses a name that is a branch and a tag" refuses 'git tag both && git branch both' both 'a branch and a tag'
check "push matches ref names exactly" refuses 'git update-ref refs/x/refs/heads/ghost HEAD' ghost 'no branch or tag ghost'
check "push refuses a tag that is no commit" refuses 'git tag tree "HEAD^{tree}"' tree 'does not point to a commit'
in_volume "git config core.fsyncMethod \"\$(printf '\302\233')31m\""
escapes_stderr() {
    "$script" push --yes dev-kit-test main > "$tmp/push.log" 2>&1 || {
        cat "$tmp/push.log"
        return 1
    }
    grep -q fsyncMethod "$tmp/push.log" && grep -q "^  nothing new$" "$tmp/push.log" && ! grep -q $'\302\233' "$tmp/push.log"
}
check "push makes control characters on stderr visible" escapes_stderr
in_volume 'git config --unset core.fsyncMethod'
check "push leaves no volume behind after a refusal" test -z "$(push_volumes)"

# A release tag: push shows how the copies here differ from the tag's files before it asks, and
# after the push takes them over only when asked in a terminal, never with --yes, and never a file
# that cannot be read plainly
in_volume "git tag v9.9.11"
release_matches() {
    "$script" push --yes dev-kit-test main v9.9.11 > "$tmp/push.log" 2>&1 || {
        cat "$tmp/push.log"
        return 1
    }
    grep -q 'devcontainer.json: the same as .devcontainer/devcontainer.json in v9.9.11' "$tmp/push.log" \
        && grep -q 'nothing of v9.9.11 to take over' "$tmp/push.log"
}
check "push of a release whose files match the copies says so" release_matches
cp .devcontainer/devcontainer.json "$tmp/host-before.json"
in_volume "printf '{ \"name\": \"released\" }\n' > .devcontainer/devcontainer.json \
    && git add .devcontainer/devcontainer.json && $commit -m 'change the devcontainer' && git tag v9.9.12"
release_differs_yes() {
    "$script" push --yes dev-kit-test main v9.9.12 > "$tmp/push.log" 2>&1 || {
        cat "$tmp/push.log"
        return 1
    }
    grep -q '^+{ "name": "released" }$' "$tmp/push.log" && grep -q 'push --yes never takes them over' "$tmp/push.log" \
        && grep -q 'devcontainer.json: 1 line(s) added, 1 removed' "$tmp/push.log" \
        && [[ $(grep -n '^+{ "name": "released" }$' "$tmp/push.log" | cut -d: -f1) -lt $(grep -n 'never takes' "$tmp/push.log" | cut -d: -f1) ]] \
        && cmp -s .devcontainer/devcontainer.json "$tmp/host-before.json"
}
check "push --yes of a release shows how the copies differ but keeps them" release_differs_yes
# Runs push of main and $1 in a pseudo-terminal (script) and types $2 at once, then $3 when the
# question about the copies appears, if it does (nothing: the end of the input)
asked() {
    local pid
    rm -f "$tmp/in"
    mkfifo "$tmp/in"
    script -qec "\"$script\" push dev-kit-test main $1" /dev/null < "$tmp/in" > "$tmp/push.log" 2>&1 &
    pid=$!
    exec 3> "$tmp/in"
    printf '%s' "$2" >&3
    for _ in $(seq 240); do
        grep -q 'Take them over' "$tmp/push.log" && break
        kill -0 "$pid" 2> /dev/null || break
        sleep 0.5
    done
    # push may have ended without the question
    (
        trap '' PIPE
        printf '%s' "$3" >&3
    ) 2> /dev/null || :
    exec 3>&-
    wait "$pid"
}
release_declined() {
    asked v9.9.12 $'y\n' $'n\n' || {
        cat "$tmp/push.log"
        return 1
    }
    grep -q 'the copies here stay as they are' "$tmp/push.log" && cmp -s .devcontainer/devcontainer.json "$tmp/host-before.json"
}
check "push of a release keeps the copies when you decline" release_declined
release_typed_ahead() {
    asked v9.9.12 $'y\ny\n' '' || {
        cat "$tmp/push.log"
        return 1
    }
    grep -q 'the copies here stay as they are' "$tmp/push.log" && cmp -s .devcontainer/devcontainer.json "$tmp/host-before.json"
}
check "push of a release does not take an answer typed ahead" release_typed_ahead
release_taken_over() {
    asked v9.9.12 $'y\n' $'y\n' || {
        cat "$tmp/push.log"
        return 1
    }
    grep -q 'took .devcontainer/devcontainer.json of v9.9.12 over' "$tmp/push.log" \
        && [[ $(cat .devcontainer/devcontainer.json) == '{ "name": "released" }' ]] \
        && cmp -s .devcontainer/Dockerfile "$src/Dockerfile"
}
check "push of a release takes the tag's files over when you agree" release_taken_over
# Not offered: a link, a file with a NUL (diff would call it binary), a change too long to read
refused_release() {
    local tag=$1 setup=$2 message=$3
    in_volume "$setup && git add Dockerfile && $commit -m '$tag' && git tag $tag"
    asked "$tag" $'y\n' $'y\n' || {
        cat "$tmp/push.log"
        return 1
    }
    grep -q "$message" "$tmp/push.log" && grep -q "nothing of $tag to take over" "$tmp/push.log" \
        && cmp -s .devcontainer/Dockerfile "$src/Dockerfile"
}
check "push of a release takes over no symbolic link" \
    refused_release v9.9.13 'ln -sf /etc/passwd Dockerfile' 'Dockerfile in v9.9.13 is no regular file'
check "push of a release takes over no file with control characters" \
    refused_release v9.9.14 'rm -f Dockerfile && printf "# \000\nFROM scratch AS dev\nLABEL hidden=1\n" > Dockerfile' 'holds control characters'
check "push of a release takes over no change too long to read" \
    refused_release v9.9.15 'echo "FROM scratch AS dev" > Dockerfile && i=0 && while [ $i -lt 300 ]; do echo "# $i"; i=$((i + 1)); done >> Dockerfile' 'more than can be read'
in_volume "git checkout -q v9.9.12 -- Dockerfile && $commit -m 'back' && git tag v9.9.2 v9.9.11 && git branch v8.0.0"
check "push compares the highest release tag" \
    bash -c '"$1" push --yes dev-kit-test v9.9.15 v9.9.2 2>&1 | grep -q "devcontainer files of v9.9.15"' _ "$script"
check "push compares no branch named like a release" \
    bash -c 'out=$("$1" push --yes dev-kit-test v8.0.0 2>&1) && [[ $out != *"devcontainer files"* ]]' _ "$script"
check "push leaves no volume behind after a release" test -z "$(push_volumes)"
cp "$tmp/host-before.json" .devcontainer/devcontainer.json
# Without a release tag, a push of main is compared too (a change to the devcontainer alone needs
# no release); other branches are not
main_compared() {
    "$script" push --yes dev-kit-test main > "$tmp/push.log" 2>&1 || {
        cat "$tmp/push.log"
        return 1
    }
    grep -q 'the devcontainer files of main against the copies here' "$tmp/push.log" \
        && grep -q '^+{ "name": "released" }$' "$tmp/push.log" && grep -q 'push --yes never takes them over' "$tmp/push.log"
}
check "push of main shows how the copies differ" main_compared
check "push of another branch compares nothing" \
    bash -c 'out=$("$1" push --yes dev-kit-test many 2>&1) && [[ $out != *"devcontainer files"* ]]' _ "$script"

# The repository's files change: prepare warns, diff and show escape them
in_volume 'printf "{ \"runArgs\": [\"--privileged\"] }\n" > .devcontainer/devcontainer.json && echo "LABEL x=y" >> Dockerfile'
warns() {
    prepare
    grep -q "devcontainer.json differs" "$tmp/prepare.log" && grep -q "Dockerfile differs" "$tmp/prepare.log"
}
check "prepare warns about both changed files" warns
diff_shows() {
    local out
    out=$("$script" diff dev-kit-test) && return 1
    [[ $out == *'+{ "runArgs": ["--privileged"] }'* && $out == *'+LABEL x=y'* ]] \
        && [[ $out == *'^['* && $out != *$'\033'* ]]
}
check "diff shows both changes with control characters visible" diff_shows
in_volume 'printf "# \000\nLABEL hidden=1\n\tRUN true\n" > Dockerfile'
diff_shows_binary() {
    local out
    out=$("$script" diff dev-kit-test) && return 1
    [[ $out == *'+# ^@'* && $out == *'+LABEL hidden=1'* && $out == *'+^IRUN true'* && $out != *'Binary'* ]]
}
check "diff shows what a file with a NUL holds, and tabs" diff_shows_binary
in_volume 'printf "FROM scratch AS dev\nLABEL x=y\n" > Dockerfile'
in_volume 'printf "\033]0;title\007{}\n" > .devcontainer/devcontainer.json'
show_escapes() {
    [[ $("$script" show dev-kit-test devcontainer.json) == '^[]0;title^G{}' ]]
}
check "show makes control characters visible" show_escapes

# A fork keeps its own files next to upstream's: .devcontainer/Dockerfile, and both files in
# .devcontainer/fork/ when upstream has a devcontainer of its own. prepare records the layout in
# ./layout and refuses when the repository changes it; diff and show use the recorded one, so what
# the volume holds cannot change which files they compare
check "prepare records the layout" grep -qx root layout
in_volume 'printf "FROM scratch AS dev\nRUN true\n" > .devcontainer/Dockerfile'
layout_refused() {
    ! prepare && grep -q "now in the layout 'devcontainer', but ./layout records 'root'" "$tmp/prepare.log"
}
check "prepare refuses a layout the repository changed to" layout_refused
recorded_layout_used() {
    local out
    out=$("$script" diff dev-kit-test) && return 1
    [[ $out == *'+++ repository: Dockerfile'* && $out == *'+LABEL x=y'* && $out != *'RUN true'* ]]
}
check "diff compares the recorded layout, whatever the volume holds now" recorded_layout_used
rm layout
fork_dockerfile() {
    local out
    prepare && grep -qx devcontainer layout \
        && grep -q "repository's .devcontainer/Dockerfile differs" "$tmp/prepare.log" || return 1
    out=$("$script" diff dev-kit-test) && return 1
    [[ $out == *'+++ repository: .devcontainer/Dockerfile'* && $out == *'+RUN true'* && $out != *'LABEL x=y'* ]] \
        && [[ $out == *'+++ repository: .devcontainer/devcontainer.json'* ]] \
        && [[ $("$script" show dev-kit-test Dockerfile 2> "$tmp/shown.err") == $'FROM scratch AS dev\nRUN true' ]] \
        && grep -q 'showing .devcontainer/Dockerfile' "$tmp/shown.err"
}
check "with the layout devcontainer the fork's own Dockerfile is compared" fork_dockerfile
in_volume 'mkdir .devcontainer/fork && printf "{ \"name\": \"fork\" }\n" > .devcontainer/fork/devcontainer.json'
fork_directory() {
    local out
    ! prepare && grep -q "now in the layout 'fork', but ./layout records 'devcontainer'" "$tmp/prepare.log" || return 1
    echo fork > layout
    out=$("$script" diff dev-kit-test) && return 1
    [[ $out == *'+++ repository: .devcontainer/fork/devcontainer.json'* && $out == *'+++ repository: .devcontainer/fork/Dockerfile'* ]] \
        && [[ $("$script" show dev-kit-test devcontainer.json 2> /dev/null) == '{ "name": "fork" }' ]] \
        && ! "$script" show dev-kit-test Dockerfile 2> "$tmp/shown.err" \
        && grep -q 'cannot read .devcontainer/fork/Dockerfile' "$tmp/shown.err"
}
check "with the layout fork both files are taken from .devcontainer/fork/" fork_directory
in_volume 'rm -rf .devcontainer/fork .devcontainer/Dockerfile'
rm layout

# What the volume holds cannot make the reading container hang or grow
in_volume 'ln -sf /dev/zero .devcontainer/devcontainer.json && head -c 3000000 /dev/zero | tr "\0" x > Dockerfile'
limits() {
    local size
    ! timeout 60 "$script" show dev-kit-test devcontainer.json > "$tmp/shown" 2> /dev/null || return 1
    [[ ! -s $tmp/shown ]] || return 1
    size=$(timeout 60 "$script" show dev-kit-test Dockerfile | wc -c)
    ((size == 1048576))
}
check "show reads no devices and at most 1 MiB" limits

# No clone while a container uses the volume (it could put hooks into the clone)
in_volume 'rm -rf .git'
docker run -d --name dev-kit-test-holder -v dev-kit-test-workspace:/src --entrypoint sleep "$image" 60 > /dev/null
refuses_clone() {
    ! prepare && grep -q 'a container uses it' "$tmp/prepare.log"
}
check "prepare does not clone while a container uses the volume" refuses_clone
docker rm -f -v dev-kit-test-holder > /dev/null
refuses_leftovers() {
    ! prepare && grep -q 'has files but no repository' "$tmp/prepare.log" && ! grep -q 'cloning' "$tmp/prepare.log"
}
check "prepare does not clone into a volume with files" refuses_leftovers

# show --raw passes the file on unchanged, for saving it
in_volume 'rm -f .devcontainer/devcontainer.json && printf "{ \"name\": \"caf\303\251\" }\n" > .devcontainer/devcontainer.json'
raw() {
    "$script" show --raw dev-kit-test devcontainer.json > "$tmp/raw" && [[ $(cat "$tmp/raw") == '{ "name": "café" }' ]]
}
check "show --raw passes the file on unchanged" raw

# Refusals
check "diff and show of an unknown name create no volume" bash -c '! "$1" diff dev-kit-nothing && ! docker volume inspect dev-kit-nothing-workspace > /dev/null 2>&1' _ "$script"
check "an invalid name is refused" bash -c '! "$1" prepare "Bad Name" /x' _ "$script"
check "a taken name is refused" bash -c '! "$1" prepare claude-code /x' _ "$script"
check "outside of a host folder it refuses" bash -c 'cd / && ! "$1" diff dev-kit-test' _ "$script"

((failed == 0))
