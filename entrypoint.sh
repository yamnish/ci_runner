#!/bin/bash
set -e

RUNNER_DIR="/actions-runner"
DATA_DIR="/runner/data"
CONFIG_FILE="${DATA_DIR}/.runner"

log()   { echo "$*"; }
error() { echo "ERROR: $*" >&2; }

# ── Normal start (config already exists) ──────────────────────────────────────

if [ -f "${CONFIG_FILE}" ]; then
    if [ "${1}" = "--setup" ]; then
        echo "Runner is already configured."
        printf "Reconfigure? This will remove existing registration. [y/N]: "
        read -r confirm
        if [ "${confirm}" != "y" ] && [ "${confirm}" != "Y" ]; then
            log "Aborted."
            exit 0
        fi
        rm -f "${DATA_DIR}/.runner" \
              "${DATA_DIR}/.credentials" \
              "${DATA_DIR}/.credentials_rsaparams" \
              "${DATA_DIR}/.env"
        # fall through to wizard
    else
        # Restore config from volume and start runner
        for f in .runner .credentials .credentials_rsaparams .env; do
            [ -f "${DATA_DIR}/${f}" ] && cp "${DATA_DIR}/${f}" "${RUNNER_DIR}/"
        done
        chown -R runner:runner "${RUNNER_DIR}"
        cd "${RUNNER_DIR}"
        exec /usr/sbin/gosu runner ./run.sh
    fi
fi

# ── Guard: no tty = can't run wizard ──────────────────────────────────────────

if [ ! -t 0 ]; then
    error "Runner is not configured. Run setup first:"
    error "  docker compose run --rm runner"
    exit 1
fi

# ── Interactive wizard ─────────────────────────────────────────────────────────

echo ""
echo "=== GitHub Actions Runner Setup ==="
echo ""
echo "Select runner scope:"
echo "  1) user  — registers for all personal repos (undocumented GitHub feature)"
echo "  2) org   — registers for all repos in an organization (official)"
echo "  3) repo  — registers for a single repository"
echo ""
printf "Enter choice [1/2/3]: "
read -r scope_choice

case "${scope_choice}" in
    1) SCOPE="user" ;;
    2) SCOPE="org"  ;;
    3) SCOPE="repo" ;;
    *)
        error "Invalid choice: ${scope_choice}"
        exit 1
        ;;
esac

# ── Scope-specific instructions & prompts ─────────────────────────────────────

