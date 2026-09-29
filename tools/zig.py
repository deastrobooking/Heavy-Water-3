#!/usr/bin/env python3
"""Run the project's pinned Zig; bootstrap locally without changing PATH. Python 3.10+."""
import hashlib
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent.parent
VERSION = "0.16.0-dev.3142+5ccfeb926"
HASHES = {
    "aarch64-macos": "0ab967ed551814e7450ce9b6dc11853c96697e9307b8f9bb4283669d3a9860a8",
    "x86_64-macos": "7ff94c3c5b70e6b90a9aa74308e05f36620a1c0f2b5c7b62635310eb1c93310b",
    "x86_64-linux": "ab4e7bf6358a63e50aeec2243547b63791c75523685ad458d0c339448d723a88",
    "aarch64-linux": "4801ddd0fe720e5b0c177230caa2301ed3ce2e3701beec6c18888b49244c1a5a",
    "x86_64-windows": "3d7adb49db5a80d0c5f29a5dc692dbdf765102d06bff456efc00e5d3a19a92f8",
}


def main():
    system = {"Darwin": "macos", "Linux": "linux", "Windows": "windows"}.get(platform.system())
    arch = {"arm64": "aarch64", "aarch64": "aarch64", "AMD64": "x86_64", "x86_64": "x86_64"}.get(platform.machine())
    host = f"{arch}-{system}"
    if host not in HASHES:
        raise RuntimeError(f"No pinned download for {platform.system()} / {platform.machine()}")
    name = f"zig-{host}-{VERSION}"
    cache = ROOT / ".tools"
    binary = cache / name / ("zig.exe" if system == "windows" else "zig")
    if not binary.exists():
        cache.mkdir(exist_ok=True)
        suffix = ".zip" if system == "windows" else ".tar.xz"
        url = f"https://pkg.hexops.org/zig/{name}{suffix}"
        print(f"Installing Zig {VERSION} in {cache}", file=sys.stderr)
        with tempfile.TemporaryDirectory(dir=cache) as temporary:
            archive = Path(temporary) / ("compiler" + suffix)
            with urllib.request.urlopen(url, timeout=120) as response, archive.open("wb") as output:
                shutil.copyfileobj(response, output)
            digest = hashlib.sha256(archive.read_bytes()).hexdigest()
            if digest != HASHES[host]:
                raise RuntimeError("Compiler checksum mismatch; archive was not extracted")
            # Extract only the checksum-pinned official archive into a private staging directory.
            if suffix == ".zip":
                with zipfile.ZipFile(archive) as package:
                    package.extractall(temporary)
            else:
                with tarfile.open(archive) as package:
                    package.extractall(temporary)
            shutil.move(str(Path(temporary) / name), str(cache / name))
    actual = subprocess.check_output([str(binary), "version"], text=True).strip()
    if actual != VERSION:
        raise RuntimeError(f"Expected Zig {VERSION}, found {actual}")
    os.chdir(ROOT)
    return subprocess.call([str(binary), *sys.argv[1:]])


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        sys.exit(f"toolchain: {error}")
