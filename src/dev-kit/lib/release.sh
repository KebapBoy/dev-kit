# shellcheck shell=bash
# dev-kit release: turns [Unreleased] in CHANGELOG.md into a release (changelog, version, signed
# commit and tag), or pushes the release that HEAD is.

release_usage() {
    cat << 'EOF'
Usage: dev-kit release <x.y.z> -m <summary> [--no-check]
       dev-kit release --push

Prepares a release on main, without pushing:
  1. checks: clean working tree, version greater than the current one, entries under
     "## [Unreleased]" in CHANGELOG.md, "just check" (skip with --no-check)
  2. turns "## [Unreleased]" into "## [x.y.z] - YYYY-MM-DD" (and updates the compare links at the
     bottom, if there are any)
  3. sets the version in the repository's version source: VERSION, package.json (through npm) or
     pyproject.toml (through uv if it is there) in the top directory, or else the one version.go
     with Version = "x.y.z"
  4. commits "chore: release x.y.z" with the summary as body and tags v<x.y.z> (both signed if git
     has a signing key)

--push pushes main and the release tag on HEAD to origin, both or neither.
EOF
}

cmd_release() {
    local version="" summary="" push=false check=true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -m | --message)
                [[ $# -ge 2 ]] || die "$1 needs a value"
                summary=$2
                shift 2
                ;;
            --push)
                push=true
                shift
                ;;
            --no-check)
                check=false
                shift
                ;;
            -h | --help)
                release_usage
                return
                ;;
            -*) die "unknown option: $1" ;;
            *)
                [[ -z "$version" ]] || die "only one version, please"
                version=$1
                shift
                ;;
        esac
    done

    cd_repo_root
    if [[ "$push" == true ]]; then
        [[ -z "$version" && -z "$summary" ]] || die "--push takes no version or summary"
        release_push
        return
    fi

    [[ -n "$version" ]] || die "which version? dev-kit release <x.y.z> -m <summary>"
    is_version "$version" || die "not a version x.y.z: $version"
    [[ -n "$summary" ]] || die "a summary for the commit body is required: -m <summary>"
    require_branch main
    require_clean_tree
    ! git rev-parse --quiet --verify "refs/tags/v$version" > /dev/null || die "tag v$version exists already"

    local source current
    source=$(release_version_source)
    current=$(release_read_version "$source")
    is_version "$current" || die "$source: current version '$current' is not x.y.z"
    version_gt "$version" "$current" || die "$version is not greater than the current version $current"
    release_check_changelog

    if [[ "$check" == true ]]; then
        local recipes=""
        if [[ -f justfile ]] && command -v just > /dev/null; then
            recipes=$(just --summary 2> /dev/null || true)
        fi
        if [[ " $recipes " == *" check "* ]]; then
            info "running just check"
            just check || die "just check failed; fix it or release with --no-check"
        else
            info "no justfile with a check recipe, nothing to check"
        fi
    fi

    release_update_changelog "$version"
    release_write_version "$source" "$version"
    git add --update
    git commit --quiet -m "chore: release $version" -m "$summary"

    local sign=--annotate
    if [[ -n "$(git config --get user.signingkey || true)" ]]; then
        sign=--sign
    fi
    git tag "$sign" -m "v$version" -m "$summary" "v$version"
    info "released $version ($current -> $version, $source): commit $(git rev-parse --short HEAD), tag v$version"
    info "push with: dev-kit release --push"
}

# Pushes main and the release tag on HEAD, atomically
release_push() {
    require_branch main
    local tag
    tag=$(git tag --points-at HEAD --list 'v*' | sort -V | tail -n 1)
    [[ -n "$tag" ]] || die "HEAD has no release tag v<x.y.z>; run dev-kit release <x.y.z> first"
    [[ "$(git log -1 --format=%s)" == "chore: release ${tag#v}" ]] \
        || die "HEAD is not the release commit of $tag"
    git push --atomic origin main "refs/tags/$tag"
    info "pushed main and $tag"
}

