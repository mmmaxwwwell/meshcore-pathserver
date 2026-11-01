"""Write a synthetic graph snapshot (format v1) for the site to render before real data exists.

usage: make-sample.py <out-dir>

Deterministic: same seed, same file. Repeaters are scattered over central
Connecticut; links join repeaters within radio range with a confidence that
falls with distance. Some 1-byte prefixes are deliberately shared so the
site's wire-ambiguity warning has something to show. Every name says
"Sample" and the snapshot sets "sample": true.
"""
import hashlib, json, math, os, random, sys

SEED = 20261101
N = 140
BBOX = (41.2, 42.0, -73.6, -72.2)  # lat min/max, lon min/max
RANGE_KM = 22.0


def km(a, b):
    la1, lo1, la2, lo2 = map(math.radians, (a["lat"], a["lon"], b["lat"], b["lon"]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 6371 * 2 * math.asin(math.sqrt(h))


def main():
    out = sys.argv[1]
    rnd = random.Random(SEED)
    nodes = []
    for i in range(N):
        key = rnd.randbytes(6)
        if i % 9 == 0 and i:  # share a 1-byte prefix with an earlier node
            key = nodes[rnd.randrange(i)]["_key"][:1] + key[1:]
        nodes.append({
            "_key": key,
            "id": key.hex(),
            "name": f"Sample R{i:03d}",
            "type": "room" if i % 23 == 0 else "repeater",
            "lat": round(rnd.uniform(*BBOX[:2]), 4),
            "lon": round(rnd.uniform(*BBOX[2:]), 4),
            "hashBytes": rnd.choice((1, 1, 1, 2, 2, 3)),
            "lastAdvert": "2026-11-01T12:00:00Z",
        })
    links = []
    for a in range(N):
        for b in range(a + 1, N):
            d = km(nodes[a], nodes[b])
            if d > RANGE_KM or rnd.random() > 0.55:
                continue
            conf = max(0.3, min(0.999, 1.0 - (d / RANGE_KM) ** 2 * 0.3 + rnd.uniform(-0.06, 0.01)))
            links.append({
                "a": a, "b": b, "conf": round(conf, 3), "count": rnd.randint(3, 600),
                "dirs": rnd.choice(("both", "both", "both", "ab", "ba")),
                "last": "2026-11-01T17:00:00Z",
                "snr": round(rnd.uniform(-8, 12), 1) if rnd.random() < 0.1 else None,
            })
    for n in nodes:
        del n["_key"]
    graph = {
        "version": 1, "generated": "2026-11-01T18:00:00Z", "sample": True,
        "window": {"from": "2026-10-26T00:00:00Z", "to": "2026-11-01T18:00:00Z"},
        "stats": {"packets": 0, "observers": 0, "hopsResolved": None, "hopsWrong": None},
        "nodes": nodes, "links": links,
    }
    body = json.dumps(graph, separators=(",", ":"), ensure_ascii=False).encode()
    name = f"graph-{hashlib.sha256(body).hexdigest()}.json"
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        if f.startswith("graph-"):
            os.remove(os.path.join(out, f))
    with open(os.path.join(out, name), "wb") as f:
        f.write(body)
    with open(os.path.join(out, "latest.json"), "w") as f:
        json.dump({"version": 1, "graph": name, "generated": graph["generated"]}, f)
    print(f"{name}: {len(nodes)} nodes, {len(links)} links")


if __name__ == "__main__":
    main()
