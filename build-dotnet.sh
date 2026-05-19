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
(cd "$RUNTIME_ROOT" && ./build.sh -os browser -s mono+libs /p:WasmEnableThreads="$PTHREAD_FLAG" -c Release)

# Build the patched WasmAppBuilder so the bundle ships our modified
# PInvokeTableGenerator + mono_wasm_marshal_get_managed_wrapper signature.
# The runtime build above usually produces this too, but build it explicitly
# to be safe — it's cheap and idempotent.
echo "Building WasmAppBuilder task assembly"
(cd "$RUNTIME_ROOT" && ./dotnet.sh build -c Release src/tasks/WasmAppBuilder/WasmAppBuilder.csproj)

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
if [[ ! -f "$TASKS_OUT/net10.0/WasmAppBuilder.dll" ]]; then
  echo "error: WasmAppBuilder.dll not built at: $TASKS_OUT/net10.0/" >&2
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
# override to point at $(MicrosoftNetCoreAppRuntimePackDir)/tasks/net10.0/WasmAppBuilder.dll
# from a Directory.Build.targets (imported after Sdk.targets, so the override wins).
mkdir -p "$STAGE_DIR/tasks/net10.0" "$STAGE_DIR/tasks/net472"
for tfm in net10.0 net472; do
  if [[ ! -f "$TASKS_OUT/$tfm/WasmAppBuilder.dll" ]]; then
    echo "warn: $TASKS_OUT/$tfm/WasmAppBuilder.dll missing, skipping" >&2
    continue
  fi
  cp -a "$TASKS_OUT/$tfm/WasmAppBuilder.dll" "$STAGE_DIR/tasks/$tfm/"
  # deps.json is needed for net10.0 (Core) to resolve dependencies. For net472
  # MSBuild it's not used. Copy when present.
  if [[ -f "$TASKS_OUT/$tfm/WasmAppBuilder.deps.json" ]]; then
    cp -a "$TASKS_OUT/$tfm/WasmAppBuilder.deps.json" "$STAGE_DIR/tasks/$tfm/"
  fi
  # WasmAppBuilder uses Microsoft.NET.WebAssembly.Webcil; SDK nupkg ships it
  # alongside the task. Match that layout so the resolver doesn't pull a
  # mismatched copy from the host SDK.
  if [[ -f "$TASKS_OUT/$tfm/Microsoft.NET.WebAssembly.Webcil.dll" ]]; then
    cp -a "$TASKS_OUT/$tfm/Microsoft.NET.WebAssembly.Webcil.dll" "$STAGE_DIR/tasks/$tfm/"
  fi
done

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_ZIP"
(cd "$STAGE_DIR" && 7z a "$OUTPUT_ZIP" './*' >/dev/null)

echo "dotnet zip created: $OUTPUT_ZIP"
sha256sum "$OUTPUT_ZIP"