# Prints the version source of the repository: VERSION, package.json or pyproject.toml in the top
# directory, or else the one version.go anywhere in it; fails if there is none or more than one
release_version_source() {
    local sources=() file
    [[ -f VERSION ]] && sources+=(VERSION)
    [[ -f package.json ]] && sources+=(package.json)
    [[ -f pyproject.toml ]] && sources+=(pyproject.toml)
    if [[ ${#sources[@]} -eq 0 ]]; then
        while IFS= read -r file; do
            sources+=("$file")
        done < <(git ls-files -- 'version.go' '*/version.go')
    fi
    [[ ${#sources[@]} -gt 0 ]] || die "no version source (VERSION, package.json, pyproject.toml or version.go)"
    [[ ${#sources[@]} -eq 1 ]] || die "more than one version source: ${sources[*]}"
    printf '%s\n' "${sources[0]}"
}

release_read_version() {
    case "$1" in
        VERSION)
            tr -d '[:space:]' < VERSION
            ;;
        package.json)
            command -v node > /dev/null || die "package.json: node is needed to read the version"
            node -p 'require("./package.json").version'
            ;;
        pyproject.toml)
            grep -Eq '^dynamic *=.*"version"' pyproject.toml && die "pyproject.toml: the version is dynamic"
            # version = "..." in the [project] table
            awk '/^\[/ { p = ($0 == "[project]") } p && /^version *= *"/ { sub(/^version *= *"/, ""); sub(/".*/, ""); print; exit }' pyproject.toml
            ;;
        *)
            release_go_versions "$1" | head -n 1
            ;;
    esac
}

# Prints every Version = "..." in a Go file; there must be exactly one
release_go_versions() {
    local found
    found=$(grep -oE '(^|[^A-Za-z0-9_])[Vv]ersion[[:space:]]*=[[:space:]]*"[^"]*"' "$1" | sed -E 's/.*"([^"]*)"$/\1/' || true)
    [[ $(printf '%s' "$found" | grep -c '') -eq 1 ]] || die "$1: needs exactly one Version = \"x.y.z\""
    printf '%s\n' "$found"
}

release_write_version() {
    local source=$1 version=$2
    case "$source" in
        VERSION)
            printf '%s\n' "$version" > VERSION
            ;;
        package.json)
            command -v npm > /dev/null || die "package.json: npm is needed to set the version"
            npm version "$version" --no-git-tag-version > /dev/null
            ;;
        pyproject.toml)
            if command -v uv > /dev/null; then
                uv version "$version" --no-sync > /dev/null
            else
                [[ ! -f uv.lock ]] || die "pyproject.toml: uv is needed to update uv.lock too"
                local tmp
                tmp=$(mktemp)
                awk -v v="$version" '/^\[/ { p = ($0 == "[project]") } p && !done && /^version *= *"/ { sub(/"[^"]*"/, "\"" v "\""); done = 1 } { print }' pyproject.toml > "$tmp"
                cat "$tmp" > pyproject.toml
                rm -f "$tmp"
            fi
            ;;
        *)
            release_go_versions "$source" > /dev/null
            sed -i -E "s/(^|[^A-Za-z0-9_])([Vv]ersion[[:space:]]*=[[:space:]]*\")[^\"]*(\")/\1\2$version\3/" "$source"
            ;;
    esac
    [[ "$(release_read_version "$source")" == "$version" ]] || die "$source: could not set the version"
}

# Fails unless CHANGELOG.md has entries under "## [Unreleased]"
release_check_changelog() {
    [[ -f CHANGELOG.md ]] || die "no CHANGELOG.md"
    grep -q '^## \[Unreleased\][[:space:]]*$' CHANGELOG.md || die "CHANGELOG.md has no \"## [Unreleased]\""
    # Lines between [Unreleased] and the next version, without blank lines and link references
    local entries
    entries=$(awk '/^## \[Unreleased\]/ { u = 1; next } u && /^## \[/ { exit } u && /^\[[^]]+\]: / { next } u && NF { print }' CHANGELOG.md)
    grep -q '^- ' <<< "$entries" || die "nothing to release: no entries under \"## [Unreleased]\" in CHANGELOG.md"
}

# Turns [Unreleased] into the release and updates the compare links at the bottom, if any:
#   [Unreleased]: <repo>/compare/vA...HEAD
# becomes
#   [Unreleased]: <repo>/compare/vB...HEAD
#   [B]: <repo>/compare/vA...vB
release_update_changelog() {
    local version=$1 today tmp
    today=$(date +%F)
    tmp=$(mktemp)
    awk -v v="$version" -v d="$today" '
        /^## \[Unreleased\][[:space:]]*$/ && !done {
            print "## [Unreleased]"
            print ""
            print "## [" v "] - " d
            done = 1
            next
        }
        /^\[Unreleased\]: .*\/compare\/.*\.\.\.HEAD[[:space:]]*$/ {
            line = $0
            sub(/^\[Unreleased\]: /, "", line)
            base = line
            sub(/\/compare\/.*/, "", base)
            prev = line
            sub(/.*\/compare\//, "", prev)
            sub(/\.\.\.HEAD.*/, "", prev)
            print "[Unreleased]: " base "/compare/v" v "...HEAD"
            print "[" v "]: " base "/compare/" prev "...v" v
            next
        }
        { print }
    ' CHANGELOG.md > "$tmp"
    cat "$tmp" > CHANGELOG.md
    rm -f "$tmp"
}
