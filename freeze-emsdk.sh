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

# .NET 11 provisions the emsdk (`build.sh -os browser -s provision.emsdk`) into a tool cache,
# $(WasmToolCacheDir)emscripten/<version>-<host rid>/ (eng/wasm/WasmToolCache.props). Resolve it with the runtime's own
# eng/wasm/wasm-tool-cache.sh, so the cache root (DOTNET_WASM_TOOL_CACHE_DIR, else the main checkout's
# .dotnet/wasm-tools), worktree anchoring and host RID (linux-x64, osx-arm64, ...) are exactly the build's; it only
# reports an entry whose .complete sentinel exists. .NET 10 kept the emsdk in src/mono/browser/emsdk.
wasm_tool_cache_emsdk() {
  local root="$1"
  [[ -f "$root/eng/wasm/wasm-tool-cache.sh" ]] || return 1
  (
    . "$root/eng/wasm/wasm-tool-cache.sh"
    wasm_tool_cache_dir emscripten "$root/src/mono/browser/emscripten-version.txt" "$root"
  )
}

EMSDK_SRC=""
if [[ -d "$RUNTIME_ROOT/src/mono/browser/emsdk" ]]; then
  EMSDK_SRC="$RUNTIME_ROOT/src/mono/browser/emsdk"
elif CACHE_EMSDK="$(wasm_tool_cache_emsdk "$RUNTIME_ROOT")" && [[ -d "$CACHE_EMSDK/emscripten" ]]; then
  EMSDK_SRC="$CACHE_EMSDK"
elif [[ -d "$RUNTIME_ROOT/emscripten" && -d "$RUNTIME_ROOT/bin" ]]; then
  EMSDK_SRC="$RUNTIME_ROOT"
else
  echo "error: unable to locate emsdk root from input: $RUNTIME_ROOT" >&2
  echo "expected <runtime-root>/src/mono/browser/emsdk (.NET 10), the runtime's wasm tool cache (.NET 11)," >&2
  echo "or a direct emsdk root" >&2
  exit 1
fi

EMSDK_SRC="$(cd "$EMSDK_SRC" && pwd)"

# Patch and rebuild a COPY. The source is the toolchain the runtime itself builds with (and, in .NET 11, a
# cache shared by every worktree of the checkout); patching it in place would make the next runtime build use a
# patched emscripten without anyone deciding to.
# On disk, beside the output (or FREEZE_TMPDIR): the copy holds a whole LLVM toolchain, and /tmp is often a RAM-backed
# tmpfs that other work (perf maps, browser profiles) also fills.
STAGE_PARENT="${FREEZE_TMPDIR:-$(dirname "$OUTPUT_ZIP")}"
mkdir -p "$STAGE_PARENT"
# Absolute: the staged paths become EM_CONFIG / EM_CACHE, which embuilder rejects when relative (e.g. the output is
# ./emsdk-frozen.zip, so the parent is ".").
STAGE_PARENT="$(cd "$STAGE_PARENT" && pwd)"
STAGE_ROOT="$(mktemp -d -p "$STAGE_PARENT" freeze-emsdk-XXXXXX)"
trap 'rm -rf "$STAGE_ROOT"' EXIT
echo "Copying $EMSDK_SRC to a staging copy"
cp -a "$EMSDK_SRC/." "$STAGE_ROOT/emsdk/"
EMSDK_SRC="$STAGE_ROOT/emsdk"

# Function to apply a patch file to the emsdk emscripten directory
apply_patch() {
  local patch_file="$1"
  
  # A missing patch is an error, not a skip: a renamed file would otherwise drop out of the toolchain silently.
  if [[ ! -f "$patch_file" ]]; then
    echo "error: patch not found: $patch_file" >&2
    exit 1
  fi
  
  if ! patch -p1 --forward --directory "$EMSDK_SRC/emscripten" < "$patch_file"; then
    echo "error: failed to apply patch: $patch_file" >&2
    exit 1
  fi
  
  # Clean up any .rej files left behind
  find "$EMSDK_SRC/emscripten" -name "*.rej" -delete
}

for path in \
  "$EMSDK_SRC/emsdk_env.sh" \
  "$EMSDK_SRC/emscripten/.emscripten"
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
if [[ ! -f "$EMSDK_SRC/emscripten/src/lib/libwasmfs_opfs.js" ]]; then
  echo "error: missing wasmfs OPFS src/lib/libwasmfs_opfs.js in emsdk source (emscripten 6 layout)" >&2
  exit 1
fi

