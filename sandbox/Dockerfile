# syntax=docker/dockerfile:1.7
# Isolated Linux environment for REA experiments.
# Node version is pinned by the repository's .nvmrc and passed by compose.
ARG NODE_VERSION=24.22.1

FROM node:${NODE_VERSION}-bookworm-slim AS base

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    HUSKY=0 \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_FUND=false

# Python and Java are needed by REA bridges (JADX/Ghidra use the JRE).
# procps is required by REA's owned-process checks on Linux.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      binutils \
      ca-certificates \
      curl \
      file \
      git \
      gosu \
      jq \
      less \
      nano \
      openjdk-17-jre-headless \
      p7zip-full \
      procps \
      python3 \
      python3-pip \
      python3-venv \
      ripgrep \
      unzip \
      util-linux \
      xz-utils \
 && rm -rf /var/lib/apt/lists/*

# The official node image already provides UID 1000 as the `node` user.
RUN install -d -o node -g node /opt/rea /opt/npm-cache

WORKDIR /opt/rea

# Dependency layer: changes only when the lockfile changes.
FROM base AS deps
COPY package.json package-lock.json ./
COPY scripts ./scripts
RUN npm ci --no-audit --no-fund

# Build layer: compiles the runtime and packaged skills.
FROM deps AS build
COPY . .
RUN npm run build:cached \
 && ln -sf /opt/rea/scripts/rea.mjs /usr/local/bin/rea \
 && chmod +x /opt/rea/scripts/rea.mjs

COPY sandbox/scripts/entrypoint.sh /usr/local/bin/rea-entrypoint
# Runtime files stay root-owned but world-readable. Only the cache is writable
# by the sandbox user; the dev lane gets its own writable node_modules volume.
RUN chmod +x /usr/local/bin/rea-entrypoint \
 && install -d -o node -g node /opt/rea/.cache

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/rea-entrypoint"]
CMD ["rea", "--help"]
