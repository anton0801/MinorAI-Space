// Share Link (PRO): stores a map image under a random name in the public "shared" bucket.
// Actions: {"action":"upload","mapId":"…","png":"<base64>"} → {url}; {"action":"delete","mapId":"…"}.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { currentPlan } from "../_shared/plan.ts";

const MAX_LINKS = 200;
const MAX_BYTES = 8_000_000;
const PNG_SIGNATURE = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function publicURL(path: string): string {
  return supabase.storage.from("shared").getPublicUrl(path).data.publicUrl;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") ?? "";
  const { data: auth, error: authError } = await supabase.auth.getUser(token);
  if (authError || !auth.user) return json({ error: "unauthorized" }, 401);
  const userId = auth.user.id;

  if (Number(req.headers.get("content-length") ?? 0) > MAX_BYTES * 1.4) return json({ error: "too_large" }, 413);
  const raw = await req.text();
  if (raw.length > MAX_BYTES * 1.4) return json({ error: "too_large" }, 413);
  let body: Record<string, unknown>;
  try {
    body = JSON.parse(raw);
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  const mapId = String(body.mapId ?? "");
  if (!/^[0-9a-fA-F-]{36}$/.test(mapId)) return json({ error: "bad_request" }, 400);

  const { data: existing } = await supabase
    .from("shared_links")
    .select("path")
    .eq("user_id", userId)
    .eq("map_id", mapId)
    .maybeSingle();

  if (body.action === "delete") {
    // By map id, whichever account shared it: the same iPhone may have shared the map while signed
    // in to another account. Map ids never appear in public links, so only the map's owner knows it.
    const { data: rows } = await supabase.from("shared_links").select("path").eq("map_id", mapId);
    const paths = (rows ?? []).map((row: { path: string }) => row.path);
    if (paths.length) {
      const { error } = await supabase.storage.from("shared").remove(paths);
      if (error) return json({ error: "server_error" }, 500);
      await supabase.from("shared_links").delete().eq("map_id", mapId);
    }
    return json({ deleted: true });
  }

  if (body.action !== "upload") return json({ error: "bad_request" }, 400);
  if ((await currentPlan(supabase, userId)) !== "pro") return json({ error: "plan_required" }, 402);

  let bytes: Uint8Array;
  try {
    bytes = Uint8Array.from(atob(String(body.png ?? "")), (c) => c.charCodeAt(0));
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  if (bytes.length === 0 || bytes.length > MAX_BYTES) return json({ error: "too_large" }, 413);
  if (!PNG_SIGNATURE.every((b, i) => bytes[i] === b)) return json({ error: "bad_request" }, 400);
  // A real image header: the IHDR chunk first, with sane dimensions (blocks arbitrary files).
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const isHeader = bytes.length > 24 && String.fromCharCode(...bytes.subarray(12, 16)) === "IHDR";
  const width = isHeader ? view.getUint32(16) : 0;
  const height = isHeader ? view.getUint32(20) : 0;
  if (!isHeader || width < 1 || height < 1 || width > 12_000 || height > 12_000) {
    return json({ error: "bad_request" }, 400);
  }

  if (!existing) {
    const { count } = await supabase.from("shared_links").select("id", { count: "exact", head: true }).eq("user_id", userId);
    if ((count ?? 0) >= MAX_LINKS) return json({ error: "limit_reached", kind: "shares" }, 402);
  }

  const path = existing?.path ?? `${crypto.randomUUID()}.png`;
  const { error: uploadError } = await supabase.storage.from("shared").upload(path, bytes, {
    contentType: "image/png",
    upsert: true,
    cacheControl: "60",
  });
  if (uploadError) {
    console.error("share upload", uploadError.message);
    return json({ error: "server_error" }, 500);
  }
  if (!existing) {
    const { error } = await supabase.from("shared_links").insert({ user_id: userId, map_id: mapId, path });
    if (error) {
      await supabase.storage.from("shared").remove([path]);
      return json({ error: "server_error" }, 500);
    }
  }
  return json({ url: `${publicURL(path)}?v=${Date.now()}` });
});
