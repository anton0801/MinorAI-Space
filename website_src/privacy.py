# The Privacy Policy page (EN + RU) from one structure. Built by build.py.

from common import I, svg, icon, head, page

B = {
 "en": {"device": "On your iPhone", "server": "Our server (EU)", "ai": "AI provider", "apple": "Apple"},
 "ru": {"device": "На вашем iPhone", "server": "Наш сервер (ЕС)", "ai": "Провайдер ИИ", "apple": "Apple"},
}
def badges(lang, *kinds):
    return "".join(f'<span class="badge {k}">{B[lang][k]}</span>' for k in kinds)

T = {}
T["en"] = dict(
 title="Privacy Policy — Minor AI",
 eyebrow="Privacy Policy",
 h1='Your ideas <span class="grad">stay yours.</span>',
 lead="What Minor AI does with your data, in plain words: what stays on your iPhone, what goes to our server and to AI providers, how long it’s kept and how to switch each part off.",
 updated="Updated October 4, 2026", read="About 9 minutes", owner="Regina Danilova",
 contents="Contents", contact_q="Questions about your data?",
 glance=[
  ("ban", "#ff8f8f", "No ads, no selling", "We don’t sell or rent your data, show ads or track you across other apps and websites."),
  ("shield", "#2fff9e", "AI only with your OK", "Nothing goes to an AI provider until you allow it. You can turn it off any time."),
  ("spark", "#c9a2ff", "Not used to train AI", "Your maps, chats and files are not used to train AI models — ours or the providers’."),
  ("phone", "#7cc4ff", "Your maps, your devices", "Maps live on your iPhone and sync only to your own account. Sync can be switched off."),
  ("pin", "#ffd66b", "Servers in the EU", "Our backend runs in Frankfurt, Germany. Data is encrypted in transit."),
  ("trash", "#fc86c3", "Delete in one tap", "Settings → Delete Account removes your account, synced maps and pictures."),
 ],
 sections=[],
)
T["ru"] = dict(
 title="Политика конфиденциальности — Minor AI",
 eyebrow="Политика конфиденциальности",
 h1='Ваши идеи <span class="grad">остаются вашими.</span>',
 lead="Что Minor AI делает с вашими данными — простыми словами: что остаётся на iPhone, что уходит на наш сервер и к провайдерам ИИ, сколько хранится и как выключить каждую часть.",
 updated="Обновлено 4 октября 2026 г.", read="Около 9 минут", owner="Regina Danilova",
 contents="Содержание", contact_q="Вопросы о ваших данных?",
 glance=[
  ("ban", "#ff8f8f", "Без рекламы и продажи данных", "Мы не продаём и не сдаём ваши данные, не показываем рекламу и не отслеживаем вас в других приложениях и на сайтах."),
  ("shield", "#2fff9e", "ИИ — только с вашего согласия", "К провайдеру ИИ ничего не уходит, пока вы не разрешите. Выключить можно в любой момент."),
  ("spark", "#c9a2ff", "Не обучаем ИИ", "Ваши карты, чаты и файлы не используются для обучения моделей ИИ — ни нами, ни провайдерами."),
  ("phone", "#7cc4ff", "Ваши карты — ваши устройства", "Карты живут на iPhone и синхронизируются только с вашим аккаунтом. Синхронизацию можно выключить."),
  ("pin", "#ffd66b", "Серверы в ЕС", "Наш бэкенд работает во Франкфурте (Германия). Данные шифруются при передаче."),
  ("trash", "#fc86c3", "Удаление в один тап", "Настройки → Удалить аккаунт удаляет аккаунт, синхронизированные карты и картинки."),
 ],
 sections=[],
)

MAIL = '<a href="mailto:support@minorai.site">support@minorai.site</a>'

