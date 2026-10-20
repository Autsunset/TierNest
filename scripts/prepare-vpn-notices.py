#!/usr/bin/env python3
"""Bundle the pinned Cargo dependency declarations and available license texts.

Generated paths and manifests contain no developer filesystem paths. The full
locked Android dependency graph is included, including build tools and both ABIs.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parent.parent
packages = {}
for target in ("aarch64-linux-android", "x86_64-linux-android"):
    metadata = json.loads(subprocess.check_output([
        "cargo", "+1.95.0", "metadata", "--locked", "--offline", "--format-version", "1",
        "--filter-platform", target, "--manifest-path", str(root / "native/vpn/Cargo.toml"),
    ], env=os.environ))
    packages.update((package["id"], package) for package in metadata["packages"])
output = root / "android/app/build/generated/vpnNotices/licenses/rust"
if output.exists():
    shutil.rmtree(output)
output.mkdir(parents=True, exist_ok=True)
notices = []
for package in sorted(packages.values(), key=lambda p: (p["name"], p["version"])):
    source = Path(package["manifest_path"]).parent
    destination = output / (package["name"] + "-" + package["version"])
    files = []
    candidates = list(source.iterdir())
    if package.get("license_file"):
        candidates.append(source / package["license_file"])
    # Workspace crates sometimes keep their license at the repository root.
    if package.get("source", "") and package["source"].startswith("git+"):
        candidates.extend(source.parent.glob("LICENSE*"))
        candidates.extend(source.parent.glob("COPYING*"))
    for file in sorted(set(candidates)):
        if file.is_file() and file.name.upper().startswith(("LICENSE", "LICENCE", "COPYING", "NOTICE")):
            destination.mkdir(exist_ok=True)
            shutil.copyfile(file, destination / file.name)
            files.append(str((destination / file.name).relative_to(output)))
    notices.append({"name": package["name"], "version": package["version"],
        "license": package.get("license"), "repository": package.get("repository"),
        "source": package.get("source") or "TierNest/native/vpn", "license_files": files})
(output / "dependencies.json").write_text(json.dumps(notices, ensure_ascii=False, indent=2) + "\n")
print(f"Bundled notices for {len(notices)} locked Rust packages")
