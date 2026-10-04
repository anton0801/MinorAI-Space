# The home page: a short promise, a live map that grows out of the phone, three scenes
# (gather → go deeper → take action), switchable example maps, then privacy, plans and a download.
from common import svg, icon, both as b, head, page, app_store_button, APP_STORE


def mn(en, ru, cls="", id=None, parent=None, extra=""):
    """A node in a scene's mini map. Connectors are drawn by home.js from data-parent."""
    attrs = f' id="{id}"' if id else ""
    attrs += f' data-parent="{parent}"' if parent else ""
    return f'<div class="mn {cls}"{attrs}>{extra}{b(en, ru)}</div>'


def check(done=False):
    return f'<span class="chk{" done" if done else ""}">{svg("check")}</span>'


def due(en, ru, cls=""):
    return f'<span class="due {cls}">{svg("bell")}{b(en, ru)}</span>'


HERO = f'''
    <section class="home-hero">
      <div class="wrap hero-copy">
        <span class="eyebrow"><span class="dot"></span>{b("AI mind maps for iPhone", "ИИ-карты мыслей для iPhone")}</span>
        <h1 data-l="en">Give your thoughts <span class="grad">shape.</span></h1>
        <h1 data-l="ru">Дайте мысли <span class="grad">форму.</span></h1>
        <p class="lead" data-l="en">Turn topics, documents and conversations into maps that help you make sense of things and move forward.</p>
        <p class="lead" data-l="ru">Превращайте темы, документы и разговоры в карты, которые помогают разобраться и двигаться дальше.</p>
        <div class="cta">
          {app_store_button()}
          <a class="btn btn-ghost" href="#stage" data-play>{svg("play", "i-play")}{b("See it in action", "Посмотреть в действии")}</a>
        </div>
        <p class="note">{b("Free to start · iPhone with iOS 16 or later", "Бесплатный старт · iPhone с iOS 16 и новее")}</p>
      </div>
      <div class="wrap">
        <div class="stage" id="stage">
          <p class="sr">{b("Animation: the topic “Launch my project” becomes a mind map with the branches Audience, Product and Launch, and the Launch branch is expanded with AI.",
                          "Анимация: тема «Запустить свой проект» превращается в карту с ветками «Аудитория», «Продукт» и «Запуск», а ветка «Запуск» раскрывается с помощью ИИ.")}</p>
          <div class="stage-glow" aria-hidden="true"></div>
          <div class="phone live" aria-hidden="true">
            <div class="screen">
              <div class="sb"><b>9:41</b><span class="island"></span><span class="sb-r"><i class="sig"></i><i class="bat"></i></span></div>
              <div class="scr scr-start">
                <div class="app-top">{svg("menu")}<span class="plan-pill"><i></i>Minor Plus</span></div>
                <div class="st-title">{b("Start a Map", "Новая карта")}</div>
                <div class="st-sub">{b("Pick a source or just type a topic.", "Выберите источник или просто напишите тему.")}</div>
                <div class="tiles">
                  <div class="tile sel">{svg("text")}<b>{b("Topic", "Тема")}</b><small>{b("Type any subject", "Любая тема")}</small></div>
                  <div class="tile">{svg("doc")}<b>{b("Document", "Документ")}</b><small>{b("PDF, TXT or RTF", "PDF, TXT или RTF")}</small></div>
                  <div class="tile">{svg("link")}<b>{b("Link", "Ссылка")}</b><small>{b("Article or web page", "Статья или веб-страница")}</small></div>
                  <div class="tile">{svg("scan")}<b>{b("Scan", "Скан")}</b><small>{b("Notes, slides, a whiteboard", "Конспект, слайды, доска")}</small></div>
                </div>
                <div class="composer">
                  <span class="field"><span class="ph">{b("Map any topic or paste a link", "Любая тема или ссылка")}</span><span class="typed"></span><i class="caret"></i></span>
                  <span class="send">{svg("up")}</span>
                </div>
              </div>
              <div class="scr scr-map">
                <div class="map-top">{svg("home")}<div class="mt"><b class="mt-title"></b><small class="mt-sub"></small></div>{svg("dots")}</div>
                <div class="map-bottom">
                  <div class="bar tools"><span>+ {b("Node", "Узел")}</span><span>{b("List", "Список")}</span><span>{b("Fit", "Вместить")}</span><span>{b("Search", "Поиск")}</span></div>
                  <div class="bar actions"><span class="primary">{svg("spark")}{b("Expand", "Развить")}</span><span>{b("Ask", "Спросить")}</span><span>{b("Edit", "Изменить")}</span><span>{b("Style", "Стиль")}</span></div>
                  <div class="cmd">{b("Change this map, or ask a question", "Команда или вопрос")}<span class="send">{svg("up")}</span></div>
                </div>
              </div>
            </div>
          </div>
          <div class="map-layer" aria-hidden="true"></div>
          <button type="button" class="replay" hidden>{svg("replay")}{b("Play again", "Ещё раз")}</button>
        </div>
      </div>
    </section>'''


