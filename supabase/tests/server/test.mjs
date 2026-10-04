import { isPrivateAddress, checkURL, htmlToText, decodeEntities, fetchPublicText, NetError } from "./build/net.mjs";
import { clientSecret } from "./build/apple.mjs";
import { isYouTube } from "./build/youtube.mjs";
import { resolveChatModel, resolveMapModel, modelForTier, costMicros, estimateMicros, modelInfo, BUDGET_USD, ModelLockedError, imageQuality, estimateImageMicros, imageCostMicros, LIMITS } from "./build/models.mjs";
import { time, later } from "./build/subscriptions.mjs";
import { parseIntent, cleanWorkspace, workspaceBlock } from "./build/intent.mjs";
import { deckRules, normalizeDeck, normalizeElements, normalizeLook, normalizeSlide, planFrom } from "./build/deck.mjs";
import { signJWT } from "./build/es256.mjs";
import { PUSH, ruDays } from "./build/pushText.mjs";
import { apnsPayload } from "./build/push.mjs";
import { parseBits } from "./build/devicecheck.mjs";
import { newCode, cleanCode, isPaidTransaction, INVITE_DAYS, INVITE_LIMIT, DISCOUNT_PERCENT, DISCOUNT_PRODUCTS, redeemURL } from "./build/referrals.mjs";
import { budgetMicros } from "./build/plan.mjs";
import { areaOf, BONUS_BUDGET_USD, textUnits, clip } from "./build/models.mjs";
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
ok(cleanWorkspace(Array.from({ length: 90 }, (_, i) => ({ ref: "m-" + String(i).padStart(6, "0"), title: "t" }))).length === 60, "workspace capped");
ok(workspaceBlock(ws, "2026-10-03").includes('m-1a2b3c "Spanish verbs": 12 ideas, tasks 2/5 done, edited 2026-10-01, pinned'), "workspace line");
ok(workspaceBlock([], "2026-10-03").includes("no mind maps"), "empty workspace");
// Presentations: markers and cleanup.
ok(parseIntent("DECK: История Рима")?.prompt === "История Рима", "deck from a topic");
ok(parseIntent("DECK: ^")?.prompt === "^", "deck from the conversation");
ok(parseIntent("DECK: m-1a2b3c", true)?.maps?.[0] === "m-1a2b3c", "deck from a map");
const editDeck = parseIntent("EDITDECK: d-00aa11 | add a slide about pricing", true);
ok(editDeck?.kind === "editdeck" && editDeck.maps[0] === "d-00aa11" && editDeck.command === "add a slide about pricing", "edit a deck");
ok(parseIntent("EDIT: m-1a2b3c | x", true)?.kind === "edit", "EDIT is not mistaken for EDITDECK");
ok(parseIntent("OPEN: d-00aa11", true)?.maps?.[0] === "d-00aa11", "open a deck");
ok(workspaceBlock(cleanWorkspace([{ ref: "d-00aa11", title: "Pitch", ideas: 9 }]), "2026-10-04").includes('d-00aa11 "Pitch": 9 slides'), "decks in the workspace");
const deck = normalizeDeck({ title: "Pitch", slides: [
  { layout: "cover", title: "Minor", subtitle: "Think in maps" },
  { layout: "bigNumber", title: "Growth" },
  { layout: "bullets", title: "Why", bullets: ["a", "", "b", 3] },
  { layout: "table", title: "Plans", table: [["Plan", "Price"], ["Free", "$0"], ["Plus"]] },
  { layout: "weird", title: "Fallback" },
  { layout: "quote", quote: "Simple is hard", author: "Someone" },
  {},
] }, 30);
ok(deck.slides.length === 6, "empty slides dropped");
ok(deck.slides[1].layout === "bullets", "bigNumber without a number falls back");
ok(deck.slides[2].bullets.length === 2, "empty bullets dropped");
ok(deck.slides[3].table[2].length === 2 && deck.slides[3].table[2][1] === "", "table rows padded");
ok(deck.slides[4].layout === "bullets", "unknown layout becomes bullets");
ok(deck.slides[5].quote.text === "Simple is hard", "quote as text");
ok(normalizeDeck({ slides: Array.from({ length: 40 }, (_, i) => ({ layout: "bullets", title: "S" + i })) }, 8).slides.length === 8, "slides capped by plan");
ok(normalizeSlide({ layout: "bullets", title: "x".repeat(300) }).title.length === 90, "title clipped");