# ---------------- English sections ----------------
en = T["en"]["sections"]
en.append(("about", "Who we are", f'''
<p>This policy covers the Minor AI app (“Minor”, “the app”) and this website. Minor is published on the App Store by <strong>Regina Danilova</strong> (“we”, “us”), who is responsible for your personal data (the data controller). Questions or requests: {MAIL}.</p>
<p>Minor helps you think in mind maps and chat with AI. Some features need AI providers and our server; the rest works on your iPhone. Each section below says which is which.</p>'''))
en.append(("device", "What stays on your iPhone", f'''
<p>These never leave your device unless you send them to AI or turn on sync:</p>
<div class="legend">{badges("en","device")}</div>
<ul>
<li><strong>Chats</strong> and the images created in them.</li>
<li><strong>Version history</strong> of your maps (the last 30 versions of each).</li>
<li><strong>Task reminders</strong> — notifications are scheduled on the device.</li>
<li><strong>The Today widget</strong>, <strong>Siri and Shortcuts</strong> actions — they read your maps on the device.</li>
<li><strong>Pages and text you share to Minor</strong> from other apps wait on the device until you build a map.</li>
<li><strong>Dictation and Voice Mode</strong> — speech becomes text on your iPhone where Apple supports it for your language; answers are read aloud by your iPhone.</li>
<li><strong>Scans</strong> — text in photos of notes or slides is recognized on your iPhone.</li>
<li><strong>Flashcard progress</strong>, the <strong>morning brief</strong> and the widget’s list of tasks.</li>
<li>Maps and presentations too, when <strong>Sync Maps</strong> is off or you are signed out.</li>
</ul>'''))
en.append(("datamap", "Data map", f'''
<p>Every kind of data Minor handles, where it goes and how long it is kept.</p>
<div class="legend">{badges("en","device","server","ai","apple")}</div>
<div class="table-scroll"><table class="data-table">
<thead><tr><th>Data</th><th>What exactly</th><th>Where it goes</th><th>How long</th></tr></thead>
<tbody>
<tr><td>Maps</td><td data-h="What exactly">Ideas, notes, tasks and dates, pictures, styles, connections</td><td data-h="Where it goes">{badges("en","device","server")} {badges("en","ai")}<br><small>Server only with Sync Maps on; AI gets only what an AI action needs</small></td><td data-h="How long">Until you delete them</td></tr>
<tr><td>Presentations</td><td data-h="What exactly">Slides, speaker notes, pictures</td><td data-h="Where it goes">{badges("en","device","server")} {badges("en","ai")}<br><small>Server only with Sync Maps on; AI writes and rewrites slides you ask for</small></td><td data-h="How long">Until you delete them</td></tr>
<tr><td>Shared maps</td><td data-h="What exactly">A map you share with Edit Together, and who edits it</td><td data-h="Where it goes">{badges("en","server")}<br><small>Visible to the people you invite</small></td><td data-h="How long">Until you stop sharing it or delete your account</td></tr>
<tr><td>Chats</td><td data-h="What exactly">Your messages, attached photos, files and maps</td><td data-h="Where it goes">{badges("en","device","ai")}</td><td data-h="How long">On the device until you delete them</td></tr>
<tr><td>Account</td><td data-h="What exactly">Email and password hash, or Apple user ID</td><td data-h="Where it goes">{badges("en","server")}</td><td data-h="How long">While your account exists</td></tr>
<tr><td>AI requests</td><td data-h="What exactly">Text, photos, documents and links you send to AI</td><td data-h="Where it goes">{badges("en","server","ai")}</td><td data-h="How long">Not stored after the answer; error logs up to 7 days</td></tr>
<tr><td>Purchases</td><td data-h="What exactly">Product, transaction IDs, dates, refund status</td><td data-h="Where it goes">{badges("en","apple","server")}</td><td data-h="How long">While your account exists; kept without your identity after deletion</td></tr>
<tr><td>Usage</td><td data-h="What exactly">Monthly counts of maps, AI actions, chats and AI cost</td><td data-h="Where it goes">{badges("en","server")}</td><td data-h="How long">While your account exists</td></tr>
<tr><td>Device identifier</td><td data-h="What exactly">An app-only ID (identifierForVendor) for free-plan limits</td><td data-h="Where it goes">{badges("en","server")}</td><td data-h="How long">With monthly usage counts</td></tr>
<tr><td>Notifications</td><td data-h="What exactly">This device’s push token, app language and which notifications you want</td><td data-h="Where it goes">{badges("en","server","apple")}</td><td data-h="How long">Until you sign out, turn them off or delete your account</td></tr>
<tr><td>Invitations</td><td data-h="What exactly">Your invitation code, who invited whom, rewards, a one-way hash of the device ID</td><td data-h="Where it goes">{badges("en","server","apple")}</td><td data-h="How long">While your account exists</td></tr>
<tr><td>Voice</td><td data-h="What exactly">Your speech for dictation and voice maps</td><td data-h="Where it goes">{badges("en","device","apple")}</td><td data-h="How long">Audio never reaches us</td></tr>
</tbody></table></div>'''))
en.append(("collect", "Details by feature", f'''
<h3>{svg("user")} Account</h3>
<p>AI features need an account: <strong>email and password</strong>, or <strong>Sign in with Apple</strong>. With Apple we receive an Apple user identifier and an email address, which can be a private relay address. Passwords are stored by our authentication provider as secure hashes; we never see them.</p>
<h3>{svg("spark")} What you send to AI</h3>
<p>Topics, links, documents (PDF, TXT, RTF), photos, chat messages, dictated text and the parts of your maps an AI action needs — for example the idea you expand or the map you ask to change. It is processed to produce the answer and is <strong>not stored on our server</strong> afterwards, except in short-lived error logs.</p>
<h3>{svg("chat")} The chat assistant and your maps</h3>
<p>So the assistant can work with your maps (“what maps do I have?”, “add verbs to my Spanish map”), each chat message includes a short list of your maps: titles, number of ideas, task progress and the last edit date. A map’s content is sent only when you attach it with @, ask about that map or ask to change it; “Plan My Day” sends your open tasks. Changes can be undone in the chat. Off switch: <strong>Settings → Assistant Sees My Maps</strong>.</p>
<h3>{svg("sync")} Map sync and backup</h3>
<p>When you are signed in, your maps and their pictures are copied to our server so they are the same on all your devices and survive a lost phone. Only your account can read them. Off switch: <strong>Settings → Sync Maps</strong> — maps then stay on the device only.</p>
<h3>{svg("map")} Presentations</h3>
<p>To make a presentation, the map, topic or chat you pick goes to the AI provider, which writes the slides and speaker notes; rewriting a slide sends that slide. Presentations are stored on your device and, with Sync Maps on, on our server like maps. Exports (PDF, PowerPoint) are made on your iPhone.</p>
<h3>{svg("user")} Edit Together</h3>
<p>When you share a map, its content is stored on our server so the people you invite can open it: editors can change it, viewers only see it. An invite link works for 14 days; only a hash of it is stored. Each change records who made it. People on a shared map see who else is on it: the owner sees everyone’s email address, others see the owner’s and a shortened form of the rest. The owner can change roles, remove people (which also turns off old invite links) and stop sharing; anyone can leave. Everyone keeps their own copy.</p>
<h3>{svg("calendar")} Calendar</h3>
<p>If you turn on <strong>Tasks in Calendar</strong>, Minor adds tasks with a due date to a “Minor AI” calendar on your device (and in iCloud when your calendars sync there). Minor doesn’t read your other events.</p>
<h3>{svg("map")} AI images</h3>
<p>Your description (and, on a map, the idea and its path) goes to OpenAI, which draws the picture. The image comes back to your device; we don’t keep it. If you report an image, its description is kept for review.</p>
<h3>{svg("phone")} Photos you add</h3>
<p>Photos on ideas stay on your device (and in your synced maps if sync is on). Photos sent in chat go to the AI provider with that message.</p>
<h3>{svg("bell")} Voice and dictation</h3>
<p>Dictation in the chat and voice maps use Apple speech recognition — on your device when your language supports it, otherwise on Apple’s servers under Apple’s privacy policy. Audio never reaches us; only the text you then send.</p>
<h3>{svg("info")} Links and videos</h3>
<p>When you map a web page or a YouTube video, our server downloads the page or the video’s transcript to read it. The site sees a request from our server, not from your device.</p>
<h3>{svg("card")} Purchases and usage</h3>
<p>For subscriptions we receive the App Store details needed to unlock your plan. Payment details stay with Apple. Each month we count maps, AI actions, chats and link reads, and the cost of AI processing, to apply plan limits and your monthly AI allowance. For the free plan we store an app-only device identifier with these counts so limits can’t be reset by new accounts; it is never used for ads.</p>
<h3>{svg("bell")} Notifications</h3>
<p>Task reminders and the morning brief are created on your device. Notifications about shared maps (a change, someone joined, a new role), invitations and your AI allowance come from our server through Apple Push Notification service: we keep this device’s push token, the app language and your choices, and Apple delivers the message. Turn them off in <strong>Settings → Shared Map Updates / Invitations and Limits</strong> or in iOS Settings.</p>
<h3>{svg("user")} Invitations</h3>
<p>Everyone gets an invitation code. When a friend signs up with yours, we store that you invited them and which rewards were given; you see only how many friends joined, made a map or subscribed — not who. So one iPhone can take only one invitation, we store a one-way hash of the device identifier and ask Apple’s DeviceCheck to remember one bit for the device; Apple doesn’t learn who you are and we don’t learn anything else about the device.</p>
<h3>{svg("map")} Shared links (PRO)</h3>
<p>Share Link uploads an image of the map; anyone with the link can view it until you stop sharing, delete the map or delete your account.</p>
<h3>{svg("ban")} What we don’t collect</h3>
<p>No contacts, location, advertising identifier or browsing history. No third-party analytics or advertising SDKs. Notifications go only through Apple.</p>'''))
en.append(("ai", "AI providers", f'''
<p>AI requests are processed by <strong>OpenAI</strong> or <strong>Anthropic</strong>, depending on the model you choose. They receive the content of the request and a random, non-reversible identifier that helps them detect abuse — not your name or email.</p>
<div class="callout">{svg("shield")}<div>Under their API terms, content sent through the API is <strong>not used to train their models</strong>. They may keep it for a limited time to detect abuse. Please don’t send sensitive data (for example health or financial details) you don’t want processed this way.</div></div>
<p>Minor asks for your permission before the first AI request. Withdraw it any time in <strong>Settings → AI Data Sharing</strong>; AI features then stop until you allow them again.</p>'''))
en.append(("use", "Why we use data", '''
<div class="table-scroll"><table class="data-table">
<thead><tr><th>Purpose</th><th>Data</th><th>Legal basis (EU/UK)</th></tr></thead>
<tbody>
<tr><td>AI features: maps, ideas, chat, images, quizzes</td><td data-h="Data">What you send, your account</td><td data-h="Legal basis">Our contract with you; your consent to AI processing</td></tr>
<tr><td>Map sync and backup</td><td data-h="Data">Your maps and their pictures</td><td data-h="Legal basis">Contract (you can turn it off)</td></tr>
<tr><td>Accounts and sign-in</td><td data-h="Data">Email, password hash, Apple ID</td><td data-h="Legal basis">Contract</td></tr>
<tr><td>Subscriptions and limits</td><td data-h="Data">Purchase details, usage counts</td><td data-h="Legal basis">Contract</td></tr>
<tr><td>Preventing abuse of free limits</td><td data-h="Data">Device identifier, usage counts, the DeviceCheck bit for invitations</td><td data-h="Legal basis">Legitimate interest in a service that stays available and affordable</td></tr>
<tr><td>Fixing errors, security, support</td><td data-h="Data">Short-lived logs, what you write to us</td><td data-h="Legal basis">Legitimate interest; contract</td></tr>
</tbody></table></div>
<p>We don’t use your content to train AI, don’t sell or rent personal data, and don’t use it for advertising.</p>'''))
en.append(("services", "Services we use", '''
<div class="svc-grid">
<div class="svc"><h4>Supabase <span class="where">EU · Frankfurt</span></h4><p>Our backend: accounts, plans and usage, the functions that forward AI requests, synced maps and shared images.</p></div>
<div class="svc"><h4>OpenAI <span class="where">USA</span></h4><p>GPT models for maps and chat, and image generation.</p></div>
<div class="svc"><h4>Anthropic <span class="where">USA</span></h4><p>Claude models for maps and chat.</p></div>
<div class="svc"><h4>Apple <span class="where">Global</span></h4><p>Sign in with Apple, purchases and subscription notices, speech recognition.</p></div>
<div class="svc"><h4>Resend <span class="where">USA</span></h4><p>Sends sign-up and password-reset codes to your email.</p></div>
</div>
<p>They process data only on our behalf and under their own security and privacy commitments.</p>'''))
en.append(("where", "Where data is stored", '''
<p>Our backend runs on Supabase in the European Union (Frankfurt, Germany). AI providers and some services may process data in the United States. Where data leaves the EEA or UK, we rely on the safeguards these providers offer, such as the European Commission’s Standard Contractual Clauses.</p>'''))
en.append(("retention", "How long we keep data", '''
<div class="table-scroll"><table class="data-table">
<thead><tr><th>Data</th><th>Kept</th></tr></thead>
<tbody>
<tr><td>Maps and chats on your device</td><td data-h="Kept">Until you delete them, delete your account or delete the app</td></tr>
<tr><td>Synced maps, presentations and pictures</td><td data-h="Kept">While your account exists. A deleted one leaves only a small marker so your other devices delete it too</td></tr>
<tr><td>Shared maps</td><td data-h="Kept">Until the owner stops sharing or deletes their account; the people invited keep their own copies</td></tr>
<tr><td>Account, plan and usage</td><td data-h="Kept">While your account exists; usage is counted per calendar month</td></tr>
<tr><td>AI request content</td><td data-h="Kept">Not stored after the answer; technical logs are deleted within 7 days</td></tr>
<tr><td>Shared map images</td><td data-h="Kept">Until you stop sharing, delete the map or delete your account</td></tr>
<tr><td>After account deletion</td><td data-h="Kept">Without any link to you: subscription records (for App Store renewals and refunds) and monthly counts tied to the device identifier</td></tr>
</tbody></table></div>'''))
en.append(("controls", "Your controls and rights", f'''
<p>Everything below is in the app’s Settings:</p>
<div class="ctl-grid">
<div class="ctl">{icon("shield")}<div><h4>AI Data Sharing</h4><p>Allow or stop sending content to AI providers.</p><span class="path">Settings → AI Data Sharing</span></div></div>
<div class="ctl">{icon("chat")}<div><h4>Assistant Sees My Maps</h4><p>Let the chat assistant see your list of maps.</p><span class="path">Settings → Assistant Sees My Maps</span></div></div>
<div class="ctl">{icon("sync")}<div><h4>Sync Maps</h4><p>Keep maps on all your devices, or only on this one.</p><span class="path">Settings → Sync Maps</span></div></div>
<div class="ctl">{icon("bell")}<div><h4>Task Reminders</h4><p>Notifications for tasks with a due date.</p><span class="path">Settings → Task Reminders</span></div></div>
<div class="ctl">{icon("calendar")}<div><h4>Tasks in Calendar</h4><p>Show tasks with a date in a “Minor AI” calendar.</p><span class="path">Settings → Tasks in Calendar</span></div></div>
<div class="ctl">{icon("user")}<div><h4>Edit Together</h4><p>Stop sharing a map, or leave one shared with you.</p><span class="path">Map menu → Edit Together</span></div></div>
<div class="ctl">{icon("trash")}<div><h4>Delete Account</h4><p>Deletes your account, usage, synced maps, presentations and pictures, maps you share, shared images, and everything on the device. Revokes Sign in with Apple.</p><span class="path">Settings → Delete Account</span></div></div>
<div class="ctl">{icon("card")}<div><h4>Subscriptions</h4><p>Deleting the account doesn’t cancel a subscription — manage it with Apple.</p><span class="path">iPhone Settings → Apple ID → Subscriptions</span></div></div>
</div>
<p>Depending on where you live (for example the EU, EEA, UK or California), you can ask to access, correct, delete or export your data, object to or restrict processing, and withdraw consent. Write to {MAIL} — we answer within 30 days. You can also complain to your local data protection authority. We don’t “sell” or “share” personal information as defined by California law.</p>'''))
en.append(("children", "Children", '''
<p>Minor is not directed to children under 13 (or the minimum age in your country), and we don’t knowingly collect their data. If you believe a child has given us personal data, contact us and we will delete it.</p>'''))
en.append(("security", "Security", '''
<p>Data is encrypted in transit (HTTPS). Your sign-in session is kept in the iOS Keychain. Synced maps are protected by row-level security, so only your account can read them. AI provider keys exist only on our server. No system is perfectly secure, but we work to protect your data and will tell you if a breach affects you, as the law requires.</p>'''))
en.append(("website", "This website", '''
<p>minorai.site uses no cookies, analytics or trackers. It only remembers your language choice in your browser’s local storage.</p>'''))
en.append(("changes", "Changes and contact", f'''
<p>We post changes on this page and update the date at the top. For significant changes we will also tell you in the app.</p>
<div class="contact-card"><div><h2>Questions about your data?</h2><p>Regina Danilova · {MAIL}</p></div><a class="btn btn-primary" href="mailto:support@minorai.site">Write to us</a></div>'''))

