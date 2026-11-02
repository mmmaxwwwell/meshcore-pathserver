# MeshCore Paths

A path server for [MeshCore](https://github.com/meshcore-dev/MeshCore): a radio
plus a computer that listens to the mesh, works out which repeaters can hear
which from the paths flood packets carry, and answers a direct message with
the best direct path between two nodes. The public site at
[paths.mmmaxwwwell.dev](https://paths.mmmaxwwwell.dev) explains it and shows
the published graph with route lookup in the browser.

- [Architecture](docs/architecture.md): observers, resolver, snapshots, privacy, scaling
- [Snapshot format](docs/snapshot-format.md): the JSON the site and path servers read

## Site

```bash
nix develop            # Node 22 + Python 3
cd site
npm ci
npm test               # route lookup unit tests
npm run dev            # http://localhost:4321, sample data from public/data
npm run build          # static site in dist/
```

`site/public/data/` holds SYNTHETIC sample data (`python3 tools/make-sample.py
site/public/data`). Real snapshots live only in the R2 bucket; the Pages
Function in `site/functions/data/` serves them and falls back to the sample.

## Infrastructure and deployment

Cloudflare (Pages project `meshcore-paths`, R2 bucket `meshcore-paths-data`
bound as `DATA`, `paths.mmmaxwwwell.dev`) is OpenTofu in [`infra/`](infra/README.md).
The Forgejo workflow `.forgejo/workflows/ci.yml` tests and builds every push,
plans infra changes, and on `main` applies them and deploys the site.
