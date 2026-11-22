#!/usr/bin/env python3
"""Collects the APKs of one release for the Wings website.

Run from the repository root after `flutter build` (CI does this):

    python3 tools/site_release.py

It copies the three release packages into `site/downloads/v<version>/`, restores
the packages of previous releases from the live website so every old version
stays downloadable, merges `site/downloads/index.json`, and points
`site/updates/latest.json` at the new files while keeping its release notes.
"""

from __future__ import annotations

import datetime
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SITE = os.path.join(ROOT, "site")
DOWNLOADS = os.path.join(SITE, "downloads")
MANIFEST = os.path.join(SITE, "updates", "latest.json")
INDEX = os.path.join(DOWNLOADS, "index.json")
SITE_URL = "https://wingsapp.vercel.app"

ABIS = {
    "arm64-v8a": "app-arm64-v8a-release.apk",
    "armeabi-v7a": "app-armeabi-v7a-release.apk",
    "universal": "app-release.apk",
}


def read_version() -> tuple[str, int]:
    text = open(os.path.join(ROOT, "pubspec.yaml"), encoding="utf-8").read()
    match = re.search(r"^version:\s*([0-9.]+)\+([0-9]+)", text, re.M)
    if not match:
        raise SystemExit("pubspec.yaml has no x.y.z+build version")
    return match.group(1), int(match.group(2))


def fetch(url: str) -> bytes | None:
    try:
        with urllib.request.urlopen(url, timeout=60) as response:
            return response.read()
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError):
        return None


def restore_previous(index: dict) -> None:
    """Keeps every older APK available in the new deployment.

    Vercel deployments are snapshots: a file that is not part of the upload
    disappears. Copying the previous packages down first is what makes the
    archive keep working release after release.
    """
    for release in index.get("releases", []):
        for name, path in (release.get("files") or {}).items():
            if str(path).startswith(("http://", "https://")):
                continue
            relative = path.lstrip("/")
            target = os.path.join(SITE, relative)
            if os.path.exists(target):
                continue
            data = fetch(f"{SITE_URL}/{relative}")
            if not data or len(data) < 1024:
                print(f"skip missing older package: {path}")
                continue
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with open(target, "wb") as handle:
                handle.write(data)
            print(f"restored {path} ({len(data) // 1024} KiB)")


def main() -> None:
    version, build = read_version()
    tag = f"v{version}"
    index: dict = {"releases": []}
    if os.path.exists(INDEX):
        try:
            index = json.load(open(INDEX, encoding="utf-8"))
        except ValueError:
            index = {"releases": []}
    restore_previous(index)

    files: dict[str, str] = {}
    sizes: dict[str, int] = {}
    for abi, artifact in ABIS.items():
        source = os.path.join(ROOT, "build", "app", "outputs", "flutter-apk", artifact)
        if not os.path.exists(source):
            print(f"missing build output: {artifact}")
            continue
        # The V1.0 release uses the compact asset prefix (1.0), while the
        # application version remains 1.0.0 in pubspec.yaml.
        asset_version = version[:-2] if version.endswith(".0") else version
        target_name = f"wings-{asset_version}-{abi}.apk"
        files[abi] = f"https://github.com/lo-oord/Wings/releases/download/{tag}/{target_name}"
        sizes[abi] = os.path.getsize(source)
        print(f"packaged {target_name} ({os.path.getsize(source) // 1024} KiB)")

    releases = [r for r in index.get("releases", []) if r.get("version") != version]
    releases.insert(
        0,
        {
            "version": version,
            "build": build,
            "date": os.environ.get("RELEASE_DATE") or datetime.date.today().isoformat(),
            "files": files,
            "sizes": sizes,
        },
    )
    index = {"releases": releases}
    with open(INDEX, "w", encoding="utf-8") as handle:
        json.dump(index, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    manifest: dict = {}
    if os.path.exists(MANIFEST):
        manifest = json.load(open(MANIFEST, encoding="utf-8"))
    manifest.update(
        {
            "version": version,
            "build": build,
            "apk_url": files.get("universal", ""),
            "apk_urls": files,
            "page_url": f"{SITE_URL}/download",
        }
    )
    with open(MANIFEST, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    print(f"release {tag} is ready with {len(releases)} version(s) in the archive")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:  # pragma: no cover
        sys.exit(error.returncode)
