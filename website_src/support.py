# The support page: search, four topics, common situations, answers as short steps with a small
# picture of the place in the app, and a contact block that fills in the subject.
from urllib.parse import quote
from common import svg, icon, both as b, head, page, EMAIL

# ---------- Small pictures of the app (HTML, so they follow the language switch) ----------

def tap(hl):
    return '<i class="tap" aria-hidden="true"></i>' if hl else ""


def fig(content, cap_en, cap_ru, cls=""):
    return (f'<figure class="ui {cls}"><div class="ui-screen" aria-hidden="true">{content}</div>'
            f'<figcaption>{b(cap_en, cap_ru)}</figcaption></figure>')


def toggle(on=True):
    return f'<span class="ui-toggle{" on" if on else ""}"></span>'


def settings_rows(group_en, group_ru, rows):
    """rows: (icon, en, ru, value_en, value_ru, kind, highlighted); kind: chev | on | off | danger | none"""
    out = (f'<div class="ui-label">{b(group_en, group_ru)}</div>' if group_en else "") + '<div class="ui-group">'
    for ic, en, ru, ven, vru, kind, hl in rows:
        cls = "ui-row" + (" hl" if hl else "") + (" danger" if kind == "danger" else "")
        value = f'<span class="v">{b(ven, vru)}</span>' if ven else ""
        end = svg("chevron", "chev") if kind == "chev" else toggle(kind == "on") if kind in ("on", "off") else ""
        out += f'<div class="{cls}">{svg(ic)}<span class="l">{b(en, ru)}</span>{value}{end}{tap(hl)}</div>'
    return out + "</div>"


def ui_settings(group_en, group_ru, rows, cap_en, cap_ru):
    content = f'<div class="ui-title">{b("Settings", "Настройки")}</div>' + settings_rows(group_en, group_ru, rows)
    return fig(content, cap_en, cap_ru)


def ui_create():
    content = f'''<div class="ui-h">{b("Start a Map", "Новая карта")}</div>
<div class="ui-tiles"><div class="t sel">{svg("text")}{b("Topic", "Тема")}</div><div class="t">{svg("doc")}{b("Document", "Документ")}</div></div>
<div class="ui-usage hl"><div class="u-top"><b>{b("Free Maps", "Бесплатные карты")}</b><b>{b("3 of 3 this month", "3 из 3 в этом месяце")}</b></div><i class="u-bar"></i><small>{b("Resets on the 1st. Minor Plus removes the limit.", "Обновится 1-го числа. С Minor Plus лимит намного выше.")}</small>{tap(True)}</div>
<div class="ui-btn light">{b("Get Minor Plus", "Оформить Minor Plus")}</div>'''
    return fig(content, "Start a Map → Free Maps", "Новая карта → Бесплатные карты")


def ui_signin():
    content = f'''<div class="ui-seg"><span class="on">{b("Sign In", "Войти")}</span><span>{b("Create Account", "Создать аккаунт")}</span></div>
<div class="ui-field">{b("Email", "Почта")}</div><div class="ui-field">{b("Password", "Пароль")}</div>
<div class="ui-btn mint">{b("Sign In", "Войти")}</div>
<div class="ui-link hl">{b("Forgot password?", "Забыли пароль?")}{tap(True)}</div>
<div class="ui-or"><i></i>{b("or", "или")}<i></i></div>
<div class="ui-btn light apple"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M16.4 12.6c0-2.3 1.9-3.4 2-3.5-1.1-1.6-2.8-1.8-3.4-1.8-1.4-.1-2.8.9-3.5.9s-1.9-.9-3.1-.8C6.8 7.4 5.3 8.3 4.5 9.8c-1.7 2.9-.4 7.2 1.2 9.5.8 1.1 1.7 2.4 2.9 2.3 1.2 0 1.6-.7 3-.7s1.8.7 3.1.7c1.3 0 2.1-1.1 2.8-2.3.9-1.3 1.3-2.6 1.3-2.6s-2.4-.9-2.4-4.1zM14.1 5.8c.6-.8 1.1-1.9 1-3-.9 0-2.1.6-2.7 1.4-.6.7-1.1 1.8-1 2.9 1 .1 2.1-.5 2.7-1.3z"/></svg>{b("Continue with Apple", "Продолжить с Apple")}</div>'''
    return fig(content, "Sign-in screen → Forgot password?", "Экран входа → Забыли пароль?")


