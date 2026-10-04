// Support: search across the answers, open an answer from a link, and fill in the email subject.
(function () {
  var html = document.documentElement;
  var input = document.getElementById("help-q");
  var clear = document.querySelector(".s-clear");
  var status = document.querySelector(".search-status");
  var body = document.querySelector(".help-body");
  var empty = document.querySelector(".no-results");
  var faqs = Array.prototype.slice.call(document.querySelectorAll("details.faq"));
  var sections = Array.prototype.slice.call(document.querySelectorAll(".help-sec"));
  function lang() { return html.getAttribute("data-lang") === "ru" ? "ru" : "en"; }

  // Words are matched by their beginning, so “refunds” finds “refund” and “кода” finds “код”.
  // Small words don't count, and a few everyday words also look for the words the answers use.
  var STOP = ("не ни в во и на как что я мне у меня с со по а но или ли это мой моя мои нет да для к о об от из за же " +
    "i my me the a an to is it its not no do does did how can cant can't in on of for with and or what why where").split(" ");
  var SYN = { "оплат": "покуп", "оплач": "покуп", "купил": "покуп", "деньг": "возврат", "вернут": "возврат", "логин": "вход",
    "войт": "вход", "приход": "письм", "сбро": "пароль", "money": "refund", "paid": "purchase", "pay": "purchase",
    "bought": "purchase", "login": "sign", "log": "sign", "email": "code", "mic": "microphone" };
  function norm(text) { return text.toLowerCase().replace(/ё/g, "е").replace(/[^a-zа-я0-9]+/g, " "); }
  function stem(word) { return word.length > 4 ? word.slice(0, Math.max(4, word.length - 2)) : word; }
  function variants(word) {
    var out = [stem(word)];
    for (var key in SYN) if (word.indexOf(key) === 0) out.push(SYN[key]);
    return out;
  }
  function has(text, alts) { return alts.some(function (a) { return text.indexOf(a) !== -1; }); }

  function textOf(details, onlyTitle) {
    // Only the visible language counts.
    var scope = onlyTitle ? details.querySelector("summary") : details;
    var parts = scope.querySelectorAll('[data-l="' + lang() + '"]');
    var out = "";
    for (var i = 0; i < parts.length; i++) out += " " + parts[i].textContent;
    return norm(out);
  }

  function search() {
    var q = norm(input.value).trim();
    clear.hidden = !q;
    body.classList.toggle("searching", !!q);
    if (!q) {
      faqs.forEach(function (f) { f.classList.remove("miss"); });
      sections.forEach(function (s) { s.classList.remove("miss"); });
      empty.hidden = true;
      status.textContent = "";
      return;
    }
    var words = q.split(" ").filter(function (w) { return w && STOP.indexOf(w) === -1; });
    if (!words.length) words = q.split(" ").filter(Boolean);
    var groups = words.map(variants);
    var scores = faqs.map(function (f) {
      var text = textOf(f), title = textOf(f, true), score = 0;
      groups.forEach(function (alts) {
        if (has(text, alts)) score += 1;
        if (has(title, alts)) score += 0.5;
      });
      return score;
    });
    var best = Math.max.apply(null, scores);
    var found = 0;
    faqs.forEach(function (f, i) {
      var hit = best > 0 && scores[i] >= best * 0.7;
      f.classList.toggle("miss", !hit);
      if (hit) found++;
    });
    sections.forEach(function (s) { s.classList.toggle("miss", !s.querySelector("details.faq:not(.miss)")); });
    empty.hidden = found > 0;
    status.textContent = lang() === "ru"
      ? (found ? "Найдено ответов: " + found : "")
      : (found ? found + (found === 1 ? " answer" : " answers") + " found" : "");
    faqs.forEach(function (f) { if (f.classList.contains("miss")) f.open = false; });
    var first = document.querySelector("details.faq:not(.miss)");
    if (first && found <= 2) first.open = true;
  }

  if (input) {
    input.addEventListener("input", search);
    input.addEventListener("keydown", function (event) {
      if (event.key === "Escape") { input.value = ""; search(); }
      if (event.key === "Enter") {
        var first = document.querySelector("details.faq:not(.miss)");
        if (first) { first.open = true; first.scrollIntoView({ behavior: "smooth", block: "start" }); }
      }
    });
    clear.addEventListener("click", function () { input.value = ""; search(); input.focus(); });
    document.addEventListener("minor:lang", function () { if (input.value) search(); });
  }

  // A link like /support/#purchase-missing opens that answer.
  function openFromHash() {
    var id = decodeURIComponent(location.hash.slice(1));
    var target = id && document.getElementById(id);
    if (target && target.tagName === "DETAILS") {
      target.open = true;
      setTimeout(function () { target.scrollIntoView({ block: "start", behavior: "instant" }); }, 0);
    }
  }
  window.addEventListener("hashchange", openFromHash);
  openFromHash();

  // Contact: the chosen topic becomes the email subject, and the body asks for the useful details.
  var mail = document.querySelector(".mail-btn");
  var topics = Array.prototype.slice.call(document.querySelectorAll(".topic"));
  var current = "other";
  function updateMail() {
    var chip = topics.filter(function (t) { return t.getAttribute("data-topic") === current; })[0];
    var name = chip ? chip.getAttribute("data-" + lang()) : "";
    var subject = "Minor AI — " + name;
    var bodyText = lang() === "ru"
      ? "Что произошло:\n\n\n—\nМодель iPhone:\nВерсия iOS:\nВерсия Minor (Настройки → внизу экрана):\n"
      : "What happened:\n\n\n—\niPhone model:\niOS version:\nMinor version (Settings → bottom of the screen):\n";
    mail.setAttribute("href", "mailto:support@minorai.site?subject=" + encodeURIComponent(subject) + "&body=" + encodeURIComponent(bodyText));
  }
  topics.forEach(function (chip) {
    chip.addEventListener("click", function () {
      current = chip.getAttribute("data-topic");
      topics.forEach(function (t) { t.setAttribute("aria-pressed", String(t === chip)); });
      updateMail();
    });
  });
  if (mail) {
    updateMail();
    document.addEventListener("minor:lang", updateMail);
  }
})();
