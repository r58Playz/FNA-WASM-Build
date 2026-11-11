# FNA-WASM-Build


[![WASM Build (FNA)](https://github.com/r58Playz/FNA-WASM-Build/actions/workflows/WASM.FNA.yml/badge.svg)](https://github.com/r58Playz/FNA-WASM-Build/actions/workflows/WASM.FNA.yml)

This repo is for automating the build of WebAssembly (WASM) native libraries for [FNA](https://fna-xna.github.io/) and [MonoGame](https://monogame.net/), including:

* [SDL3.a](https://github.com/libsdl-org/SDL) - Simple DirectMedia Layer.
* [SDL2.a](https://github.com/libsdl-org/sdl2-compat) - Simple DirectMedia Layer (via sdl2-compat) 
* [FNA3D.a](https://github.com/FNA-XNA/FNA3D) - 3D graphics library for FNA.
* [FAudio.a](https://github.com/FNA-XNA/FAudio) - XAudio reimplementation for FNA.
* [openssl](https://github.com/openssl/openssl) - OpenSSL WASM.
* `liba` + `hot_reload_detour` - Library used for MonoMod on WASM.
* [dotnet](https://github.com/dotnet/runtime) - Patched dotnet wasm multithreaded runtime for MonoMod on WASM. Also includes custom WASM JIT

There is currently just one workflow:
1.  **WASM Build (FNA)**.  

## Patches
This fork contains a few patches (and uses SDL3 as the base):
- `SDL3.patch` fixes some issues with `EM_ASM` not being proxied to main thread.
- `SDL2.patch` (for sdl2-compat) and `SDL3-SDL2.patch` (for sdl3) to build a cursed static build of sdl2-compat
- `FNA3D.patch` adds `-pthread` to the `CFLAGS` so FNA3D is built with WASM threads support.
- `dotnet.patch` patches the dotnet runtime so MonoMod can be used.

It also builds dotnet for macOS, combining macos built mono aot cross with linux built dlls.

## Usage

Go to the Actions tab and download the .zip artifact from the latest workflow run.  
~~See for further details:  https://gist.github.com/TheSpydog/e94c8c23c01615a5a3b2cc1a0857415c~~ (out of date)

## Frozen emsdk artifact

The workflow also produces `emsdk.zip` on Linux and `emsdk-osx-arm64.zip` on macOS. Each archive is a frozen copy of
the emsdk the patched runtime provisions (`./build.sh -os browser -s provision.emsdk`), including dotnet-style
`emsdk_env` and `.emscripten` configuration. In .NET 11 that emsdk lives in the runtime's wasm tool cache
(`<main checkout>/.dotnet/wasm-tools/emscripten/<version>-<host rid>`, or under `DOTNET_WASM_TOOL_CACHE_DIR`); .NET 10
kept it in `src/mono/browser/emsdk`. It is intended for consumers that need emsdk behavior to match dotnet runtime
packaging.

For local generation after building runtime in `liba/runtime`:

```bash
./freeze-emsdk.sh ./liba/runtime ./Binaries/emsdk-frozen.zip
```