def ui_map_menu():
    items = [("text", "Rename", "Переименовать", False), ("cards", "Study", "Учёба", False),
             ("slides", "Create Presentation", "Создать презентацию", False), ("people", "Edit Together", "Редактировать вместе", True),
             ("clock", "Version History", "История версий", False)]
    menu = "".join(f'<div class="mi{" hl" if hl else ""}">{svg(ic)}{b(en, ru)}{tap(hl)}</div>' for ic, en, ru, hl in items)
    content = f'''<div class="ui-maptop">{svg("home")}<b>{b("Launch plan", "План запуска")}</b><span class="dots">{svg("dots")}</span></div>
<div class="ui-menu">{menu}</div>'''
    return fig(content, "Map → ••• → Edit Together", "Карта → ••• → Редактировать вместе")


def ui_sidebar():
    rows = [("Launch plan", "План запуска", "Today", "Сегодня"), ("Biology exam", "Экзамен по биологии", "Yesterday", "Вчера")]
    lst = "".join(f'<div class="li"><i class="thumb"></i><span>{b(en, ru)}<small>{b(den, dru)}</small></span></div>' for en, ru, den, dru in rows)
    content = f'''<div class="ui-seg three"><span>{b("Maps", "Карты")}</span><span class="on hl">{b("Slides", "Слайды")}{tap(True)}</span><span>{b("Chats", "Чаты")}</span></div>
<div class="ui-newdeck">+ {b("New Presentation", "Новая презентация")}</div>
<div class="ui-list">{lst}</div>
<div class="ui-gear">{svg("gear")}</div>'''
    return fig(content, "Menu ☰ → Slides", "Меню ☰ → Слайды")


def ui_chat():
    content = f'''<div class="ui-chattop">{svg("menu")}<span class="model">GPT-6 Luna ⌄</span><span class="wave hl">{svg("wave")}{tap(True)}</span></div>
<div class="ui-bubble">{b("Plan my week around the exam", "Спланируй неделю перед экзаменом")}</div>
<div class="ui-composer"><span class="ph">{b("Ask me anything", "Спросите что угодно")}</span>
<div class="row"><i class="c">+</i><i class="m">{b("Media", "Медиа")}</i><i class="c mic hl">{svg("mic")}</i><i class="send">{svg("up")}</i></div></div>'''
    return fig(content, "Chat → waveform: Voice Mode · microphone: dictation", "Чат → волна: голосовой режим · микрофон: диктовка")


def ui_ios_settings():
    content = f'''<div class="ui-title ios">Minor AI</div>
<div class="ui-label">{b("Allow Minor AI to access", "Разрешить Minor AI доступ")}</div>
<div class="ui-group">
<div class="ui-row hl">{svg("mic")}<span class="l">{b("Microphone", "Микрофон")}</span>{toggle(True)}{tap(True)}</div>
<div class="ui-row hl">{svg("wave")}<span class="l">{b("Speech Recognition", "Распознавание речи")}</span>{toggle(True)}</div>
<div class="ui-row">{svg("bell")}<span class="l">{b("Notifications", "Уведомления")}</span>{svg("chevron", "chev")}</div>
</div>'''
    return fig(content, "iPhone Settings → Minor AI", "Настройки iPhone → Minor AI")


# ---------- Answers ----------

def steps(*items):
    return '<ol class="steps">' + "".join(f"<li>{b(en, ru)}</li>" for en, ru in items) + "</ol>"


def para(en, ru):
    return f"<p>{b(en, ru)}</p>"


S = lambda en, ru: f"<strong>{b(en, ru)}</strong>"  # an exact name in the app

CATS = [
    ("maps", "map", "#2fff9e", "Maps & sources", "Карты и источники", "Creating and editing maps, documents, sync, editing together", "Создание и правка карт, документы, синхронизация, совместная работа"),
    ("ai", "spark", "#c9a2ff", "AI & limits", "ИИ и лимиты", "Models, the monthly allowance, images, presentations, voice", "Модели, месячный лимит, картинки, презентации, голос"),
    ("billing", "card", "#ffd66b", "Subscription & purchases", "Подписка и покупки", "Plus and PRO, cancelling, refunds, restoring a purchase", "Plus и PRO, отмена, возврат, восстановление покупки"),
    ("account", "user", "#7cc4ff", "Account & data", "Аккаунт и данные", "Signing in, password, deleting your data, language", "Вход, пароль, удаление данных, язык"),
]

SETTINGS_PATH = ("Menu ☰ → ⚙ Settings", "Меню ☰ → ⚙ Настройки")

FAQ = []
def faq(cat, id, q_en, q_ru, body, figure=""):
    FAQ.append(dict(cat=cat, id=id, q_en=q_en, q_ru=q_ru, body=body, figure=figure))


