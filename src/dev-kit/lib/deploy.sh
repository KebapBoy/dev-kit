# shellcheck shell=bash
# dev-kit deploy: deploys the release on origin/main through the webhook of the repository's
# Dockhand git stack and waits until the app reports the new version.

DEPLOY_DEFAULT_CONFIG=/etc/dev-kit/deploy.env

deploy_usage() {
    cat << 'EOF'
Usage: dev-kit deploy [--fork] [--config <file>]

Deploys what is on origin/main:
  1. checks that origin/main is a release: it carries a tag v<x.y.z> that is on origin too (--fork:
     any commit, for forks, which deploy main without releases). This is a guardrail of the
     command; the webhook itself deploys whatever main is.
  2. calls the webhook of the git stack (POST, signed with HMAC-SHA256 like a GitHub webhook);
     the stack pulls main, builds and starts, and answers when it is done. If a proxy in front
     of Dockhand gives up waiting first (504 or 524, e.g. Cloudflare after 100 seconds),
     Dockhand keeps deploying: a release then counts as deployed once the health URL reports
     its version; without DEPLOY_HEALTH_URL, and for --fork, check the deploy in Dockhand.
  3. waits until the health URL answers and, for a release, reports its version

Settings come from /etc/dev-kit/deploy.env (or --config, or $DEV_KIT_CONFIG), KEY=VALUE lines:
  DEPLOY_WEBHOOK_URL     webhook of the stack, e.g. https://dockhand.example.com/api/git/stacks/1/webhook
  DEPLOY_WEBHOOK_SECRET  its secret
  DEPLOY_HEALTH_URL      optional: e.g. https://myapp.example.com/healthz
  DEPLOY_TIMEOUT         optional: seconds for the deploy and for the health check (default 600);
                         at least 100 behind Cloudflare, so the proxy gives up before dev-kit does
EOF
}

cmd_deploy() {
    local fork=false config="${DEV_KIT_CONFIG:-$DEPLOY_DEFAULT_CONFIG}"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --fork)
                fork=true
                shift
                ;;
            --config)
                [[ $# -ge 2 ]] || die "$1 needs a value"
                config=$2
                shift 2
                ;;
            -h | --help)
                deploy_usage
                return
                ;;
            *) die "unknown argument: $1" ;;
        esac
    done

    cd_repo_root
    deploy_load_config "$config"

    info "fetching origin"
    git fetch --quiet --tags origin main || die "cannot fetch origin"
    local commit version="" tag
    commit=$(git rev-parse origin/main)
    tag=$(git tag --points-at "$commit" --list 'v*' | sort -V | tail -n 1)
    if [[ "$fork" == true ]]; then
        info "deploying origin/main at ${commit:0:7}"
    else
        if [[ -z "$tag" ]] || ! is_version "${tag#v}"; then
            die "origin/main (${commit:0:7}) is not a release: release and push first (forks: --fork)"
        fi
        deploy_require_remote_tag "$tag" "$commit"
        version=${tag#v}
        info "deploying $version (origin/main at ${commit:0:7})"
    fi

    deploy_call_webhook "$commit" "$version"
    if [[ -n "$DEPLOY_HEALTH_URL" ]]; then
        deploy_wait_healthy "$version"
    else
        info "no DEPLOY_HEALTH_URL, not checking the app"
    fi
}

# Fails unless tag $1 is on origin and points at commit $2 (a local tag is not a release)
deploy_require_remote_tag() {
    local tag=$1 commit=$2 refs remote_commit
    refs=$(git ls-remote --tags origin "refs/tags/$tag" "refs/tags/$tag^{}") || die "cannot list the tags of origin"
    # An annotated tag is listed twice; the line with ^{} names its commit
    remote_commit=$(awk -v r="refs/tags/$tag^{}" '$2 == r { print $1 }' <<< "$refs")
    [[ -n "$remote_commit" ]] || remote_commit=$(awk -v r="refs/tags/$tag" '$2 == r { print $1 }' <<< "$refs")
    [[ "$remote_commit" == "$commit" ]] || die "$tag is not on origin at ${commit:0:7}; push it with: dev-kit release --push (or on the host: dev-kit-host push <name> main $tag)"
}