SOURCES = [("text", "Topic", "Тема"), ("doc", "Document", "Документ"), ("link", "Link", "Ссылка"),
           ("video", "YouTube", "YouTube"), ("mic", "Voice", "Голос"), ("scan", "Scan", "Скан"), ("chat", "Chat", "Чат")]

SCENE_GATHER = f'''
          <div class="sv sv-gather">
            <div class="doc">
              <div class="doc-head">{svg("doc")}<b>{b("Lecture 7 · Photosynthesis.pdf", "Лекция 7 · Фотосинтез.pdf")}</b><span>{b("12 pages", "12 страниц")}</span></div>
              <p data-l="en"><mark class="m0">Photosynthesis</mark> turns light into chemical energy. It runs in two stages: the <mark class="m1">light reactions</mark> in the thylakoid membranes and the <mark class="m2">Calvin cycle</mark> in the stroma. The key pigment is <mark class="m3">chlorophyll</mark>, and the result is <mark class="m4">glucose and oxygen</mark>.</p>
              <p data-l="ru"><mark class="m0">Фотосинтез</mark> превращает свет в химическую энергию. Он идёт в две стадии: <mark class="m1">световая фаза</mark> в мембранах тилакоидов и <mark class="m2">цикл Кальвина</mark> в строме. Главный пигмент — <mark class="m3">хлорофилл</mark>, а итог — <mark class="m4">глюкоза и кислород</mark>.</p>
              <div class="doc-lines"><i></i><i></i><i></i></div>
            </div>
            <div class="mm mm-gather">
              {mn("Photosynthesis", "Фотосинтез", "root", id="g0")}
              {mn("Light reactions", "Световая фаза", "c-mint", parent="g0")}
              {mn("Calvin cycle", "Цикл Кальвина", "c-violet", parent="g0")}
              {mn("Chlorophyll", "Хлорофилл", "c-sky", parent="g0")}
              {mn("Glucose + O₂", "Глюкоза + O₂", "c-sun", parent="g0")}
              <svg class="mm-links" aria-hidden="true"></svg>
            </div>
          </div>'''

SCENE_DEEPER = f'''
          <div class="sv sv-deeper">
            <div class="mm mm-deeper">
              {mn("Photosynthesis", "Фотосинтез", "root dim", id="d0")}
              {mn("Light reactions", "Световая фаза", "c-mint sel", id="d1", parent="d0")}
              {mn("Calvin cycle", "Цикл Кальвина", "c-violet dim", id="d2", parent="d0")}
              {mn("Water splits, releasing O₂", "Вода расщепляется, выделяется O₂", "c-mint new n1", parent="d1", extra=svg("spark", "ai"))}
              {mn("Energy is stored in ATP", "Энергия запасается в АТФ", "c-mint new n2", parent="d1", extra=svg("spark", "ai"))}
              {mn("Example: bubbles on pondweed", "Пример: пузырьки у водорослей", "c-mint new n3", parent="d1", extra=svg("spark", "ai"))}
              <svg class="mm-links" aria-hidden="true"></svg>
            </div>
            <div class="explain">
              <b>{b("Why it matters", "Почему это важно")}</b>
              <p>{b("Light gives the energy to split water — that’s where the oxygen we breathe comes from.",
                    "Свет даёт энергию, чтобы расщепить воду, — отсюда кислород, которым мы дышим.")}</p>
            </div>
            <div class="actionbar"><span class="primary">{svg("spark")}{b("Expand", "Развить")}</span><span>{b("Ask", "Спросить")}</span><span>{b("Edit", "Изменить")}</span><span>{b("Style", "Стиль")}</span></div>
          </div>'''