# Maps & sources
faq("maps", "map-wont-build", "A map won’t build", "Карта не создаётся", steps(
    ("Check the internet connection and try again.", "Проверьте интернет и попробуйте ещё раз."),
    (f"Make sure you’re signed in — AI features work through an account: {S('Menu ☰ → ⚙ Settings → Account', 'Меню ☰ → ⚙ Настройки → Аккаунт')}.",
     f"Проверьте, что вы вошли в аккаунт — функции ИИ работают через него: {S('Меню ☰ → ⚙ Настройки → Аккаунт', 'Меню ☰ → ⚙ Настройки → Аккаунт')}."),
    (f"Look at {S('Free Maps', 'Бесплатные карты')} on the Start a Map screen. “3 of 3” means this month’s free maps are used: they come back on the 1st, or get Minor Plus.",
     f"Посмотрите на полосу {S('Free Maps', 'Бесплатные карты')} на экране «Новая карта». «3 из 3» — бесплатные карты этого месяца закончились: они вернутся 1-го числа, или оформите Minor Plus."),
    (f"Check that AI is allowed: {S('Settings → AI Data Sharing', 'Настройки → Передача данных ИИ')} should say Allowed.",
     f"Проверьте, что ИИ разрешён: в {S('Settings → AI Data Sharing', 'Настройки → Передача данных ИИ')} должно быть «Разрешено»."),
    ("Building from a document or a link? See “A document or link can’t be read” below.", "Карта из документа или ссылки? Смотрите «Не читается документ или ссылка» ниже."),
), ui_create())

faq("maps", "make-map", "How do I make a map?", "Как создать карту?", steps(
    (f"On the home screen tap the globe at the bottom — {S('Start a Map', 'Новая карта')} opens.", f"На главном экране нажмите на глобус внизу — откроется {S('Start a Map', 'Новая карта')}."),
    ("Pick a source — Topic, Document, Link, YouTube, Voice, Scan or From Chat — or just type a topic.", "Выберите источник — Тема, Документ, Ссылка, YouTube, Голос, Скан или Из чата — или просто напишите тему."),
    ("Tap the arrow. A map is usually ready in 10–20 seconds. You can leave the screen — Minor tells you when it’s ready.", "Нажмите стрелку. Обычно карта готова за 10–20 секунд. Экран можно закрыть — Minor сообщит, когда карта будет готова."),
))

faq("maps", "edit-map", "How do I edit a map?", "Как редактировать карту?", steps(
    ("Tap an idea to select it.", "Нажмите на идею, чтобы выбрать её."),
    (f"Use the bar below it: {S('Expand', 'Развить')} (AI adds ideas), {S('Ask', 'Спросить')}, {S('Edit', 'Изменить')}, {S('Style', 'Стиль')}.",
     f"Используйте панель снизу: {S('Expand', 'Развить')} (ИИ добавит идеи), {S('Ask', 'Спросить')}, {S('Edit', 'Изменить')}, {S('Style', 'Стиль')}."),
    ("To move an idea, press and hold it, then drag it onto another one.", "Чтобы переместить идею, нажмите и удерживайте её, затем перетащите на другую."),
    ("Or type a command in the field at the bottom, for example “Add three examples to Pricing”. Undo is in the top bar.", "Или напишите команду в поле внизу, например «Добавь три примера к ценам». Отмена — в верхней панели."),
))

faq("maps", "doc-link", "A document or link can’t be read", "Не читается документ или ссылка", steps(
    ("Use a PDF, TXT or RTF file with selectable text. A scanned PDF has no text — use Scan to photograph the pages instead.", "Используйте PDF, TXT или RTF с выделяемым текстом. В отсканированном PDF текста нет — сфотографируйте страницы через «Скан»."),
    ("Free reads documents up to 10 pages, Plus and PRO up to 300. Very long documents are mapped from the beginning.", "Бесплатно читаются документы до 10 страниц, в Plus и PRO — до 300. Очень длинные документы обрабатываются с начала."),
    ("Some websites block reading. Copy the text and paste it into the topic field.", "Некоторые сайты запрещают чтение. Скопируйте текст и вставьте его в поле темы."),
))

