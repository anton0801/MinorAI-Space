import { isPrivateAddress, checkURL, htmlToText, decodeEntities, fetchPublicText, NetError } from "./build/net.mjs";
import { clientSecret } from "./build/apple.mjs";
import { isYouTube } from "./build/youtube.mjs";
import { resolveChatModel, resolveMapModel, modelForTier, costMicros, estimateMicros, modelInfo, BUDGET_USD, ModelLockedError, imageQuality, estimateImageMicros, imageCostMicros, LIMITS } from "./build/models.mjs";
import { time, later } from "./build/subscriptions.mjs";
import { parseIntent, cleanWorkspace, workspaceBlock } from "./build/intent.mjs";
import crypto from "node:crypto";
globalThis.Deno = { env: { get: () => undefined } };
let pass = 0, fail = 0;
const ok = (c, n) => { c ? pass++ : fail++; console.log(c ? "ok  " : "FAIL", n); };
const throws = (f, n) => { try { f(); ok(false, n); } catch { ok(true, n); } };
ok(isPrivateAddress("::ffff:7f00:1"), "private ::ffff:7f00:1");
for (const ip of ["127.0.0.1","10.1.2.3","169.254.169.254","192.168.1.1","172.20.0.1","100.100.100.200","0.0.0.0","::1","fd00::1","fe80::1","::ffff:127.0.0.1","198.18.0.1"]) ok(isPrivateAddress(ip), "private " + ip);
for (const ip of ["8.8.8.8","1.1.1.1","2606:4700::1111","172.32.0.1"]) ok(!isPrivateAddress(ip), "public " + ip);
throws(() => checkURL("http://localhost./"), "localhost. rejected");
throws(() => checkURL("http://metadata.google.internal./x"), "metadata.internal. rejected");
throws(() => checkURL("ftp://example.com"), "ftp rejected");
throws(() => checkURL("http://example.com:8080/"), "odd port rejected");
throws(() => checkURL("http://user:pw@example.com/"), "credentials rejected");
ok(checkURL("example.com/a").hostname === "example.com", "bare host ok");
ok(checkURL("https://Example.com./x").hostname.toLowerCase() === "example.com", "trailing dot stripped");
// redirect to a private host is blocked at the next hop
const fakeFetch = async (url) => url.hostname === "public.test.com"
  ? new Response(null, { status: 302, headers: { location: "http://169.254.169.254/latest" } })
  : new Response("secret", { status: 200, headers: { "content-type": "text/plain" } });
