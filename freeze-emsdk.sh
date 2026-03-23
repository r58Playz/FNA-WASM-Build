#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 <runtime-root|emsdk-root> [output-zip]" >&2
  echo "example: $0 ./liba/runtime ./liba/emsdk-frozen.zip" >&2
  echo "example: $0 ./emsdk ./emsdk-frozen.zip" >&2
  exit 1
fi

RUNTIME_ROOT="$1"
OUTPUT_ZIP="${2:-$PWD/emsdk-frozen.zip}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -d "$RUNTIME_ROOT" ]]; then
  echo "error: input path does not exist or is not a directory: $RUNTIME_ROOT" >&2
  exit 1
fi

RUNTIME_ROOT="$(cd "$RUNTIME_ROOT" && pwd)"

PATCH_CALLBACK="${SCRIPT_DIR}/emsdk.patch"
PATCH_WASMFS="${SCRIPT_DIR}/emsdk.2.patch"

EMSDK_SRC=""
if [[ -d "$RUNTIME_ROOT/src/mono/browser/emsdk" ]]; then
  EMSDK_SRC="$RUNTIME_ROOT/src/mono/browser/emsdk"
elif [[ -d "$RUNTIME_ROOT/emscripten" && -d "$RUNTIME_ROOT/bin" ]]; then
  EMSDK_SRC="$RUNTIME_ROOT"
else
  echo "error: unable to locate emsdk root from input: $RUNTIME_ROOT" >&2
  echo "expected either <runtime-root>/src/mono/browser/emsdk or a direct emsdk root" >&2
  exit 1
fi

EMSDK_SRC="$(cd "$EMSDK_SRC" && pwd)"

for path in \
  "$EMSDK_SRC/emsdk_env.sh" \
  "$EMSDK_SRC/emscripten/.emscripten" \
  "$EMSDK_SRC/emscripten/.emsdk_version" \
  "$EMSDK_SRC/node/.emsdk_version" \
  "$EMSDK_SRC/.emsdk_version"
do
  if [[ ! -e "$path" ]]; then
    echo "error: required file missing for frozen emsdk: $path" >&2
    exit 1
  fi
done

if [[ ! -f "$EMSDK_SRC/emscripten/system/lib/html5/callback.c" ]]; then
  echo "error: missing callback.c in emsdk source" >&2
  exit 1
fi
if [[ ! -f "$EMSDK_SRC/emscripten/system/lib/wasmfs/thread_utils.h" ]]; then
  echo "error: missing wasmfs thread_utils.h in emsdk source" >&2
  exit 1
fi

if [[ -f "$PATCH_CALLBACK" ]]; then
  patch -p1 --forward --directory "$EMSDK_SRC/emscripten" < "$PATCH_CALLBACK" >/dev/null || true
  rm -f "$EMSDK_SRC/emscripten/system/lib/html5/callback.c.rej"
fi

if [[ -f "$PATCH_WASMFS" ]]; then
  patch -p1 --forward --directory "$EMSDK_SRC/emscripten" < "$PATCH_WASMFS" >/dev/null || true
  rm -f "$EMSDK_SRC/emscripten/system/lib/wasmfs/thread_utils.h.rej"
fi

if ! rg -q -- "emscripten_proxy_async\\(" "$EMSDK_SRC/emscripten/system/lib/html5/callback.c"; then
  echo "error: callback.c is missing emscripten_proxy_async patch" >&2
  exit 1
fi
if rg -q -- "emscripten_proxy_sync\\(" "$EMSDK_SRC/emscripten/system/lib/html5/callback.c"; then
  echo "error: callback.c still contains emscripten_proxy_sync" >&2
  exit 1
fi
if ! rg -q -- "thread = std::thread\\(" "$EMSDK_SRC/emscripten/system/lib/wasmfs/thread_utils.h"; then
  echo "error: thread_utils.h is missing wasmfs thread init patch" >&2
  exit 1
fi

echo "Preparing emsdk cache artifacts via embuilder"
EM_CONFIG="$EMSDK_SRC/emscripten/.emscripten" \
  EM_FROZEN_CACHE= \
  "$EMSDK_SRC/emscripten/embuilder" build libc-mt libhtml5 libwasmfs libwasmfs-debug

for path in \
  "$EMSDK_SRC/emscripten/cache/sysroot/lib/wasm32-emscripten/libc-mt.a" \
  "$EMSDK_SRC/emscripten/cache/sysroot/lib/wasm32-emscripten/libhtml5.a" \
  "$EMSDK_SRC/emscripten/cache/sysroot/lib/wasm32-emscripten/libwasmfs.a"
do
  if [[ ! -f "$path" ]]; then
    echo "error: expected cached archive missing after embuilder: $path" >&2
    exit 1
  fi
done

if ! strings "$EMSDK_SRC/emscripten/cache/sysroot/lib/wasm32-emscripten/libhtml5.a" | rg -q -- "emscripten_proxy_async failed"; then
  echo "error: libhtml5.a does not contain async callback assertion signature" >&2
  exit 1
fi
if strings "$EMSDK_SRC/emscripten/cache/sysroot/lib/wasm32-emscripten/libhtml5.a" | rg -q -- "emscripten_proxy_sync failed"; then
  echo "error: libhtml5.a still contains sync callback assertion signature" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_ZIP")"
rm -f "$OUTPUT_ZIP"

python3 - "$EMSDK_SRC" "$OUTPUT_ZIP" <<'PY'
import os
import stat
import sys
import zipfile

src = os.path.abspath(sys.argv[1])
dst = os.path.abspath(sys.argv[2])

with zipfile.ZipFile(dst, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
    root_info = zipfile.ZipInfo("emsdk/")
    root_info.external_attr = (stat.S_IFDIR | 0o755) << 16
    zf.writestr(root_info, "")

    for base, dirs, files in os.walk(src):
        dirs.sort()
        files.sort()

        rel_base = os.path.relpath(base, src)
        arc_base = "emsdk" if rel_base == "." else f"emsdk/{rel_base}"

        if rel_base != ".":
            dir_info = zipfile.ZipInfo(f"{arc_base}/")
            mode = os.stat(base, follow_symlinks=False).st_mode
            dir_info.external_attr = mode << 16
            zf.writestr(dir_info, "")

        for name in files:
            full = os.path.join(base, name)
            rel = os.path.relpath(full, src)
            arc = f"emsdk/{rel}"

            st = os.stat(full, follow_symlinks=False)
            if stat.S_ISLNK(st.st_mode):
                target = os.readlink(full)
                info = zipfile.ZipInfo(arc)
                info.create_system = 3
                info.external_attr = (stat.S_IFLNK | 0o777) << 16
                zf.writestr(info, target)
                continue

            info = zipfile.ZipInfo.from_file(full, arc)
            info.external_attr = st.st_mode << 16
            with open(full, "rb") as f:
                zf.writestr(info, f.read())
PY

echo "frozen emsdk zip created: $OUTPUT_ZIP"
sha256sum "$OUTPUT_ZIP"