// Templates: the AI follows the slide plan.
ok(planFrom(["cover", "bullets", "nope", "closing"], 30).join() === "cover,bullets,closing", "plan keeps known layouts");
ok(planFrom(["cover"], 30) === undefined && planFrom("x", 30) === undefined, "too short or not a list: no plan");
ok(planFrom(Array(40).fill("bullets"), 8).length === 8, "plan capped by plan's slides");
ok(deckRules(3, ["cover", "table", "closing"]).includes('2. "table"'), "rules list the plan");
// The AI designer: looks.
const look = normalizeLook({ look: { name: "Navy gold", background: { kind: "gradient", colors: ["#0b1026", "#1B2A5C"], angle: 400 }, accent: "#f5c451", palette: ["#F5C451", "#ffffff", "bad", "#123456"], titleFont: "didot", bodyFont: "comic", glow: false } });
ok(look.accent === "#F5C451" && look.background.colors[0] === "#0B1026", "colors upper-cased");
ok(look.background.angle === 40, "angle wrapped");
ok(look.titleFont === "didot" && look.bodyFont === "system", "unknown font falls back");
ok(look.palette.length === 3 && look.glow === false, "bad palette colors dropped");
ok(normalizeLook({ look: { background: { colors: ["red"] }, accent: "#fff" } }) === null, "a look needs real colors");
ok(normalizeLook({ background: { kind: "gradient", colors: ["#000000"] }, accent: "#2FFF9E" }).background.colors.length === 2, "one gradient color doubled");
// The AI designer: elements.
const els = normalizeElements({ elements: [
  { kind: "text", text: "Hello", x: 2000, y: -5, w: 300, h: 80, fontSize: 999, color: "#FFF" },
  { kind: "image", x: 0, y: 0, w: 100, h: 100 },
  { kind: "shape", shape: "blob", fill: "#ff0000", x: 10, y: 10, w: 5000, h: 5 },
  { kind: "icon", symbol: "star.fill); drop", x: 0, y: 0, w: 120, h: 120 },
  { kind: "chart", chart: { kind: "pie", labels: ["A", "B"], values: [1, "2"] }, x: 0, y: 0, w: 600, h: 400 },
  { kind: "chart", chart: { labels: ["A"], values: [1] } },
  { kind: "table", rows: [["Only header"]] },
  { kind: "qr" },
  { kind: "text" },
] });
ok(els.length === 4, "unusable elements dropped");
ok(els[0].x === 980 && els[0].y === 0 && els[0].fontSize === 160 && els[0].color === undefined, "text clamped into the slide; bad color dropped");
ok(els[1].w === 1280 && els[1].h === 24 && els[1].shape === undefined && els[1].fill === "#FF0000", "shape sized and checked");
ok(els[2].symbol === undefined, "odd symbol names dropped");
ok(els[3].chart.kind === "pie" && els[3].chart.values[1] === 2, "chart kept with numbers");
ok(normalizeElements({ elements: Array(20).fill({ kind: "icon", symbol: "bolt.fill" }) }).length === 8, "at most 8 elements");

