#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec sudo unshare --mount --uts --ipc --pid --fork --mount-proc \
  --map-root-user \
  env -i \
  PATH=/usr/bin:/bin \
  HOME=/nonexistent \
  PYTHONNOUSERSITE=1 \
  PYTHONHASHSEED=0 \
  bash -c 'cd "$1" && exec /usr/bin/python3 -m src'
