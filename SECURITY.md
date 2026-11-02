# Security

## Reporting a vulnerability

Please report privately through GitHub's
[private vulnerability reporting](https://github.com/mmmaxwwwell/meshcore-pathserver/security/advisories/new),
not a public issue. Expect an answer within a week.

In scope: the site at paths.mmmaxwwwell.dev, its data function, the
published snapshots, the infrastructure code, and the CI pipeline. Also in
scope: anything that lets the public graph reveal where an observer is
(see [docs/architecture.md](docs/architecture.md) "Privacy").

## What protects this project

- **Secrets:** gitleaks pre-commit hook (dev shell), gitleaks + TruffleHog
  over the full git history and the built site on every CI run, GitHub secret
  scanning with push protection on the mirror. TruffleHog runs without
  verification, so candidate secrets are never sent to third parties.
- **Code:** Semgrep (pinned community rules) in CI, CodeQL on the mirror.
- **Dependencies:** npm audit, Trivy, Grype and osv-scanner on every run and
  weekly; HIGH/CRITICAL in anything that ships fails the build. Licenses are
  checked too: copyleft fails the build, except the findings accepted in
  [`.trivyignore.yaml`](.trivyignore.yaml), each with its reason.
- **Build toolchain:** the Nix toolchain SBOM is scanned by Grype on every
  run and the counts are reported, but they do not gate: those tools never
  ship, and CVE matching against nixpkgs version strings is mostly false
  positives (nixpkgs patches in place). The full list is in the CI reports.
- **Updates:** Renovate (weekly, on Forgejo) opens PRs for npm packages,
  flake inputs and CI action digests; security fixes immediately. Each PR
  passes the full gate before merge. Property-based tests (fast-check)
  check the route finder against a brute-force reference.
- **Infrastructure:** OpenTofu (`infra/`) scanned by Trivy; state encrypted.
- **CI:** actions pinned by commit, workflow security lint (zizmor,
  actionlint), least-privilege tokens, secrets only on the steps that use them.
- **SBOMs** (CycloneDX 1.6, validated on every run), published with the site
  at `/.well-known/sbom/` beside `SHA256SUMS`, each signed with cosign (key
  in `cosign.pub`, committed once the signing key is minted):
  - `site-npm.cdx.json`: the npm dependency tree behind the site;
  - `site-dist.cdx.json`: every file the site serves, with its SHA-256;
  - `toolchain.cdx.json` / `.spdx.json`: the Nix build-time closure (sbomnix);
  - `meshcore-paths.cdx.json`: all three merged;
  - `site-bundle.tar.gz`: the exact bundle deployed.

  Check one:

  ```bash
  f=meshcore-paths.cdx.json
  curl -sO https://paths.mmmaxwwwell.dev/.well-known/sbom/$f
  curl -sO https://paths.mmmaxwwwell.dev/.well-known/sbom/$f.sigstore.json
  cosign verify-blob --key cosign.pub --insecure-ignore-tlog --bundle $f.sigstore.json $f
  ```
- **Site:** strict Content-Security-Policy, no third-party scripts, styles
  or fonts, no cookies, untrusted radio data rendered as text only.
