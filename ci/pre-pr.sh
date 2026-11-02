#!/usr/bin/env bash
# The sh -c scripts below are single-quoted on purpose: paths arrive as $0/$1.
# shellcheck disable=SC2016
# ci/pre-pr.sh — the one gate, identical locally and in CI:
#
#   nix develop -c ci/pre-pr.sh
#
# Stages (each writes machine-readable output under reports/; the last stage
# fails the run if any scanner wrote nothing, so a silently skipped scan can
# never pass):
#   lint     shellcheck, actionlint, zizmor (workflow security), tofu fmt
#   site     npm ci, npm audit, unit tests (must run > 0), build
#   infra    tofu validate, trivy config (IaC misconfiguration)
#   secrets  gitleaks (full git history + build output), trufflehog (same,
#            --no-verification: candidate secrets are never sent anywhere)
#   sast     semgrep with the pinned community rules (flake input), no metrics
#   sbom     CycloneDX: npm dependency tree, the built site, the Nix toolchain;
#            (sbomnix: licenses + CPEs from the locked nixpkgs); each validated;
#            one merged SBOM; copied into the site at
#            /.well-known/sbom/ with SHA-256 sums
#   sca      trivy (vuln + license + secret over the repo, accepted findings
#            in .trivyignore.yaml with reasons), grype and
#            osv-scanner over the SBOM / lockfile
#
# Gate: HIGH or CRITICAL in anything that ships (npm runtime deps, the site
# bundle, the IaC) fails. The Nix toolchain SBOM is scanned and REPORTED, not
# gated: it is build-time only and CVE matching against nixpkgs versions is
# mostly false positives (patched in place, version strings unchanged).
#
# Network: npm registry (npm ci / audit), the vulnerability databases trivy
# (ghcr.io), grype (grype.anchore.io) and osv-scanner (api.osv.dev) need.
# No scanner uploads code or findings; semgrep runs with --metrics=off.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
R="$root/reports"
rm -rf "$R"
mkdir -p "$R/sbom"
: "${SEMGREP_RULES:?run inside nix develop (the flake pins the semgrep rules)}"
fail=0
stage() { printf '\n=== %s ===\n' "$*"; }
gate() {  # name, command...: run, remember failure, keep going so every report exists
  local name="$1"; shift
  if "$@"; then echo "ok: $name"; else echo "::error::FAILED: $name"; fail=1; fi
}