try { await fetchPublicText("https://public.test.com/x", { resolve: async () => ["93.184.216.34"], fetcher: fakeFetch }); ok(false, "redirect to metadata blocked"); }
catch (e) { ok(e instanceof NetError && e.message === "bad_link", "redirect to metadata blocked"); }
try { await fetchPublicText("https://rebind.test.com/x", { resolve: async () => ["10.0.0.5"], fetcher: fakeFetch }); ok(false, "dns to private blocked"); }
catch (e) { ok(e instanceof NetError, "dns to private blocked"); }
const page = await fetchPublicText("https://ok.test.com/", { resolve: async () => ["93.184.216.34"], fetcher: async () => new Response("x".repeat(5000), { status: 200, headers: { "content-type": "text/plain" } }), maxBytes: 1000 });
ok(page.text.length === 1000, "byte cap respected");
ok(htmlToText("<p>Hi&amp;bye</p><script>var a='<p>no</p>'</script><nav>menu</nav> there &#x41; &#999999999;") === "Hi&bye there A", "html to text");
ok(decodeEntities("&amp;lt;") === "&lt;", "no double decoding");
const t0 = Date.now(); htmlToText("<script".repeat(300000)); const dt = Date.now() - t0; ok(dt < 500, `linear on 2 MB unclosed tags (${dt} ms)`);
ok(isYouTube("https://youtube.com:443/watch?v=x") && isYouTube("youtube.com./watch") && !isYouTube("https://notyoutube.com/x"), "youtube host parsing");
// Apple client secret: sign with a generated P-256 key and verify
const { privateKey, publicKey } = crypto.generateKeyPairSync("ec", { namedCurve: "P-256" });
const pem = privateKey.export({ type: "pkcs8", format: "pem" });
const secret = await clientSecret({ teamID: "7X47AV9RN8", keyID: "ABC123", privateKey: pem }, 1_800_000_000);
const [h, p, s] = secret.split(".");
const verified = crypto.verify("sha256", Buffer.from(`${h}.${p}`), { key: publicKey, dsaEncoding: "ieee-p1363" }, Buffer.from(s, "base64url"));
const claims = JSON.parse(Buffer.from(p, "base64url"));
ok(verified && claims.iss === "7X47AV9RN8" && claims.sub === "com.minorailifegroup.MinorAI" && claims.aud === "https://appleid.apple.com", "apple client secret signs and verifies");
ok((await clientSecret({})) === null, "no apple keys → null");
// IPv6: only global unicast counts as public
for (const ip of ["::7f00:1", "::ffff:0:7f00:1", "fec0::1", "2001:db8::1", "2002:7f00:1::1", "64:ff9b::7f00:1"]) ok(isPrivateAddress(ip), "private " + ip);
ok(!isPrivateAddress("2a00:1450:4001:81b::200e"), "public 2a00:1450::");
// models: chat is open to everyone, maps by plan
const both = { openai: true, anthropic: true };
ok(resolveChatModel("gpt-6-astra", both).model === "gpt-6-astra", "free chat may use Astra");
ok(resolveChatModel("claude-fable-5-1", { openai: true, anthropic: false }).model === "gpt-6-astra", "Fable falls back to the same tier on OpenAI");
ok(resolveChatModel(undefined, both).model === "gpt-6-luna", "default chat model is the lite one");
ok(resolveChatModel("unknown-model", both).tier === "lite", "unknown model → lite");
throws(() => resolveMapModel("free", "frontier", both), "free maps can't use frontier");
throws(() => resolveMapModel("plus", "frontier", both), "plus maps can't use frontier");
ok(resolveMapModel("pro", "frontier", both).tier === "frontier", "pro maps may use frontier");
ok(resolveMapModel("free", undefined, both).model === "gpt-6.1-sol", "free maps use the standard model");
ok(resolveMapModel("plus", "advanced", { openai: true, anthropic: false }).model === "gpt-6.1-sol", "advanced without Anthropic steps down, never up to a PRO model");
ok(resolveMapModel("pro", "claude-fable-5-1", both).model === "claude-fable-5-1", "pro picks Fable for maps");
throws(() => resolveMapModel("plus", "gpt-6-astra", both), "plus can't pick Astra for maps");
ok(resolveMapModel("free", "gpt-6-luna", both).tier === "standard", "lite request for maps → standard");
ok(modelForTier("lite", { openai: false, anthropic: true }).model === "claude-haiku-4-5-20251001", "lite on Anthropic is Haiku");
try { resolveMapModel("free", "advanced", both); } catch (e) { ok(e instanceof ModelLockedError, "locked error type"); }
// cost: 1M input + 1M output on Astra = $60 = 60,000,000 micros
ok(costMicros(modelInfo("gpt-6-astra"), 1_000_000, 1_000_000) === 60_000_000, "cost in micros");
const freeFrontier = estimateMicros(modelInfo("claude-fable-5-1"), 3_000, 0, 1_500);
ok(freeFrontier < BUDGET_USD.free * 1e6, `one free Fable message fits the free allowance (${freeFrontier} µ$)`);
// images: quality by plan, costs, and budgets
ok(imageQuality("free", "high") === "low" && imageQuality("plus", "high") === "medium" && imageQuality("pro", "high") === "high", "image quality follows the plan");
ok(imageCostMicros({ input_tokens_details: { text_tokens: 50, image_tokens: 0 }, output_tokens: 1756 }) === 52930, "medium image ≈ $0.053");
ok(estimateImageMicros("medium", 300) >= imageCostMicros({ input_tokens_details: { text_tokens: 100 }, output_tokens: 1756 }), "image estimate covers a medium image");
ok(LIMITS.plus.images * estimateImageMicros("medium", 300) <= BUDGET_USD.plus * 1e6 * 1.3, "Plus image count fits roughly in its allowance");
ok(LIMITS.free.images * estimateImageMicros("low", 300) < BUDGET_USD.free * 1e6, "free images fit the free allowance");
// dates are compared as instants, not strings
ok(time("2026-10-03T09:42:24.12+00:00") === time("2026-10-03T09:42:24.120Z"), "same instant in two formats");
ok(later("2026-10-03T09:42:24.12+00:00", "2026-10-03T09:42:24.130Z") === "2026-10-03T09:42:24.130Z", "later compares instants");
// The model marks picture and map requests; plain answers pass through.
ok(parseIntent("IMAGE: A dark blue BMW M5 F90 on a wet street at night")?.kind === "image", "intent image");
ok(parseIntent("**IMAGE:** a cat in space")?.prompt === "a cat in space", "intent image in bold");
ok(parseIntent("Sure!\nIMAGE: a red version of the car")?.prompt === "a red version of the car", "intent after a preamble");
ok(parseIntent("MAP: Изучение испанского")?.kind === "map", "intent map");
ok(parseIntent("MAP: ^")?.prompt === "^", "intent map of the conversation");
ok(parseIntent("Images are made of pixels.\nThe map: shows routes.") === null, "no intent in prose");
ok(parseIntent("IMAGE:") === null, "empty intent ignored");
ok(parseIntent("Maps in the game:\nMap: Erangel\nMap: Miramar") === null, "a normal \"Map:\" line is not an intent");
ok(parseIntent("IMAGE: " + "x".repeat(3000)).prompt.length === 1500, "intent prompt clipped");
// Workspace actions: only when the app sent the maps.
ok(parseIntent("READ: m-1a2b3c", true)?.maps?.[0] === "m-1a2b3c", "read one map");
ok(parseIntent("READ: m-1a2b3c, m-00ff11", true)?.maps?.length === 2, "read two maps");
ok(parseIntent("READ: m-1a2b3c") === null, "read ignored without workspace");
const edit = parseIntent("EDIT: m-1a2b3c | Добавь ветку «Глаголы» с примерами", true);
ok(edit?.kind === "edit" && edit.maps[0] === "m-1a2b3c" && edit.command.startsWith("Добавь"), "edit with command");
ok(parseIntent("EDIT: m-1a2b3c", true) === null, "edit without command ignored");
ok(parseIntent("EDIT: Spanish | add verbs", true) === null, "edit needs a reference");
ok(parseIntent("OPEN: m-abcdef", true)?.kind === "open", "open map");
ok(parseIntent("TASKS", true)?.kind === "tasks", "tasks");
ok(parseIntent("TASKS", false) === null, "tasks ignored without workspace");
ok(parseIntent("Tasks for today:\n- one", true) === null, "a normal \"Tasks\" line is not an intent");
const ws = cleanWorkspace([{ ref: "m-1A2B3C", title: "  Spanish   verbs ", ideas: 12.7, tasksDone: 2, tasksTotal: 5, edited: "2026-10-01", pinned: true }, { ref: "bad", title: "x" }, { ref: "m-000000", title: "y", edited: "yesterday" }]);
ok(ws.length === 2 && ws[0].ref === "m-1a2b3c" && ws[0].title === "Spanish verbs" && ws[0].ideas === 12 && ws[1].edited === "", "workspace cleaned");
ok(cleanWorkspace(Array.from({ length: 90 }, (_, i) => ({ ref: "m-" + String(i).padStart(6, "0"), title: "t" }))).length === 40, "workspace capped");
ok(workspaceBlock(ws, "2026-10-03").includes('m-1a2b3c "Spanish verbs": 12 ideas, tasks 2/5 done, edited 2026-10-01, pinned'), "workspace line");
ok(workspaceBlock([], "2026-10-03").includes("no mind maps"), "empty workspace");

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
