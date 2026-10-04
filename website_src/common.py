# Shared parts of every page on minorai.site: <head>, header, footer, buttons and icons.
# Pages are bilingual: elements with data-l="en" / data-l="ru" are shown for the chosen language.

APP_STORE = "https://apps.apple.com/app/id6737686540"
EMAIL = "support@minorai.site"

I = {
 "shield": '<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/><path d="M9 12l2 2 4-4"/>',
 "spark": '<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"/><path d="M19 15l.8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8z"/>',
 "ban": '<circle cx="12" cy="12" r="9"/><path d="M5.6 5.6l12.8 12.8"/>',
 "phone": '<rect x="7" y="2.5" width="10" height="19" rx="2.5"/><path d="M11 18.5h2"/>',
 "sync": '<path d="M20 11a8 8 0 0 0-14.3-4.9M4 13a8 8 0 0 0 14.3 4.9"/><path d="M20 4v7h-7M4 20v-7h7"/>',
 "pin": '<path d="M12 21s-7-6.2-7-11.5A7 7 0 0 1 19 9.5C19 14.8 12 21 12 21z"/><circle cx="12" cy="9.5" r="2.5"/>',
 "trash": '<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/>',
 "lock": '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
 "clock": '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
 "bell": '<path d="M6 16v-5a6 6 0 0 1 12 0v5l2 2H4z"/><path d="M10 20a2 2 0 0 0 4 0"/>',
 "map": '<path d="M9 4L3 6v14l6-2 6 2 6-2V4l-6 2z"/><path d="M9 4v14M15 6v14"/>',
 "user": '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
 "mail": '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3 7l9 6 9-6"/>',
 "calendar": '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/>',
 "info": '<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5v.5"/>',
 "card": '<rect x="3" y="6" width="18" height="13" rx="2"/><path d="M3 10h18"/>',
 "logout": '<path d="M15 4h3a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-3M10 17l5-5-5-5M15 12H4"/>',
 "chat": '<path d="M5 18l-1 3 4-2h9a3 3 0 0 0 3-3V7a3 3 0 0 0-3-3H7a3 3 0 0 0-3 3v9"/>',
 "up": '<path d="M12 19V5M6 11l6-6 6 6"/>',
 "down": '<path d="M12 3v12m0 0-5-5m5 5 5-5M5 21h14"/>',
 "play": '<path d="M8 5.5v13l11-6.5z"/>',
 "search": '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>',
 "arrow": '<path d="M5 12h14M13 6l6 6-6 6"/>',
 "menu": '<path d="M4 7h16M4 12h16M4 17h16"/>',
 "close": '<path d="M6 6l12 12M18 6 6 18"/>',
 "replay": '<path d="M4 12a8 8 0 1 0 2.3-5.7"/><path d="M4 4v4h4"/>',
 "check": '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
 "doc": '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5M9 13h6M9 17h6"/>',
 "link": '<path d="M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.7 1.7"/><path d="M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.7-1.7"/>',
 "video": '<rect x="3" y="5" width="18" height="14" rx="3"/><path d="m10 9 5 3-5 3z"/>',
 "mic": '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/>',
 "scan": '<path d="M4 8V6a2 2 0 0 1 2-2h2M16 4h2a2 2 0 0 1 2 2v2M20 16v2a2 2 0 0 1-2 2h-2M8 20H6a2 2 0 0 1-2-2v-2"/><path d="M8 10h8M8 14h5"/>',
 "text": '<path d="M4 7V5h16v2M9 19h6M12 5v14"/>',
 "slides": '<rect x="3" y="4" width="18" height="12" rx="2"/><path d="M8 20h8M12 16v4"/>',
 "people": '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0"/><circle cx="17" cy="9" r="2.5"/><path d="M16 14.2A5 5 0 0 1 21.5 19"/>',
 "cards": '<rect x="3" y="7" width="13" height="13" rx="2"/><path d="M8 4h11a2 2 0 0 1 2 2v11"/>',
 "wave": '<path d="M4 10v4M8 7v10M12 4v16M16 7v10M20 10v4"/>',
 "gear": '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
 "star": '<path d="M12 3.5l2.6 5.3 5.9.9-4.2 4.1 1 5.8L12 16.9l-5.3 2.7 1-5.8-4.2-4.1 5.9-.9z"/>',
 "restore": '<path d="M20 12a8 8 0 1 1-2.3-5.7"/><path d="M20 4v4h-4"/>',
 "globe": '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>',
 "dots": '<circle cx="5" cy="12" r="1.3"/><circle cx="12" cy="12" r="1.3"/><circle cx="19" cy="12" r="1.3"/>',
 "chevron": '<path d="m9 6 6 6-6 6"/>',
 "home": '<path d="M4 11 12 4l8 7M6 9.5V20h12V9.5"/>',
 "task": '<circle cx="12" cy="12" r="8.5"/><path d="M8.5 12.2l2.4 2.4 4.6-4.8"/>',
}


