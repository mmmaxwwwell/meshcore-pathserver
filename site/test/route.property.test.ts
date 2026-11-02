// Property-based tests for route lookup: random graphs, checked against a
// brute-force reference. The published graph is untrusted input to the
// browser, so findRoute must never return a route that breaks its contract.
import { test } from "node:test";
import assert from "node:assert/strict";
import fc from "fast-check";
import { findRoute, type Graph, type GraphLink, type RouteOptions } from "../src/lib/route.ts";

const HEX = "0123456789abcdef";

const graphArb: fc.Arbitrary<Graph> = fc
  .integer({ min: 2, max: 12 })
  .chain((n) =>
    fc.record({
      // Few distinct first bytes on purpose, so shared prefixes (wire ambiguities) are common.
      ids: fc.array(fc.tuple(fc.constantFrom("a1", "b2", "c3"), fc.array(fc.constantFrom(...HEX), { minLength: 10, maxLength: 10 })), { minLength: n, maxLength: n }),
      widths: fc.array(fc.integer({ min: 1, max: 3 }), { minLength: n, maxLength: n }),
      links: fc.uniqueArray(
        fc.record({
          a: fc.integer({ min: 0, max: n - 1 }),
          b: fc.integer({ min: 0, max: n - 1 }),
          conf: fc.double({ min: 0.3, max: 1, noNaN: true }),
          dirs: fc.constantFrom("ab", "ba", "both") as fc.Arbitrary<GraphLink["dirs"]>,
        }).filter((l) => l.a < l.b),
        { selector: (l) => `${l.a},${l.b}`, maxLength: n * 3 },
      ),
    }),
  )
  .map(({ ids, widths, links }) => ({
    version: 1, generated: "", window: { from: "", to: "" },
    stats: { packets: 0, observers: 0, hopsResolved: null, hopsWrong: null },
    // Unique ids even when the random tails collide: suffix the index.
    nodes: ids.map(([p, t], i) => ({
      id: (p + t.join("")).slice(0, 10) + i.toString(16).padStart(2, "0"),
      name: `n${i}`, type: "repeater" as const, lat: null, lon: null, hashBytes: widths[i], lastAdvert: "",
    })),
    links: links.map((l) => ({ ...l, count: 1, last: "", snr: null })),
  }));

const optsArb: fc.Arbitrary<RouteOptions> = fc.record({
  minConf: fc.double({ min: 0.3, max: 1, noNaN: true }),
  hopPenalty: fc.double({ min: 0, max: 1, noNaN: true }),
});

function usable(g: Graph, minConf: number) {
  const edges: [number, number, number][] = [];
  for (const l of g.links) {
    if (l.conf < minConf) continue;
    if (l.dirs !== "ba") edges.push([l.a, l.b, l.conf]);
    if (l.dirs !== "ab") edges.push([l.b, l.a, l.conf]);
  }
  return edges;
}

// Bellman-Ford: the obviously-correct (slow) shortest path cost.
function referenceCost(g: Graph, from: number, to: number, o: RouteOptions): number {
  const d = new Array(g.nodes.length).fill(Infinity);
  d[from] = 0;
  const edges = usable(g, o.minConf);
  for (let i = 0; i < g.nodes.length; i++) {
    for (const [u, v, c] of edges) d[v] = Math.min(d[v], d[u] - Math.log(c) + o.hopPenalty);
  }
  return d[to];
}

const cost = (conf: number, hops: number, o: RouteOptions) => -Math.log(conf) + hops * o.hopPenalty;

test("a route always honours its contract and is optimal", () => {
  fc.assert(
    fc.property(graphArb, optsArb, fc.nat(), fc.nat(), (g, o, fi, ti) => {
      const from = fi % g.nodes.length, to = ti % g.nodes.length;
      const r = findRoute(g, from, to, o);
      const ref = referenceCost(g, from, to, o);
      if (from === to || ref === Infinity) return r === null;
      assert.ok(r, "reachable but no route");
      assert.equal(r.nodes[0], from);
      assert.equal(r.nodes.at(-1), to);
      assert.equal(new Set(r.nodes).size, r.nodes.length, "a node repeats");
      const edges = usable(g, o.minConf);
      let conf = 1;
      for (let i = 1; i < r.nodes.length; i++) {
        const e = edges.find(([u, v]) => u === r.nodes[i - 1] && v === r.nodes[i]);
        assert.ok(e, `step ${r.nodes[i - 1]}->${r.nodes[i]} is not a usable link`);
        conf *= e[2];
      }
      assert.ok(Math.abs(conf - r.conf) < 1e-9, "conf is not the product of the links");
      assert.ok(Math.abs(cost(r.conf, r.nodes.length - 1, o) - ref) < 1e-9, "not the cheapest route");
      const relays = r.nodes.slice(1, -1);
      assert.equal(r.hops.length, relays.length);
      for (const [k, i] of relays.entries()) {
        assert.ok(g.nodes[i].hashBytes >= r.width, "width wider than a relay supports");
        assert.equal(r.hops[k], g.nodes[i].id.slice(0, 2 * r.width));
      }
      assert.match(r.text, /^#path1 [0-9a-f]{12} w=[123] (-|[0-9a-f]{2,6}(,[0-9a-f]{2,6})*) c=[01]\.\d\d$/);
      for (const a of r.ambiguities) {
        const prefix = r.hops[a.hop - 1];
        for (const o2 of a.others) {
          assert.ok(g.nodes[o2].id.startsWith(prefix) && o2 !== r.nodes[a.hop]);
          assert.ok(g.links.some((l) => (l.a === o2 && l.b === r.nodes[a.hop - 1]) || (l.b === o2 && l.a === r.nodes[a.hop - 1])));
        }
      }
      return true;
    }),
    { numRuns: 2000 },
  );
});

test("raising the confidence floor never finds a cheaper route", () => {
  fc.assert(
    fc.property(graphArb, optsArb, fc.double({ min: 0, max: 0.5, noNaN: true }), fc.nat(), fc.nat(), (g, o, bump, fi, ti) => {
      const from = fi % g.nodes.length, to = ti % g.nodes.length;
      const lo = findRoute(g, from, to, o);
      const hiOpts = { ...o, minConf: Math.min(1, o.minConf + bump) };
      const hi = findRoute(g, from, to, hiOpts);
      if (!hi) return true;
      assert.ok(lo, "a stricter floor found a route the looser one did not");
      return cost(hi.conf, hi.nodes.length - 1, o) >= cost(lo.conf, lo.nodes.length - 1, o) - 1e-9;
    }),
    { numRuns: 1000 },
  );
});
