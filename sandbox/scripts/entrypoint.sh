#!/usr/bin/env bash
# Sandbox entrypoint: prepares the workspace volume, drops privileges, then runs.
set -euo pipefail

seed_node_modules() {
  local target=/workspace/node_modules
  local lock_hash current_hash

  lock_hash="$(sha256sum /workspace/package-lock.json 2>/dev/null | cut -d' ' -f1 || true)"
  current_hash="$(cat "$target/.rea-lock-hash" 2>/dev/null || true)"

  if [ ! -f "$target/.package-lock.json" ] || [ "$lock_hash" != "$current_hash" ]; then
    echo "[rea-sandbox] Preparing node_modules from the image (first run only)..."
    find "$target" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
    chown node:node "$target"
    # Copy as the sandbox user so files are owned correctly without a slow
    # recursive chown on Docker Desktop bind/volume filesystems.
    gosu node cp -r /opt/rea/node_modules/. "$target/"
    printf '%s\n' "$lock_hash" > "$target/.rea-lock-hash"
    echo "[rea-sandbox] node_modules ready."
  fi
}

if [ "${REA_SEED_NODE_MODULES:-0}" = "1" ] \
   && [ -d /opt/rea/node_modules ] \
   && mountpoint -q /workspace/node_modules; then
  seed_node_modules
fi

if [ -n "${HOME:-}" ]; then
  mkdir -p "${HOME}" 2>/dev/null || true
fi

if [ "$(id -u)" = "0" ]; then
  chown node:node /home/node /home/node/.npm 2>/dev/null || true
  exec gosu node "$@"
fi

exec "$@"
