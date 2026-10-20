#!/usr/bin/env python3
"""Run with python3 -m unittest discover -p 'test_macos_artifacts.py'."""
import importlib.util
import json
from pathlib import Path
import platform
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location("assembler", Path(__file__).with_name("assemble-macos-dotnet.py"))
assembler = importlib.util.module_from_spec(spec)
spec.loader.exec_module(assembler)
bundle_spec = importlib.util.spec_from_file_location("bundler", Path(__file__).with_name("bundle-macos-cross.py"))
bundler = importlib.util.module_from_spec(bundle_spec)
bundle_spec.loader.exec_module(bundler)


class MacOSArtifacts(unittest.TestCase):
    @unittest.skipUnless(sys.platform == "darwin" and platform.machine() == "arm64", "requires native macOS ARM64")
    def test_transitive_dylibs_work_after_relocation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            original = root / "original"
            library = original / "lib"
            binary = original / "bin"
            library.mkdir(parents=True)
            binary.mkdir()
            (original / "answer.c").write_text("int answer(void) { return 42; }\n")
            (original / "middle.c").write_text("extern int answer(void); int middle(void) { return answer(); }\n")
            (original / "main.c").write_text("extern int middle(void); int main(void) { return middle() == 42 ? 0 : 1; }\n")
            subprocess.run(["clang", "-dynamiclib", str(original / "answer.c"),
                            "-Wl,-install_name,@rpath/libanswer.dylib", "-o", str(library / "libanswer.dylib")], check=True)
            subprocess.run(["clang", "-dynamiclib", str(original / "middle.c"), f"-L{library}", "-lanswer",
                            "-Wl,-install_name,@rpath/libmiddle.dylib", "-o", str(library / "libmiddle.dylib")], check=True)
            subprocess.run(["clang", str(original / "main.c"), f"-L{library}", "-lmiddle",
                            "-Wl,-rpath,@executable_path/../lib", "-o", str(binary / "smoke")], check=True)
            destination = root / "cross"
            bundler.bundle(binary / "smoke", destination)
            original.rename(root / "moved-original")
            subprocess.run(["env", "-u", "DYLD_LIBRARY_PATH", "-u", "DYLD_FALLBACK_LIBRARY_PATH",
                            str(destination / "smoke")], check=True)
            self.assertTrue((destination / "libanswer.dylib").is_file())
            self.assertTrue((destination / "libmiddle.dylib").is_file())

    def test_variants_preserve_payload_and_replace_all_cross_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for index, (name, variant, threads, jspi) in enumerate(assembler.VARIANTS):
                with self.subTest(variant=name):
                    compiler = root / variant / "cross"
                    compiler.mkdir(parents=True, exist_ok=True)
                    manifest = {"runtime_sha": ("a" if variant != "jit-mt" else "b") * 40,
                                "wasm_enable_threads": threads,
                                "mono_thread_suspend": "coop" if threads else "preemptive",
                                "host_rid": "osx-arm64"}
                    (compiler / "build.json").write_text(json.dumps(manifest))
                    executable = compiler / "mono-aot-cross"
                    executable.write_bytes(struct.pack("<II", 0xFEEDFACF, 0x0100000C) + variant.encode())
                    executable.chmod(0o755)
                    (compiler / "libtest.1.dylib").write_bytes(b"dependency")
                    if not (compiler / "libtest.dylib").exists():
                        (compiler / "libtest.dylib").symlink_to("libtest.1.dylib")
                    runtime = {"runtime_sha": manifest["runtime_sha"],
                               "wasm_enable_threads": threads, "wasm_enable_jspi": jspi}
                    payload = {"runtime-build.json": json.dumps(runtime).encode(),
                               "runtimes/browser-wasm/native/dotnet.native.wasm": bytes([index]),
                               "tasks/net10.0/WasmAppBuilder.dll": b"patched-task",
                               "tasks/net472/System.Memory.dll": b"companion"}
                    source = root / name
                    with zipfile.ZipFile(source, "w") as archive:
                        for path, data in payload.items():
                            archive.writestr(path, data)
                        archive.writestr("cross/mono-aot-cross", b"linux-elf")
                        archive.writestr("cross/nested/libold.so", b"linux-dependency")
                    destination = root / "output" / name
                    assembler.assemble(source, compiler, destination, threads, jspi)
                    with zipfile.ZipFile(destination) as archive:
                        for path, data in payload.items():
                            self.assertEqual(archive.read(path), data)
                        self.assertEqual(archive.read("cross/mono-aot-cross"), executable.read_bytes())
                        self.assertEqual(archive.getinfo("cross/mono-aot-cross").external_attr >> 16 & 0o777, 0o755)
                        self.assertTrue(stat.S_ISLNK(archive.getinfo("cross/libtest.dylib").external_attr >> 16))
                        self.assertEqual(archive.read("cross/libtest.dylib"), b"libtest.1.dylib")
                        self.assertFalse(any(".so" in path for path in archive.namelist()))
                    runtime["runtime_sha"] = "c" * 40
                    with zipfile.ZipFile(source, "w") as archive:
                        archive.writestr("runtime-build.json", json.dumps(runtime))
                    with self.assertRaisesRegex(ValueError, "runtime_sha"):
                        assembler.assemble(source, compiler, destination, threads, jspi)


if __name__ == "__main__":
    unittest.main()