stage lint
gate shellcheck shellcheck ci/*.sh .githooks/*
gate actionlint actionlint -shellcheck= -config-file ci/actionlint.yaml .forgejo/workflows/*.yml .github/workflows/*.yml
gate zizmor sh -c 'zizmor --offline --format sarif .forgejo/workflows .github/workflows >"$0/zizmor.sarif"; s=$?; zizmor --offline .forgejo/workflows .github/workflows; exit $s' "$R"
gate "tofu fmt" tofu -chdir=infra fmt -check -diff -recursive

stage site
(cd site && npm ci --no-fund --no-audit --loglevel=error)
gate "npm audit" sh -c 'cd site && npm audit --omit=dev --audit-level=high --json >"$0/npm-audit.json"; s=$?; jq -r ".metadata.vulnerabilities" "$0/npm-audit.json"; exit $s' "$R"
gate "unit tests" bash -c 'cd site && npm test 2>&1 | tee "$0/tests.tap"; exit "${PIPESTATUS[0]:-0}"' "$R"
gate "build" sh -c 'cd site && npm run build'

stage infra
gate "tofu validate" sh -c 'cd infra && tofu init -backend=false -input=false >/dev/null && tofu validate'
gate "trivy config" trivy config --quiet --exit-code 1 --severity HIGH,CRITICAL --format json --output "$R/trivy-config.json" infra

stage secrets
gate "gitleaks history" gitleaks git . --no-banner --redact --exit-code 1 --report-format sarif --report-path "$R/gitleaks-git.sarif"
gate "gitleaks build output" gitleaks dir site/dist --no-banner --redact --exit-code 1 --report-format sarif --report-path "$R/gitleaks-dist.sarif"
gate "trufflehog history" sh -c 'trufflehog git "file://$1" --no-verification --fail --json >"$0/trufflehog-git.jsonl" 2>"$0/trufflehog-git.log"' "$R" "$root"
gate "trufflehog build output" sh -c 'trufflehog filesystem "$1" --no-verification --fail --json >"$0/trufflehog-dist.jsonl" 2>"$0/trufflehog-dist.log"' "$R" site/dist

stage sast
gate semgrep semgrep scan --metrics=off --disable-version-check --error --quiet \
  --severity ERROR --severity WARNING \
  --config "$SEMGREP_RULES/javascript" --config "$SEMGREP_RULES/typescript" \
  --config "$SEMGREP_RULES/python" --config "$SEMGREP_RULES/bash" \
  --config "$SEMGREP_RULES/terraform" --config "$SEMGREP_RULES/yaml/github-actions" \
  --config "$SEMGREP_RULES/generic/secrets" --config "$SEMGREP_RULES/html" \
  --exclude site/node_modules --exclude site/dist --exclude site/public/data \
  --sarif --sarif-output="$R/semgrep.sarif" --text

stage sbom
S="$R/sbom"
gate "sbom npm" sh -c 'cd site && npm sbom --omit dev --sbom-format cyclonedx --sbom-type application >"$0/site-npm.cdx.json"' "$S"
gate "sbom site bundle" python3 ci/bundle-sbom.py site/dist "$(git rev-parse --short=12 HEAD)" "$S/site-dist.cdx.json"
gate "sbom toolchain" sh -c 'sbomnix .#devShells.x86_64-linux.default --buildtime \
  --cdx "$0/toolchain.cdx.json" --spdx "$0/toolchain.spdx.json" --csv /dev/null >"$1" 2>&1 || { tail -20 "$1"; exit 1; }' "$S" "$R/sbomnix.log"
for f in "$S"/*.cdx.json; do gate "valid $(basename "$f")" cyclonedx validate --input-file "$f" --fail-on-errors; done
gate "merge sbom" cyclonedx merge --hierarchical --name meshcore-paths --version "$(git rev-parse --short=12 HEAD)" \
  --input-files "$S/site-npm.cdx.json" "$S/site-dist.cdx.json" "$S/toolchain.cdx.json" --output-file "$S/meshcore-paths.cdx.json"

stage sca
gate "trivy repo" trivy fs --quiet --exit-code 1 --severity HIGH,CRITICAL --scanners vuln,secret,license \
  --skip-dirs site/node_modules --ignorefile .trivyignore.yaml --format json --output "$R/trivy-fs.json" .
gate "grype runtime" grype "sbom:$S/site-npm.cdx.json" -q --fail-on high -o json --file "$R/grype-site.json"
gate "osv-scanner" sh -c 'osv-scanner scan source --lockfile "$1" --format json --output "$0/osv.json"; s=$?; [ "$s" -eq 128 ] && s=0; exit $s' "$R" site/package-lock.json
# Reported, not gated (see header).
grype "sbom:$S/toolchain.cdx.json" -q -o json --file "$R/grype-toolchain.json" || true
jq -r '[.matches[].vulnerability.severity] | group_by(.) | map("\(.[0]): \(length)") | "toolchain (report only): " + join(", ")' "$R/grype-toolchain.json"

stage publish
mkdir -p site/dist/.well-known/sbom
cp "$S"/*.cdx.json "$S"/toolchain.spdx.json site/dist/.well-known/sbom/
(cd site/dist/.well-known/sbom && sha256sum -- * >SHA256SUMS)

stage guard
# Non-vacuous: every scanner left output, and tests actually ran.
for f in zizmor.sarif npm-audit.json tests.tap trivy-config.json gitleaks-git.sarif gitleaks-dist.sarif \
         trufflehog-git.log semgrep.sarif trivy-fs.json grype-site.json osv.json grype-toolchain.json \
         sbom/site-npm.cdx.json sbom/site-dist.cdx.json sbom/toolchain.cdx.json sbom/meshcore-paths.cdx.json; do
  if [ ! -s "$R/$f" ]; then echo "::error::scanner output missing or empty: $f"; fail=1; fi
done
passed="$(sed -n 's/^# pass \([0-9]*\)$/\1/p' "$R/tests.tap")"
[ "${passed:-0}" -gt 0 ] || { echo "::error::no unit tests ran"; fail=1; }
for f in sbom/site-npm.cdx.json sbom/toolchain.cdx.json; do
  n="$(jq '.components | length' "$R/$f")"
  [ "$n" -gt 0 ] || { echo "::error::$f lists no components"; fail=1; }
  echo "$f: $n components"
done

[ "$fail" -eq 0 ] && echo "pre-pr: all gates passed" || echo "pre-pr: FAILED"
exit "$fail"