def svg(name, cls=""):
    c = f' class="{cls}"' if cls else ""
    return f'<svg viewBox="0 0 24 24" aria-hidden="true"{c}>{I[name]}</svg>'


def icon(name, color=None):
    style = f' style="--c:{color}"' if color else ""
    return f'<div class="icon"{style}>{svg(name)}</div>'


def both(en, ru, tag="span", cls=""):
    """The same element in both languages."""
    c = f' class="{cls}"' if cls else ""
    return f'<{tag}{c} data-l="en">{en}</{tag}><{tag}{c} data-l="ru">{ru}</{tag}>'


def app_store_button(cls=""):
    extra = f" {cls}" if cls else ""
    return (f'<a class="btn btn-primary btn-store{extra}" href="{APP_STORE}">{svg("down")}'
            f'<span class="two-line"><small data-l="en">Download on the</small><small data-l="ru">Загрузите в</small>App Store</span></a>')


LANG_BOOT = """  <script>
    (function () { var l; try { l = localStorage.getItem("minor-lang"); } catch (e) {}
      var q = (location.search.match(/[?&]lang=(en|ru)/) || [])[1];
      l = q || l || ((navigator.language || "").toLowerCase().indexOf("ru") === 0 ? "ru" : "en");
      document.documentElement.setAttribute("data-lang", l); document.documentElement.setAttribute("lang", l); })();
  </script>"""


def head(title_en, title_ru, description, path, extra="", robots=None, og=True):
    url = f"https://minorai.site{path}"
    meta = [
        f'<meta name="description" content="{description}">',
        '<meta name="apple-itunes-app" content="app-id=6737686540">',
        '<meta name="theme-color" content="#100e11">',
    ]
    if robots:
        meta.append(f'<meta name="robots" content="{robots}">')
    else:
        meta.append(f'<link rel="canonical" href="{url}">')
    if og:
        meta += [
            f'<meta property="og:title" content="{title_en}">',
            f'<meta property="og:description" content="{description}">',
            '<meta property="og:image" content="https://minorai.site/assets/icon-512.png">',
            f'<meta property="og:url" content="{url}">',
        ]
    meta_html = "\n  ".join(meta)
    return f'''<!doctype html>
<html lang="en" data-lang="en" data-title-en="{title_en}" data-title-ru="{title_ru}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <title>{title_en}</title>
  {meta_html}
  <link rel="icon" type="image/png" href="/assets/favicon.png">
  <link rel="apple-touch-icon" href="/assets/apple-touch-icon.png">
  <link rel="stylesheet" href="/assets/style.css">
{LANG_BOOT}{extra}
</head>'''


NAV = [
    ("/#how", "How it works", "Как это работает", "how"),
    ("/#pricing", "Pricing", "Тарифы", "pricing"),
    ("/support/", "Support", "Поддержка", "support"),
    ("/privacy/", "Privacy", "Конфиденциальность", "privacy"),
]


