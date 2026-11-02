"""CycloneDX 1.6 SBOM of the built site: every shipped file with its SHA-256.

usage: bundle-sbom.py <dist-dir> <version> <out.cdx.json>

The bundle has no package manifests (Astro inlines and hashes the JS), so a
package scanner finds nothing in it. This lists what is actually served, so
anyone can check a deployed file against the signed SBOM. The packages that
went into the bundle are in site-npm.cdx.json.
"""
import hashlib
import json
import os
import sys
import uuid
from datetime import datetime, timezone


def main():
    dist, version, out = sys.argv[1], sys.argv[2], sys.argv[3]
    files = []
    for base, dirs, names in os.walk(dist):
        dirs.sort()
        rel_base = os.path.relpath(base, dist)
        if rel_base.split(os.sep)[:2] == [".well-known", "sbom"]:
            continue  # the SBOMs themselves are published beside the bundle, not in it
        for name in sorted(names):
            path = os.path.join(base, name)
            rel = os.path.relpath(path, dist).replace(os.sep, "/")
            with open(path, "rb") as f:
                digest = hashlib.sha256(f.read()).hexdigest()
            files.append({"type": "file", "bom-ref": f"file:{rel}", "name": rel,
                          "hashes": [{"alg": "SHA-256", "content": digest}]})
    if not files:
        raise SystemExit(f"bundle-sbom: no files under {dist}")
    bom = {
        "bomFormat": "CycloneDX", "specVersion": "1.6", "version": 1,
        "serialNumber": f"urn:uuid:{uuid.uuid4()}",
        "metadata": {
            "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "component": {"type": "application", "bom-ref": "meshcore-paths-site",
                          "name": "meshcore-paths-site", "version": version},
        },
        "components": files,
        "dependencies": [{"ref": "meshcore-paths-site", "dependsOn": [c["bom-ref"] for c in files]}],
    }
    with open(out, "w", encoding="utf-8") as f:
        json.dump(bom, f, indent=1)
    print(f"{out}: {len(files)} files")


if __name__ == "__main__":
    main()
