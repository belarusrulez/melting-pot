#!/bin/sh
# test/e2e/run.sh — host driver for the docker e2e harness.
#
# Reads the Claude subscription OAuth token from the macOS keychain (so the raw
# token never appears in argv, env files, or the transcript), then either runs
# the scenarios directly on the host (--host) or builds + runs the Docker image
# (--docker, default). The token is injected at run time only — NEVER baked.
#
# Usage:
#   sh test/e2e/run.sh --host            # run scenarios on this host (sandboxed)
#   sh test/e2e/run.sh --docker          # build image, run scenarios inside it
#   sh test/e2e/run.sh --host ONLY="I-canary D-agent-synonym"
#
# Token source (override with MELT_TOKEN_CMD):
#   security find-generic-password -a "$USER" -s claude-oauth-token -w
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
MODE=--docker
PASS_ENV=""
for a in "$@"; do
  case "$a" in
    --host|--docker) MODE=$a ;;
    *=*) PASS_ENV="$PASS_ENV $a" ;;
    *) echo "unknown arg: $a"; exit 2 ;;
  esac
done

# --- fetch token (keychain by default) BEFORE any HOME games ---
TOKEN_CMD=${MELT_TOKEN_CMD:-"security find-generic-password -a \"$USER\" -s claude-oauth-token -w"}
TOKEN=$(eval "$TOKEN_CMD" 2>/dev/null || true)
if [ -z "${TOKEN:-}" ]; then
  if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then TOKEN=$CLAUDE_CODE_OAUTH_TOKEN
  elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then TOKEN=""   # let API key path through
  else echo "ERROR: no token in keychain and no CLAUDE_CODE_OAUTH_TOKEN/ANTHROPIC_API_KEY set"; exit 3
  fi
fi

case "$MODE" in
  --host)
    echo "== e2e: HOST mode =="
    export CLAUDE_CODE_OAUTH_TOKEN="${TOKEN:-${CLAUDE_CODE_OAUTH_TOKEN:-}}"
    [ -n "${TOKEN:-}" ] || export ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
    # shellcheck disable=SC2086
    env $PASS_ENV ARTIFACTS="${ARTIFACTS:-$(mktemp -d)}" sh "$HERE/run-scenarios.sh"
    ;;
  --docker)
    echo "== e2e: DOCKER mode =="
    IMG=melt-e2e:local
    docker build -f "$HERE/Dockerfile" -t "$IMG" "$REPO"
    OUT=$(mktemp -d /tmp/melt-e2e.XXXXXX)
    CID="melt-e2e-$$"
    # Write artifacts to a container-local dir (no bind mount — avoids macOS
    # Docker Desktop uid/perm issues), then docker cp them out. Token via env
    # only (not argv, not a layer). Keep container until cp, then remove.
    set +e
    docker run --name "$CID" \
      -e CLAUDE_CODE_OAUTH_TOKEN="${TOKEN:-}" \
      -e ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}" \
      -e ARTIFACTS=/home/melt/artifacts \
      $(for kv in $PASS_ENV; do printf -- '-e %s ' "$kv"; done) \
      "$IMG"
    rc=$?
    docker cp "$CID:/home/melt/artifacts/." "$OUT" 2>/dev/null
    docker rm -f "$CID" >/dev/null 2>&1
    set -e
    echo "artifacts copied to: $OUT"
    exit $rc
    ;;
esac