faq("maps", "sync", "Where are my maps? Do they sync?", "Где мои карты? Синхронизируются ли они?", steps(
    ("When you’re signed in, maps, presentations and their pictures sync between your devices and come back on a new iPhone.", "Когда вы вошли в аккаунт, карты, презентации и их картинки синхронизируются между устройствами и вернутся на новом iPhone."),
    (f"To switch it off: {S('Settings → Sync Maps', 'Настройки → Синхронизация карт')}. Chats always stay on the iPhone.", f"Выключить: {S('Settings → Sync Maps', 'Настройки → Синхронизация карт')}. Чаты всегда хранятся на iPhone."),
    (f"Every map keeps its earlier versions: {S('••• → Version History', '••• → История версий')}.", f"У каждой карты есть прежние версии: {S('••• → Version History', '••• → История версий')}."),
    ("For a copy outside Minor, use Export: PDF, image, Markdown, or Xmind and MindNode with PRO.", "Для копии вне Minor используйте экспорт: PDF, картинка, Markdown, а с PRO — Xmind и MindNode."),
), ui_settings("General", "Основные", [
    ("globe", "Language", "Язык", "System", "Как в системе", "chev", False),
    ("sync", "Sync Maps", "Синхронизация карт", "", "", "on", True),
    ("bell", "Task Reminders", "Напоминания о задачах", "", "", "on", False),
], "Settings → Sync Maps", "Настройки → Синхронизация карт"))

faq("maps", "together", "How do I edit a map together with someone?", "Как редактировать карту вместе с кем-то?", steps(
    (f"Open the map → {S('••• → Edit Together', '••• → Редактировать вместе')}.", f"Откройте карту → {S('••• → Edit Together', '••• → Редактировать вместе')}."),
    (f"Choose {S('Editor', 'Редактор')} (changes the map) or {S('Viewer', 'Наблюдатель')} (only sees it), then send the invite link.", f"Выберите {S('Editor', 'Редактор')} (меняет карту) или {S('Viewer', 'Наблюдатель')} (только смотрит) и отправьте ссылку-приглашение."),
    ("The other person opens the link and signs in. Changes show up for everyone within seconds.", "Человек открывает ссылку и входит в аккаунт. Изменения видны всем за несколько секунд."),
    (f"Under {S('People', 'Участники')} you change roles or remove someone (old links then stop working). Inviting needs Minor Plus (up to 5 people per map) or PRO (up to 25); joining is free.", f"В разделе {S('People', 'Участники')} можно менять роли и убирать людей (старые ссылки при этом перестают работать). Приглашать можно с Minor Plus (до 5 человек в карте) или PRO (до 25), присоединиться — бесплатно."),
), ui_map_menu())

faq("maps", "voice-input", "Voice input doesn’t work", "Не работает голосовой ввод", steps(
    (f"Open {S('iPhone Settings → Minor AI', 'Настройки iPhone → Minor AI')} and allow Microphone and Speech Recognition.", f"Откройте {S('iPhone Settings → Minor AI', 'Настройки iPhone → Minor AI')} и разрешите Микрофон и Распознавание речи."),
    ("Make sure no other app is using the microphone, for example a call.", "Проверьте, что микрофон не занят другим приложением, например звонком."),
    ("A voice note for a map can be up to 5 minutes. Voice maps are part of Minor Plus.", "Голосовая заметка для карты — до 5 минут. Карты из голоса доступны в Minor Plus."),
), ui_ios_settings())

# AI & limits
faq("ai", "models", "Which AI models can I use?", "Какие модели ИИ доступны?", para(
    "In chat, every plan can use every model: GPT-6 Luna, GPT-6.1 Sol, GPT-6 Astra, Claude Haiku 4.5, Claude Sonnet 5.5, Claude Opus 5.5 and Claude Fable 5.1. For building maps, standard models are available to everyone, Claude Opus 5.5 with Plus, and GPT-6 Astra and Claude Fable 5.1 with PRO.",
    "В чате в любом тарифе доступны все модели: GPT-6 Luna, GPT-6.1 Sol, GPT-6 Astra, Claude Haiku 4.5, Claude Sonnet 5.5, Claude Opus 5.5 и Claude Fable 5.1. Для построения карт стандартные модели доступны всем, Claude Opus 5.5 — с Plus, GPT-6 Astra и Claude Fable 5.1 — с PRO."))

faq("ai", "allowance", "What is the monthly AI allowance?", "Что такое месячный лимит ИИ?", steps(
    ("Each plan includes a monthly AI allowance. Every request uses part of it, depending on the model and the amount of text.", "В каждый тариф входит месячный лимит ИИ. Каждый запрос расходует его часть — в зависимости от модели и объёма текста."),
    ("The number next to a model (for example ×20) shows how much faster it uses the allowance than the lightest model.", "Число рядом с моделью (например, ×20) показывает, во сколько раз быстрее она расходует лимит, чем самая лёгкая."),
    ("Plus has 20× and PRO 40× the free allowance. Allowances and monthly counts renew on the 1st of each month (UTC).", "В Plus лимит в 20 раз больше бесплатного, в PRO — в 40 раз. Лимиты и счётчики обновляются 1-го числа каждого месяца (UTC)."),
))

