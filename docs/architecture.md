# Architecture

A path server listens to a MeshCore mesh, works out which repeaters can hear
which, and answers "how do I get from A to B" with a direct path. This
document covers the whole system: observers, the resolver, the published
graph, and the public site at `paths.mmmaxwwwell.dev`.

## Shape

```
 observer = radio (companion) + computer
   │  reads every packet the radio hears (companion push 0x88, raw bytes + SNR)
   │  keeps: route type, payload type, path (hop hashes + width), packet hash,
   │         SNR, time, and adverts in full. Drops every encrypted payload.
   │
   ├─▶ local resolver ─▶ local path server: answers "path <target>" DMs
   │
   └─▶ (phase 2) signed observation batches ──▶ ingest Worker ──▶ R2 observations/
                                                                      │ every ~10 min
                                                                      ▼
                                                        central resolver (same code)
                                                                      │
                                     R2 graphs/graph-<sha256>.json  (immutable)
                                     R2 latest.json                 (pointer, short TTL)
                                                                      │
                     Pages Function /data/* ◀── CDN cache ◀───────────┘
                                │
                     Astro site (static): what it is, how it works, explore + route lookup
                     observers' path servers also pull the merged graph from /data/
```

**Phase 1 (one observer):** the observer runs the resolver itself and
uploads the graph snapshot to R2 with a write-only token. Nothing
accepts inbound traffic; the observer only makes outbound requests.

**Phase 2 (many observers):** observers upload observation batches instead,
an ingest Worker checks the signature and appends them, and one
central resolver merges everyone's evidence. Every observer's path
server then answers from the merged graph, which is much larger than the
tree any single radio sees.

## Why it scales

- **Reads never reach a computer we run.** The site is static and the data is
  static JSON behind Cloudflare's CDN. A graph file is named by its hash,
  so it never changes and can be cached forever. Only `latest.json` (a few
  bytes) is revalidated, with a 60 s max-age.
- **Route lookup runs in the browser.** Dijkstra over ~10k links takes a few
  milliseconds; the server never computes a route for a visitor.
- **Writes are small and append-only.** An observer produces at most a few KB
  per minute. Ingest is idempotent by batch id, so a retried upload is
  harmless.
- **Compute is batched.** The resolver re-runs on a schedule, not per packet.
  Its cost grows with the number of distinct paths, not with the number of
  visitors.

## Resolving 1-byte hop hashes

Most of the mesh still uses 1-byte path hashes, and in New England 202 of
the 241 prefixes in use are shared by two or more repeaters. The resolver
keeps every candidate and its probability internally and publishes only
links it is confident about:

1. Hard rule-outs: only repeaters and rooms relay; the last hop must be
   heard directly by the observer; a multi-byte hop that matches exactly one
   repeater is ground truth; a repeater that has not advertised recently is
   dropped; two hops too far apart to be neighbours are ruled out.
2. Soft evidence: known links (from multi-byte paths, traces, and earlier
   confident resolutions), distance, the advert origin anchoring the first
   hop, hop index vs the candidate's distance from the observer.
3. Iterate until stable. Each published link has a confidence value.

Measured on 5.8 days of one observer (37,625 packets), held out against
multi-byte paths cut to one byte: the resolver gets 95.5% of hops right,
0.59% wrong and leaves 3.9% unresolved. Hops it scores at 0.9 or above are
right 99.4% of the time (a first naive pass managed 77% / 1.1% / 22%).

## Answers on the air

The DM answer is hop hash bytes, so a 1-byte hop is forwarded by every
repeater with that prefix that hears the previous hop. The router avoids
hops where a same-prefix repeater neighbours the previous hop. It uses
2- or 3-byte hashes when every repeater on the route advertises support for
them. When no route clears the confidence bar it says so (`flood`) instead
of guessing.

Format: `#path1 <target 12 hex> w=<bytes> <hop,hop,...> c=<confidence>` or
`#path1 <target 12 hex> flood`.

## Privacy

- Never stored or published: encrypted payloads (DMs, channel messages,
  room posts), sender identities of messages, message timing per sender.
- Published: repeaters and rooms (name, key prefix, location if they
  advertise one, hash width). They already broadcast all of this in their
  adverts. Also published: links between repeaters, with confidence.
- **Observers are never named and their own direct links are removed from
  the public graph.** Otherwise the published graph would show which
  repeater each observer sits next to, and so roughly where it is.
  Observers keep their full graph locally for answering DMs.
- **Below three observers, links are published without direction or
  counts** (`dirs: "both"`, `count: 0`). One observer's packets all flow
  toward it, so link directions would form arrows pointing at it, and the
  repeater next to it would carry the largest counts. With several
  observers the flows mix and both are published.
- Companions (phones, handhelds) never appear in the public graph.

## Components and where they live

| Component | Where |
|---|---|
| Snapshot format | [snapshot-format.md](snapshot-format.md) |
| Site + `/data/*` function | `site/` (Astro, Cloudflare Pages, R2 binding `DATA`) |
| Sample data generator | `tools/make-sample.py` |
| Resolver | moves here from the first observer's code once it passes its holdout test |
| Observer deployments | each operator's own infrastructure, not this repo |