case "${SCOPE}" in
    user)
        echo ""
        echo "=== User-level Runner ==="
        echo ""
        echo "This uses an undocumented GitHub API. May stop working in future."
        echo ""
        echo "To get a registration token, run this command:"
        echo ""
        echo "  curl -s -X POST \\"
        echo "    -H \"Authorization: Bearer YOUR_CLASSIC_PAT\" \\"
        echo "    -H \"Accept: application/vnd.github+json\" \\"
        echo "    https://api.github.com/user/actions/runners/registration-token \\"
        echo "    | jq -r .token"
        echo ""
        echo "Requirements for YOUR_CLASSIC_PAT:"
        echo "  - Classic PAT (not fine-grained)"
        echo "  - Scopes: repo, workflow"
        echo "  - Create at: https://github.com/settings/tokens"
        echo ""
        printf "Enter your GitHub username: "
        read -r GITHUB_USERNAME
        if [ -z "${GITHUB_USERNAME}" ]; then
            error "GitHub username is required."
            exit 1
        fi
        RUNNER_URL="https://github.com/${GITHUB_USERNAME}"
        ;;

    org)
        echo ""
        echo "=== Org-level Runner ==="
        echo ""
        printf "Enter organization name: "
        read -r ORG_NAME
        if [ -z "${ORG_NAME}" ]; then
            error "Organization name is required."
            exit 1
        fi
        echo ""
        echo "To get a registration token, open in browser:"
        echo "  https://github.com/organizations/${ORG_NAME}/settings/actions/runners/new"
        echo ""
        echo "Or via API:"
        echo ""
        echo "  curl -s -X POST \\"
        echo "    -H \"Authorization: Bearer YOUR_CLASSIC_PAT\" \\"
        echo "    -H \"Accept: application/vnd.github+json\" \\"
        echo "    https://api.github.com/orgs/${ORG_NAME}/actions/runners/registration-token \\"
        echo "    | jq -r .token"
        echo ""
        echo "Requirements for YOUR_CLASSIC_PAT:"
        echo "  - Classic PAT (not fine-grained)"
        echo "  - Scopes: admin:org"
        echo "  - Create at: https://github.com/settings/tokens"
        echo ""
        RUNNER_URL="https://github.com/${ORG_NAME}"
        ;;

    repo)
        echo ""
        echo "=== Repo-level Runner ==="
        echo ""
        printf "Enter repo (format: owner/repo): "
        read -r REPO_SLUG
        if [ -z "${REPO_SLUG}" ] || [ "${REPO_SLUG}" = "${REPO_SLUG##*/}" ]; then
            error "Invalid format. Expected owner/repo."
            exit 1
        fi
        OWNER="${REPO_SLUG%%/*}"
        REPO="${REPO_SLUG##*/}"
        echo ""
        echo "To get a registration token, open in browser:"
        echo "  https://github.com/${OWNER}/${REPO}/settings/actions/runners/new"
        echo ""
        echo "Or via API:"
        echo ""
        echo "  curl -s -X POST \\"
        echo "    -H \"Authorization: Bearer YOUR_CLASSIC_PAT\" \\"
        echo "    -H \"Accept: application/vnd.github+json\" \\"
        echo "    https://api.github.com/repos/${OWNER}/${REPO}/actions/runners/registration-token \\"
        echo "    | jq -r .token"
        echo ""
        echo "Requirements for YOUR_CLASSIC_PAT:"
        echo "  - Classic PAT (not fine-grained)"
        echo "  - Scopes: repo"
        echo "  - Create at: https://github.com/settings/tokens"
        echo ""
        RUNNER_URL="https://github.com/${OWNER}/${REPO}"
        ;;
esac

printf "Enter registration token: "
read -rs TOKEN || true
echo ""
if [ -z "${TOKEN}" ]; then
    error "Registration token is required."
    exit 1
fi

# ── Common parameters ──────────────────────────────────────────────────────────

echo ""
DEFAULT_NAME="$(hostname)"
printf "Enter runner name [default: %s]: " "${DEFAULT_NAME}"
read -r RUNNER_NAME
RUNNER_NAME="${RUNNER_NAME:-${DEFAULT_NAME}}"

echo ""
echo "Enter labels (comma-separated) [default: self-hosted,linux,x64]:"
echo "Examples:"
echo "  high-power    → for heavy builds (use in workflow: runs-on: [self-hosted, high-power])"
echo "  low-power     → for light tasks"
echo "  gpu           → machines with GPU"
echo "  arm64         → ARM architecture"
echo ""
printf "Enter labels: "
read -r LABELS
LABELS="${LABELS:-self-hosted,linux,x64}"

# ── Summary & registration ─────────────────────────────────────────────────────

echo ""
echo "=== Configuration Summary ==="
echo "  Scope:  ${SCOPE}"
echo "  Target: ${RUNNER_URL}"
echo "  Name:   ${RUNNER_NAME}"
echo "  Labels: ${LABELS}"
echo ""
echo ""
echo "Registering runner..."
echo ""

mkdir -p "${DATA_DIR}"

chown -R runner:runner "${DATA_DIR}"

cd "${RUNNER_DIR}"
/usr/sbin/gosu runner ./config.sh \
    --url "${RUNNER_URL}" \
    --token "${TOKEN}" \
    --name "${RUNNER_NAME}" \
    --labels "${LABELS}" \
    --unattended

# Persist config files to volume
for f in .runner .credentials .credentials_rsaparams .env; do
    [ -f "${RUNNER_DIR}/${f}" ] && cp "${RUNNER_DIR}/${f}" "${DATA_DIR}/"
done

echo ""
echo "✓ Runner registered successfully!"
echo ""
echo "To start the runner:"
echo "  docker compose up -d"
echo ""
echo "To check logs:"
echo "  docker compose logs -f"