faq("ai", "ai-data", "What is sent to AI providers?", "Что передаётся провайдерам ИИ?", para(
    f"Only the content of your request — a topic, document text, chat messages or the part of a map an action needs — goes to OpenAI or Anthropic to create the answer. Your name and email are not sent, and providers don’t train models on API data. You can switch this off in {S('Settings → AI Data Sharing', 'Настройки → Передача данных ИИ')} and {S('Assistant Sees My Maps', 'Помощник видит мои карты')}. Details are in the <a href=\"/privacy/\">Privacy Policy</a>.",
    f"Только содержимое запроса — тема, текст документа, сообщения чата или часть карты, нужная для действия, — уходит в OpenAI или Anthropic, чтобы получить ответ. Имя и почта не передаются, а провайдеры не обучают модели на данных из API. Отключить можно в {S('Settings → AI Data Sharing', 'Настройки → Передача данных ИИ')} и {S('Assistant Sees My Maps', 'Помощник видит мои карты')}. Подробнее — в <a href=\"/privacy/\">Политике конфиденциальности</a>."))

faq("ai", "images", "How do I create images?", "Как создавать картинки?", steps(
    ("In chat, just ask: “Draw a cozy reading corner” — or tap the brush and describe the picture.", "В чате просто попросите: «Нарисуй уютный уголок для чтения» — или нажмите кисточку и опишите картинку."),
    (f"On a map, select an idea → {S('••• → Create Image with AI', '••• → Создать картинку с ИИ')}, or add your own photo.", f"На карте выберите идею → {S('••• → Create Image with AI', '••• → Создать картинку с ИИ')} или добавьте своё фото."),
    (f"Free includes 3 images a month, Plus 60 and PRO 150 in high quality. If an image is inappropriate, open it and tap {S('Report', 'Пожаловаться')}.",
     f"Бесплатно — 3 картинки в месяц, в Plus — 60, в PRO — 150 в высоком качестве. Если картинка неуместна, откройте её и нажмите {S('Report', 'Пожаловаться')}."),
))

faq("ai", "presentations", "How do I make a presentation?", "Как сделать презентацию?", steps(
    (f"{S('Menu ☰ → Slides → New Presentation', 'Меню ☰ → Слайды → Новая презентация')}, or in a map {S('••• → Create Presentation', '••• → Создать презентацию')}.",
     f"{S('Menu ☰ → Slides → New Presentation', 'Меню ☰ → Слайды → Новая презентация')} или в карте {S('••• → Create Presentation', '••• → Создать презентацию')}."),
    ("Pick a map, a topic or a chat. AI writes the slides and speaker notes in about half a minute.", "Выберите карту, тему или чат. ИИ напишет слайды и заметки докладчика примерно за полминуты."),
    ("Tap a slide to edit it, change its layout, rewrite it with AI or add a picture. Elements adds text, shapes and icons anywhere; with Plus also photos, tables, charts, QR codes, your own style and brand, animations and the AI designer.", "Нажмите на слайд, чтобы изменить его, сменить макет, переписать с ИИ или добавить картинку. «Элементы» добавляют текст, фигуры и иконки в любом месте; с Plus — ещё фото, таблицы, диаграммы, QR-коды, свой стиль и бренд, анимации и ИИ-дизайнер."),
    ("Present with ▶ — on a TV via AirPlay your notes stay on the phone. Export to PDF; PowerPoint export (with animations) is part of Plus.", "Показывайте кнопкой ▶ — на ТВ через AirPlay заметки остаются на телефоне. Экспорт в PDF; экспорт в PowerPoint (с анимациями) — в Plus."),
), ui_sidebar())

faq("ai", "voice-mode", "Can I talk to the assistant?", "Можно ли говорить с помощником голосом?", steps(
    ("Tap the microphone in the message field to dictate. The text appears in the field, and you send it yourself.", "Нажмите микрофон в поле сообщения, чтобы надиктовать. Текст появится в поле, а отправите вы его сами."),
    ("For a conversation, tap the green waveform button at the top of the chat: speak, pause, and the answer is read aloud.", "Для разговора нажмите зелёную кнопку с волной вверху чата: говорите, сделайте паузу — и ответ прочитается вслух."),
    (f"Long-press any answer → {S('Read Aloud', 'Прочитать вслух')}.", f"Долгое нажатие на любой ответ → {S('Read Aloud', 'Прочитать вслух')}."),
), ui_chat())

