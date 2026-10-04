// Notifications that follow what people do in the app. The app only says what happened; who gets
// a notification and what it says is decided here, and every claim is checked in the database.
// - {"action":"collab","event":"changed","map":"<id>"}: the caller just saved a shared map; the
//   others get "a collaborator made changes" (at most once per 30 minutes per map and person).
// - {"action":"collab","event":"joined","map":"<id>"}: the caller just joined; the owner hears about it.
// - {"action":"role","map":"<id>","user":"<id>"}: the owner changed someone's role; that person hears it.
// - {"action":"test"}: a test notification to the caller's own devices.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { isUUID } from "../_shared/subscriptions.ts";
import { pushAllowed, pushConfigured, sendPush } from "../_shared/push.ts";
import { PUSH } from "../_shared/pushText.ts";

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

const RECENT_MS = 15 * 60_000;

function recent(iso: string | null | undefined): boolean {
  const at = iso ? Date.parse(iso) : NaN;
  return Number.isFinite(at) && at > Date.now() - RECENT_MS;
}

// Recipients that haven't had a notification on this topic lately.
async function throttled(users: string[], topic: string, seconds: number): Promise<string[]> {
  const allowed = await Promise.all(users.map((user) => pushAllowed(supabase, user, topic, seconds)));
  return users.filter((_, i) => allowed[i]);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") ?? "";
  const { data: auth, error: authError } = await supabase.auth.getUser(token);
  if (authError || !auth.user) return json({ error: "unauthorized" }, 401);
  const userId = auth.user.id;

  if (Number(req.headers.get("content-length") ?? 0) > 2_000) return json({ error: "bad_request" }, 413);
  const body = await req.json().catch(() => ({}));
  const action = String(body.action ?? "");

  try {
    if (action === "test") {
      if (!await pushAllowed(supabase, userId, "test", 30)) return json({ error: "too_many_requests" }, 429);
      const sent = await sendPush(supabase, [userId], "account", { text: PUSH.test() });
      return json({ sent, configured: pushConfigured() });
    }

    if (!isUUID(body.map)) return json({ error: "bad_request" }, 400);
    const mapID = String(body.map).toLowerCase();
    const { data: map } = await supabase
      .from("collab_maps")
      .select("owner, updated_by, updated_at, title:data->root->>title")
      .eq("id", mapID)
      .maybeSingle();
    if (!map) return json({ error: "not_found" }, 404);
    const { data: rows } = await supabase.from("collab_members").select("user_id, role, joined_at").eq("map_id", mapID);
    const members = (rows ?? []) as { user_id: string; role: string | null; joined_at: string }[];
    const me = members.find((m) => m.user_id === userId);
    const isOwner = map.owner === userId;
    if (!isOwner && !me) return json({ error: "forbidden" }, 403);

    const title = String(map.title ?? "").trim().slice(0, 80) || "Minor AI";
    const message = { route: `minorai://map/${mapID}`, thread: `map-${mapID}` };

    if (action === "collab" && body.event === "changed") {
      const canEdit = isOwner || (me && me.role !== "viewer");
      if (!canEdit || map.updated_by !== userId || !recent(map.updated_at)) return json({ sent: 0 });
      const others = [map.owner as string, ...members.map((m) => m.user_id)].filter((id) => id !== userId);
      const to = await throttled(others, `collab:${mapID}`, 30 * 60);
      return json({ sent: await sendPush(supabase, to, "collab", { ...message, text: PUSH.collabChanged(title) }) });
    }

    if (action === "collab" && body.event === "joined") {
      if (!me || !recent(me.joined_at)) return json({ sent: 0 });
      const to = await throttled([map.owner as string], `joined:${mapID}`, 60);
      return json({ sent: await sendPush(supabase, to, "collab", { ...message, text: PUSH.collabJoined(title) }) });
    }

    if (action === "role") {
      if (!isOwner || !isUUID(body.user)) return json({ error: "forbidden" }, 403);
      const target = members.find((m) => m.user_id === String(body.user).toLowerCase());
      if (!target) return json({ error: "not_found" }, 404);
      const to = await throttled([target.user_id], `role:${mapID}`, 30);
      const role = target.role === "viewer" ? "viewer" : "editor";
      return json({ sent: await sendPush(supabase, to, "collab", { ...message, text: PUSH.roleChanged(title, role) }) });
    }

    return json({ error: "bad_request" }, 400);
  } catch (err) {
    console.error("push", err instanceof Error ? err.message : err);
    return json({ error: "server_error" }, 500);
  }
});
