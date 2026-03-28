#!/bin/bash
set -e

log() {
    echo "[runner-init] $*"
}

error() {
    echo "[runner-init] ERROR: $*" >&2
}

log "Starting GitHub Actions runner in scope: ${RUNNER_SCOPE:-user}"

if [ "${RUNNER_SCOPE}" = "org" ]; then
    log "Mode: org-level (native myoung34/github-runner support)"
    log "Org: ${ORG_NAME:-$GITHUB_USERNAME}"
    log "Registering with native org mode..."
    exec /entrypoint.sh "$@"
fi

# Default: user mode
log "Mode: user-level (undocumented user scope via personal API)"

if [ -z "${ACCESS_TOKEN}" ]; then
    error "ACCESS_TOKEN is required for user mode."
    error "Set it in .env: ACCESS_TOKEN=ghp_..."
    error "Needed scopes: repo, workflow"
    exit 1
fi

if [ -z "${GITHUB_USERNAME}" ]; then
    error "GITHUB_USERNAME is required."
    error "Set it in .env: GITHUB_USERNAME=your-github-username"
    exit 1
fi

log "Requesting registration token for user: ${GITHUB_USERNAME}"

API_RESPONSE=$(curl -sf \
    -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/user/actions/runners/registration-token")

if [ $? -ne 0 ] || [ -z "${API_RESPONSE}" ]; then
    error "Failed to get registration token from GitHub API."
    error "Check that ACCESS_TOKEN is valid and has 'repo' and 'workflow' scopes."
    exit 1
fi

RUNNER_TOKEN=$(echo "${API_RESPONSE}" | jq -r '.token // empty')

if [ -z "${RUNNER_TOKEN}" ]; then
    error "GitHub API returned unexpected response:"
    echo "${API_RESPONSE}" | jq . >&2 || echo "${API_RESPONSE}" >&2
    exit 1
fi

REPO_URL="https://github.com/${GITHUB_USERNAME}"
log "Registration token obtained successfully."
log "Registering runner at: ${REPO_URL}"

export RUNNER_TOKEN="${RUNNER_TOKEN}"
export REPO_URL="${REPO_URL}"
export RUNNER_SCOPE="repo"

exec /entrypoint.sh "$@"