# Subscription & purchases
faq("billing", "purchase-missing", "My purchase didn’t show up", "Покупка не появилась", steps(
    ("Sign in to the same Minor account you used before.", "Войдите в тот же аккаунт Minor, что и раньше."),
    (f"Open {S('Menu ☰ → ⚙ Settings → Restore Purchases', 'Меню ☰ → ⚙ Настройки → Восстановить покупки')}. The same button is at the bottom of the subscription screen.",
     f"Откройте {S('Menu ☰ → ⚙ Settings → Restore Purchases', 'Меню ☰ → ⚙ Настройки → Восстановить покупки')}. Такая же кнопка есть внизу экрана подписки."),
    ("Make sure the iPhone uses the same Apple ID that made the purchase.", "Проверьте, что на iPhone тот же Apple ID, с которого была покупка."),
    ("Still on the free plan? Write to us with the date of purchase. Never send card details.", "Всё ещё бесплатный тариф? Напишите нам и укажите дату покупки. Данные карты присылать не нужно."),
), ui_settings("Account", "Аккаунт", [
    ("user", "Account", "Аккаунт", "you@icloud.com", "you@icloud.com", "none", False),
    ("star", "Subscription", "Подписка", "Free", "Бесплатно", "chev", False),
    ("restore", "Restore Purchases", "Восстановить покупки", "", "", "chev", True),
], "Settings → Restore Purchases", "Настройки → Восстановить покупки"))

faq("billing", "plans", "What do Plus and PRO include?", "Что входит в Plus и PRO?", para(
    "<strong>Plus</strong>: up to 300 maps and 20 presentations a month, YouTube and voice maps, documents up to 300 pages, inviting up to 5 people to a map, presentation design (own styles, brand, charts, animations, AI designer, PowerPoint export), Claude Opus 5.5 for maps and 20× the free AI allowance. <strong>PRO</strong>: everything in Plus, up to 600 maps and 60 presentations, GPT-6 Astra and Claude Fable 5.1 for maps, 40× the free AI allowance, Xmind and MindNode export, and share links.",
    "<strong>Plus</strong>: до 300 карт и 20 презентаций в месяц, карты из YouTube и голоса, документы до 300 страниц, до 5 приглашённых в каждую карту, дизайн презентаций (свои стили, бренд, диаграммы, анимации, ИИ-дизайнер, экспорт в PowerPoint), Claude Opus 5.5 для карт и лимит ИИ в 20 раз больше бесплатного. <strong>PRO</strong>: всё из Plus, до 600 карт и 60 презентаций, GPT-6 Astra и Claude Fable 5.1 для карт, лимит ИИ в 40 раз больше бесплатного, экспорт в Xmind и MindNode и ссылки на карты."))

faq("billing", "cancel", "How do I cancel or change my subscription?", "Как отменить или изменить подписку?", steps(
    (f"On the iPhone open {S('Settings → [your name] → Subscriptions → Minor AI', 'Настройки → [ваше имя] → Подписки → Minor AI')}, or in Minor {S('Settings → Subscription', 'Настройки → Подписка')}.",
     f"На iPhone откройте {S('Settings → [your name] → Subscriptions → Minor AI', 'Настройки → [ваше имя] → Подписки → Minor AI')} или в Minor {S('Settings → Subscription', 'Настройки → Подписка')}."),
    ("Cancel at least 24 hours before the period ends to avoid the next charge.", "Отмените минимум за 24 часа до конца периода, чтобы не было следующего списания."),
    ("Your plan stays until the end of the paid period.", "Тариф сохранится до конца оплаченного периода."),
) + para('<a href="https://apps.apple.com/account/subscriptions">Open subscriptions →</a>', '<a href="https://apps.apple.com/account/subscriptions">Открыть подписки →</a>'))

faq("billing", "refund", "How do I get a refund?", "Как вернуть деньги?", para(
    "Payments are processed by Apple, so refunds are requested from Apple at <a href=\"https://reportaproblem.apple.com\">reportaproblem.apple.com</a>. We can’t issue refunds ourselves.",
    "Платежи обрабатывает Apple, поэтому возврат запрашивается у Apple на <a href=\"https://reportaproblem.apple.com\">reportaproblem.apple.com</a>. Сами мы оформить возврат не можем."))

# Account & data
faq("account", "cant-sign-in", "I can’t sign in", "Не получается войти", steps(
    ("Check the email address for typos.", "Проверьте, нет ли опечатки в почте."),
    (f"Forgot the password? Tap {S('Forgot password?', 'Забыли пароль?')} and set a new one with the 6-digit code from the email.",
     f"Забыли пароль? Нажмите {S('Forgot password?', 'Забыли пароль?')} и задайте новый с помощью 6-значного кода из письма."),
    (f"No email? Check Spam, wait a minute and tap {S('Send the code again', 'Отправить код ещё раз')}.", f"Письма нет? Проверьте «Спам», подождите минуту и нажмите {S('Send the code again', 'Отправить код ещё раз')}."),
    (f"Signed up with Apple? Use {S('Continue with Apple', 'Продолжить с Apple')} with the same Apple ID.", f"Регистрировались через Apple? Нажмите {S('Continue with Apple', 'Продолжить с Apple')} с тем же Apple ID."),
), ui_signin())