# ---------------- Russian sections ----------------
ru = T["ru"]["sections"]
ru.append(("about", "Кто мы", f'''
<p>Эта политика относится к приложению Minor AI («Minor», «приложение») и этому сайту. Minor опубликовано в App Store разработчиком <strong>Regina Danilova</strong> («мы»), которая отвечает за ваши персональные данные (оператор данных). Вопросы и запросы: {MAIL}.</p>
<p>Minor помогает думать картами и общаться с ИИ. Часть функций работает через провайдеров ИИ и наш сервер, остальное — прямо на iPhone. В каждом разделе ниже сказано, что где.</p>'''))
ru.append(("device", "Что остаётся на вашем iPhone", f'''
<p>Это не покидает устройство, пока вы сами не отправите это ИИ или не включите синхронизацию:</p>
<div class="legend">{badges("ru","device")}</div>
<ul>
<li><strong>Чаты</strong> и созданные в них картинки.</li>
<li><strong>История версий</strong> карт (последние 30 версий каждой).</li>
<li><strong>Напоминания о задачах</strong> — уведомления планируются на устройстве.</li>
<li><strong>Виджет «Сегодня»</strong>, действия <strong>Siri и «Команд»</strong> — они читают карты на устройстве.</li>
<li><strong>Страницы и текст, присланные в Minor</strong> из других приложений, ждут на устройстве, пока вы не построите карту.</li>
<li><strong>Диктовка и голосовой режим</strong> — речь превращается в текст на iPhone, если Apple поддерживает это для вашего языка; ответы читает вслух сам iPhone.</li>
<li><strong>Сканы</strong> — текст на фото конспектов и слайдов распознаётся на iPhone.</li>
<li><strong>Прогресс карточек</strong>, <strong>утренняя сводка</strong> и список задач виджета.</li>
<li>Карты и презентации — тоже, когда <strong>Синхронизация карт</strong> выключена или вы не вошли в аккаунт.</li>
</ul>'''))
ru.append(("datamap", "Карта данных", f'''
<p>Все виды данных, с которыми работает Minor, — куда они попадают и сколько хранятся.</p>
<div class="legend">{badges("ru","device","server","ai","apple")}</div>
<div class="table-scroll"><table class="data-table">
<thead><tr><th>Данные</th><th>Что именно</th><th>Куда попадают</th><th>Сколько хранятся</th></tr></thead>
<tbody>
<tr><td>Карты</td><td data-h="Что именно">Идеи, заметки, задачи и сроки, картинки, стили, связи</td><td data-h="Куда попадают">{badges("ru","device","server")} {badges("ru","ai")}<br><small>На сервер — только при включённой синхронизации; ИИ получает только то, что нужно для действия</small></td><td data-h="Сколько хранятся">Пока вы их не удалите</td></tr>
<tr><td>Презентации</td><td data-h="Что именно">Слайды, заметки докладчика, картинки</td><td data-h="Куда попадают">{badges("ru","device","server")} {badges("ru","ai")}<br><small>На сервер — только при включённой синхронизации; ИИ пишет и переписывает слайды по вашей просьбе</small></td><td data-h="Сколько хранятся">Пока вы их не удалите</td></tr>
<tr><td>Совместные карты</td><td data-h="Что именно">Карта, которой вы поделились через «Редактировать вместе», и кто её редактирует</td><td data-h="Куда попадают">{badges("ru","server")}<br><small>Видна людям, которых вы пригласили</small></td><td data-h="Сколько хранятся">Пока вы не закроете доступ или не удалите аккаунт</td></tr>
<tr><td>Чаты</td><td data-h="Что именно">Ваши сообщения, приложенные фото, файлы и карты</td><td data-h="Куда попадают">{badges("ru","device","ai")}</td><td data-h="Сколько хранятся">На устройстве, пока вы их не удалите</td></tr>
<tr><td>Аккаунт</td><td data-h="Что именно">Почта и хеш пароля или идентификатор Apple</td><td data-h="Куда попадают">{badges("ru","server")}</td><td data-h="Сколько хранятся">Пока существует аккаунт</td></tr>
<tr><td>Запросы к ИИ</td><td data-h="Что именно">Текст, фото, документы и ссылки, которые вы отправляете ИИ</td><td data-h="Куда попадают">{badges("ru","server","ai")}</td><td data-h="Сколько хранятся">Не хранятся после ответа; журналы ошибок — до 7 дней</td></tr>
<tr><td>Покупки</td><td data-h="Что именно">Продукт, идентификаторы транзакций, даты, статус возврата</td><td data-h="Куда попадают">{badges("ru","apple","server")}</td><td data-h="Сколько хранятся">Пока существует аккаунт; после удаления — без связи с вами</td></tr>
<tr><td>Использование</td><td data-h="Что именно">Месячные счётчики карт, действий ИИ, чатов и стоимости ИИ</td><td data-h="Куда попадают">{badges("ru","server")}</td><td data-h="Сколько хранятся">Пока существует аккаунт</td></tr>
<tr><td>Идентификатор устройства</td><td data-h="Что именно">Идентификатор только для приложения (identifierForVendor) для лимитов бесплатного тарифа</td><td data-h="Куда попадают">{badges("ru","server")}</td><td data-h="Сколько хранятся">Вместе с месячными счётчиками</td></tr>
<tr><td>Уведомления</td><td data-h="Что именно">Push-токен этого устройства, язык приложения и какие уведомления вы хотите получать</td><td data-h="Куда попадают">{badges("ru","server","apple")}</td><td data-h="Сколько хранятся">Пока вы не выйдете, не выключите их или не удалите аккаунт</td></tr>
<tr><td>Приглашения</td><td data-h="Что именно">Ваш код приглашения, кто кого пригласил, награды, необратимый хеш идентификатора устройства</td><td data-h="Куда попадают">{badges("ru","server","apple")}</td><td data-h="Сколько хранятся">Пока существует аккаунт</td></tr>
<tr><td>Голос</td><td data-h="Что именно">Ваша речь для диктовки и голосовых карт</td><td data-h="Куда попадают">{badges("ru","device","apple")}</td><td data-h="Сколько хранятся">Звук к нам не попадает</td></tr>
</tbody></table></div>'''))
ru.append(("collect", "Подробно по функциям", f'''
<h3>{svg("user")} Аккаунт</h3>
<p>Для функций ИИ нужен аккаунт: <strong>почта и пароль</strong> или <strong>«Вход с Apple»</strong>. При входе через Apple мы получаем идентификатор пользователя Apple и адрес почты (это может быть скрытый адрес). Пароли хранятся у провайдера авторизации в виде защищённых хешей — мы их не видим.</p>
<h3>{svg("spark")} Что вы отправляете ИИ</h3>
<p>Темы, ссылки, документы (PDF, TXT, RTF), фото, сообщения чата, надиктованный текст и те части карт, которые нужны для действия ИИ — например, идея, которую вы развиваете, или карта, которую просите изменить. Это обрабатывается для ответа и <strong>не хранится на нашем сервере</strong> после него, кроме кратковременных журналов ошибок.</p>
<h3>{svg("chat")} Чат-помощник и ваши карты</h3>
<p>Чтобы помощник работал с вашими картами («какие у меня карты?», «добавь глаголы в карту по испанскому»), к каждому сообщению прикладывается короткий список карт: названия, число идей, прогресс задач и дата изменения. Содержимое карты отправляется, только когда вы прикрепляете её через @, спрашиваете о ней или просите её изменить; «Спланировать день» отправляет ваши открытые задачи. Изменения можно отменить в чате. Выключить: <strong>Настройки → Помощник видит мои карты</strong>.</p>
<h3>{svg("sync")} Синхронизация и резервная копия карт</h3>
<p>Когда вы вошли в аккаунт, карты и их картинки копируются на наш сервер, чтобы быть одинаковыми на всех ваших устройствах и не потеряться вместе с телефоном. Читать их может только ваш аккаунт. Выключить: <strong>Настройки → Синхронизация карт</strong> — тогда карты хранятся только на устройстве.</p>
<h3>{svg("map")} Презентации</h3>
<p>Чтобы сделать презентацию, выбранная карта, тема или чат уходит провайдеру ИИ, который пишет слайды и заметки докладчика; при переписывании слайда отправляется этот слайд. Презентации хранятся на устройстве и, при включённой синхронизации, на нашем сервере — как карты. Экспорт (PDF, PowerPoint) делается на iPhone.</p>
<h3>{svg("user")} Редактировать вместе</h3>
<p>Когда вы делитесь картой, её содержимое хранится на нашем сервере, чтобы приглашённые могли её открывать: редакторы — менять, наблюдатели — только смотреть. Ссылка-приглашение действует 14 дней; хранится только её хеш. У каждого изменения отмечается, кто его сделал. Участники совместной карты видят, кто ещё в ней: владелец видит почту всех, остальные — почту владельца и сокращённую почту других. Владелец может менять роли, убирать людей (старые ссылки-приглашения при этом отключаются) и закрывать доступ; выйти может любой. У каждого остаётся своя копия.</p>
<h3>{svg("calendar")} Календарь</h3>
<p>Если включить <strong>Задачи в Календаре</strong>, Minor добавляет задачи со сроком в календарь «Minor AI» на устройстве (и в iCloud, если ваши календари синхронизируются там). Другие ваши события Minor не читает.</p>
<h3>{svg("map")} Картинки ИИ</h3>
<p>Ваше описание (а на карте — идея и путь к ней) уходит в OpenAI, которая рисует картинку. Картинка приходит на устройство; мы её не храним. Если вы пожалуетесь на картинку, её описание сохраняется для проверки.</p>
<h3>{svg("phone")} Фото, которые вы добавляете</h3>
<p>Фото на идеях остаются на устройстве (и в синхронизированных картах, если синхронизация включена). Фото в чате уходят провайдеру ИИ вместе с сообщением.</p>
<h3>{svg("bell")} Голос и диктовка</h3>
<p>Диктовка в чате и голосовые карты используют распознавание речи Apple — на устройстве, если ваш язык это поддерживает, иначе на серверах Apple по политике конфиденциальности Apple. Звук к нам не попадает — только текст, который вы затем отправите.</p>
<h3>{svg("info")} Ссылки и видео</h3>
<p>Когда вы строите карту по веб-странице или видео YouTube, наш сервер загружает страницу или субтитры видео, чтобы их прочитать. Сайт видит запрос от нашего сервера, а не от вашего устройства.</p>
<h3>{svg("card")} Покупки и использование</h3>
<p>Для подписок мы получаем данные App Store, нужные для включения тарифа. Платёжные данные остаются у Apple. Каждый месяц мы считаем карты, действия ИИ, сообщения и чтения ссылок, а также стоимость обработки ИИ — чтобы применять лимиты тарифа и месячный лимит ИИ. Для бесплатного тарифа вместе со счётчиками хранится идентификатор устройства только для приложения, чтобы лимиты нельзя было сбросить новыми аккаунтами; для рекламы он не используется.</p>
<h3>{svg("bell")} Уведомления</h3>
<p>Напоминания о задачах и утренняя сводка создаются на устройстве. Уведомления об общих картах (изменения, новый участник, новая роль), приглашениях и лимите ИИ приходят с нашего сервера через Apple Push Notification service: мы храним push-токен устройства, язык приложения и ваш выбор, а доставляет сообщение Apple. Выключить: <strong>Настройки → Изменения в общих картах / Приглашения и лимиты</strong> или в Настройках iOS.</p>
<h3>{svg("user")} Приглашения</h3>
<p>У каждого есть код приглашения. Когда друг регистрируется с вашим кодом, мы сохраняем, что его пригласили вы, и какие награды выданы; вы видите только, сколько друзей пришли, сделали карту или подписались, — но не кто именно. Чтобы на одном iPhone можно было использовать только одно приглашение, мы храним необратимый хеш идентификатора устройства и просим Apple DeviceCheck запомнить для устройства один бит; Apple не узнаёт, кто вы, а мы — ничего больше об устройстве.</p>
<h3>{svg("map")} Ссылки на карты (PRO)</h3>
<p>«Поделиться ссылкой» загружает изображение карты; его может открыть любой, у кого есть ссылка, пока вы не закроете доступ, не удалите карту или аккаунт.</p>
<h3>{svg("ban")} Что мы не собираем</h3>
<p>Ни контактов, ни геопозиции, ни рекламного идентификатора, ни истории браузера. Никаких сторонних SDK аналитики и рекламы. Уведомления идут только через Apple.</p>'''))
ru.append(("ai", "Провайдеры ИИ", f'''
<p>Запросы к ИИ обрабатывают <strong>OpenAI</strong> или <strong>Anthropic</strong> — в зависимости от выбранной модели. Они получают содержимое запроса и случайный необратимый идентификатор для выявления злоупотреблений — но не ваше имя и почту.</p>
<div class="callout">{svg("shield")}<div>По условиям их API содержимое, отправленное через API, <strong>не используется для обучения моделей</strong>. Оно может храниться ограниченное время для выявления злоупотреблений. Не отправляйте чувствительные данные (например, о здоровье или финансах), если не хотите, чтобы они так обрабатывались.</div></div>
<p>Перед первым запросом к ИИ Minor спрашивает разрешения. Отозвать его можно в любой момент: <strong>Настройки → Передача данных ИИ</strong>; после этого функции ИИ не работают, пока вы снова не разрешите.</p>'''))
ru.append(("use", "Зачем мы используем данные", '''
<div class="table-scroll"><table class="data-table">
<thead><tr><th>Цель</th><th>Данные</th><th>Правовое основание (ЕС/Великобритания)</th></tr></thead>
<tbody>
<tr><td>Функции ИИ: карты, идеи, чат, картинки, тесты</td><td data-h="Данные">То, что вы отправляете, аккаунт</td><td data-h="Основание">Договор с вами; ваше согласие на обработку ИИ</td></tr>
<tr><td>Синхронизация и резервная копия карт</td><td data-h="Данные">Ваши карты и их картинки</td><td data-h="Основание">Договор (можно выключить)</td></tr>
<tr><td>Аккаунты и вход</td><td data-h="Данные">Почта, хеш пароля, идентификатор Apple</td><td data-h="Основание">Договор</td></tr>
<tr><td>Подписки и лимиты</td><td data-h="Данные">Данные покупок, счётчики использования</td><td data-h="Основание">Договор</td></tr>
<tr><td>Защита бесплатных лимитов</td><td data-h="Данные">Идентификатор устройства, счётчики, бит DeviceCheck для приглашений</td><td data-h="Основание">Законный интерес сохранять сервис доступным и недорогим</td></tr>
<tr><td>Исправление ошибок, безопасность, поддержка</td><td data-h="Данные">Кратковременные журналы, то, что вы нам пишете</td><td data-h="Основание">Законный интерес; договор</td></tr>
</tbody></table></div>
<p>Мы не обучаем ИИ на вашем содержимом, не продаём и не сдаём персональные данные и не используем их для рекламы.</p>'''))
ru.append(("services", "Сервисы, которые мы используем", '''
<div class="svc-grid">
<div class="svc"><h4>Supabase <span class="where">ЕС · Франкфурт</span></h4><p>Наш бэкенд: аккаунты, тарифы и использование, функции, передающие запросы к ИИ, синхронизированные карты и изображения по ссылкам.</p></div>
<div class="svc"><h4>OpenAI <span class="where">США</span></h4><p>Модели GPT для карт и чата, создание картинок.</p></div>
<div class="svc"><h4>Anthropic <span class="where">США</span></h4><p>Модели Claude для карт и чата.</p></div>
<div class="svc"><h4>Apple <span class="where">По всему миру</span></h4><p>Вход с Apple, покупки и уведомления о подписках, распознавание речи.</p></div>
<div class="svc"><h4>Resend <span class="where">США</span></h4><p>Отправляет коды регистрации и сброса пароля на вашу почту.</p></div>
</div>
<p>Они обрабатывают данные только по нашему поручению и в рамках своих обязательств по безопасности и конфиденциальности.</p>'''))
ru.append(("where", "Где хранятся данные", '''
<p>Наш бэкенд работает на Supabase в Европейском союзе (Франкфурт, Германия). Провайдеры ИИ и некоторые сервисы могут обрабатывать данные в США. Когда данные покидают ЕЭЗ или Великобританию, мы полагаемся на гарантии этих провайдеров, например на Стандартные договорные условия Европейской комиссии.</p>'''))
ru.append(("retention", "Сколько мы храним данные", '''
<div class="table-scroll"><table class="data-table">
<thead><tr><th>Данные</th><th>Срок</th></tr></thead>
<tbody>
<tr><td>Карты и чаты на устройстве</td><td data-h="Срок">Пока вы их не удалите, не удалите аккаунт или приложение</td></tr>
<tr><td>Синхронизированные карты, презентации и картинки</td><td data-h="Срок">Пока существует аккаунт. От удалённых остаётся лишь небольшая отметка, чтобы они удалились и на других устройствах</td></tr>
<tr><td>Совместные карты</td><td data-h="Срок">Пока владелец не закроет доступ или не удалит аккаунт; у приглашённых остаются свои копии</td></tr>
<tr><td>Аккаунт, тариф и использование</td><td data-h="Срок">Пока существует аккаунт; использование считается по календарным месяцам</td></tr>
<tr><td>Содержимое запросов к ИИ</td><td data-h="Срок">Не хранится после ответа; технические журналы удаляются в течение 7 дней</td></tr>
<tr><td>Изображения карт по ссылке</td><td data-h="Срок">Пока вы не закроете доступ, не удалите карту или аккаунт</td></tr>
<tr><td>После удаления аккаунта</td><td data-h="Срок">Без связи с вами: записи о подписках (для продлений и возвратов App Store) и месячные счётчики, привязанные к идентификатору устройства</td></tr>
</tbody></table></div>'''))
ru.append(("controls", "Ваши настройки и права", f'''
<p>Всё это — в настройках приложения:</p>
<div class="ctl-grid">
<div class="ctl">{icon("shield")}<div><h4>Передача данных ИИ</h4><p>Разрешить или прекратить отправку содержимого провайдерам ИИ.</p><span class="path">Настройки → Передача данных ИИ</span></div></div>
<div class="ctl">{icon("chat")}<div><h4>Помощник видит мои карты</h4><p>Разрешить помощнику видеть список ваших карт.</p><span class="path">Настройки → Помощник видит мои карты</span></div></div>
<div class="ctl">{icon("sync")}<div><h4>Синхронизация карт</h4><p>Карты на всех ваших устройствах — или только на этом.</p><span class="path">Настройки → Синхронизация карт</span></div></div>
<div class="ctl">{icon("bell")}<div><h4>Напоминания о задачах</h4><p>Уведомления о задачах со сроком.</p><span class="path">Настройки → Напоминания о задачах</span></div></div>
<div class="ctl">{icon("calendar")}<div><h4>Задачи в Календаре</h4><p>Показывать задачи со сроком в календаре «Minor AI».</p><span class="path">Настройки → Задачи в Календаре</span></div></div>
<div class="ctl">{icon("user")}<div><h4>Редактировать вместе</h4><p>Закрыть доступ к карте или выйти из чужой.</p><span class="path">Меню карты → Редактировать вместе</span></div></div>
<div class="ctl">{icon("trash")}<div><h4>Удалить аккаунт</h4><p>Удаляет аккаунт, счётчики, синхронизированные карты, презентации и картинки, карты, которыми вы делитесь, изображения по ссылкам и всё на устройстве. Отзывает вход с Apple.</p><span class="path">Настройки → Удалить аккаунт</span></div></div>
<div class="ctl">{icon("card")}<div><h4>Подписки</h4><p>Удаление аккаунта не отменяет подписку — управляйте ею в Apple.</p><span class="path">Настройки iPhone → Apple ID → Подписки</span></div></div>
</div>
<p>В зависимости от места проживания (например, ЕС, ЕЭЗ, Великобритания или Калифорния) вы можете запросить доступ к своим данным, их исправление, удаление или выгрузку, возразить против обработки или ограничить её и отозвать согласие. Напишите на {MAIL} — мы ответим в течение 30 дней. Вы также можете подать жалобу в местный орган по защите данных.</p>'''))
ru.append(("children", "Дети", '''
<p>Minor не предназначено для детей младше 13 лет (или минимального возраста в вашей стране), и мы сознательно не собираем их данные. Если вы считаете, что ребёнок передал нам данные, напишите нам — мы их удалим.</p>'''))
ru.append(("security", "Безопасность", '''
<p>Данные шифруются при передаче (HTTPS). Сессия входа хранится в Связке ключей iOS. Синхронизированные карты защищены построчными правами доступа — читать их может только ваш аккаунт. Ключи провайдеров ИИ есть только на нашем сервере. Абсолютно защищённых систем не бывает, но мы работаем над защитой данных и сообщим вам об утечке, если этого требует закон.</p>'''))
ru.append(("website", "Этот сайт", '''
<p>minorai.site не использует cookies, аналитику и трекеры. Сайт запоминает только выбранный язык — в локальном хранилище браузера.</p>'''))
ru.append(("changes", "Изменения и контакты", f'''
<p>Изменения мы публикуем на этой странице и обновляем дату вверху. О существенных изменениях мы также сообщим в приложении.</p>
<div class="contact-card"><div><h2>Вопросы о ваших данных?</h2><p>Regina Danilova · {MAIL}</p></div><a class="btn btn-primary" href="mailto:support@minorai.site">Написать нам</a></div>'''))

