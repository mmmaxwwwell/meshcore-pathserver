import { test } from "node:test";
import assert from "node:assert/strict";
import { findRoute, type Graph, type GraphLink, type GraphNode } from "../src/lib/route.ts";

function node(id: string, hashBytes = 1): GraphNode {
  return { id, name: id, type: "repeater", lat: null, lon: null, hashBytes, lastAdvert: "" };
}
function link(a: number, b: number, conf: number, dirs: GraphLink["dirs"] = "both"): GraphLink {
  return { a, b, conf, count: 1, dirs, last: "", snr: null };
}
function graph(nodes: GraphNode[], links: GraphLink[]): Graph {
  return {
    version: 1, generated: "", window: { from: "", to: "" },
    stats: { packets: 0, observers: 0, hopsResolved: null, hopsWrong: null }, nodes, links,
  };
}

test("prefers the more certain route and reports its confidence", () => {
  // 0 -> 1 -> 3 (0.99 * 0.99) beats 0 -> 2 -> 3 (0.95 * 0.95)
  const g = graph(
    [node("aa0000000000"), node("bb0000000000"), node("cc0000000000"), node("dd0000000000")],
    [link(0, 1, 0.99), link(1, 3, 0.99), link(0, 2, 0.95), link(2, 3, 0.95)],
  );
  const r = findRoute(g, 0, 3)!;
  assert.deepEqual(r.nodes, [0, 1, 3]);
  assert.equal(r.hops.join(), "bb");
  assert.ok(Math.abs(r.conf - 0.9801) < 1e-9);
  assert.equal(r.text, "#path1 dd0000000000 w=1 bb c=0.98");
});

test("never uses a link below the confidence floor", () => {
  const g = graph([node("aa0000000000"), node("bb0000000000"), node("cc0000000000")],
    [link(0, 1, 0.99), link(1, 2, 0.5)]);
  assert.equal(findRoute(g, 0, 2), null);
});

test("a one-way link is only used in the direction it was seen", () => {
  const g = graph([node("aa0000000000"), node("bb0000000000")], [link(0, 1, 0.99, "ab")]);
  assert.ok(findRoute(g, 0, 1));
  assert.equal(findRoute(g, 1, 0), null);
});

test("uses the widest hash every relay supports", () => {
  const g = graph(
    [node("aa0000000000"), node("bb1100000000", 3), node("cc2200000000", 2), node("dd0000000000")],
    [link(0, 1, 0.99), link(1, 2, 0.99), link(2, 3, 0.99)],
  );
  const r = findRoute(g, 0, 3)!;
  assert.equal(r.width, 2);
  assert.deepEqual(r.hops, ["bb11", "cc22"]);
});

test("flags a hop whose 1-byte prefix another neighbour of the previous hop shares", () => {
  // 0 hears both 1 (bb..) and 2 (bb.. too): a 1-byte "bb" hop would be forwarded by both.
  const g = graph(
    [node("aa0000000000"), node("bb0100000000"), node("bb0200000000"), node("dd0000000000")],
    [link(0, 1, 0.99), link(0, 2, 0.4), link(1, 3, 0.99)],
  );
  const r = findRoute(g, 0, 3)!;
  assert.deepEqual(r.ambiguities, [{ hop: 1, others: [2] }]);
});

test("direct neighbours need no relays", () => {
  const g = graph([node("aa0000000000", 3), node("bb0000000000", 3)], [link(0, 1, 0.99)]);
  const r = findRoute(g, 0, 1)!;
  assert.deepEqual(r.hops, []);
  assert.equal(r.text, "#path1 bb0000000000 w=1 - c=0.99");
});