SCENE_ACT = f'''
          <div class="sv sv-act">
            <div class="mm mm-act">
              {mn("Exam plan", "План подготовки", "root", id="a0")}
              {mn("Lecture notes", "Конспект лекций", "c-sky t1 is-done", parent="a0", extra=check(True))}
              <div class="mn c-sky t2" data-parent="a0">{check()}{b("Review flashcards", "Повторить карточки")}{due("Today", "Сегодня")}</div>
              <div class="mn c-sky t3" data-parent="a0">{check()}{b("Practice test", "Пробный тест")}{due("Fri", "Пт")}</div>
              <svg class="mm-links" aria-hidden="true"></svg>
            </div>
            <div class="today">
              <div class="td-head"><b>{b("Today", "Сегодня")}</b><span class="td-count"><span class="c1">{b("1 of 3 done", "Готово 1 из 3")}</span><span class="c2">{b("2 of 3 done", "Готово 2 из 3")}</span></span></div>
              <div class="td-bar"><i></i></div>
              <ul>
                <li class="r1 done">{check(True)}{b("Lecture notes", "Конспект лекций")}</li>
                <li class="r2">{check()}{b("Review flashcards", "Повторить карточки")}<span class="td-time">9:00</span></li>
                <li class="r3">{check()}{b("Practice test", "Пробный тест")}<span class="td-time">{b("Fri", "Пт")}</span></li>
              </ul>
            </div>
            <div class="toast">{svg("bell")}<span><b>Minor AI</b>{b("Practice test is due on Friday", "Пробный тест — в пятницу")}</span></div>
          </div>'''


def scene(num, en_title, ru_title, en_text, ru_text, visual, extra="", reverse=False):
    return f'''
        <div class="scene{" reverse" if reverse else ""}" data-scene>
          <div class="scene-copy">
            <span class="scene-num">{num}</span>
            <h3>{b(en_title, ru_title)}</h3>
            <p>{b(en_text, ru_text)}</p>{extra}
          </div>{visual}
        </div>'''


source_chips = '<div class="src-chips">' + "".join(f'<span>{svg(i)}{b(en, ru)}</span>' for i, en, ru in SOURCES) + '</div>'

HOW = f'''
    <section class="how" id="how">
      <div class="wrap">
        <p class="kicker">{b("How it works", "Как это работает")}</p>
        <h2 class="section-title">{b("From a thought to a plan.", "От мысли — к плану.")}</h2>
        {scene("01", "Gather your thoughts", "Соберите мысли",
               "Add a topic, a document, a link, a video, your voice or a photo of your notes.<br>Minor finds the main ideas and lays them out in branches.",
               "Добавьте тему, документ, ссылку, видео, голос или фото конспекта.<br>Minor найдёт главные идеи и разложит их по веткам.",
               SCENE_GATHER, extra=source_chips)}
        {scene("02", "Go deeper", "Разберитесь глубже",
               "Pick any idea and tap Expand — AI adds examples and explanations.<br>Or ask about it in the chat.",
               "Выберите любую идею и нажмите «Развить» — ИИ добавит примеры и пояснения.<br>Или спросите о ней в чате.",
               SCENE_DEEPER, reverse=True)}
        {scene("03", "Take action", "Перейдите к действиям",
               "Turn ideas into tasks with dates.<br>They show up in Today, in reminders and in your calendar.",
               "Превратите идеи в задачи со сроками.<br>Они появятся в «Сегодня», в напоминаниях и в календаре.",
               SCENE_ACT)}
      </div>
    </section>'''


EXAMPLES = f'''
    <section class="examples" id="examples">
      <div class="wrap">
        <p class="kicker">{b("Examples", "Примеры")}</p>
        <h2 class="section-title">{b("Maps worth opening.", "Карты, которые хочется открыть.")}</h2>
        <p class="section-lead">{b("Switch between ready-made maps. Tap an idea to light up its branch.", "Переключайте готовые карты. Нажмите на идею — подсветится вся её ветка.")}</p>
        <div class="ex-tabs" role="tablist" aria-label="{'Example maps'}">
          <button type="button" role="tab" aria-selected="true" data-ex="exam">{svg("cards")}{b("Exam prep", "Подготовка к экзамену")}</button>
          <button type="button" role="tab" aria-selected="false" data-ex="launch">{svg("arrow")}{b("Project launch", "Запуск проекта")}</button>
          <button type="button" role="tab" aria-selected="false" data-ex="lang">{svg("globe")}{b("Learning a language", "Изучение языка")}</button>
        </div>
        <div class="ex-canvas" role="tabpanel" aria-live="polite">
          <div class="map-layer"></div>
          <noscript><p class="ex-noscript">{b("Turn on JavaScript to see the example maps.", "Включите JavaScript, чтобы увидеть примеры карт.")}</p></noscript>
        </div>
        <div class="ex-foot">
          <span class="ex-stats"></span>
          <a href="{APP_STORE}">{b("Build yours in Minor", "Постройте свою в Minor")} {svg("arrow")}</a>
        </div>
      </div>
    </section>'''


