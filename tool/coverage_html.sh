#!/usr/bin/env bash
# Generate an HTML coverage report from Flutter tests.
# Requires: Flutter SDK + genhtml (from the lcov package).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v genhtml >/dev/null 2>&1; then
  echo "genhtml not found. Install lcov, then re-run:" >&2
  echo "  macOS:  brew install lcov" >&2
  echo "  Ubuntu: sudo apt-get install -y lcov" >&2
  echo "  Windows: choco install lcov  (or run this script under WSL/Git Bash)" >&2
  exit 1
fi

flutter test --coverage
mkdir -p coverage/html
genhtml coverage/lcov.info -o coverage/html --quiet
echo "Open coverage/html/index.html"
