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

check "release: VERSION, changelog, commit and tag" test_release_version_file
check "release: pyproject.toml without uv" test_release_pyproject
check "release: version.go" test_release_version_go
check "release: a top-level source wins over version.go" test_release_top_level_wins
check "release: refuses what it must not release" test_release_refuses
check "release: --push pushes main and the tag" test_release_push
