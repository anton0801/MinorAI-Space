# Small pages: the invite links (a shared map, a friend's invitation) and the 404 page.
from common import svg, both as b, head, page, app_store_button

JOIN_SCRIPT = """
  <script>
    (function () {
      // New links carry the token after "#"; older ones in the query.
      var token = (location.hash.match(/[#&]t=([A-Za-z0-9_\\-]+)/) || location.search.match(/[?&]t=([A-Za-z0-9_\\-]+)/) || [])[1];
      var open = document.getElementById("open");
      if (!token) { open.style.display = "none"; return; }
      var target = "minorai://join/" + token;
      open.setAttribute("href", target);
      // Try the app right away; the buttons stay for when it isn't installed.
      setTimeout(function () { location.href = target; }, 300);
    })();
  </script>"""


def join():
    body = f'''  <main id="main" class="pp-hero center-page">
    <div class="wrap narrow">
      <img class="page-logo" src="/assets/icon-512.png" alt="" width="96" height="96">
      <h1>{b("You’re invited to a map", "Вас пригласили в карту")}</h1>
      <p class="lead">{b("Open it in Minor AI to see it and edit it together. Changes show up for everyone within seconds.",
                        "Откройте её в Minor AI, чтобы смотреть и редактировать вместе. Изменения видны всем за несколько секунд.")}</p>
      <div class="cta center">
        <a class="btn btn-primary" id="open" href="#">{b("Open in Minor AI", "Открыть в Minor AI")}</a>
        <a class="btn btn-ghost" href="https://apps.apple.com/app/id6737686540">{b("Get the App", "Скачать приложение")}</a>
      </div>
      <p class="note">{b("The link works for 14 days. You’ll be asked to sign in.", "Ссылка действует 14 дней. Нужно будет войти в аккаунт.")}</p>
    </div>
  </main>{JOIN_SCRIPT}'''
    h = head("Join a shared map — Minor AI", "Совместная карта — Minor AI", "Open a shared mind map in Minor AI.", "/join/", robots="noindex", og=False)
    return page(h, body)


INVITE_SCRIPT = """
  <script>
    (function () {
      var code = ((location.hash.match(/[#&]c=([A-Za-z0-9]+)/) || location.search.match(/[?&]c=([A-Za-z0-9]+)/) || [])[1] || "").toUpperCase();
      var box = document.getElementById("code-box");
      var open = document.getElementById("open");
      if (!/^[A-HJ-NP-Z2-9]{8}$/.test(code)) { box.style.display = "none"; open.style.display = "none"; return; }
      document.getElementById("code").textContent = code;
      var target = "minorai://invite/" + code;
      open.setAttribute("href", target);
      var copy = document.getElementById("copy");
      copy.addEventListener("click", function () {
        var done = function () { copy.classList.add("copied"); setTimeout(function () { copy.classList.remove("copied"); }, 1600); };
        if (navigator.clipboard) { navigator.clipboard.writeText(code).then(done, function () {}); }
      });
      setTimeout(function () { location.href = target; }, 400);
    })();
  </script>"""


def invite():
    body = f'''  <main id="main" class="pp-hero center-page">
    <div class="wrap narrow">
      <img class="page-logo" src="/assets/icon-512.png" alt="" width="96" height="96">
      <h1>{b("A friend invited you to Minor AI", "Друг приглашает вас в Minor AI")}</h1>
      <p class="lead">{b("Turn notes, videos and ideas into mind maps and presentations. Sign up with this code and get 3 days of Minor Plus free.",
                        "Превращайте заметки, видео и идеи в интеллект-карты и презентации. Зарегистрируйтесь с этим кодом и получите 3 дня Minor Plus бесплатно.")}</p>
      <div class="invite-code" id="code-box">
        <span class="invite-label">{b("Invitation code", "Код приглашения")}</span>
        <strong id="code" class="invite-value"></strong>
        <button type="button" class="btn btn-ghost btn-sm" id="copy"><span class="copy-idle">{b("Copy", "Скопировать")}</span><span class="copy-done">{b("Copied", "Скопировано")}</span></button>
      </div>
      <div class="cta center">
        <a class="btn btn-primary" id="open" href="#">{b("Open in Minor AI", "Открыть в Minor AI")}</a>
        <a class="btn btn-ghost" href="https://apps.apple.com/app/id6737686540">{b("Get the App", "Скачать приложение")}</a>
      </div>
      <p class="note">{b("New to Minor AI? Install the app, create an account, then enter the code in Settings → Invite Friends within 14 days.",
                        "Впервые в Minor AI? Установите приложение, создайте аккаунт и введите код в Настройки → Пригласить друзей в течение 14 дней.")}</p>
    </div>
  </main>{INVITE_SCRIPT}'''
    h = head("You’re invited — Minor AI", "Приглашение — Minor AI", "A friend invited you to Minor AI: 3 days of Minor Plus free.", "/invite/", robots="noindex", og=False)
    return page(h, body)


def not_found():
    body = f'''  <main id="main" class="pp-hero center-page">
    <div class="wrap narrow">
      <p class="big-code">404</p>
      <h1>{b("This page got lost.", "Эта страница потерялась.")}</h1>
      <p class="lead">{b("But your thoughts don’t have to. Go back home or find an answer in Support.", "Но ваши мысли не обязаны. Вернитесь на главную или найдите ответ в поддержке.")}</p>
      <div class="cta center">
        <a class="btn btn-primary" href="/">{b("Home", "На главную")}</a>
        <a class="btn btn-ghost" href="/support/">{b("Support", "Поддержка")}</a>
      </div>
    </div>
  </main>'''
    h = head("Page not found — Minor AI", "Страница не найдена — Minor AI", "Page not found.", "/404.html", robots="noindex", og=False)
    return page(h, body)