faq("account", "why-account", "Why do I need an account?", "Зачем нужен аккаунт?", para(
    "AI features use an account so your plan and monthly limits work on all your devices, and your maps can sync. Sign in with email and password or with Apple. You can open the app and look around without one.",
    "Функции ИИ работают через аккаунт, чтобы тариф и месячные лимиты действовали на всех ваших устройствах, а карты синхронизировались. Войти можно по почте и паролю или через Apple. Открыть приложение и осмотреться можно и без аккаунта."))

faq("account", "delete", "How do I delete my account?", "Как удалить аккаунт?", steps(
    ("First cancel your App Store subscription — deleting the account doesn’t cancel it.", "Сначала отмените подписку App Store — удаление аккаунта её не отменяет."),
    (f"Open {S('Menu ☰ → ⚙ Settings → Delete Account', 'Меню ☰ → ⚙ Настройки → Удалить аккаунт')} at the very bottom.", f"Откройте {S('Menu ☰ → ⚙ Settings → Delete Account', 'Меню ☰ → ⚙ Настройки → Удалить аккаунт')} в самом низу."),
    ("Your account, synced maps, presentations, pictures and usage records are deleted, and maps and chats on this iPhone are erased.", "Будут удалены аккаунт, синхронизированные карты, презентации, картинки и счётчики использования, а карты и чаты на этом iPhone — стёрты."),
) + para(f"You can also ask us to delete your data: <a href=\"mailto:{EMAIL}\">{EMAIL}</a>.", f"Можно также попросить удалить данные: <a href=\"mailto:{EMAIL}\">{EMAIL}</a>."),
ui_settings("", "", [
    ("logout", "Log Out", "Выйти", "", "", "none", False),
    ("trash", "Delete Account", "Удалить аккаунт", "", "", "danger", True),
], "Settings → Delete Account", "Настройки → Удалить аккаунт"))

faq("account", "language", "How do I change the language?", "Как сменить язык?", steps(
    (f"Open {S('Menu ☰ → ⚙ Settings → Language', 'Меню ☰ → ⚙ Настройки → Язык')}.", f"Откройте {S('Menu ☰ → ⚙ Settings → Language', 'Меню ☰ → ⚙ Настройки → Язык')}."),
    ("Choose English, Русский or System.", "Выберите English, Русский или «Как в системе»."),
))


FEATURED = [
    ("map-wont-build", "map", "#2fff9e", "A map won’t build", "Карта не создаётся", "Limits, sign-in, documents", "Лимит, вход, документы"),
    ("purchase-missing", "card", "#ffd66b", "My purchase didn’t show up", "Покупка не появилась", "Restore it in two taps", "Восстановите в два касания"),
    ("cant-sign-in", "lock", "#7cc4ff", "I can’t sign in", "Не получается войти", "Password, code, Apple", "Пароль, код, Apple"),
]

TOPICS = [("map", "A map", "Карта"), ("ai", "AI & limits", "ИИ и лимиты"), ("billing", "A purchase", "Покупка"),
          ("account", "Account", "Аккаунт"), ("other", "Something else", "Другое")]


def mailto(subject):
    return f"mailto:{EMAIL}?subject={quote(subject)}"


def faq_html(item):
    fig_html = item["figure"]
    grid = f'<div class="answer-grid{" has-fig" if fig_html else ""}"><div class="answer-text">{item["body"]}</div>{fig_html}</div>'
    foot = (f'<div class="answer-foot">'
            f'<a data-l="en" href="{mailto("Minor AI — " + item["q_en"])}">{svg("mail")}Didn’t help? Write to us</a>'
            f'<a data-l="ru" href="{mailto("Minor AI — " + item["q_ru"])}">{svg("mail")}Не помогло? Напишите нам</a></div>')
    return f'''
          <details class="faq" id="{item["id"]}" data-cat="{item["cat"]}">
            <summary>{b(item["q_en"], item["q_ru"])}</summary>
            <div class="answer">{grid}{foot}</div>
          </details>'''


