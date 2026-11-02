{
  description = "MeshCore path server: site, infra, tools, and the security pipeline";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Semgrep's community rules, pinned by flake.lock: scans never download
    # rules at run time. Used in CI only (Semgrep Rules License: internal use).
    # sbomnix and semgrep: both fail to build in the main nixpkgs right now
    # (2026-11: a python dependency; a patchelf assertion). This rev builds
    # both (the one the maintainer's machines run). Drop when main builds them.
    nixpkgs-tools.url = "github:NixOS/nixpkgs/29916453413845e54a65b8a1cf996842300cd299";
    semgrep-rules = {
      url = "github:semgrep/semgrep-rules";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, nixpkgs-tools, semgrep-rules }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      forAll = f: nixpkgs.lib.genAttrs systems (s: f nixpkgs.legacyPackages.${s});
      # Providers come from nixpkgs, so CI and laptops run the same build and
      # `tofu init` downloads nothing.
      tofu = pkgs: pkgs.opentofu.withPlugins (p: [ p.cloudflare_cloudflare ]);
      tools = pkgs: nixpkgs-tools.legacyPackages.${pkgs.stdenv.hostPlatform.system};
      scanners = pkgs: [ (tools pkgs).sbomnix (tools pkgs).semgrep ] ++ (with pkgs; [
        gitleaks trufflehog          # secrets: git history + build output
        trivy grype osv-scanner      # SCA, IaC misconfig, licenses
        cyclonedx-cli                # SBOM validate/merge; sbomnix (Nix toolchain) and semgrep (SAST) above
        cosign                       # signs SBOMs and the site bundle
        actionlint zizmor shellcheck # CI and script lint
        renovate                     # dependency update PRs (renovate.yml)
        jq
      ]);
    in {
      packages = forAll (pkgs: { tofu = tofu pkgs; });
      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.nodejs_22 pkgs.python3 pkgs.wrangler (tofu pkgs) ] ++ scanners pkgs;
          SEMGREP_RULES = semgrep-rules;
          shellHook = ''
            # Secrets never reach a commit: gitleaks on every staged change.
            if [ -d .git ] && [ "$(git config core.hooksPath)" != .githooks ]; then
              git config core.hooksPath .githooks
            fi
          '';
        };
      });
    };
}