def header(active=None):
    def links(cls):
        out = []
        for href, en, ru, key in NAV:
            cur = ' aria-current="page"' if key == active else ""
            out.append(f'<a class="{cls}" href="{href}"{cur}>{both(en, ru)}</a>')
        return "\n        ".join(out)
    return f'''
  <a class="skip-link" href="#main">{both("Skip to content", "К содержимому")}</a>
  <header class="site-header">
    <div class="wrap">
      <a class="brand" href="/"><img src="/assets/apple-touch-icon.png" alt="" width="30" height="30">Minor AI</a>
      <nav class="nav" aria-label="Main">
        {links("nav-link")}
      </nav>
      <div class="header-actions">
        <div class="lang-switch" role="group" aria-label="Language">
          <button type="button" data-set-lang="en" aria-pressed="true">EN</button>
          <button type="button" data-set-lang="ru" aria-pressed="false">RU</button>
        </div>
        <a class="btn btn-primary btn-sm header-get" href="{APP_STORE}">{both("Download", "Скачать")}</a>
        <button type="button" class="menu-btn" aria-expanded="false" aria-controls="mobile-nav">{svg("menu", "i-open")}{svg("close", "i-close")}<span class="sr">{both("Menu", "Меню")}</span></button>
      </div>
    </div>
    <nav class="mobile-nav" id="mobile-nav" aria-label="Mobile">
      <div class="wrap">
        {links("mnav-link")}
        <div class="lang-switch" role="group" aria-label="Language">
          <button type="button" data-set-lang="en" aria-pressed="true">English</button>
          <button type="button" data-set-lang="ru" aria-pressed="false">Русский</button>
        </div>
      </div>
    </nav>
  </header>'''


def footer():
    terms = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    return f'''
  <footer class="site-footer">
    <div class="wrap">
      <div class="foot-top">
        <div class="foot-brand">
          <a class="brand" href="/"><img src="/assets/apple-touch-icon.png" alt="" width="30" height="30">Minor AI</a>
          <p>{both("Give your thoughts shape. AI mind maps for iPhone.", "Дайте мысли форму. ИИ-карты мыслей для iPhone.")}</p>
          {app_store_button("btn-sm")}
        </div>
        <nav class="foot-cols" aria-label="Footer">
          <div>
            <h4>{both("Product", "Продукт")}</h4>
            <a href="/#how">{both("How it works", "Как это работает")}</a>
            <a href="/#examples">{both("Examples", "Примеры")}</a>
            <a href="/#pricing">{both("Pricing", "Тарифы")}</a>
          </div>
          <div>
            <h4>{both("Help", "Помощь")}</h4>
            <a href="/support/">{both("Support", "Поддержка")}</a>
            <a href="/support/#contact">{both("Write to us", "Написать нам")}</a>
          </div>
          <div>
            <h4>{both("Legal", "Документы")}</h4>
            <a href="/privacy/">{both("Privacy Policy", "Конфиденциальность")}</a>
            <a href="{terms}">{both("Terms of Use", "Условия использования")}</a>
          </div>
        </nav>
      </div>
      <div class="foot-bottom">
        <span>© <span data-year>2026</span> Regina Danilova · Minor AI</span>
        <span>{both("No cookies, no trackers.", "Без cookies и трекеров.")} <a href="mailto:{EMAIL}">{EMAIL}</a></span>
      </div>
    </div>
  </footer>'''


def page(head_html, body, active=None, scripts=(), body_class="", before_header=""):
    cls = f' class="{body_class}"' if body_class else ""
    tags = "\n  ".join(f'<script src="{s}" defer></script>' for s in ("/assets/site.js", *scripts))
    return f'''{head_html}
<body{cls}>{before_header}{header(active)}
{body}
{footer()}
  {tags}
</body>
</html>
'''