def build():
    counts = {c[0]: sum(1 for f in FAQ if f["cat"] == c[0]) for c in CATS}
    entries = "".join(f'''
          <a class="entry" href="#{cid}" style="--c:{color}">{icon(ic, color)}<span class="entry-t">{b(en, ru)}</span><span class="entry-d">{b(den, dru)}</span><span class="entry-n">{b(f"{counts[cid]} answers", f"Ответов: {counts[cid]}")}</span></a>'''
        for cid, ic, color, en, ru, den, dru in CATS)
    featured = "".join(f'''
          <a class="situation" href="#{fid}" style="--c:{color}">{icon(ic, color)}<span><b>{b(en, ru)}</b><small>{b(den, dru)}</small></span>{svg("arrow", "go")}</a>'''
        for fid, ic, color, en, ru, den, dru in FEATURED)
    sections = ""
    for cid, ic, color, en, ru, den, dru in CATS:
        items = "".join(faq_html(f) for f in FAQ if f["cat"] == cid)
        sections += f'''
        <section class="help-sec" id="{cid}" style="--c:{color}">
          <div class="help-head">{icon(ic, color)}<div><h2>{b(en, ru)}</h2><p>{b(den, dru)}</p></div></div>{items}
        </section>'''
    chips = "".join(f'<button type="button" class="topic" data-topic="{tid}" data-en="{en}" data-ru="{ru}" aria-pressed="{"true" if tid == "other" else "false"}">{b(en, ru)}</button>' for tid, en, ru in TOPICS)

    body = f'''  <main id="main" class="support">
    <div class="pp-hero help-hero">
      <div class="wrap">
        <span class="eyebrow"><span class="dot"></span>{b("Support", "Поддержка")}</span>
        <h1 data-l="en">We’ll help you <span class="grad">sort it out.</span></h1>
        <h1 data-l="ru">Поможем <span class="grad">разобраться.</span></h1>
        <p class="lead">{b("Short answers in clear steps — and if they don’t help, we’ll answer you ourselves.", "Короткие ответы по шагам — а если не помогут, ответим вам сами.")} <a class="inline-link" href="#contact">{b("Write to us", "Написать нам")} {svg("arrow")}</a></p>
        <div class="help-search" role="search">
          {svg("search", "s-ic")}
          <input type="search" id="help-q" autocomplete="off" aria-label="Search answers" placeholder="Describe the problem: “no code”, “refund”…" data-ph-en="Describe the problem: “no code”, “refund”…" data-ph-ru="Опишите проблему: «не приходит код», «вернуть деньги»…">
          <button type="button" class="s-clear" hidden aria-label="Clear">{svg("close")}</button>
        </div>
        <p class="search-status" aria-live="polite"></p>
      </div>
    </div>

    <div class="wrap help-body">
      <nav class="entries" aria-label="Topics">{entries}
      </nav>

      <div class="situations-box">
        <h2 class="mini-title">{b("Common situations", "Частые ситуации")}</h2>
        <div class="situations">{featured}
        </div>
      </div>
{sections}
      <div class="no-results" hidden>
        <h3>{b("Nothing found", "Ничего не нашлось")}</h3>
        <p>{b("Try other words — or write to us, and we’ll help.", "Попробуйте другие слова — или напишите нам, и мы поможем.")}</p>
      </div>

      <section class="contact-box" id="contact">
        <div class="cb-copy">
          <h2 data-l="en">Didn’t find <span class="grad">a solution?</span></h2>
          <h2 data-l="ru">Не нашли <span class="grad">решение?</span></h2>
          <p>{b("Tell us your iPhone model, iOS version, the app version (Settings → bottom of the screen) and what happened.",
                "Напишите модель iPhone, версию iOS, версию приложения (Настройки → внизу экрана) и что произошло.")}</p>
          <div class="pp-meta">
            <span class="pp-chip">{svg("clock")}{b("We reply within 1–2 business days", "Отвечаем в течение 1–2 рабочих дней")}</span>
            <span class="pp-chip">{svg("chat")}English · Русский</span>
          </div>
        </div>
        <div class="cb-form">
          <p class="label">{b("What is it about?", "О чём обращение?")}</p>
          <div class="topics" role="group">{chips}</div>
          <a class="btn btn-primary mail-btn" href="{mailto("Minor AI — support")}">{svg("mail")}{b("Write to support", "Написать в поддержку")}</a>
          <small class="mail-note">{b("Opens your mail app with the subject filled in", "Откроется почта с заполненной темой")} · {EMAIL}</small>
        </div>
      </section>
    </div>
  </main>'''
    h = head("Support — Minor AI", "Поддержка — Minor AI",
             "Help with Minor AI: building maps, AI limits, subscriptions, signing in and deleting your data.",
             "/support/", og=False)
    return page(h, body, active="support", scripts=("/assets/support.js",), body_class="support-page")