def article(lang):
    t = T[lang]
    secs = t["sections"]
    toc = "".join(f'<li><a href="#{lang}-{sid}">{title}</a></li>' for sid, title, _ in secs)
    glance = "".join(f'<div class="card" style="--accent:{c}22">{icon(ic, c)}<h3>{h}</h3><p>{p}</p></div>' for ic, c, h, p in t["glance"])
    body = ""
    for n, (sid, title, html) in enumerate(secs, 1):
        body += f'''
      <section class="pp-section" id="{lang}-{sid}">
        <div class="pp-head"><span class="num">{n:02d}</span><h2>{title}</h2></div>{html}
      </section>'''
    return f'''
  <div data-l="{lang}">
    <div class="pp-hero">
      <div class="wrap">
        <span class="eyebrow"><span class="dot"></span>{t["eyebrow"]}</span>
        <h1>{t["h1"]}</h1>
        <p class="lead">{t["lead"]}</p>
        <div class="pp-meta">
          <span class="pp-chip">{svg("calendar")}{t["updated"]}</span>
          <span class="pp-chip">{svg("clock")}{t["read"]}</span>
          <span class="pp-chip">{svg("user")}{t["owner"]}</span>
        </div>
        <div class="pp-glance">{glance}</div>
        <details class="pp-toc-mobile"><summary>{t["contents"]}</summary><ol>{toc}</ol></details>
      </div>
    </div>
    <div class="wrap pp-layout">
      <aside class="pp-side" data-l="{lang}" aria-label="{t["contents"]}">
        <p class="label">{t["contents"]}</p>
        <ol>{toc}</ol>
        <div class="side-contact">{t["contact_q"]}<br>{MAIL}</div>
      </aside>
      <article>{body}
      </article>
    </div>
  </div>'''

def build():
    h = head(T["en"]["title"], T["ru"]["title"],
             "How Minor AI collects, uses and protects your data: what stays on your iPhone, what goes to our server and AI providers, and how to switch it off.",
             "/privacy/", og=False)
    body = f'''  <main id="main">{article("en")}{article("ru")}
  </main>
  <a class="to-top" href="#" aria-label="Back to top">{svg("up")}</a>'''
    return page(h, body, active="privacy", before_header='\n  <div class="read-progress" aria-hidden="true"></div>')
