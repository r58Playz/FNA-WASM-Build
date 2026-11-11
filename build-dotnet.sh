#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 <runtime-root> <pthread:true|false> [output-zip]" >&2
  echo "example: $0 ./liba/runtime true ./liba/runtime.zip" >&2
  echo "example: $0 ../dotnet-runtime false ./ST-dotnet.zip" >&2
  exit 1
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
  usage
fi

RUNTIME_ROOT="$1"
PTHREAD_FLAG="$2"
OUTPUT_ZIP="${3:-$PWD/dotnet.zip}"

case "$PTHREAD_FLAG" in
  true|false) ;;
  *)
    echo "error: pthread flag must be 'true' or 'false', got: $PTHREAD_FLAG" >&2
    exit 1
    ;;
esac

if [[ -n "${WASM_ENABLE_JSPI:-}" ]]; then
  # The wasm-jit-11.0.0 runtime has no JSPI mode (the fork's JSPI commit was dropped in the move to .NET 11).
  echo "warn: WASM_ENABLE_JSPI is ignored; the runtime no longer has a JSPI build" >&2
fi

if [[ ! -d "$RUNTIME_ROOT" ]]; then
  echo "error: runtime root does not exist: $RUNTIME_ROOT" >&2
  exit 1
fi
if [[ ! -x "$RUNTIME_ROOT/build.sh" ]]; then
  echo "error: build.sh not found or not executable in: $RUNTIME_ROOT" >&2
  exit 1
fi

RUNTIME_ROOT="$(cd "$RUNTIME_ROOT" && pwd)"
OUTPUT_DIR="$(cd "$(dirname "$OUTPUT_ZIP")" && pwd)"
OUTPUT_ZIP="$OUTPUT_DIR/$(basename "$OUTPUT_ZIP")"

echo "Building dotnet runtime (pthread=$PTHREAD_FLAG) in $RUNTIME_ROOT"
(cd "$RUNTIME_ROOT" && ./build.sh -os browser -s mono+libs /p:RunAOTCompilation=true /p:WasmEnableThreads="$PTHREAD_FLAG" -c Release -nodeReuse:false)

# Build the patched WasmAppBuilder so the bundle ships our modified
# PInvokeTableGenerator + mono_wasm_marshal_get_managed_wrapper signature.
# The runtime build above usually produces this too, but build it explicitly
# to be safe — it's cheap and idempotent.
echo "Building WasmAppBuilder task assembly"
(cd "$RUNTIME_ROOT" && ./dotnet.sh build -nodeReuse:false -c Release src/tasks/WasmAppBuilder/WasmAppBuilder.csproj)

RUNTIME_OUT="$RUNTIME_ROOT/artifacts/bin/microsoft.netcore.app.runtime.browser-wasm/Release"
CROSS_OUT="$RUNTIME_ROOT/artifacts/bin/mono/browser.wasm.Release/cross/browser-wasm"
TASKS_OUT="$RUNTIME_ROOT/artifacts/bin/WasmAppBuilder/Release"

if [[ ! -d "$RUNTIME_OUT" ]]; then
  echo "error: runtime output not found: $RUNTIME_OUT" >&2
  exit 1
fi
if [[ ! -x "$CROSS_OUT/mono-aot-cross" ]]; then
  echo "error: mono-aot-cross not built at: $CROSS_OUT/mono-aot-cross" >&2
  exit 1
fi
# .NET 10 writes TFM folders (net10.0/net472); .NET 11 uses net/netframework.
# Keep the checkout's layout and require a .NET task, even if only the
# optional .NET Framework task was built.
TASK_TFMS=()
HAS_NET_TASKS=false
for task_dir in "$TASKS_OUT"/net "$TASKS_OUT"/netframework "$TASKS_OUT"/net[0-9]*; do
  [[ -f "$task_dir/WasmAppBuilder.dll" ]] || continue
  tfm="${task_dir##*/}"
  TASK_TFMS+=("$tfm")
  case "$tfm" in
    net|net[0-9]*.[0-9]*) HAS_NET_TASKS=true ;;
  esac
done
if [[ "$HAS_NET_TASKS" != true ]]; then
  echo "error: WasmAppBuilder.dll not built under: $TASKS_OUT (expected net/ or net<version>/)" >&2
  exit 1
fi

STAGE_DIR="$(mktemp -d -t fna-dotnet-zip-XXXXXX)"
trap 'rm -rf "$STAGE_DIR"' EXIT

cp -a "$RUNTIME_OUT/." "$STAGE_DIR/"

mkdir -p "$STAGE_DIR/cross"
cp -a "$CROSS_OUT/mono-aot-cross" "$STAGE_DIR/cross/"
for lib in libc++.so.1 libc++abi.so.1; do
  if [[ -e "$CROSS_OUT/$lib" ]]; then
    cp -a "$CROSS_OUT/$lib" "$STAGE_DIR/cross/"
  fi
done

# Bundle the patched task assemblies. The SDK targets resolve the task DLL via
# the WasmAppBuilderTasksAssemblyPath MSBuild property, which the consumer can
# override to point at $(MicrosoftNetCoreAppRuntimePackDir)/tasks/<tfm>/WasmAppBuilder.dll
# from a Directory.Build.targets (imported after Sdk.targets, so the override wins).
for tfm in "${TASK_TFMS[@]}"; do
  mkdir -p "$STAGE_DIR/tasks/$tfm"
  # Preserve the task's full dependency closure, including net472 companions.
  cp -a "$TASKS_OUT/$tfm/." "$STAGE_DIR/tasks/$tfm/"
done

python3 - "$RUNTIME_ROOT" "$PTHREAD_FLAG" "$STAGE_DIR/runtime-build.json" <<'PY'
import json
from pathlib import Path
import subprocess
import sys

root, threads, destination = sys.argv[1:]
manifest = {
    "runtime_sha": subprocess.check_output(["git", "-C", root, "rev-parse", "HEAD"], text=True).strip(),
    "wasm_enable_threads": threads == "true",
}
Path(destination).write_text(json.dumps(manifest, indent=2) + "\n")
PY

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_ZIP"
(cd "$STAGE_DIR" && 7z a "$OUTPUT_ZIP" './*' >/dev/null)

echo "dotnet zip created: $OUTPUT_ZIP"
sha256sum "$OUTPUT_ZIP"
