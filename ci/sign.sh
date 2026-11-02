#!/usr/bin/env bash
# ci/sign.sh — sign what ships, after ci/pre-pr.sh passed (main only).
#
#   COSIGN_PRIVATE_KEY, COSIGN_PASSWORD   from CI secrets (never on argv)
#
# Signs every SBOM and a tarball of the exact site bundle with the project
# key; signatures go next to the SBOMs at /.well-known/sbom/. Verify with the
# committed public key:
#   cosign verify-blob --key cosign.pub --bundle <file>.sigstore.json <file>
# No transparency-log upload: nothing leaves CI but the files we publish.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${COSIGN_PRIVATE_KEY:?}" "${COSIGN_PASSWORD:?}"
out=site/dist/.well-known/sbom
tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
  --exclude=./.well-known/sbom -C site/dist -czf "$out/site-bundle.tar.gz" .
for f in "$out"/*.json "$out/site-bundle.tar.gz" "$out/SHA256SUMS"; do
  cosign sign-blob --yes --key env://COSIGN_PRIVATE_KEY --use-signing-config=false --tlog-upload=false \
    --bundle "$f.sigstore.json" "$f" >/dev/null
  cosign verify-blob --key cosign.pub --insecure-ignore-tlog --bundle "$f.sigstore.json" "$f" >/dev/null
  echo "signed $(basename "$f")"
done
