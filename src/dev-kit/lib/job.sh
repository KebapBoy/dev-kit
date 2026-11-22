# shellcheck shell=bash
# dev-kit job: runs a long command in the background and waits for it in short steps, so an agent
# calls a tool at least every few minutes while it waits and its prompt cache stays warm.

job_usage() {
    cat << 'EOF'
Usage: dev-kit job start <name> <command>
       dev-kit job wait <name> [--max <seconds>] [--lines <n>]
       dev-kit job stop <name>
       dev-kit job list

Runs a long command (build, test suite, install) in the background and waits for it in steps of
at most a few minutes. Meant for AI agents: each "wait" returns at the latest after --max seconds,
so the agent calls a tool again before its prompt cache expires, and right away when the command
is done.

start   Runs <command> with bash in the current directory, detached from the terminal, output
        (stdout and stderr) to <name>.log in the job directory. Refuses while a job of that name
        is still running.
wait    Waits until the job is done, but at most --max seconds (default 240), then prints one
        status line:
          RUNNING <name> <seconds>s <lines> lines   and the last 2 lines of the log
          DONE <name> exit=<code> <seconds>s        and the last --lines lines (default 20)
          DONE <name> exit=gone <seconds>s          the process ended without an exit code
                                                    (killed, container restarted)
          DONE <name> exit=stopped <seconds>s       stopped with "dev-kit job stop"
        Exits with the command's exit code once it is done, 0 while it runs.
stop    Stops the job and everything it started (TERM to its process group).
list    Shows every job with its status and log file.

<name>: lower-case letters, digits, ".", "_" and "-", up to 64 characters.
The job directory is $XDG_RUNTIME_DIR/dev-kit-jobs, or /tmp/dev-kit-jobs-<uid> without it.
EOF
}

cmd_job() {
    local sub="${1:-}"
    [[ $# -gt 0 ]] && shift
    case "$sub" in
        start) job_start "$@" ;;
        wait) job_wait "$@" ;;
        stop) job_stop "$@" ;;
        list) job_list "$@" ;;
        "" | -h | --help) job_usage ;;
        *)
            job_usage >&2
            die "unknown job command: $sub"
            ;;
    esac
}

# The job directory, created private to the user; fails if someone else owns it or it is a link
job_dir() {
    local dir
    if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
        dir="$XDG_RUNTIME_DIR/dev-kit-jobs"
    else
        dir="/tmp/dev-kit-jobs-$(id -u)"
    fi
    mkdir -m 0700 "$dir" 2> /dev/null || true
    [[ -d "$dir" && ! -L "$dir" && -O "$dir" ]] || die "job directory $dir is not a directory of $(id -un)"
    chmod 0700 "$dir"
    printf '%s\n' "$dir"
}

job_check_name() {
    [[ "$1" =~ ^[a-z0-9][a-z0-9._-]{0,63}$ ]] || die "invalid job name: '$1' (a-z, 0-9, '.', '_', '-')"
}

# True while a process of the job still holds its lock: the wrapper takes it before the command
# starts and every process of the job inherits it. A stale pid file alone never counts as running.
job_alive() {
    [[ -f "$1.lock" ]] || return 1
    ! flock -n "$1.lock" true 2> /dev/null
}

# The job's process group, read once and checked: never 0 or 1 (kill -1 reaches every process of
# the user)
job_pid() {
    local pid
    pid=$(cat "$1.pid" 2> /dev/null) || return 1
    [[ "$pid" =~ ^[1-9][0-9]*$ && "$pid" -gt 1 ]] || return 1
    printf '%s\n' "$pid"
}

# Marks the job done with $2 as exit code, unless it is marked already (ln fails if .exit exists)
job_mark_done() {
    local tmp
    tmp=$(mktemp "$1.exit.XXXXXX")
    printf '%s\n' "$2" > "$tmp"
    [[ -f "$1.end" ]] || date +%s > "$1.end"
    ln "$tmp" "$1.exit" 2> /dev/null || true
    rm -f "$tmp"
}

# The exit code as written, or "invalid" for anything else
job_exit_code() {
    local code
    code=$(cat "$1.exit" 2> /dev/null) || code=""
    [[ "$code" =~ ^([0-9]+|stopped)$ ]] || code=invalid
    printf '%s\n' "$code"
}

# The last $2 lines of the log without control characters: the log may come from code that a
# container controls, and must not reach the terminal as escape sequences
job_tail() {
    tail -n "$2" "$1.log" 2> /dev/null | LC_ALL=C tr -d '\000-\010\013-\037\177'
}

# Seconds from start to end, or to now while the job runs
job_elapsed() {
    local start end
    start=$(cat "$1.start" 2> /dev/null) || start=$(date +%s)
    end=$(cat "$1.end" 2> /dev/null) || end=$(date +%s)
    [[ "$start" =~ ^[0-9]+$ && "$end" =~ ^[0-9]+$ ]] || {
        echo "?"
        return
    }
    echo $((end - start))
}

