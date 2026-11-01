import type { Graph } from './route.ts';

// latest.json is a 60 s pointer; the graph it names is immutable, so the browser cache keeps it.
export async function loadGraph(): Promise<Graph> {
  const latest = await fetch('/data/latest.json', { cache: 'no-cache' });
  if (!latest.ok) throw new Error(`latest.json: HTTP ${latest.status}`);
  const { version, graph } = (await latest.json()) as { version: number; graph: string };
  if (version !== 1 || !/^graph-[0-9a-f]{64}\.json$/.test(graph)) throw new Error('unsupported snapshot');
  const res = await fetch(`/data/${graph}`);
  if (!res.ok) throw new Error(`${graph}: HTTP ${res.status}`);
  return (await res.json()) as Graph;
}
