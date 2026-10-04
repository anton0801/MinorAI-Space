// Shared by every page: language, the mobile menu, and the reading aids of long documents.

// Language: ?lang=ru|en, then the visitor's saved choice, then the browser language.
(function () {
  var root = document.documentElement;
  function stored() {
    try { return localStorage.getItem("minor-lang"); } catch (e) { return null; }
  }
  function save(lang) {
    try { localStorage.setItem("minor-lang", lang); } catch (e) { /* private mode */ }
  }
  function apply(lang) {
    root.setAttribute("data-lang", lang);
    root.setAttribute("lang", lang);
    var buttons = document.querySelectorAll("[data-set-lang]");
    for (var i = 0; i < buttons.length; i++) {
      buttons[i].setAttribute("aria-pressed", String(buttons[i].getAttribute("data-set-lang") === lang));
    }
    var title = root.getAttribute("data-title-" + lang);
    if (title) document.title = title;
    var fields = document.querySelectorAll("[data-ph-" + lang + "]");
    for (var k = 0; k < fields.length; k++) fields[k].setAttribute("placeholder", fields[k].getAttribute("data-ph-" + lang));
    document.dispatchEvent(new CustomEvent("minor:lang", { detail: lang }));
  }
  var query = (location.search.match(/[?&]lang=(en|ru)/) || [])[1];
  var browser = (navigator.language || "en").toLowerCase().indexOf("ru") === 0 ? "ru" : "en";
  apply(query || stored() || browser);

  document.addEventListener("click", function (event) {
    var button = event.target.closest && event.target.closest("[data-set-lang]");
    if (!button) return;
    var lang = button.getAttribute("data-set-lang");
    save(lang);
    apply(lang);
  });

  var year = document.querySelectorAll("[data-year]");
  for (var j = 0; j < year.length; j++) year[j].textContent = String(new Date().getFullYear());
})();

// Mobile menu.
(function () {
  var header = document.querySelector(".site-header");
  var button = header && header.querySelector(".menu-btn");
  if (!button) return;
  function set(open) {
    header.classList.toggle("open", open);
    button.setAttribute("aria-expanded", String(open));
  }
  button.addEventListener("click", function () { set(!header.classList.contains("open")); });
  header.addEventListener("click", function (event) {
    if (event.target.closest && event.target.closest(".mnav-link")) set(false);
  });
  document.addEventListener("keydown", function (event) { if (event.key === "Escape") set(false); });
  window.addEventListener("resize", function () { if (window.innerWidth > 920) set(false); });
})();

// Long documents: reading progress, the section you are in, and a way back to the top.
(function () {
  var bar = document.querySelector(".read-progress");
  var top = document.querySelector(".to-top");
  if (!bar && !top) return;
  function visibleLinks() {
    var lang = document.documentElement.getAttribute("data-lang");
    return Array.prototype.slice.call(document.querySelectorAll('.pp-side[data-l="' + lang + '"] a[href^="#"]'));
  }
  function update() {
    var doc = document.documentElement;
    var max = doc.scrollHeight - window.innerHeight;
    var y = window.scrollY || doc.scrollTop;
    if (bar) bar.style.width = (max > 0 ? Math.min(100, (y / max) * 100) : 0) + "%";
    if (top) top.classList.toggle("show", y > 900);
    var links = visibleLinks();
    var current = null;
    for (var i = 0; i < links.length; i++) {
      var target = document.getElementById(links[i].getAttribute("href").slice(1));
      if (target && target.getBoundingClientRect().top < 140) current = links[i];
    }
    for (var j = 0; j < links.length; j++) links[j].classList.toggle("active", links[j] === (current || links[0]));
  }
  window.addEventListener("scroll", update, { passive: true });
  window.addEventListener("resize", update);
  document.addEventListener("minor:lang", function () { setTimeout(update, 0); });
  document.addEventListener("click", function (event) {
    var link = event.target.closest && event.target.closest(".pp-toc-mobile a");
    if (link) link.closest("details").removeAttribute("open");
  });
  update();
})();