# Reads the settings from KEY=VALUE lines (no shell: nothing in the file runs). Errors name the line
# number, never its content, which may hold the secret.
deploy_load_config() {
    local file=$1 line key value number=0
    [[ -f "$file" ]] || die "no settings in $file (see: dev-kit help deploy)"
    DEPLOY_WEBHOOK_URL=""
    DEPLOY_WEBHOOK_SECRET=""
    DEPLOY_HEALTH_URL=""
    DEPLOY_TIMEOUT=600
    while IFS= read -r line || [[ -n "$line" ]]; do
        number=$((number + 1))
        line=${line%$'\r'}
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
        [[ "$line" =~ ^[[:space:]]*([A-Z_]+)[[:space:]]*=[[:space:]]*(.*)$ ]] \
            || die "$file, line $number: not KEY=VALUE"
        key=${BASH_REMATCH[1]}
        value=${BASH_REMATCH[2]}
        # Strip one pair of surrounding quotes
        if [[ "$value" =~ ^\"(.*)\"$ || "$value" =~ ^\'(.*)\'$ ]]; then
            value=${BASH_REMATCH[1]}
        fi
        case "$key" in
            DEPLOY_WEBHOOK_URL | DEPLOY_WEBHOOK_SECRET | DEPLOY_HEALTH_URL | DEPLOY_TIMEOUT)
                printf -v "$key" '%s' "$value"
                ;;
            *) info "$file, line $number: ignoring unknown setting $key" ;;
        esac
    done < "$file"
    [[ -n "$DEPLOY_WEBHOOK_URL" ]] || die "$file: DEPLOY_WEBHOOK_URL is missing"
    [[ -n "$DEPLOY_WEBHOOK_SECRET" ]] || die "$file: DEPLOY_WEBHOOK_SECRET is missing"
    [[ "$DEPLOY_WEBHOOK_URL" =~ ^https?:// ]] || die "$file: DEPLOY_WEBHOOK_URL is not an http(s) URL"
    [[ -z "$DEPLOY_HEALTH_URL" || "$DEPLOY_HEALTH_URL" =~ ^https?:// ]] \
        || die "$file: DEPLOY_HEALTH_URL is not an http(s) URL"
    [[ "$DEPLOY_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || die "$file: DEPLOY_TIMEOUT is not a number of seconds"
    if [[ "$DEPLOY_WEBHOOK_URL" == http://* ]]; then
        info "warning: the webhook URL is plain http; the request is signed, but anyone on the way can read and replay it"
    fi
    if [[ "$DEPLOY_HEALTH_URL" == http://* ]]; then
        info "warning: the health URL is plain http; anyone on the way can fake its answer"
    fi
}

# Prints the HMAC-SHA256 of stdin with the key $1, in hex. The key never appears in a command line
# (printf is a builtin; openssl and od read stdin), so other processes cannot see it.
deploy_hmac_sha256() {
    local key=$1 key_hex ipad="" opad="" i byte hex
    if [[ $(printf '%s' "$key" | wc -c) -gt 64 ]]; then
        key_hex=$(printf '%s' "$key" | openssl dgst -sha256 -r | cut -c1-64)
    else
        key_hex=$(printf '%s' "$key" | od -An -v -tx1 | tr -d ' \n')
    fi
    while [[ ${#key_hex} -lt 128 ]]; do
        key_hex+='00'
    done
    for ((i = 0; i < 128; i += 2)); do
        byte=$((16#${key_hex:i:2}))
        printf -v hex '\\x%02x' $((byte ^ 0x36))
        ipad+=$hex
        printf -v hex '\\x%02x' $((byte ^ 0x5c))
        opad+=$hex
    done
    {
        printf '%b' "$opad"
        {
            printf '%b' "$ipad"
            cat
        } | openssl dgst -sha256 -binary
    } | openssl dgst -sha256 -r | cut -c1-64
}

# Calls the webhook for commit $1 (release $2, empty for --fork) and fails unless the stack reports
# success, or a proxy gave up waiting and the health check can still tell: then it sets
# DEPLOY_PROXY_TIMEOUT. The signature header goes to curl through a file descriptor, not its
# command line: anyone who sees the signature can replay the request (the webhook has no replay
# protection). curl waits up to DEPLOY_TIMEOUT for the answer, as long as the deploy may take.
deploy_call_webhook() {
    local commit=$1 version=$2 body signature response status
    body=$(printf '{"ref":"refs/heads/main","after":"%s","sender":"dev-kit"}' "$commit")
    signature=$(printf '%s' "$body" | deploy_hmac_sha256 "$DEPLOY_WEBHOOK_SECRET")
    info "calling the webhook (Dockhand pulls, builds and starts the stack; this can take minutes)"
    response=$(curl --silent --show-error --max-time "$DEPLOY_TIMEOUT" \
        -H 'Content-Type: application/json' \
        -H @<(printf 'X-Hub-Signature-256: sha256=%s\n' "$signature") \
        --data-binary "$body" \
        --write-out '\n%{http_code}' \
        "$DEPLOY_WEBHOOK_URL") || die "webhook call failed"
    status=${response##*$'\n'}
    response=${response%$'\n'*}
    if [[ "$status" == 504 || "$status" == 524 ]]; then
        deploy_proxy_timeout "$status" "$version"
        return 0
    fi
    [[ "$status" == 2* ]] || die "webhook answered $status: ${response:0:500}"
    if [[ "$response" =~ \"success\"[[:space:]]*:[[:space:]]*false ]]; then
        die "the deploy failed: ${response:0:500}"
    fi
    if [[ "$response" =~ \"skipped\"[[:space:]]*:[[:space:]]*true ]]; then
        info "the stack skipped the deploy (already at this commit)"
    else
        info "the stack deployed"
    fi
}

# The webhook answered $1, a proxy's timeout (504, or Cloudflare's 524 after 100 seconds): the proxy
# gave up, but Dockhand most likely keeps deploying. Only the health URL reporting release $2 can
# tell whether it succeeds; without one there is nothing to wait for.
deploy_proxy_timeout() {
    local status=$1 version=$2 cause
    info "the webhook answered $status: a proxy in front of Dockhand gave up waiting, but Dockhand most likely keeps deploying"
    if [[ -z "$DEPLOY_HEALTH_URL" ]]; then
        cause="without DEPLOY_HEALTH_URL"
    elif [[ -z "$version" ]]; then
        cause="--fork deploys no version that the health URL could report, so"
    fi
    [[ -z "${cause:-}" ]] || die "$cause dev-kit cannot tell whether the deploy succeeds: check the stack in Dockhand"
    DEPLOY_PROXY_TIMEOUT=true
}

# Waits until the health URL answers, for a release with a body that contains version $1
deploy_wait_healthy() {
    local version=$1 deadline body="" pattern=""
    deadline=$((SECONDS + DEPLOY_TIMEOUT))
    if [[ -n "$version" ]]; then
        # The version on its own, not as part of a longer one (1.2.1 must not match 1.2.10)
        pattern="(^|[^0-9.])${version//./\\.}([^0-9.]|$)"
        info "waiting for $DEPLOY_HEALTH_URL to report $version"
    else
        info "waiting for $DEPLOY_HEALTH_URL"
    fi
    while ((SECONDS < deadline)); do
        if body=$(curl --silent --fail --max-time 10 "$DEPLOY_HEALTH_URL" 2> /dev/null); then
            if [[ -z "$pattern" ]] || grep -Eq "$pattern" <<< "$body"; then
                info "healthy${version:+, version $version}"
                return 0
            fi
        fi
        sleep 5
    done
    [[ "${DEPLOY_PROXY_TIMEOUT:-}" != true ]] \
        || die "not healthy with version $version after ${DEPLOY_TIMEOUT}s: check the deploy in Dockhand; last answer: ${body:0:200}"
    die "not healthy${version:+ with version $version} after ${DEPLOY_TIMEOUT}s; last answer: ${body:0:200}"
}
