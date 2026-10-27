#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
pkill -x Capture || true
"$PROJECT_ROOT/scripts/build-app.sh" debug
open "$PROJECT_ROOT/build/Capture.app"
