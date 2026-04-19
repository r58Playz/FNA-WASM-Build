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
  "$EMSDK_SRC/emscripten/embuilder" build libcompiler_rt libcompiler_rt-ww libcompiler_rt-mt libcompiler_rt-wasm-sjlj libcompiler_rt-wasm-sjlj-ww libcompiler_rt-wasm-sjlj-mt libc libc-debug libc-asan libc-asan-debug libc-ww libc-ww-debug libc-ww-asan libc-ww-asan-debug libc-mt libc-mt-debug libc-mt-asan libc-mt-asan-debug libc_optz libc_optz-debug libc_optz-asan libc_optz-asan-debug libc_optz-ww libc_optz-ww-debug libc_optz-ww-asan libc_optz-ww-asan-debug libc_optz-mt libc_optz-mt-debug libc_optz-mt-asan libc_optz-mt-asan-debug libprintf_long_double libprintf_long_double-debug libprintf_long_double-asan libprintf_long_double-asan-debug libprintf_long_double-ww libprintf_long_double-ww-debug libprintf_long_double-ww-asan libprintf_long_double-ww-asan-debug libprintf_long_double-mt libprintf_long_double-mt-debug libprintf_long_double-mt-asan libprintf_long_double-mt-asan-debug libwasm_workers_stub libwasm_workers_stub-debug libwasm_workers libwasm_workers-debug libsockets libsockets-ww libsockets-mt libsockets_proxy libsockets_proxy-ww libsockets_proxy-mt libc++abi-noexcept libc++abi-ww-noexcept libc++abi-mt-noexcept libc++abi-debug-noexcept libc++abi-debug-ww-noexcept libc++abi-debug-mt-noexcept libc++abi libc++abi-ww libc++abi-mt libc++abi-debug libc++abi-debug-ww libc++abi-debug-mt libc++abi-except libc++abi-ww-except libc++abi-mt-except libc++abi-debug-except libc++abi-debug-ww-except libc++abi-debug-mt-except libc++-noexcept libc++-ww-noexcept libc++-mt-noexcept libc++ libc++-ww libc++-mt libc++-except libc++-ww-except libc++-mt-except libunwind-noexcept libunwind-ww-noexcept libunwind-mt-noexcept libunwind libunwind-ww libunwind-mt libunwind-except libunwind-ww-except libunwind-mt-except libdlmalloc libdlmalloc-tracing libdlmalloc-debug libdlmalloc-debug-tracing libdlmalloc-ww libdlmalloc-ww-tracing libdlmalloc-ww-debug libdlmalloc-ww-debug-tracing libdlmalloc-mt libdlmalloc-mt-tracing libdlmalloc-mt-debug libdlmalloc-mt-debug-tracing libemmalloc libemmalloc-tracing libemmalloc-debug libemmalloc-debug-tracing libemmalloc-ww libemmalloc-ww-tracing libemmalloc-ww-debug libemmalloc-ww-debug-tracing libemmalloc-mt libemmalloc-mt-tracing libemmalloc-mt-debug libemmalloc-mt-debug-tracing libemmalloc-memvalidate-verbose libemmalloc-memvalidate-verbose-tracing libemmalloc-memvalidate-verbose-ww libemmalloc-memvalidate-verbose-ww-tracing libemmalloc-memvalidate-verbose-mt libemmalloc-memvalidate-verbose-mt-tracing libemmalloc-memvalidate libemmalloc-memvalidate-tracing libemmalloc-memvalidate-ww libemmalloc-memvalidate-ww-tracing libemmalloc-memvalidate-mt libemmalloc-memvalidate-mt-tracing libemmalloc-verbose libemmalloc-verbose-tracing libemmalloc-verbose-ww libemmalloc-verbose-ww-tracing libemmalloc-verbose-mt libemmalloc-verbose-mt-tracing libmimalloc libmimalloc-ww libmimalloc-mt libGL libGL-getprocaddr libGL-full_es3 libGL-full_es3-getprocaddr libGL-ofb libGL-ofb-getprocaddr libGL-ofb-full_es3 libGL-ofb-full_es3-getprocaddr libGL-webgl2 libGL-webgl2-getprocaddr libGL-webgl2-full_es3 libGL-webgl2-full_es3-getprocaddr libGL-webgl2-ofb libGL-webgl2-ofb-getprocaddr libGL-webgl2-ofb-full_es3 libGL-webgl2-ofb-full_es3-getprocaddr libGL-emu libGL-emu-getprocaddr libGL-emu-full_es3 libGL-emu-full_es3-getprocaddr libGL-emu-ofb libGL-emu-ofb-getprocaddr libGL-emu-ofb-full_es3 libGL-emu-ofb-full_es3-getprocaddr libGL-emu-webgl2 libGL-emu-webgl2-getprocaddr libGL-emu-webgl2-full_es3 libGL-emu-webgl2-full_es3-getprocaddr libGL-emu-webgl2-ofb libGL-emu-webgl2-ofb-getprocaddr libGL-emu-webgl2-ofb-full_es3 libGL-emu-webgl2-ofb-full_es3-getprocaddr libGL-ww libGL-ww-getprocaddr libGL-ww-full_es3 libGL-ww-full_es3-getprocaddr libGL-ww-ofb libGL-ww-ofb-getprocaddr libGL-ww-ofb-full_es3 libGL-ww-ofb-full_es3-getprocaddr libGL-ww-webgl2 libGL-ww-webgl2-getprocaddr libGL-ww-webgl2-full_es3 libGL-ww-webgl2-full_es3-getprocaddr libGL-ww-webgl2-ofb libGL-ww-webgl2-ofb-getprocaddr libGL-ww-webgl2-ofb-full_es3 libGL-ww-webgl2-ofb-full_es3-getprocaddr libGL-ww-emu libGL-ww-emu-getprocaddr libGL-ww-emu-full_es3 libGL-ww-emu-full_es3-getprocaddr libGL-ww-emu-ofb libGL-ww-emu-ofb-getprocaddr libGL-ww-emu-ofb-full_es3 libGL-ww-emu-ofb-full_es3-getprocaddr libGL-ww-emu-webgl2 libGL-ww-emu-webgl2-getprocaddr libGL-ww-emu-webgl2-full_es3 libGL-ww-emu-webgl2-full_es3-getprocaddr libGL-ww-emu-webgl2-ofb libGL-ww-emu-webgl2-ofb-getprocaddr libGL-ww-emu-webgl2-ofb-full_es3 libGL-ww-emu-webgl2-ofb-full_es3-getprocaddr libGL-mt libGL-mt-getprocaddr libGL-mt-full_es3 libGL-mt-full_es3-getprocaddr libGL-mt-ofb libGL-mt-ofb-getprocaddr libGL-mt-ofb-full_es3 libGL-mt-ofb-full_es3-getprocaddr libGL-mt-webgl2 libGL-mt-webgl2-getprocaddr libGL-mt-webgl2-full_es3 libGL-mt-webgl2-full_es3-getprocaddr libGL-mt-webgl2-ofb libGL-mt-webgl2-ofb-getprocaddr libGL-mt-webgl2-ofb-full_es3 libGL-mt-webgl2-ofb-full_es3-getprocaddr libGL-mt-emu libGL-mt-emu-getprocaddr libGL-mt-emu-full_es3 libGL-mt-emu-full_es3-getprocaddr libGL-mt-emu-ofb libGL-mt-emu-ofb-getprocaddr libGL-mt-emu-ofb-full_es3 libGL-mt-emu-ofb-full_es3-getprocaddr libGL-mt-emu-webgl2 libGL-mt-emu-webgl2-getprocaddr libGL-mt-emu-webgl2-full_es3 libGL-mt-emu-webgl2-full_es3-getprocaddr libGL-mt-emu-webgl2-ofb libGL-mt-emu-webgl2-ofb-getprocaddr libGL-mt-emu-webgl2-ofb-full_es3 libGL-mt-emu-webgl2-ofb-full_es3-getprocaddr libwebgpu libwebgpu-ww libwebgpu-mt libwebgpu_cpp libwebgpu_cpp-ww libwebgpu_cpp-mt libfetch libfetch-ww libfetch-mt libwasmfs libwasmfs-icase libwasmfs-debug libwasmfs-debug-icase libwasmfs-asan libwasmfs-asan-icase libwasmfs-asan-debug libwasmfs-asan-debug-icase libwasmfs-ww libwasmfs-ww-icase libwasmfs-ww-debug libwasmfs-ww-debug-icase libwasmfs-ww-asan libwasmfs-ww-asan-icase libwasmfs-ww-asan-debug libwasmfs-ww-asan-debug-icase libwasmfs-mt libwasmfs-mt-icase libwasmfs-mt-debug libwasmfs-mt-debug-icase libwasmfs-mt-asan libwasmfs-mt-asan-icase libwasmfs-mt-asan-debug libwasmfs-mt-asan-debug-icase libubsan_minimal_rt libubsan_minimal_rt-ww libubsan_minimal_rt-mt libsanitizer_common_rt libsanitizer_common_rt-ww libsanitizer_common_rt-mt libubsan_rt libubsan_rt-ww libubsan_rt-mt liblsan_common_rt liblsan_common_rt-ww liblsan_common_rt-mt liblsan_rt liblsan_rt-ww liblsan_rt-mt libasan_rt libasan_rt-ww libasan_rt-mt libstubs libstubs-debug libbulkmemory libbulkmemory-asan crt1 crt1_reactor crt1_proxy_main crtbegin libstandalonewasm libstandalonewasm-nocatch libstandalonewasm-pure libstandalonewasm-nocatch-pure libstandalonewasm-memgrow libstandalonewasm-nocatch-memgrow libstandalonewasm-memgrow-pure libstandalonewasm-nocatch-memgrow-pure libnoexit libal libembind libembind-rtti libwasmfs_no_fs libwasmfs_noderawfs libhtml5 libasan_js libjsmath

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
