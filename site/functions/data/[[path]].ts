// Serves /data/* from the R2 bucket bound as DATA (wrangler.toml).
// Graph files are content-addressed and cached forever; latest.json is the only
// file that changes, so it alone is revalidated. Falls through to the static
// sample data in public/data when R2 has no such object (local dev, first deploy).

interface Env {
  DATA: R2Bucket;
}

const NAME = /^(latest\.json|graph-[0-9a-f]{64}\.json)$/;

export const onRequestGet: PagesFunction<Env> = async ({ params, env, next }) => {
  const parts = Array.isArray(params.path) ? params.path : [params.path];
  const name = parts.join("/");
  if (!NAME.test(name)) return new Response("not found", { status: 404 });
  const obj = await env.DATA.get(name);
  if (!obj) return next();
  const immutable = name !== "latest.json";
  return new Response(obj.body, {
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": immutable ? "public, max-age=31536000, immutable" : "public, max-age=60",
      etag: obj.httpEtag,
      "x-content-type-options": "nosniff",
    },
  });
};
