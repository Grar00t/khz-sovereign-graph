#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
git -C "$ROOT" config core.hooksPath .githooks
chmod +x "$ROOT"/.githooks/pre-commit "$ROOT"/.githooks/pre-push
printf '%s\n' 'core.hooksPath=.githooks'