job_start() {
    [[ $# -eq 2 ]] || die "usage: dev-kit job start <name> <command>"
    local name=$1 command=$2 dir base
    job_check_name "$name"
    [[ -n "$command" ]] || die "empty command"
    command -v flock > /dev/null || die "needs flock (util-linux or BusyBox)"
    dir=$(job_dir)
    base="$dir/$name"
    if job_alive "$base"; then
        die "job $name is still running (dev-kit job wait $name, or dev-kit job stop $name)"
    fi
    rm -f "$base.log" "$base.exit" "$base.pid" "$base.start" "$base.end"
    : > "$base.lock"
    date +%s > "$base.start"
    # The wrapper is the leader of a new session and process group: stop reaches everything the
    # command starts. It holds the lock (fd 9, inherited by the command) while the job runs, and
    # writes the exit code last and atomically, so a present .exit means done.
    # shellcheck disable=SC2016 # the script expands its own arguments
    setsid nohup bash -c '
        exec 9< "$0.lock"
        flock -n 9 || exit 1
        echo $$ > "$0.pid"
        bash -c "$1" > "$0.log" 2>&1 < /dev/null
        code=$?
        date +%s > "$0.end"
        tmp=$(mktemp "$0.exit.XXXXXX") && echo $code > "$tmp" && { ln "$tmp" "$0.exit" 2> /dev/null; rm -f "$tmp"; }
    ' "$base" "$command" < /dev/null > /dev/null 2>&1 &
    # Wait briefly for the pid, so stop and list work right after start
    local i
    for ((i = 0; i < 50; i++)); do
        [[ -s "$base.pid" ]] && break
        sleep 0.1
    done
    echo "started $name, log: $base.log"
}

job_wait() {
    [[ $# -ge 1 ]] || die "usage: dev-kit job wait <name> [--max <seconds>] [--lines <n>]"
    local name=$1 max=240 lines=20
    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max | --lines)
                [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || die "$1 needs a number"
                if [[ "$1" == --max ]]; then
                    max=$2
                else
                    lines=$2
                fi
                shift 2
                ;;
            *) die "unknown argument: $1" ;;
        esac
    done
    job_check_name "$name"
    local base
    base="$(job_dir)/$name"
    [[ -f "$base.start" ]] || die "no job $name"

    local end=$((SECONDS + max))
    while [[ ! -f "$base.exit" ]] && ((SECONDS < end)); do
        # No process holds the lock and there is no exit code: the job was killed
        job_alive "$base" || break
        sleep 1
    done

    if [[ -f "$base.exit" ]]; then
        local code
        code=$(job_exit_code "$base")
        echo "DONE $name exit=$code $(job_elapsed "$base")s"
        job_tail "$base" "$lines"
        if [[ "$code" =~ ^[0-9]+$ ]]; then
            return "$((code > 255 ? 1 : code))"
        fi
        return 1
    elif ! job_alive "$base"; then
        echo "DONE $name exit=gone $(job_elapsed "$base")s"
        job_tail "$base" "$lines"
        return 1
    fi
    echo "RUNNING $name $(job_elapsed "$base")s $(wc -l < "$base.log" | tr -d ' ') lines"
    job_tail "$base" 2
}

job_stop() {
    [[ $# -eq 1 ]] || die "usage: dev-kit job stop <name>"
    local name=$1 base pid
    job_check_name "$name"
    base="$(job_dir)/$name"
    [[ -f "$base.start" ]] || die "no job $name"
    if ! job_alive "$base" || ! pid=$(job_pid "$base"); then
        info "job $name is not running"
        return
    fi
    kill -TERM -- "-$pid" 2> /dev/null || true
    # Give the job 10 seconds to end, then KILL what is left of its process group
    local i
    for ((i = 0; i < 100; i++)); do
        job_alive "$base" || break
        sleep 0.1
    done
    if job_alive "$base"; then
        kill -KILL -- "-$pid" 2> /dev/null || true
        for ((i = 0; i < 50; i++)); do
            job_alive "$base" || break
            sleep 0.1
        done
    fi
    job_alive "$base" && die "job $name still runs (a process outside its process group holds its lock)"
    # If it finished on its own in the meantime, its own exit code stays
    job_mark_done "$base" stopped
    echo "stopped $name"
}

job_list() {
    local dir start base name status
    dir=$(job_dir)
    for start in "$dir"/*.start; do
        [[ -e "$start" ]] || continue
        base=${start%.start}
        name=${base##*/}
        if [[ -f "$base.exit" ]]; then
            status="exit=$(job_exit_code "$base")"
        elif job_alive "$base"; then
            status=running
        else
            status=gone
        fi
        printf '%-24s %-12s %6ss  %s\n' "$name" "$status" "$(job_elapsed "$base")" "$base.log"
    done
}
