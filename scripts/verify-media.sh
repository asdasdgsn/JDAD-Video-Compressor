#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="${1:-$(mktemp -d /tmp/FrameShift-check.XXXXXX)}"
FRAMESHIFT_ENGINE_DIR="$PWD/.engine/install/bin" swift run -c release MediaCheck "$ROOT"
