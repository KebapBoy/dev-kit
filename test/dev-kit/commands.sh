# shellcheck shell=bash
# Tests of the dev-kit commands, sourced by test.sh after dev-container-features-test-lib. Each test
# works in a throwaway repository and never needs the network.

# A new repository on main with a CHANGELOG.md that has an entry under [Unreleased] and compare
# links; $1 is the remote it pushes to (a bare repository), if any
new_repo() {
    local dir
    dir=$(mktemp -d)
    git -C "$dir" init --quiet --initial-branch=main
    git -C "$dir" config user.name "Test"
    git -C "$dir" config user.email "test@example.com"
    git -C "$dir" config commit.gpgsign false
    git -C "$dir" config tag.gpgsign false
    cat > "$dir/CHANGELOG.md" << 'EOF'
# Changelog

## [Unreleased]

### Added

- Something new

## [0.1.0] - 2026-01-01

### Added

- The first version

[Unreleased]: https://example.com/myapp/compare/v0.1.0...HEAD
[0.1.0]: https://example.com/myapp/releases/tag/v0.1.0
EOF
    printf '%s\n' "$dir"
}

commit_all() {
    git -C "$1" add -A
    git -C "$1" commit --quiet -m "chore: test"
}

test_release_version_file() {
    local dir
    dir=$(new_repo)
    echo 0.1.0 > "$dir/VERSION"
    commit_all "$dir"
    (cd "$dir" && dev-kit release 0.2.0 -m "Something new" --no-check) || return 1
    [[ "$(cat "$dir/VERSION")" == 0.2.0 ]] \
        && grep -q "^## \[0.2.0\] - $(date +%F)$" "$dir/CHANGELOG.md" \
        && grep -q '^## \[Unreleased\]$' "$dir/CHANGELOG.md" \
        && grep -qF '[Unreleased]: https://example.com/myapp/compare/v0.2.0...HEAD' "$dir/CHANGELOG.md" \
        && grep -qF '[0.2.0]: https://example.com/myapp/compare/v0.1.0...v0.2.0' "$dir/CHANGELOG.md" \
        && [[ "$(git -C "$dir" log -1 --format=%s)" == "chore: release 0.2.0" ]] \
        && [[ "$(git -C "$dir" log -1 --format=%b | head -n 1)" == "Something new" ]] \
        && [[ "$(git -C "$dir" rev-parse 'v0.2.0^{commit}')" == "$(git -C "$dir" rev-parse HEAD)" ]] \
        && [[ -z "$(git -C "$dir" status --porcelain)" ]]
}

test_release_pyproject() {
    local dir
    dir=$(new_repo)
    printf '[project]\nname = "myapp"\nversion = "0.1.0"\n\n[tool.other]\nversion = "9.9.9"\n' > "$dir/pyproject.toml"
    commit_all "$dir"
    (cd "$dir" && dev-kit release 1.0.0 -m "First stable" --no-check) || return 1
    grep -q '^version = "1.0.0"$' "$dir/pyproject.toml" && grep -q '^version = "9.9.9"$' "$dir/pyproject.toml"
}

test_release_version_go() {
    local dir
    dir=$(new_repo)
    mkdir -p "$dir/internal/version"
    printf 'package version\n\n// Version of the app\nconst Version = "0.1.0"\n\nconst GoVersion = "1.0"\n' > "$dir/internal/version/version.go"
    commit_all "$dir"
    (cd "$dir" && dev-kit release 0.1.1 -m "A fix" --no-check) || return 1
    grep -q '^const Version = "0.1.1"$' "$dir/internal/version/version.go" \
        && grep -q '^const GoVersion = "1.0"$' "$dir/internal/version/version.go"
}

# A VERSION in the top directory wins over a version.go elsewhere (e.g. in an example)
test_release_top_level_wins() {
    local dir
    dir=$(new_repo)
    echo 0.1.0 > "$dir/VERSION"
    mkdir -p "$dir/examples/go"
    printf 'package version\n\nconst Version = "0.1.0"\n' > "$dir/examples/go/version.go"
    commit_all "$dir"
    (cd "$dir" && dev-kit release 0.2.0 -m "Something new" --no-check) || return 1
    [[ "$(cat "$dir/VERSION")" == 0.2.0 ]] && grep -q '"0.1.0"' "$dir/examples/go/version.go"
}

