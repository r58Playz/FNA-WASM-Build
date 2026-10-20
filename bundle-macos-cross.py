#!/usr/bin/env python3
"""Bundle an ARM64 Mono cross compiler and relocate its non-system dylibs."""
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def system_library(name):
    return name.startswith(("/usr/lib/", "/System/Library/"))


def rpaths(binary):
    return re.findall(r"cmd LC_RPATH\n\s+cmdsize \d+\n\s+path (.*?) \(offset", output("otool", "-l", str(binary)))


def dependencies(binary):
    # otool -L includes a dylib's own LC_ID_DYLIB; do not treat it as a dependency.
    identities = output("otool", "-D", str(binary)).splitlines()[1:]
    return [line.strip().split(" (compatibility version", 1)[0]
            for line in output("otool", "-L", str(binary)).splitlines()[1:]
            if line.strip().split(" (compatibility version", 1)[0] not in identities]


def expand(name, binary, executable):
    return Path(name.replace("@loader_path", str(binary.parent))
                .replace("@executable_path", str(executable.parent)))


def resolve(name, binary, executable, inherited_rpaths):
    if name.startswith("@rpath/"):
        suffix = name[len("@rpath/"):]
        candidates = [expand(path, binary, executable) / suffix for path in rpaths(binary)]
        candidates += [path / suffix for path in inherited_rpaths]
    else:
        candidates = [expand(name, binary, executable)]
    for candidate in candidates:
        if candidate.is_file():
            return candidate.resolve()
    raise RuntimeError(f"Cannot resolve {name} required by {binary}: {candidates}")


def bundle(executable, destination):
    destination.mkdir(parents=True, exist_ok=False)
    executable = executable.resolve()
    pending = [(executable, [])]
    copied = {}
    while pending:
        source, inherited_rpaths = pending.pop()
        if source in copied:
            continue
        if output("lipo", "-archs", str(source)) != "arm64":
            raise RuntimeError(f"Expected ARM64-only Mach-O: {source}")
        target = destination / source.name
        if target.exists():
            raise RuntimeError(f"Conflicting dependency basename: {source}")
        shutil.copy2(source, target)
        # Some package files are read-only; install_name_tool must be able to edit.
        target.chmod(target.stat().st_mode | 0o200)
        copied[source] = target
        search = [expand(path, source, executable) for path in rpaths(source)] + inherited_rpaths
        for name in dependencies(source):
            if system_library(name):
                continue
            dependency = resolve(name, source, executable, search)
            pending.append((dependency, search))
            subprocess.run(["install_name_tool", "-change", name,
                            f"@loader_path/{dependency.name}", str(target)], check=True)
        if source != executable:
            subprocess.run(["install_name_tool", "-id", f"@loader_path/{target.name}", str(target)], check=True)
    for target in copied.values():
        # Editing a load command invalidates an existing ARM64 code signature.
        subprocess.run(["codesign", "--force", "--sign", "-", str(target)], check=True)
        subprocess.run(["codesign", "--verify", str(target)], check=True)
        for name in dependencies(target):
            if not system_library(name) and not (name.startswith("@loader_path/") and
                                                 (destination / name[len("@loader_path/"):]).is_file()):
                raise RuntimeError(f"Unbundled dependency in {target}: {name}")


def main():
    if len(sys.argv) != 5 or sys.argv[4] not in ("true", "false"):
        raise SystemExit("usage: bundle-macos-cross.py <mono-aot-cross> <cross-dir> <runtime-root> <pthread:true|false>")
    executable, destination, runtime = map(Path, sys.argv[1:4])
    threads = sys.argv[4] == "true"
    bundle(executable, destination)
    manifest = {
        "runtime_sha": output("git", "-C", str(runtime), "rev-parse", "HEAD"),
        "wasm_enable_threads": threads,
        "mono_thread_suspend": "coop" if threads else "preemptive",
        "host_rid": "osx-arm64",
    }
    (destination / "build.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