MORE_ITEMS = [
    ("slides", "#c9a2ff", "Presentations", "Презентации", "A deck from any map in half a minute. Export to PowerPoint or PDF.", "Слайды из любой карты за полминуты. Экспорт в PowerPoint и PDF."),
    ("chat", "#2fff9e", "An assistant that knows your maps", "Помощник, который знает ваши карты", "Ask what’s missing — or tell it to add a branch to a map.", "Спросите, чего не хватает, — или попросите добавить ветку в карту."),
    ("people", "#7cc4ff", "Edit together", "Вместе", "Share a link and work on one map with friends or a team.", "Поделитесь ссылкой и работайте над одной картой с друзьями или командой."),
    ("cards", "#ffd66b", "Study", "Учёба", "Flashcards with spaced repetition and AI quizzes from any map.", "Карточки с интервальными повторениями и тесты от ИИ по любой карте."),
]
MORE = f'''
    <section class="more">
      <div class="wrap">
        <h2 class="section-title small">{b("Also in Minor", "А ещё в Minor")}</h2>
        <div class="more-grid">''' + "".join(f'''
          <div class="card">{icon(ic, c)}<h3>{b(en, ru)}</h3><p>{b(pen, pru)}</p></div>''' for ic, c, en, ru, pen, pru in MORE_ITEMS) + '''
        </div>
      </div>
    </section>'''


TRUST = [
    ("ban", "#ff8f8f", "No ads, no selling", "Без рекламы и продажи данных", "We don’t sell your data, show ads or track you across apps.", "Мы не продаём данные, не показываем рекламу и не следим за вами в других приложениях."),
    ("shield", "#2fff9e", "AI only with your OK", "ИИ — только с вашего согласия", "Nothing goes to an AI provider until you allow it.", "Ничего не уходит провайдеру ИИ, пока вы не разрешите."),
    ("spark", "#c9a2ff", "Not used to train AI", "Не для обучения ИИ", "Your maps, chats and files don’t train AI models.", "Ваши карты, чаты и файлы не используются для обучения моделей."),
]
PRIVACY = f'''
    <section class="trust">
      <div class="wrap">
        <div class="trust-box">
          <div class="trust-head">
            <h2 class="section-title small" data-l="en">Your ideas <span class="grad">stay yours.</span></h2>
            <h2 class="section-title small" data-l="ru">Ваши идеи <span class="grad">остаются вашими.</span></h2>
            <a class="more-link" href="/privacy/">{b("Privacy Policy", "Политика конфиденциальности")} {svg("arrow")}</a>
          </div>
          <div class="trust-grid">''' + "".join(f'''
            <div class="trust-item">{icon(ic, c)}<div><h3>{b(en, ru)}</h3><p>{b(pen, pru)}</p></div></div>''' for ic, c, en, ru, pen, pru in TRUST) + '''
          </div>
        </div>
      </div>
    </section>'''


def plan(name, price_en, price_ru, alt_en, alt_ru, items, cls=""):
    lis = "".join(f"<li>{b(en, ru)}</li>" for en, ru in items)
    return f'''
          <div class="plan {cls}">
            <h3>{name}</h3>
            <div class="price">{b(price_en, price_ru)}</div>
            <div class="price-alt">{b(alt_en, alt_ru)}</div>
            <ul>{lis}</ul>
          </div>'''


MODELS = [("GPT-6 Luna", "×1"), ("Claude Haiku 4.5", "×10"), ("GPT-6.1 Sol", "×20"), ("Claude Sonnet 5.5", "×25"),
          ("Claude Opus 5.5", "×50"), ("GPT-6 Astra", "×100"), ("Claude Fable 5.1", "×130")]

