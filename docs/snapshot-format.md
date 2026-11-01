# Snapshot format (version 1)

Two files, both JSON, served under `/data/`.

## `latest.json` — the pointer

Small, revalidated every 60 s.

```json
{ "version": 1, "graph": "graph-3f9a…e1.json", "generated": "2026-11-01T18:00:00Z" }
```

## `graph-<sha256 of the file>.json` — the graph

Immutable (`Cache-Control: public, max-age=31536000, immutable`).

```json
{
  "version": 1,
  "generated": "2026-11-01T18:00:00Z",
  "sample": false,
  "window": { "from": "2026-10-26T00:00:00Z", "to": "2026-11-01T18:00:00Z" },
  "stats": {
    "packets": 37625, "observers": 1, "hopsResolved": 0.77, "hopsWrong": 0.011
  },
  "nodes": [
    { "id": "5f3c19e0b7a2", "name": "Example Ridge", "type": "repeater",
      "lat": 41.70, "lon": -72.98, "hashBytes": 1, "lastAdvert": "2026-11-01T12:00:00Z" }
  ],
  "links": [
    { "a": 0, "b": 1, "conf": 0.97, "count": 412, "dirs": "both",
      "last": "2026-11-01T17:55:00Z", "snr": null }
  ]
}
```

- `nodes[].id`: first 6 bytes of the public key, hex. Unique within a
  snapshot (the resolver widens it if not). Route hops use its prefix.
- `type`: `repeater` or `room`. Nothing else relays.
- `lat`/`lon`: `null` when the node does not advertise a location.
- `hashBytes`: path hash width the node advertises (1–3). A route may use
  width `w` only if every hop has `hashBytes >= w`.
- `links[].a`/`b`: indices into `nodes`, `a < b`.
- `conf`: probability that both ends are who the resolver says. 0–1.
- `dirs`: `ab`, `ba` or `both`: which directions packets were seen crossing
  the link. LoRa links can be asymmetric.
- `count`: packets that crossed the link; `0` when withheld (below three
  observers, see architecture.md "Privacy").
- With fewer than three observers `dirs` is always `both`: routes over it are
  advisory, the observer's private graph has the real directions.
- `snr`: dB, only when measured (trace), else `null`.
- `sample`: `true` for synthetic data (the site labels it).

Readers must ignore unknown fields. A breaking change bumps `version`
and the new files sit beside the old until every reader moves.
