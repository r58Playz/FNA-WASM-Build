#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 || ( "$2" != true && "$2" != false ) ]]; then
  echo "usage: $0 <runtime-root> <pthread:true|false> <output-directory>" >&2
  exit 1
fi
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  echo "error: this build requires native macOS ARM64" >&2
  exit 1
fi

RUNTIME_ROOT="$(cd "$1" && pwd)"
THREADS="$2"
mkdir -p "$3"
OUTPUT_DIR="$(cd "$3" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# In mono.aotcross, TargetOS/Architecture describe the compiler HOST.
# Restrict the target list: the default also builds Android/WASI/Apple targets.
(cd "$RUNTIME_ROOT" && ./build.sh -os osx -arch arm64 -s mono.aotcross -c Release \
  /p:BuildMonoAOTCrossCompilerOnly=true /p:MonoCrossAOTTargetOS=browser \
  /p:WasmEnableThreads="$THREADS" -nodeReuse:false)

# This is the target build's output, before monoaotcross.proj copies it into
# artifacts/bin/mono/osx.arm64.Release/cross/osx-arm64/browser-wasm/.
CROSS_OUT="$RUNTIME_ROOT/artifacts/bin/mono/browser.wasm.Release/cross/browser-wasm"
SUSPEND=preemptive
if [[ "$THREADS" == true ]]; then SUSPEND=coop; fi
grep -qx "GC_SUSPEND:STRING=$SUSPEND" \
  "$RUNTIME_ROOT/artifacts/obj/mono/browser.wasm.Release/cross/CMakeCache.txt"
python3 "$SCRIPT_DIR/bundle-macos-cross.py" "$CROSS_OUT/mono-aot-cross" \
  "$OUTPUT_DIR/cross" "$RUNTIME_ROOT" "$THREADS"

# Exercise the relocated package, without dyld search-path overrides.
otool -L "$OUTPUT_DIR/cross/mono-aot-cross"
env -u DYLD_LIBRARY_PATH -u DYLD_FALLBACK_LIBRARY_PATH \
  "$OUTPUT_DIR/cross/mono-aot-cross" --print-icall-table > "$OUTPUT_DIR/icall-table.json"
python3 - "$OUTPUT_DIR/icall-table.json" <<'PY'
import json
import sys
with open(sys.argv[1]) as stream:
    assert json.load(stream), "empty icall table"
PY
