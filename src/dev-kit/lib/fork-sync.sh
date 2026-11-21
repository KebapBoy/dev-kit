# shellcheck shell=bash
# dev-kit fork-sync: shows what upstream has that this fork does not, and tries the merge without
# touching the working tree.

fork_sync_usage() {
    cat << 'EOF'
Usage: dev-kit fork-sync [--branch <branch>] [--to <ref>]

For a fork with a remote "upstream":
  1. fetches upstream: branches to upstream/*, tags to refs/upstream-tags/* (so they never mix
     with the fork's own tags)
  2. shows the upstream releases (tags) and commits that are not in HEAD yet, and how many commits
     the fork has of its own
  3. tries to merge upstream/<branch> (or --to <ref>, e.g. a release tag) into HEAD in memory
     (git merge-tree) and lists the files that would conflict

Nothing is merged and the working tree stays as it is. The last line is the result:
"result: up-to-date", "result: clean" or "result: conflicts".

--branch   upstream branch to compare with (default: upstream's default branch)
--to       what to merge instead of upstream/<branch>, e.g. an upstream release tag (v1.2.0)

Commit subjects and names come from upstream: control characters are removed before they are
shown.
EOF
}

cmd_fork_sync() {
    local branch="" target=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --branch | --to)
                [[ $# -ge 2 ]] || die "$1 needs a value"
                if [[ "$1" == --branch ]]; then
                    branch=$2
                else
                    target=$2
                fi
                shift 2
                ;;
            -h | --help)
                fork_sync_usage
                return
                ;;
            *) die "unknown argument: $1" ;;
        esac
    done

    cd_repo_root
    # Everything shown comes partly from upstream: no terminal control characters
    fork_sync_report "$branch" "$target" | LC_ALL=C tr -d '\000-\010\013-\037\177'
}

fork_sync_report() {
    local branch=$1 target=$2
    git remote get-url upstream > /dev/null 2>&1 \
        || die "no remote upstream; add it with: git remote add upstream <url of the original repository>"
    git merge-tree --write-tree HEAD HEAD > /dev/null 2>&1 || die "git 2.38 or newer is needed (merge-tree --write-tree)"

    info "fetching upstream"
    git fetch --quiet --no-tags upstream '+refs/heads/*:refs/remotes/upstream/*' \
        '+refs/tags/*:refs/upstream-tags/*' || die "cannot fetch upstream"
    if [[ -z "$branch" ]]; then
        git remote set-head upstream --auto > /dev/null 2>&1 || true
        branch=$(git rev-parse --abbrev-ref upstream/HEAD 2> /dev/null || true)
        branch=${branch#upstream/}
        if [[ -z "$branch" || "$branch" == HEAD ]]; then
            branch=main
            git rev-parse --quiet --verify upstream/main > /dev/null || branch=master
        fi
    fi
    git rev-parse --quiet --verify "upstream/$branch^{commit}" > /dev/null || die "no branch upstream/$branch"
    if [[ -z "$target" ]]; then
        target="upstream/$branch"
    elif git rev-parse --quiet --verify "refs/upstream-tags/$target^{commit}" > /dev/null; then
        target="refs/upstream-tags/$target"
    fi
    git rev-parse --quiet --verify "$target^{commit}" > /dev/null || die "unknown ref: $target"

    local upstream="upstream/$branch" base last behind ahead
    base=$(git merge-base HEAD "$upstream") || die "HEAD and $upstream have no common history"
    last=$(git for-each-ref --merged "$base" --sort=-version:refname --count=1 \
        --format='%(refname:strip=2)' refs/upstream-tags/)
    behind=$(git rev-list --count "HEAD..$upstream")
    ahead=$(git rev-list --count --no-merges "$upstream..HEAD")

    printf '%-22s %s\n' \
        "upstream:" "$(git remote get-url upstream | sed -E 's#://[^/@]*@#://#') ($branch)" \
        "$upstream:" "$(git log -1 --format='%h %cs %s' "$upstream")" \
        "last merged release:" "${last:-none} (merge base $(git log -1 --format='%h %cs' "$base"))" \
        "own commits:" "$ahead" \
        "new upstream commits:" "$behind"

    local tags
    tags=$(git for-each-ref --merged "$upstream" --no-merged HEAD --sort=-version:refname --count=20 \
        --format='%(refname:strip=2)' refs/upstream-tags/)
    if [[ -n "$tags" ]]; then
        echo
        echo "New upstream releases:"
        local tag_list
        mapfile -t tag_list <<< "$tags"
        printf '  %s\n' "${tag_list[@]}"
    fi
    if [[ "$behind" -gt 0 ]]; then
        echo
        echo "New upstream commits (without merges, newest first, at most 30):"
        git log --no-merges --format='  %h %cs %s' -n 30 "HEAD..$upstream"
    fi

    echo
    if git merge-base --is-ancestor "$target" HEAD; then
        echo "HEAD already contains $target."
        echo "result: up-to-date"
        return
    fi
    local output status=0
    output=$(git merge-tree --write-tree --name-only --no-messages HEAD "$target") || status=$?
    case "$status" in
        0)
            echo "Merging $target into HEAD has no conflicts. To merge: git merge $target"
            echo "result: clean"
            ;;
        1)
            echo "Merging $target into HEAD conflicts in:"
            # The first line is the id of the merged tree, the rest are the conflicting files
            tail -n +2 <<< "$output" | sed '/^$/d; s/^/  /'
            echo "To merge and resolve them: git merge $target"
            echo "result: conflicts"
            ;;
        *) die "git merge-tree failed: $output" ;;
    esac
}
