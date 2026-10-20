#!/usr/bin/env python3
"""Replace each Linux runtime ZIP's cross/ with the matching macOS bundle."""
import argparse
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import zipfile


VARIANTS = (
    ("ST-dotnet.zip", "st", False, False),
    ("dotnet.zip", "mt", True, False),
    ("dotnet-jit.zip", "jit-mt", True, False),
    ("dotnet-jspi-jit.zip", "jit-mt", True, True),
)


def assemble(source, compiler, destination, threads, jspi):
    with zipfile.ZipFile(source) as archive:
        runtime = json.loads(archive.read("runtime-build.json"))
    cross = json.loads((compiler / "build.json").read_text())
    for key, expected in (("runtime_sha", runtime["runtime_sha"]),
                          ("wasm_enable_threads", threads),
                          ("mono_thread_suspend", "coop" if threads else "preemptive"),
                          ("host_rid", "osx-arm64")):
        if cross[key] != expected:
            raise ValueError(f"{source.name}: compiler {key}={cross[key]!r}, expected {expected!r}")
    if runtime["wasm_enable_threads"] != threads or runtime["wasm_enable_jspi"] != jspi:
        raise ValueError(f"Wrong runtime configuration: {source}")
    executable = compiler / "mono-aot-cross"
    if not executable.is_file() or executable.stat().st_mode & 0o111 == 0:
        raise ValueError(f"Compiler missing or not executable: {executable}")
    with executable.open("rb") as stream:
        if stream.read(8) != struct.pack("<II", 0xFEEDFACF, 0x0100000C):
            raise ValueError(f"Expected ARM64 Mach-O compiler: {executable}")
    # Staging each variant separately also prevents mixing the JIT/JSPI payloads.
    with tempfile.TemporaryDirectory(prefix="fna-macos-dotnet-") as temporary:
        stage = Path(temporary)
        subprocess.run(["unzip", "-q", str(source.resolve()), "-d", str(stage)], check=True)
        shutil.rmtree(stage / "cross")
        shutil.copytree(compiler, stage / "cross", symlinks=True)
        # zip -y stores symlinks; Unix modes retain the compiler's executable bits.
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.unlink(missing_ok=True)
        subprocess.run(["zip", "-qry", str(destination.resolve()), "."], cwd=stage, check=True)
    with zipfile.ZipFile(destination) as archive:
        if archive.getinfo("cross/mono-aot-cross").external_attr >> 16 & 0o111 == 0:
            raise ValueError(f"ZIP lost executable permissions: {destination}")
    print(f"Created {destination}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifacts", type=Path, help="directory containing the Linux runtime ZIPs")
    parser.add_argument("compilers", type=Path, help="extracted macOS bundles: st/cross, mt/cross, jit-mt/cross")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    for name, compiler, threads, jspi in VARIANTS:
        matches = list(args.artifacts.rglob(name))
        if len(matches) != 1:
            raise ValueError(f"Expected one {name} under {args.artifacts}, found {matches}")
        destination = args.output / name.replace(".zip", "-osx-arm64.zip")
        assemble(matches[0], args.compilers / compiler / "cross", destination, threads, jspi)


if __name__ == "__main__":
    main()
