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
STABLE_VERSION = "0.17.0"
DEV_VERSION = "0.18.0-dev.146+35accc06e"
MACH_VERSION = "0.16.0-dev.3142+5ccfeb926"
HASHES = {
    MACH_VERSION: {
        "aarch64-macos": "0ab967ed551814e7450ce9b6dc11853c96697e9307b8f9bb4283669d3a9860a8",
        "x86_64-macos": "7ff94c3c5b70e6b90a9aa74308e05f36620a1c0f2b5c7b62635310eb1c93310b",
        "x86_64-linux": "ab4e7bf6358a63e50aeec2243547b63791c75523685ad458d0c339448d723a88",
        "aarch64-linux": "4801ddd0fe720e5b0c177230caa2301ed3ce2e3701beec6c18888b49244c1a5a",
        "x86_64-windows": "3d7adb49db5a80d0c5f29a5dc692dbdf765102d06bff456efc00e5d3a19a92f8",
    },
    "0.17.0": {
        "aarch64-macos": "b607e9b9234790a008116ae5bdb71c6243b84b9fb42a53a9e70fde41c06c536a",
        "x86_64-macos": "4f9a1c5269aa17ebda5e6d3c2b89d6cbf36f7d2b22a0306e9ab98f25f95529c6",
        "x86_64-linux": "1cbe9df9f27e6b78d14ccbca43b6703a404ef79ef1c463de901d7f088d4e2026",
        "aarch64-linux": "9e8d11661d4ae3bd57702a3832781e23ad151dde5798e16a5ccd503f65234ff8",
        "x86_64-windows": "b5663f69581dcf391293fbf16c06cb80d81d806545ce618b4d0bab7f0eb8c428",
        "aarch64-windows": "0a59d91fa1cb40cf068e9b0954434ce973500c7a2ea749f1e01af62cdab52d26",
        "x86-windows": "c7b83507549c7bcd42cd58c4910b47037f4150ed7778e11b3684f130620969d1",
    },
    "0.18.0-dev.146+35accc06e": {
        "aarch64-macos": "7200a37ab074878c28e4baa3608667b99ceef2bdccd7fa8009014a71f529a242",
        "x86_64-macos": "b97b6314f73cf14f55f3ad1b7c316ccf2a6e0aec3895e318f1f0f7f35fc911db",
        "x86_64-linux": "1061dbb921f62b67765810609a80c17fa69eeced9f21e9a7e0d06b4e0d7a3715",
        "aarch64-linux": "09251ef727afa183aabb904bf70300614de58963ad70329c9e3ecda03ebdb949",
        "x86_64-windows": "ec5d64aae44b54ce8425ecd7b40f1fa5c8061d1dc80939b02ed036513d69ae67",
        "aarch64-windows": "1b221ff8185872e6cc57eafc349ddc739404be09f688eab76a15912277411ea7",
        "x86-windows": "f0b1de02707a46dc012dcd48725345b86299f9681baca1d4d3c39c072512eab4",
    },
}


def main():
    channel = os.environ.get("HEAVYWATER_ZIG_CHANNEL", "mach")
    versions = {"mach": MACH_VERSION, "0.17": STABLE_VERSION, "0.18-dev": DEV_VERSION}
    if channel not in versions:
        raise RuntimeError("HEAVYWATER_ZIG_CHANNEL must be 'mach', '0.17', or '0.18-dev'")
    version = versions[channel]
    system = {"Darwin": "macos", "Linux": "linux", "Windows": "windows"}.get(platform.system())
    arch = {"arm64": "aarch64", "aarch64": "aarch64", "AMD64": "x86_64", "x86_64": "x86_64"}.get(platform.machine())
    host = f"{arch}-{system}"
    if host not in HASHES[version]:
        raise RuntimeError(f"No pinned download for {platform.system()} / {platform.machine()}")
    name = f"zig-{host}-{version}"
    cache = ROOT / ".tools"
    binary = cache / name / ("zig.exe" if system == "windows" else "zig")
    if not binary.exists():
        cache.mkdir(exist_ok=True)
        suffix = ".zip" if system == "windows" else ".tar.xz"
        if version == STABLE_VERSION:
            url = f"https://ziglang.org/download/{version}/{name}{suffix}"
        elif version == DEV_VERSION:
            url = f"https://ziglang.org/builds/{name}{suffix}"
        else:
            url = f"https://pkg.hexops.org/zig/{name}{suffix}"
        print(f"Installing Zig {version} in {cache}", file=sys.stderr)
        with tempfile.TemporaryDirectory(dir=cache) as temporary:
            archive = Path(temporary) / ("compiler" + suffix)
            with urllib.request.urlopen(url, timeout=120) as response, archive.open("wb") as output:
                shutil.copyfileobj(response, output)
            digest = hashlib.sha256(archive.read_bytes()).hexdigest()
            if digest != HASHES[version][host]:
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
    if actual != version:
        raise RuntimeError(f"Expected Zig {version}, found {actual}")
    os.chdir(ROOT)
    return subprocess.call([str(binary), *sys.argv[1:]])


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        sys.exit(f"toolchain: {error}")