# Each of these must fail and leave the repository as it was
test_release_refuses() {
    local dir head
    dir=$(new_repo)
    echo 0.1.0 > "$dir/VERSION"
    commit_all "$dir"
    head=$(git -C "$dir" rev-parse HEAD)
    cd "$dir" || return 1
    ! dev-kit release 0.1.0 -m "Same version" --no-check || return 1
    ! dev-kit release 0.2 -m "Not x.y.z" --no-check || return 1
    ! dev-kit release 0.2.0 --no-check || return 1
    echo change >> VERSION
    ! dev-kit release 0.2.0 -m "Dirty tree" --no-check || return 1
    git checkout --quiet VERSION
    git checkout --quiet -b feature
    ! dev-kit release 0.2.0 -m "Not on main" --no-check || return 1
    git checkout --quiet main
    sed -i '/^- Something new$/d' CHANGELOG.md
    git commit --quiet -am "chore: empty unreleased"
    head=$(git rev-parse HEAD)
    ! dev-kit release 0.2.0 -m "Nothing to release" --no-check || return 1
    echo 1.0.0 > package.json
    git add package.json
    git commit --quiet -m "chore: second source"
    head=$(git rev-parse HEAD)
    ! dev-kit release 0.2.0 -m "Two sources" --no-check || return 1
    cd - > /dev/null || return 1
    [[ "$(git -C "$dir" rev-parse HEAD)" == "$head" && -z "$(git -C "$dir" tag)" ]]
}

test_release_push() {
    local dir remote
    remote=$(mktemp -d)
    git init --quiet --bare "$remote"
    dir=$(new_repo)
    git -C "$dir" remote add origin "$remote"
    echo 0.1.0 > "$dir/VERSION"
    commit_all "$dir"
    cd "$dir" || return 1
    ! dev-kit release --push || return 1
    dev-kit release 0.2.0 -m "Something new" --no-check || return 1
    dev-kit release --push || return 1
    cd - > /dev/null || return 1
    [[ "$(git -C "$remote" rev-parse main)" == "$(git -C "$dir" rev-parse HEAD)" ]] \
        && git -C "$remote" rev-parse --quiet --verify refs/tags/v0.2.0 > /dev/null
}

# Runs bash code with a command file loaded: lib_run <command> <code> [<argument>...]; the code
# sees the arguments as $1, $2, ...
lib_run() {
    local command=$1 code=$2
    shift 2
    bash -c "set -euo pipefail; source /usr/local/lib/dev-kit/common.sh; source /usr/local/lib/dev-kit/$command.sh; $code" \
        _ "$@"
}

