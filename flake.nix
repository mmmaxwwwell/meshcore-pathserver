{
  description = "MeshCore path server: site, infra and tools";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      forAll = f: nixpkgs.lib.genAttrs systems (s: f nixpkgs.legacyPackages.${s});
      # Providers come from nixpkgs, so CI and laptops run the same build and
      # `tofu init` downloads nothing.
      tofu = pkgs: pkgs.opentofu.withPlugins (p: [ p.cloudflare_cloudflare ]);
    in {
      packages = forAll (pkgs: { tofu = tofu pkgs; });
      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.nodejs_22 pkgs.python3 pkgs.wrangler (tofu pkgs) ];
        };
      });
    };
}