// Apple provider tokens (APNs, DeviceCheck) sign and verify.
{
  const { privateKey, publicKey } = crypto.generateKeyPairSync("ec", { namedCurve: "P-256" });
  const pem = privateKey.export({ type: "pkcs8", format: "pem" });
  const jwt = await signJWT({ keyID: "KEY1234567", teamID: "7X47AV9RN8", privateKey: pem.replace(/\n/g, "\\n") }, { iss: "7X47AV9RN8", iat: 1_800_000_000 });
  const [h, p, s] = jwt.split(".");
  const header = JSON.parse(Buffer.from(h, "base64url"));
  const good = crypto.verify("sha256", Buffer.from(`${h}.${p}`), { key: publicKey, dsaEncoding: "ieee-p1363" }, Buffer.from(s, "base64url"));
  ok(good && header.alg === "ES256" && header.kid === "KEY1234567" && JSON.parse(Buffer.from(p, "base64url")).iss === "7X47AV9RN8", "provider token signs with an escaped .p8");
}
// Push texts and payloads.
ok(ruDays(1) === "1 день" && ruDays(3) === "3 дня" && ruDays(7) === "7 дней" && ruDays(11) === "11 дней" && ruDays(21) === "21 день" && ruDays(30) === "30 дней", "russian day forms");
ok(PUSH.friendJoined(3, false)("ru").body.includes("+3 дня") && PUSH.friendJoined(3, false)("en-US").body.includes("3 days"), "reward text per language");
ok(PUSH.friendJoined(3, true)("ru").body.includes("сохранены") && PUSH.friendSubscribed(30)("ru").body.includes("скидка 30%"), "waiting days and the discount explained");
ok(PUSH.collabChanged("Plan")("pt").title === "Plan", "unknown language falls back to English");
const apns = apnsPayload({ title: "T".repeat(500), body: "B" }, { route: "minorai://map/x", thread: "map-x" });
ok(apns.aps.alert.title.length === 120 && apns.route === "minorai://map/x" && apns.aps["thread-id"] === "map-x" && apns.aps.sound === "default", "apns payload");
ok(!("route" in apnsPayload({ title: "a", body: "b" }, {})), "no route when none");
// DeviceCheck replies.
function parseBitsThrows(status) { try { parseBits(status, ""); return null; } catch (e) { return e.message; } }
ok(parseBits(200, "Failed to find bit state") === false, "new device has no bit");
ok(parseBits(200, '{"bit0":true,"bit1":false,"last_update_time":"2026-10"}') === true, "bit 0 read");
throws(() => parseBits(400, "Missing or badly formatted device token payload"), "bad token throws");
// Invitation codes.
const codes = new Set(Array.from({ length: 200 }, () => newCode()));
ok([...codes].every((c) => /^[A-HJ-NP-Z2-9]{8}$/.test(c)) && codes.size === 200, "codes use the safe alphabet");
ok(newCode(() => new Uint8Array(8).fill(255)) === "99999999", "no modulo surprises at 255");
ok(cleanCode(" ab cd-ef23 ") === "ABCDEF23" && cleanCode("ABCDEF2O") === null && cleanCode("") === null, "codes cleaned and checked");
ok(INVITE_DAYS.friend === 3 && INVITE_DAYS.join === 3 && INVITE_LIMIT === 3 && DISCOUNT_PERCENT === 30, "rewards: 3 days each, 3 friends, 30% off");
ok(DISCOUNT_PRODUCTS.length === 4 && !DISCOUNT_PRODUCTS.some((p) => p.includes("HalfYear")), "discounts only for plans on sale");
ok(redeemURL("AB12CD34") === "https://apps.apple.com/redeem?ctx=offercodes&id=6737686540&code=AB12CD34", "offer code redemption link");
ok(isPaidTransaction({ environment: "Production", price: 4990 }), "paid production period counts");
ok(!isPaidTransaction({ environment: "Sandbox" }) && !isPaidTransaction({ environment: "Xcode" }), "test purchases don't count");
ok(!isPaidTransaction({ environment: "Production", offerDiscountType: "FREE_TRIAL" }) && !isPaidTransaction({ environment: "Production", price: 0 }), "free trials don't count");
// Allowance per plan and the breakdown areas.
ok(budgetMicros({ plan: "plus", subscription: "1", sandbox: false }) === 5_000_000, "plus allowance");
ok(budgetMicros({ plan: "pro", subscription: "1", sandbox: true }) === 5_000_000, "test purchase capped at $5");
ok(textUnits("abc") === 3 && textUnits("абв") === 9 && textUnits("🙂") === 6, "non-ASCII text counts as more tokens");
ok(clip("ab🙂cd", 4) === "ab…" && clip("abcdef", 4) === "abc…" && clip("abc", 4) === "abc", "clip never splits an emoji");
ok(parseBitsThrows(401) === "key" && parseBitsThrows(500) === "apple_500", "DeviceCheck key errors are told apart");
ok(budgetMicros({ plan: "plus", subscription: null, sandbox: false, bonusUntil: "2030-01-01T00:00:00Z" }) === BONUS_BUDGET_USD * 1_000_000, "free Plus from invitations has a smaller allowance");
ok(budgetMicros({ plan: "free", subscription: null, sandbox: false }) === 250_000, "free allowance");
ok(areaOf("expand") === "maps" && areaOf("quiz") === "maps" && areaOf("deckStyle") === "decks" && areaOf("chat") === "chat" && areaOf("image") === "images" && areaOf("report") === null, "actions map to areas");

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