# The HMAC of deploy matches openssl's, also for a key longer than a block and for key bytes that
# turn into zero bytes
test_deploy_hmac() {
    local key ours theirs
    for key in s3cret 6666 "$(printf 'k%.0s' {1..80})"; do
        # shellcheck disable=SC2016 # expanded by lib_run
        ours=$(printf '%s' '{"a":1}' | lib_run deploy 'deploy_hmac_sha256 "$1"' "$key")
        theirs=$(printf '%s' '{"a":1}' | openssl dgst -sha256 -hmac "$key" -r | cut -c1-64)
        [[ ${#ours} -eq 64 && "$ours" == "$theirs" ]] || return 1
    done
}

# The settings file is data: quotes are stripped, nothing in it runs, the secret is required
test_deploy_config() {
    local dir
    dir=$(mktemp -d)
    {
        echo '# comment'
        echo 'DEPLOY_WEBHOOK_URL=https://dockhand.example.com/api/git/stacks/1/webhook'
        echo "DEPLOY_WEBHOOK_SECRET=\"\$(touch $dir/ran)\""
        echo "DEPLOY_TIMEOUT='30'"
        echo 'OTHER=1'
    } > "$dir/deploy.env"
    # shellcheck disable=SC2016 # expanded by lib_run
    lib_run deploy 'deploy_load_config "$1" && printf "%s|%s" "$DEPLOY_WEBHOOK_SECRET" "$DEPLOY_TIMEOUT"' \
        "$dir/deploy.env" > "$dir/out" 2> /dev/null || return 1
    [[ "$(cat "$dir/out")" == "\$(touch $dir/ran)|30" && ! -e "$dir/ran" ]] || return 1
    echo 'DEPLOY_WEBHOOK_URL=https://dockhand.example.com/x' > "$dir/deploy.env"
    # shellcheck disable=SC2016 # expanded by lib_run
    ! lib_run deploy 'deploy_load_config "$1"' "$dir/deploy.env" 2> /dev/null || return 1
    # A broken line is reported by its number, never with its content
    printf 'DEPLOY_WEBHOOK_URL=https://dockhand.example.com/x\nDEPLOY_WEBHOOK_SECRET: hidden-value\n' > "$dir/deploy.env"
    # shellcheck disable=SC2016 # expanded by lib_run
    ! lib_run deploy 'deploy_load_config "$1"' "$dir/deploy.env" 2> "$dir/err" || return 1
    grep -q 'line 2' "$dir/err" && ! grep -q hidden-value "$dir/err"
}

# deploy refuses an origin/main without a release tag, before it calls the webhook
test_deploy_refuses_unreleased() {
    local dir remote
    remote=$(mktemp -d)
    git init --quiet --bare "$remote"
    dir=$(new_repo)
    git -C "$dir" remote add origin "$remote"
    commit_all "$dir"
    git -C "$dir" push --quiet origin main
    printf 'DEPLOY_WEBHOOK_URL=https://192.0.2.1/webhook\nDEPLOY_WEBHOOK_SECRET=x\n' > "$dir.env"
    (cd "$dir" && ! dev-kit deploy --config "$dir.env" 2> "$dir.err") && grep -q 'is not a release' "$dir.err" || return 1
    # A release tag that is only local is not a release either
    git -C "$dir" tag -a v1.0.0 -m v1.0.0
    (cd "$dir" && ! dev-kit deploy --config "$dir.env" 2> "$dir.err") && grep -q 'is not on origin' "$dir.err"
}

# An upstream repository with a release v1.0.0 and a fork of it with a commit of its own
new_fork() {
    local upstream fork
    upstream=$(new_repo)
    printf 'line 1\nline 2\n' > "$upstream/app.txt"
    commit_all "$upstream"
    git -C "$upstream" tag v1.0.0
    fork=$(mktemp -d)
    git clone --quiet "$upstream" "$fork"
    git -C "$fork" remote rename origin upstream
    git -C "$fork" config user.name "Test"
    git -C "$fork" config user.email "test@example.com"
    git -C "$fork" config commit.gpgsign false
    echo "fork" > "$fork/fork.txt"
    commit_all "$fork"
    printf '%s %s\n' "$upstream" "$fork"
}

test_fork_sync() {
    local upstream fork out
    read -r upstream fork <<< "$(new_fork)"
    cd "$fork" || return 1
    out=$(dev-kit fork-sync 2> /dev/null) || return 1
    grep -q '^result: up-to-date$' <<< "$out" || return 1

    # upstream releases v1.1.0 with a change the fork does not touch
    echo "new" > "$upstream/new.txt"
    commit_all "$upstream"
    git -C "$upstream" tag v1.1.0
    out=$(dev-kit fork-sync 2> /dev/null) || return 1
    grep -q '^  v1.1.0$' <<< "$out" && grep -q '^result: clean$' <<< "$out" \
        && grep -q 'last merged release: *v1.0.0' <<< "$out" || return 1

    # both change the same line
    sed -i 's/line 1/upstream/' "$upstream/app.txt"
    commit_all "$upstream"
    sed -i 's/line 1/fork/' app.txt
    git commit --quiet -am "chore: fork change"
    out=$(dev-kit fork-sync 2> /dev/null) || return 1
    grep -q '^  app.txt$' <<< "$out" && grep -q '^result: conflicts$' <<< "$out" || return 1
    # --to the release before the conflict merges cleanly
    out=$(dev-kit fork-sync --to v1.1.0 2> /dev/null) || return 1
    grep -q '^result: clean$' <<< "$out" || return 1
    # upstream tags stay out of the fork's own tags
    [[ -z "$(git tag --list v1.1.0)" ]] || return 1
    # control characters from upstream never reach the terminal
    git -C "$upstream" commit --quiet --allow-empty -m "$(printf 'evil \033]52;c;eA==\a subject')"
    out=$(dev-kit fork-sync 2> /dev/null) || return 1
    grep -q 'evil .*subject' <<< "$out" && ! grep -q $'\033' <<< "$out" || return 1
    # nothing was merged
    [[ -z "$(git status --porcelain)" ]] && ! git merge-base --is-ancestor refs/upstream-tags/v1.1.0 HEAD
    local status=$?
    cd - > /dev/null || return 1
    return $status
}

test_fork_sync_needs_upstream() {
    local dir
    dir=$(new_repo)
    commit_all "$dir"
    (cd "$dir" && ! dev-kit fork-sync 2> /dev/null)
}

test_job_wait() {
    local name="test-$$-wait" out
    dev-kit job start "$name" 'echo first; sleep 3; echo last; exit 3' > /dev/null || return 1
    # wait returns after --max while the job runs, with exit code 0
    out=$(dev-kit job wait "$name" --max 1) || return 1
    grep -q "^RUNNING $name " <<< "$out" && grep -q '^first$' <<< "$out" || return 1
    # and with the job's exit code once it is done
    out=$(dev-kit job wait "$name" --max 30)
    [[ $? -eq 3 ]] && grep -q "^DONE $name exit=3 " <<< "$out" && grep -q '^last$' <<< "$out"
}

test_job_stop() {
    local name="test-$$-stop" log pid out
    log=$(dev-kit job start "$name" 'sleep 300 & sleep 300') || return 1
    # a second job of the same name is refused while the first runs
    dev-kit job start "$name" true > /dev/null 2>&1 && return 1
    # start prints "started <name>, log: <dir>/<name>.log"; the pid is in <dir>/<name>.pid
    log=${log##*log: }
    pid=$(cat "${log%.log}.pid") || return 1
    dev-kit job stop "$name" > /dev/null || return 1
    sleep 1
    # nothing of the job's process group is left
    ! kill -0 -- "-$pid" 2> /dev/null || return 1
    out=$(dev-kit job wait "$name" --max 5) && return 1
    grep -q "^DONE $name exit=stopped " <<< "$out"
}

test_job_stale_pid() {
    local name="test-$$-stale" log pid other out
    log=$(dev-kit job start "$name" 'sleep 300') || return 1
    log=${log##*log: }
    pid=$(cat "${log%.log}.pid") || return 1
    # the job dies without an exit code, and its pid file now names an unrelated process group
    kill -KILL -- "-$pid"
    # shellcheck disable=SC2016 # expanded by the inner shell
    setsid sh -c 'echo $$ > "$1"; exec sleep 300' sh "${log%.log}.pid" < /dev/null > /dev/null 2>&1 &
    sleep 0.5
    other=$(cat "${log%.log}.pid") || return 1
    out=$(dev-kit job wait "$name" --max 5) && return 1
    grep -q "^DONE $name exit=gone " <<< "$out" || return 1
    dev-kit job stop "$name" > /dev/null 2>&1
    # the unrelated process survives
    kill -0 "$other" 2> /dev/null || return 1
    kill "$other"
}

test_job_control_characters() {
    local name="test-$$-ctl" out
    dev-kit job start "$name" "printf 'a\\033]0;title\\007b\\n'" > /dev/null || return 1
    out=$(dev-kit job wait "$name" --max 10) || return 1
    grep -q '^a\]0;titleb$' <<< "$out" && ! grep -q $'\033' <<< "$out"
}

test_job_refuses() {
    ! dev-kit job start 'Bad/name' true 2> /dev/null \
        && ! dev-kit job wait "test-$$-missing" 2> /dev/null \
        && ! dev-kit job wait "test-$$-missing" --max x 2> /dev/null
}

check "release: VERSION, changelog, commit and tag" test_release_version_file
check "release: pyproject.toml without uv" test_release_pyproject
check "release: version.go" test_release_version_go
check "release: a top-level source wins over version.go" test_release_top_level_wins
check "release: refuses what it must not release" test_release_refuses
check "release: --push pushes main and the tag" test_release_push
check "deploy: HMAC-SHA256 like openssl" test_deploy_hmac
check "deploy: the settings are data, not code" test_deploy_config
check "deploy: refuses an unreleased origin/main" test_deploy_refuses_unreleased
check "fork-sync: releases, commits, clean and conflicting merges" test_fork_sync
check "fork-sync: needs a remote upstream" test_fork_sync_needs_upstream
check "job: wait returns while running and with the exit code when done" test_job_wait
check "job: stop ends the whole process group" test_job_stop
check "job: refuses bad names and unknown jobs" test_job_refuses
check "job: a stale pid file never stops an unrelated process" test_job_stale_pid
check "job: no control characters from the log reach the terminal" test_job_control_characters
