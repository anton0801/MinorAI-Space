// Account actions that need the service role.
// - {"action":"apple_code","code":"…"}: keeps the Sign in with Apple refresh token so it can be revoked later.
// - {"action":"delete"}: removes shared and synced map images, revokes the Apple token, then deletes
//   the user (profiles, usage, synced maps, shared link rows and Apple tokens go with it through
//   ON DELETE CASCADE).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { exchangeCode, revoke } from "../_shared/apple.ts";

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

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") ?? "";
  const { data: auth, error: authError } = await supabase.auth.getUser(token);
  if (authError || !auth.user) return json({ error: "unauthorized" }, 401);
  const userId = auth.user.id;

  if (Number(req.headers.get("content-length") ?? 0) > 10_000) return json({ error: "bad_request" }, 413);
  const body = await req.json().catch(() => ({}));

  if (body.action === "apple_code") {
    const code = String(body.code ?? "");
    if (!code || code.length > 2000) return json({ error: "bad_request" }, 400);
    const refreshToken = await exchangeCode(code);
    if (refreshToken) {
      await supabase.from("apple_tokens").upsert({ user_id: userId, refresh_token: refreshToken });
    }
    return json({ stored: Boolean(refreshToken) });
  }

  if (body.action !== "delete") return json({ error: "bad_request" }, 400);

  // Shared map images are public files; remove them before the rows disappear.
  const { data: links } = await supabase.from("shared_links").select("path").eq("user_id", userId);
  const paths = (links ?? []).map((row: { path: string }) => row.path);
  // Early builds uploaded straight to "<user id>/…" in the bucket; remove those too.
  const { data: legacy } = await supabase.storage.from("shared").list(userId, { limit: 1000 });
  for (const file of legacy ?? []) paths.push(`${userId}/${file.name}`);
  if (paths.length) {
    const { error } = await supabase.storage.from("shared").remove(paths);
    if (error) console.warn("shared cleanup", error.message);
  }

  // Pictures of synced maps are private files; the map rows go with the user (ON DELETE CASCADE).
  for (let round = 0; round < 50; round++) {
    const { data: files } = await supabase.storage.from("map-images").list(userId, { limit: 1000 });
    if (!files?.length) break;
    const { error: removeError } = await supabase.storage.from("map-images").remove(files.map((f: { name: string }) => `${userId}/${f.name}`));
    if (removeError) {
      console.warn("map images cleanup", removeError.message);
      break;
    }
    if (files.length < 1000) break;
  }

  const { data: apple } = await supabase.from("apple_tokens").select("refresh_token").eq("user_id", userId).maybeSingle();
  if (apple?.refresh_token) {
    const revoked = await revoke(apple.refresh_token).catch(() => false);
    if (!revoked) console.warn("apple token not revoked", userId);
  }

  const { error } = await supabase.auth.admin.deleteUser(userId);
  if (error) {
    console.error("delete user", error.message);
    return json({ error: "server_error" }, 500);
  }
  return json({ deleted: true });
});
