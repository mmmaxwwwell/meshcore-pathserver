// Route lookup over a published graph snapshot (docs/snapshot-format.md).
// Pure: no DOM, no fetch. The site and the tests share it.

export interface GraphNode {
  id: string;
  name: string;
  type: "repeater" | "room";
  lat: number | null;
  lon: number | null;
  hashBytes: number;
  lastAdvert: string;
}

export interface GraphLink {
  a: number;
  b: number;
  conf: number;
  count: number;
  dirs: "ab" | "ba" | "both";
  last: string;
  snr: number | null;
}

export interface Graph {
  version: number;
  generated: string;
  sample?: boolean;
  window: { from: string; to: string };
  stats: { packets: number; observers: number; hopsResolved: number | null; hopsWrong: number | null };
  nodes: GraphNode[];
  links: GraphLink[];
}

export interface RouteOptions {
  minConf: number; // links below this are not used
  hopPenalty: number; // added per hop, so a slightly less certain short route beats a long one
}

export const DEFAULT_ROUTE_OPTIONS: RouteOptions = { minConf: 0.9, hopPenalty: 0.05 };

export interface Ambiguity {
  hop: number; // index into route.nodes
  others: number[]; // node indices sharing the hop's prefix at the chosen width that neighbour the previous hop
}

export interface Route {
  nodes: number[]; // from .. to, inclusive
  conf: number; // product of link confidences
  width: number; // hash bytes per hop on the air
  hops: string[]; // the hop prefixes between from and to, at `width`
  ambiguities: Ambiguity[];
  text: string; // the #path1 line a path server would send
}

type Adjacency = Map<number, { to: number; conf: number }[]>;

// A link seen only one way is usable only that way: a→b packets prove b hears a.
function adjacency(g: Graph, minConf: number): Adjacency {
  const adj: Adjacency = new Map();
  const add = (from: number, to: number, conf: number) => {
    let l = adj.get(from);
    if (!l) adj.set(from, (l = []));
    l.push({ to, conf });
  };
  for (const l of g.links) {
    if (l.conf < minConf) continue;
    if (l.dirs !== "ba") add(l.a, l.b, l.conf);
    if (l.dirs !== "ab") add(l.b, l.a, l.conf);
  }
  return adj;
}

// Binary heap keyed by cost; the graph is small but routes are recomputed on every selection.
class Heap {
  private items: [number, number][] = [];
  get size() {
    return this.items.length;
  }
  push(cost: number, node: number) {
    const a = this.items;
    a.push([cost, node]);
    let i = a.length - 1;
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (a[p][0] <= a[i][0]) break;
      [a[p], a[i]] = [a[i], a[p]];
      i = p;
    }
  }
  pop(): [number, number] {
    const a = this.items;
    const top = a[0];
    const last = a.pop()!;
    if (a.length) {
      a[0] = last;
      let i = 0;
      for (;;) {
        const l = 2 * i + 1;
        const r = l + 1;
        let m = i;
        if (l < a.length && a[l][0] < a[m][0]) m = l;
        if (r < a.length && a[r][0] < a[m][0]) m = r;
        if (m === i) break;
        [a[m], a[i]] = [a[i], a[m]];
        i = m;
      }
    }
    return top;
  }
}

export function findRoute(g: Graph, from: number, to: number, opts: RouteOptions = DEFAULT_ROUTE_OPTIONS): Route | null {
  if (from === to) return null;
  const adj = adjacency(g, opts.minConf);
  const cost = new Map<number, number>([[from, 0]]);
  const prev = new Map<number, number>();
  const heap = new Heap();
  heap.push(0, from);
  while (heap.size) {
    const [c, u] = heap.pop();
    if (u === to) break;
    if (c > (cost.get(u) ?? Infinity)) continue;
    for (const { to: v, conf } of adj.get(u) ?? []) {
      const nc = c - Math.log(conf) + opts.hopPenalty;
      if (nc < (cost.get(v) ?? Infinity)) {
        cost.set(v, nc);
        prev.set(v, u);
        heap.push(nc, v);
      }
    }
  }
  if (!prev.has(to)) return null;
  const nodes = [to];
  while (nodes[0] !== from) nodes.unshift(prev.get(nodes[0])!);
  const relays = nodes.slice(1, -1);
  // No relays: the hop width is irrelevant on the air; report 1 so the line stays honest.
  const width = relays.length ? Math.min(3, ...relays.map((i) => g.nodes[i].hashBytes)) : 1;
  const linkConf = new Map(g.links.map((l) => [`${l.a},${l.b}`, l.conf]));
  let conf = 1;
  for (let i = 1; i < nodes.length; i++) {
    const [a, b] = [Math.min(nodes[i - 1], nodes[i]), Math.max(nodes[i - 1], nodes[i])];
    conf *= linkConf.get(`${a},${b}`)!;
  }
  const hops = relays.map((i) => g.nodes[i].id.slice(0, width * 2));
  const ambiguities = findAmbiguities(g, nodes, width);
  const text = `#path1 ${g.nodes[to].id} w=${width} ${hops.join(",") || "-"} c=${conf.toFixed(2)}`;
  return { nodes, conf, width, hops, ambiguities, text };
}

// A hop prefix on the air is acted on by every repeater with that prefix that hears
// the previous hop. Any link at all (even below minConf) counts as "might hear".
export function findAmbiguities(g: Graph, route: number[], width: number): Ambiguity[] {
  const neighbours = new Map<number, Set<number>>();
  for (const l of g.links) {
    if (!neighbours.has(l.a)) neighbours.set(l.a, new Set());
    if (!neighbours.has(l.b)) neighbours.set(l.b, new Set());
    neighbours.get(l.a)!.add(l.b);
    neighbours.get(l.b)!.add(l.a);
  }
  const out: Ambiguity[] = [];
  for (let h = 1; h < route.length - 1; h++) {
    const prefix = g.nodes[route[h]].id.slice(0, width * 2);
    const near = neighbours.get(route[h - 1]) ?? new Set();
    const others = [...near].filter((n) => n !== route[h] && g.nodes[n].id.startsWith(prefix));
    if (others.length) out.push({ hop: h, others });
  }
  return out;
}
