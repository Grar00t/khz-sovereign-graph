#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

python3 -m compileall -q src scripts
python3 -m pytest -q tests
python3 scripts/audit_graph.py --graph data/canonical_graph_v2.json

git diff --check

git status --short