# emscripten 6.0.2. Dropped as upstream in 6.0.2: emsdk.patch (async html5 callbacks), .2 (ProxyWorker ctor
# race, #24370), .5 (proxy_finish signal before unlock, #26582), .7 (system queue under its own mutex, the R479
# deadlock, 21a3a81daf). .3 is now a backport of upstream #27937 (readwrite-unsafe OPFS handles, in 7.0.0).
apply_patch "${SCRIPT_DIR}/emsdk.3.patch"
apply_patch "${SCRIPT_DIR}/emsdk.4.patch"
apply_patch "${SCRIPT_DIR}/emsdk.6.patch"
apply_patch "${SCRIPT_DIR}/emsdk.8.patch"
apply_patch "${SCRIPT_DIR}/emsdk.9.patch"
apply_patch "${SCRIPT_DIR}/emsdk.10.patch"
apply_patch "${SCRIPT_DIR}/emsdk.11.patch"
apply_patch "${SCRIPT_DIR}/emsdk.12.patch"

# Rebuild after patching so the archives contain patched code as well as patched sources. The list is every archive
# and crt object the provisioned cache already holds, read BEFORE embuilder runs: the cache's sanity.txt names the
# toolchain path of the machine that built it, so embuilder starts by clearing the whole cache (R502), and anything not
# on the list would then be missing from the frozen cache. Reading it from the cache also keeps the names right across
# emscripten versions (6.x names variants -wasmexcept / -legacyexcept / -wasmsjlj; 3.1.56's list did not carry over).
EMSDK_CACHE="$EMSDK_SRC/emscripten/cache"
EMSDK_SYSROOT_LIB="$EMSDK_CACHE/sysroot/lib/wasm32-emscripten"
# macOS ships Bash 3.2, which does not have mapfile.
EMBUILDER_LIBS=()
while IFS= read -r lib; do
  EMBUILDER_LIBS+=("$lib")
done < <(cd "$EMSDK_SYSROOT_LIB" && ls -1 *.a *.o 2>/dev/null | sed -E 's/\.(a|o)$//' | sort -u)
if [[ ${#EMBUILDER_LIBS[@]} -lt 50 ]]; then
  echo "error: the provisioned cache holds only ${#EMBUILDER_LIBS[@]} archives in $EMSDK_SYSROOT_LIB" >&2
  exit 1
fi
echo "Rebuilding ${#EMBUILDER_LIBS[@]} cache entries via embuilder (cache=$EMSDK_CACHE)"
# "sysroot" first reinstalls the headers, so the patched ones (emsdk.9's wasmfs.h, emsdk.12's new <sys/eventfd.h>,
# which libc's eventfd.c includes) reach the cache even when embuilder does not start by clearing it.
# EM_FROZEN_CACHE must be EMPTY to unfreeze: .NET's .emscripten computes FROZEN_CACHE = bool(os.getenv('EM_FROZEN_CACHE',
# 'True')), so "0" is a non-empty string and reads as frozen.
EM_CONFIG="$EMSDK_SRC/emscripten/.emscripten" \
  EM_CACHE="$EMSDK_CACHE" \
  EM_FROZEN_CACHE= \
  "$EMSDK_SRC/emscripten/embuilder" --force build sysroot "${EMBUILDER_LIBS[@]}"

echo "Verifying embuilder populated expected libraries in $EMSDK_SYSROOT_LIB"
for required in libc-mt.a libc.a libclang_rt.builtins.a libclang_rt.builtins-mt.a libsockets-mt.a libwasmfs-mt.a libdlmalloc-mt.a; do
  if [[ ! -f "$EMSDK_SYSROOT_LIB/$required" ]]; then
    echo "error: embuilder did not produce $required in $EMSDK_SYSROOT_LIB" >&2
    echo "(cache directory contents:)" >&2
    ls -1 "$EMSDK_SYSROOT_LIB" >&2 || true
    exit 1
  fi
done
echo "Cache populated with $(find "$EMSDK_SYSROOT_LIB" -maxdepth 1 -name '*.a' | wc -l) archives"

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
            # ZipInfo.from_file() defaults compress_type to ZIP_STORED, which
            # overrides the ZipFile-level compression=ZIP_DEFLATED. Force
            # DEFLATE per entry so files are actually compressed.
            info.compress_type = zipfile.ZIP_DEFLATED
            with open(full, "rb") as f:
                zf.writestr(info, f.read(), compresslevel=9)
PY

echo "frozen emsdk zip created: $OUTPUT_ZIP"
shasum -a 256 "$OUTPUT_ZIP"
