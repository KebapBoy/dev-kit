# shellcheck shell=bash
# Helpers shared by the dev-kit commands (sourced, not run)

info() {
    printf 'dev-kit: %s\n' "$*" >&2
}

die() {
    printf 'dev-kit: %s\n' "$*" >&2
    exit 1
}

# Changes to the top directory of the git repository the command runs in
cd_repo_root() {
    local root
    root=$(git rev-parse --show-toplevel 2> /dev/null) || die "not inside a git repository"
    cd "$root" || die "cannot change to $root"
}

# Fails unless the working tree and the index are clean
require_clean_tree() {
    [[ -z "$(git status --porcelain)" ]] || die "the working tree has uncommitted changes"
}

# Fails unless the current branch is $1
require_branch() {
    local branch
    branch=$(git symbolic-ref --quiet --short HEAD) || die "not on a branch"
    [[ "$branch" == "$1" ]] || die "on branch $branch, not $1"
}

# True if $1 is a version x.y.z
is_version() {
    [[ "$1" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
}

# True if version $1 is greater than version $2
version_gt() {
    [[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" == "$1" ]]
}
