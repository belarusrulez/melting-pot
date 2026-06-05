# test/e2e/Dockerfile — ephemeral image for the melting-pot agent-loop e2e harness.
# plans/e2e-docker-design.md §1. Auth is injected at RUN time only (never baked).
FROM debian:bookworm-slim

# --- system deps ---
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git jq sqlite3 coreutils findutils bash \
 && rm -rf /var/lib/apt/lists/* \
 && sqlite3 :memory: 'CREATE VIRTUAL TABLE t USING fts5(x);' \
      || { echo "FATAL: sqlite3 lacks FTS5"; exit 1; }

# --- non-root user with a writable HOME ---
RUN useradd -m -s /bin/bash melt
USER melt
ENV HOME=/home/melt
WORKDIR /home/melt

# --- Claude Code CLI (native installer). Pin via CLAUDE_CLI_VERSION build-arg. ---
# A CLI bump can change stream-json shapes the oracle depends on, so the version
# is asserted at build time and stamped into the image tag by run.sh.
ARG CLAUDE_CLI_VERSION=2.1.165
RUN curl -fsSL https://claude.ai/install.sh | bash -s -- "${CLAUDE_CLI_VERSION}"
ENV PATH=/home/melt/.local/bin:$PATH
RUN claude --version | grep -q "${CLAUDE_CLI_VERSION}" \
      || { echo "FATAL: claude version != ${CLAUDE_CLI_VERSION}"; claude --version; exit 1; }

# --- the repo (read-only source of skills + harness) ---
COPY --chown=melt:melt . /opt/melting-pot
ENV REPO=/opt/melting-pot

# scenarios run from a fresh sandbox per scenario (see run-scenarios.sh)
ENTRYPOINT ["sh", "/opt/melting-pot/test/e2e/run-scenarios.sh"]
