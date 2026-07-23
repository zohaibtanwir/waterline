FROM ubuntu:24.04

ARG CLAUDE_CODE_VERSION
ARG UV_VERSION
ARG PNPM_VERSION
ENV DEBIAN_FRONTEND=noninteractive

# Toolchain layer (slowest-changing — keep first for cache)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git jq ripgrep fd-find python3 python3-pip python3-venv \
    make gcc g++ openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Node 22 (NodeSource)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs && rm -rf /var/lib/apt/lists/*

# Claude Code — version DECLARED at build
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# Project dependency managers — versions DECLARED at build and ASSERTED.
# uv: standalone installer, pinned, to a system path.
# pnpm: npm -g, which installs the exact version (corepack resolves forward and
# silently ignores the pin — observed 11.15.1 requested, 11.16.0 installed).
# Both versions are compared, not merely printed: a drifted pin fails the BUILD.
RUN curl -fsSL --proto '=https' --tlsv1.2 \
      https://releases.astral.sh/github/uv/releases/download/${UV_VERSION}/uv-installer.sh \
      | env UV_INSTALL_DIR=/usr/local/bin INSTALLER_NO_MODIFY_PATH=1 sh \
    && npm install -g pnpm@${PNPM_VERSION} \
    && got_uv="$(uv --version | awk '{print $2}')" \
    && got_pnpm="$(pnpm --version)" \
    && echo "uv=$got_uv pnpm=$got_pnpm" \
    && [ "$got_uv" = "${UV_VERSION}" ] \
         || { echo "PIN MISMATCH uv: asked ${UV_VERSION}, got $got_uv" >&2; exit 1; } \
    && [ "$got_pnpm" = "${PNPM_VERSION}" ] \
         || { echo "PIN MISMATCH pnpm: asked ${PNPM_VERSION}, got $got_pnpm" >&2; exit 1; }

# Governance floor, baked read-only
COPY managed-settings.json /etc/claude-code/managed-settings.json
RUN chmod 0444 /etc/claude-code/managed-settings.json

# Non-root agent user; workspace
RUN useradd -m -u 1001 agent && mkdir -p /workspace && chown agent:agent /workspace
USER agent
WORKDIR /workspace
RUN git config --global safe.directory '*'

# All egress via the controller proxy (model API excepted later via NO_PROXY)
ENV HTTP_PROXY=http://100.98.245.52:8888 \
    HTTPS_PROXY=http://100.98.245.52:8888 \
    NO_PROXY=localhost,127.0.0.1,100.98.245.52

CMD ["/bin/bash"]