PRICING = f'''
    <section class="pricing" id="pricing">
      <div class="wrap">
        <p class="kicker">{b("Pricing", "Тарифы")}</p>
        <h2 class="section-title">{b("Simple plans.", "Простые тарифы.")}</h2>
        <p class="section-lead">{b("Start free. Upgrade when Minor becomes part of how you think.", "Начните бесплатно. Перейдите на платный тариф, когда Minor станет частью того, как вы думаете.")}</p>
        <div class="plans">''' + plan(b("Free", "Бесплатно"), "$0", "$0", "&nbsp;", "&nbsp;", [
            ("3 maps a month", "3 карты в месяц"),
            ("1 presentation a month", "1 презентация в месяц"),
            ("Chat with every model within a small AI allowance", "Чат со всеми моделями в пределах небольшого лимита ИИ"),
            ("3 AI images a month", "3 картинки ИИ в месяц"),
        ]) + plan("Minor Plus", "$12.99<small> / month</small>", "$12.99<small> / мес.</small>", "or $119.99 a year — save 23%", "или $119.99 в год — экономия 23%", [
            ("Up to 300 maps and 20 presentations a month", "До 300 карт и 20 презентаций в месяц"),
            ("YouTube and voice maps; invite up to 5 people per map", "Карты из YouTube и голоса; до 5 человек в карте"),
            ("Presentation design: own styles, charts, animations, PowerPoint", "Дизайн презентаций: свои стили, диаграммы, анимации, PowerPoint"),
            ("20× the AI allowance, 60 AI images a month", "Лимит ИИ ×20, 60 картинок в месяц"),
        ], "featured") + plan('Minor <span class="pro">PRO</span>', "$24.99<small> / month</small>", "$24.99<small> / мес.</small>", "or $219.99 a year — save 27%", "или $219.99 в год — экономия 27%", [
            ("Everything in Plus, up to 600 maps and 60 presentations", "Всё из Plus, до 600 карт и 60 презентаций"),
            ("The strongest models for maps", "Самые мощные модели для карт"),
            ("40× the AI allowance, 150 AI images a month", "Лимит ИИ ×40, 150 картинок ИИ в месяц"),
            ("Up to 25 people per map, Xmind and MindNode export", "До 25 человек в карте, экспорт в Xmind и MindNode"),
        ]) + f'''
        </div>
        <details class="disclose">
          <summary>{b("AI models and the monthly allowance", "Модели ИИ и месячный лимит")}</summary>
          <div class="disclose-body">
            <p>{b("Every plan can chat with every model. Each request uses part of your monthly AI allowance; the number shows how much faster a model uses it than the lightest one. For building maps: standard models for everyone, Claude Opus 5.5 with Plus, GPT-6 Astra and Claude Fable 5.1 with PRO.",
                  "В любом тарифе в чате доступны все модели. Каждый запрос расходует часть месячного лимита ИИ; число показывает, во сколько раз быстрее модель тратит лимит, чем самая лёгкая. Для построения карт: стандартные модели — всем, Claude Opus 5.5 — с Plus, GPT-6 Astra и Claude Fable 5.1 — с PRO.")}</p>
            <div class="models">''' + "".join(f'<span class="model">{m} <span>{x}</span></span>' for m, x in MODELS) + f'''</div>
          </div>
        </details>
        <p class="fine">{b("Prices in US dollars; the App Store shows the price in your currency, including local taxes. Subscriptions renew automatically until you cancel them in your Apple ID settings.",
                         "Цены в долларах США; App Store покажет цену в вашей валюте с учётом местных налогов. Подписка продлевается автоматически, пока вы не отмените её в настройках Apple ID.")}</p>
      </div>
    </section>'''


FINAL = f'''
    <section class="final">
      <div class="wrap">
        <div class="final-box">
          <img src="/assets/logo.png" alt="" width="88" height="88">
          <h2 class="section-title" data-l="en">Give your thoughts <span class="grad">shape.</span></h2>
          <h2 class="section-title" data-l="ru">Дайте мысли <span class="grad">форму.</span></h2>
          <p class="section-lead">{b("Download Minor AI and build your first map in seconds.", "Скачайте Minor AI и постройте первую карту за секунды.")}</p>
          {app_store_button()}
        </div>
      </div>
    </section>'''


def build():
    h = head("Minor AI — Give your thoughts shape", "Minor AI — дайте мысли форму",
             "Minor AI turns topics, documents, links, videos and conversations into clear mind maps — then helps you go deeper and turn ideas into a plan.",
             "/")
    body = f'''  <main id="main">{HERO}{HOW}{EXAMPLES}{MORE}{PRIVACY}{PRICING}{FINAL}
  </main>'''
    return page(h, body, active=None, scripts=("/assets/home.js",), body_class="home")
