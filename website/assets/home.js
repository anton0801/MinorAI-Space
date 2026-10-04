// The home page: the live map in the first screen, the three scenes and the example maps.
(function () {
  var html = document.documentElement;
  var reduce = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var NS = "http://www.w3.org/2000/svg";
  var CHECK = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>';
  var BELL = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 16v-5a6 6 0 0 1 12 0v5l2 2H4z"/><path d="M10 20a2 2 0 0 0 4 0"/></svg>';

  function lang() { return html.getAttribute("data-lang") === "ru" ? "ru" : "en"; }
  function tx(v) { return v == null ? "" : typeof v === "string" ? v : v[lang()]; }
  function T(en, ru) { return { en: en, ru: ru }; }

  // ---------- A small mind map: nodes, layout, connectors ----------
  // A node: { t, color, side: "l" | "r", task: "todo" | "done", due, soon, c: [children] }

  function prepare(data) {
    var list = [];
    (function walk(d, parent, depth) {
      var n = { d: d, parent: parent, depth: depth, kids: [], i: list.length };
      n.color = d.color || (parent && parent.depth > 0 ? parent.color : "white");
      n.side = d.side || (parent && parent.depth > 0 ? parent.side : "r");
      list.push(n);
      if (parent) parent.kids.push(n);
      (d.c || []).forEach(function (c) { walk(c, n, depth + 1); });
    })(data, null, 0);
    return list;
  }

  function fill(n) {
    var el = n.el;
    el.innerHTML = "";
    if (n.d.task) {
      var c = document.createElement("span");
      c.className = "chk" + (n.d.task === "done" ? " done" : "");
      c.innerHTML = CHECK;
      el.appendChild(c);
    }
    var s = document.createElement("span");
    s.textContent = tx(n.d.t);
    el.appendChild(s);
    if (n.d.due) {
      var d = document.createElement("span");
      d.className = "due" + (n.d.soon ? " soon" : "");
      d.innerHTML = BELL;
      d.appendChild(document.createTextNode(tx(n.d.due)));
      el.appendChild(d);
    }
  }

  function createMap(layer, data, interactive) {
    layer.innerHTML = "";
    var inner = document.createElement("div");
    inner.className = "map-layer";
    layer.appendChild(inner);
    var svg = document.createElementNS(NS, "svg");
    svg.setAttribute("class", "mlinks");
    inner.appendChild(svg);
    var list = prepare(data);
    list.forEach(function (n) {
      if (n.parent) {
        n.link = document.createElementNS(NS, "path");
        n.link.setAttribute("class", "mlink lv" + Math.min(n.depth, 3) + " c-" + n.color);
        svg.appendChild(n.link);
      }
      n.el = document.createElement("div");
      n.el.className = "mnode lv" + Math.min(n.depth, 3) + " c-" + n.color + (n.d.task === "done" ? " is-done" : "");
      if (interactive) {
        n.el.tabIndex = 0;
        n.el.setAttribute("role", "button");
      }
      n.el._node = n;
      fill(n);
      inner.appendChild(n.el);
    });
    return { list: list, inner: inner, svg: svg };
  }

  function subtreeH(n, opt) {
    if (!n.kids.length) return n.h;
    var sum = 0;
    n.kids.forEach(function (k, i) { sum += subtreeH(k, opt) + (i ? opt.gap(k.depth) : 0); });
    return Math.max(n.h, sum);
  }

  function placeKids(n, kids, dir, opt) {
    var total = 0;
    kids.forEach(function (k, i) { total += subtreeH(k, opt) + (i ? opt.gap(k.depth) : 0); });
    var y = n.cy - total / 2;
    kids.forEach(function (k, i) {
      if (i) y += opt.gap(k.depth);
      var h = subtreeH(k, opt);
      k.cy = y + h / 2;
      k.dir = dir;
      k.x = dir > 0 ? n.x + n.w + opt.dx(k.depth) : n.x - opt.dx(k.depth) - k.w;
      y += h;
      placeKids(k, k.kids, dir, opt);
    });
  }

  function bounds(list) {
    var b = { minX: Infinity, minY: Infinity, maxX: -Infinity, maxY: -Infinity };
    list.forEach(function (n) {
      b.minX = Math.min(b.minX, n.x); b.maxX = Math.max(b.maxX, n.x + n.w);
      b.minY = Math.min(b.minY, n.y); b.maxY = Math.max(b.maxY, n.y + n.h);
    });
    b.w = b.maxX - b.minX; b.h = b.maxY - b.minY;
    return b;
  }

  // mode: "balanced" (root in the middle), "tree" (root on the left) or "list" (an indented outline).
  function layout(view, mode, opt) {
    var list = view.list;
    list.forEach(function (n) { n.w = n.el.offsetWidth; n.h = n.el.offsetHeight; });
    var r = list[0];
    if (mode === "list") {
      var y = 0;
      list.forEach(function (n) {
        n.x = n.depth * opt.indent; n.y = y; n.cy = y + n.h / 2; n.dir = 1;
        y += n.h + opt.rowGap;
      });
    } else {
      r.x = mode === "balanced" ? -r.w / 2 : 0;
      r.cy = 0;
      if (mode === "balanced") {
        placeKids(r, r.kids.filter(function (k) { return k.side !== "l"; }), 1, opt);
        placeKids(r, r.kids.filter(function (k) { return k.side === "l"; }), -1, opt);
      } else {
        placeKids(r, r.kids, 1, opt);
      }
      list.forEach(function (n) { n.y = n.cy - n.h / 2; });
    }
    return bounds(list);
  }

  function linkPath(p, c, mode) {
    if (mode === "list") {
      var x0 = p.x + 12, y0 = p.y + p.h, y1 = c.cy, r = 8;
      return "M" + x0 + "," + y0 + " V" + (y1 - r) + " Q" + x0 + "," + y1 + " " + (x0 + r) + "," + y1 + " H" + c.x;
    }
    var sx = c.dir > 0 ? p.x + p.w : p.x;
    var ex = c.dir > 0 ? c.x : c.x + c.w;
    var mx = (sx + ex) / 2;
    return "M" + sx + "," + p.cy + " C" + mx + "," + p.cy + " " + mx + "," + c.cy + " " + ex + "," + c.cy;
  }

  // Moves everything by (ox, oy) and draws the connectors. Shown nodes stay shown.
  function apply(view, mode, ox, oy) {
    view.inner.classList.add("no-anim");
    view.list.forEach(function (n) {
      n.x += ox; n.y += oy; n.cy += oy;
      n.el.style.setProperty("--x", Math.round(n.x) + "px");
      n.el.style.setProperty("--y", Math.round(n.y) + "px");
      if (n.link) {
        n.link.setAttribute("d", linkPath(n.parent, n, mode));
        var len = n.link.getTotalLength();
        n.link.style.strokeDasharray = len;
        n.link.style.strokeDashoffset = n.shown ? 0 : len;
      }
    });
    void view.inner.offsetWidth;
    view.inner.classList.remove("no-anim");
  }

  function show(n, on) {
    n.shown = on !== false;
    n.el.classList.toggle("on", n.shown);
    if (n.link) n.link.style.strokeDashoffset = n.shown ? 0 : n.link.getTotalLength();
  }

  function descendants(n) {
    var out = [n];
    n.kids.forEach(function (k) { out = out.concat(descendants(k)); });
    return out;
  }

  // The app's branch highlight: the idea, everything under it and the lines to them pulse a few times.
  function pulseBranch(n) {
    descendants(n).forEach(function (m) {
      var delay = (m.depth - n.depth) * 0.14 + "s";
      [m.el, m.link].forEach(function (el) {
        if (!el) return;
        el.style.setProperty("--d", delay);
        el.classList.remove("pulse");
        void el.getBoundingClientRect();
        el.classList.add("pulse");
      });
      if (m.link) m.link.classList.add("hot");
    });
  }

  function clearSelection(view) {
    view.list.forEach(function (m) {
      m.el.classList.remove("sel", "pulse", "thinking");
      m.el.removeAttribute("aria-pressed");
      if (m.link) m.link.classList.remove("hot", "pulse");
    });
  }

  function Timers() { this.ids = []; }
  Timers.prototype.at = function (ms, fn) { this.ids.push(setTimeout(fn, ms)); };
  Timers.prototype.clear = function () { this.ids.forEach(clearTimeout); this.ids = []; };

  // ---------- The live map in the first screen ----------
  var HERO = { t: T("Launch my project", "Запустить свой проект"), c: [
    { t: T("Audience", "Аудитория"), color: "mint", side: "l", c: [{ t: T("Students", "Студенты") }, { t: T("Freelancers", "Фрилансеры") }] },
    { t: T("Product", "Продукт"), color: "violet", side: "l", c: [{ t: "MVP" }, { t: T("Pricing", "Цены") }] },
    { t: T("Launch", "Запуск"), color: "pink", side: "r", c: [{ t: T("Beta test", "Бета-тест") }, { t: T("Press kit", "Пресс-кит") }, { t: T("Launch day", "День запуска") }] },
  ] };

  (function hero() {
    var stage = document.getElementById("stage");
    if (!stage) return;
    var layer = stage.querySelector(".map-layer");
    var phone = stage.querySelector(".phone");
    var typed = stage.querySelector(".typed");
    var field = stage.querySelector(".field");
    var title = stage.querySelector(".mt-title");
    var sub = stage.querySelector(".mt-sub");
    var replay = stage.querySelector(".replay");
    var timers = new Timers();
    var view = createMap(layer, HERO, false);
    var mode = "balanced";
    var count = 8;
    var played = false, playing = false;

    function subtitle() {
      sub.textContent = lang() === "ru" ? "Узлов: " + count + " · Сохранено" : count + " nodes · Saved";
      title.textContent = tx(HERO.t);
    }

    function relayout() {
      var s = stage.getBoundingClientRect();
      var p = phone.getBoundingClientRect();
      var px = p.left - s.left, py = p.top - s.top;
      var inner = view.inner;
      inner.style.transform = "";
      var wide = window.innerWidth > 760;
      inner.classList.toggle("sm", !wide);
      var b, ox, oy;
      view.scale = 1; view.origin = [0, 0];
      if (wide) {
        mode = "balanced";
        b = layout(view, mode, { dx: function (d) { return d === 1 ? 86 : 52; }, gap: function (d) { return d === 1 ? 30 : 10; } });
        ox = px + p.width / 2; oy = py + p.height * 0.47;
        if (b.minX + ox < 4 || b.maxX + ox > s.width - 4) wide = false;
      }
      if (!wide) {
        inner.classList.add("sm");
        mode = "tree";
        b = layout(view, mode, { dx: function (d) { return d === 1 ? 16 : 13; }, gap: function (d) { return d === 1 ? 12 : 5; } });
        var left = px + 9 + 10, right = px + p.width - 9 - 10;
        ox = left; oy = py + p.height * 0.47;
        var scale = Math.min(1, (right - left) / b.w);
        if (scale < 1) {
          inner.style.transformOrigin = ox + "px " + oy + "px";
          inner.style.transform = "scale(" + scale.toFixed(3) + ")";
        }
        view.scale = scale; view.origin = [ox, oy];
      }
      apply(view, mode, ox, oy);
    }

    function reset() {
      timers.clear();
      stage.classList.remove("s-map", "s-select", "typing", "ready", "press", "tap-expand");
      clearSelection(view);
      view.list.forEach(function (n) { show(n, false); });
      typed.textContent = "";
      count = 8;
      subtitle();
      replay.hidden = true;
    }

    function finalState() {
      reset();
      stage.classList.add("s-map");
      view.list.forEach(function (n) { show(n, true); });
      count = 11;
      subtitle();
      view.list[7].el.classList.add("sel");
      descendants(view.list[7]).forEach(function (m) { if (m.link) m.link.classList.add("hot"); });
    }

    function flyRoot() {
      var r = view.list[0];
      var s = stage.getBoundingClientRect(), f = field.getBoundingClientRect();
      var el = r.el;
      // The layer may be scaled down on a phone: convert the field's position into its coordinates.
      var k = view.scale || 1, o = view.origin || [0, 0];
      var fx = o[0] + (f.left - s.left - o[0]) / k, fy = o[1] + (f.top - s.top - 4 - o[1]) / k;
      el.style.transition = "none";
      el.style.transform = "translate(" + fx + "px," + fy + "px) scale(.7)";
      el.style.opacity = ".3";
      void el.offsetWidth;
      el.style.transition = "";
      el.style.transform = "";
      el.style.opacity = "";
      show(r, true);
    }

    function play() {
      if (reduce) { finalState(); return; }
      reset();
      playing = true;
      played = true;
      var text = tx(HERO.t);
      var t = 350;
      timers.at(t, function () { stage.classList.add("typing"); });
      t += 350;
      for (var i = 1; i <= text.length; i++) {
        (function (k) { timers.at(t + k * 58, function () { typed.textContent = text.slice(0, k); }); })(i);
      }
      t += text.length * 58 + 250;
      timers.at(t, function () { stage.classList.add("ready"); });
      timers.at(t + 420, function () { stage.classList.add("press"); });
      t += 640;
      timers.at(t, function () {
        stage.classList.remove("press", "typing");
        stage.classList.add("s-map");
        flyRoot();
      });
      t += 700;
      [1, 4, 7].forEach(function (i, k) { timers.at(t + k * 160, function () { show(view.list[i], true); }); });
      [2, 3, 5, 6].forEach(function (i, k) { timers.at(t + 650 + k * 110, function () { show(view.list[i], true); }); });
      var launch = view.list[7];
      t += 2000;
      timers.at(t, function () {
        stage.classList.add("s-select");
        launch.el.classList.add("sel");
        pulseBranch(launch);
      });
      t += 1250;
      timers.at(t, function () { stage.classList.add("tap-expand"); });
      timers.at(t + 260, function () { stage.classList.remove("tap-expand"); launch.el.classList.add("thinking"); });
      t += 1100;
      timers.at(t, function () { launch.el.classList.remove("thinking"); });
      [8, 9, 10].forEach(function (i, k) {
        timers.at(t + k * 170, function () {
          show(view.list[i], true);
          count = 9 + k;
          subtitle();
        });
      });
      t += 900;
      timers.at(t, function () { pulseBranch(launch); });
      t += 2900;
      timers.at(t, function () {
        stage.classList.remove("s-select");
        view.list.forEach(function (m) { m.el.classList.remove("pulse"); if (m.link) m.link.classList.remove("pulse"); });
        replay.hidden = false;
        playing = false;
      });
    }

    subtitle();
    relayout();
    if (reduce) finalState();

    replay.addEventListener("click", play);
    var cta = document.querySelector("[data-play]");
    if (cta) cta.addEventListener("click", function (event) {
      event.preventDefault();
      var r = stage.getBoundingClientRect();
      var visible = r.top >= 0 && r.bottom <= window.innerHeight + 40;
      if (!visible) stage.scrollIntoView({ behavior: reduce ? "auto" : "smooth", block: "center" });
      setTimeout(play, visible ? 0 : 450);
    });

    if ("IntersectionObserver" in window && !reduce) {
      var io = new IntersectionObserver(function (entries) {
        entries.forEach(function (e) { if (e.isIntersecting && !played) { play(); io.disconnect(); } });
      }, { threshold: 0.9 });
      // Start when the input field is on screen, so the typing isn't missed.
      io.observe(stage.querySelector(".composer"));
    } else if (!reduce) {
      play();
    }

    var resizeTimer;
    window.addEventListener("resize", function () {
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(relayout, 120);
    });
    document.addEventListener("minor:lang", function () {
      view.list.forEach(fill);
      subtitle();
      relayout();
      if (playing) play();
    });
  })();

  // ---------- The three scenes ----------
  (function scenes() {
    var list = document.querySelectorAll("[data-scene]");
    if (!list.length) return;

    function draw(scene) {
      var maps = scene.querySelectorAll(".mm");
      for (var m = 0; m < maps.length; m++) {
        var mm = maps[m], svg = mm.querySelector(".mm-links");
        var base = mm.getBoundingClientRect();
        svg.innerHTML = "";
        var kids = mm.querySelectorAll("[data-parent]");
        for (var i = 0; i < kids.length; i++) {
          var child = kids[i], parent = document.getElementById(child.getAttribute("data-parent"));
          if (!parent || !child.offsetParent || !parent.offsetParent) continue;
          // Positions without the entrance transform, so the lines meet the nodes where they land.
          var p = { x: parent.offsetLeft, y: parent.offsetTop, w: parent.offsetWidth, h: parent.offsetHeight };
          var c = { x: child.offsetLeft, y: child.offsetTop, w: child.offsetWidth, h: child.offsetHeight };
          var d;
          if (c.x > p.x + p.w - 4) {
            var sx = p.x + p.w, sy = p.y + p.h / 2, ex = c.x, ey = c.y + c.h / 2, mx = (sx + ex) / 2;
            d = "M" + sx + "," + sy + " C" + mx + "," + sy + " " + mx + "," + ey + " " + ex + "," + ey;
          } else {
            var x0 = p.x + 12, y0 = p.y + p.h, y1 = c.y + c.h / 2;
            d = "M" + x0 + "," + y0 + " V" + (y1 - 8) + " Q" + x0 + "," + y1 + " " + (x0 + 8) + "," + y1 + " H" + c.x;
          }
          var path = document.createElementNS(NS, "path");
          path.setAttribute("d", d);
          var color = (child.className.match(/c-[a-z]+/) || ["c-white"])[0];
          path.setAttribute("class", color + (child.classList.contains("new") ? " new" : ""));
          svg.appendChild(path);
          var len = path.getTotalLength();
          path.style.strokeDasharray = len;
          var delay = parseFloat(getComputedStyle(child).transitionDelay) || 0;
          path.style.transitionDelay = Math.max(0, delay - 0.2) + "s";
          var visible = scene.classList.contains("in") && (!child.classList.contains("new") || scene.classList.contains("grown"));
          path.style.strokeDashoffset = visible ? 0 : len;
        }
        void base;
      }
    }

    function reveal(scene) {
      var paths = scene.querySelectorAll(".mm-links path");
      for (var i = 0; i < paths.length; i++) {
        var p = paths[i];
        if (!p.classList.contains("new") || scene.classList.contains("grown")) p.style.strokeDashoffset = 0;
      }
    }

    function start(scene) {
      if (scene.classList.contains("in")) return;
      scene.classList.add("in");
      reveal(scene);
      if (reduce) {
        scene.classList.add("grown", "checked", "toasted");
        draw(scene);
        return;
      }
      if (scene.querySelector(".sv-deeper")) {
        setTimeout(function () { scene.classList.add("tapped"); }, 1700);
        setTimeout(function () { scene.classList.remove("tapped"); scene.classList.add("grown"); reveal(scene); }, 2000);
      }
      if (scene.querySelector(".sv-act")) {
        setTimeout(function () { scene.classList.add("checked"); }, 2600);
        setTimeout(function () { scene.classList.add("toasted"); }, 3300);
      }
    }

    function drawAll() { for (var i = 0; i < list.length; i++) draw(list[i]); }
    drawAll();

    if ("IntersectionObserver" in window) {
      var io = new IntersectionObserver(function (entries) {
        entries.forEach(function (e) { if (e.isIntersecting) { start(e.target); io.unobserve(e.target); } });
      }, { threshold: 0.35 });
      for (var i = 0; i < list.length; i++) io.observe(list[i]);
    } else {
      for (var j = 0; j < list.length; j++) start(list[j]);
    }

    var timer;
    window.addEventListener("resize", function () { clearTimeout(timer); timer = setTimeout(drawAll, 120); });
    document.addEventListener("minor:lang", function () { setTimeout(drawAll, 0); });
  })();

  // ---------- Example maps ----------
  var EXAMPLES = {
    exam: { t: T("Biology exam", "Экзамен по биологии"), c: [
      { t: T("The cell", "Клетка"), color: "mint", side: "r", c: [{ t: T("Organelles", "Органоиды") }, { t: T("Membrane", "Мембрана") }, { t: T("Cell division", "Деление клетки") }] },
      { t: T("Genetics", "Генетика"), color: "violet", side: "r", c: [{ t: T("Mendel’s laws", "Законы Менделя") }, { t: T("DNA and RNA", "ДНК и РНК") }] },
      { t: T("Photosynthesis", "Фотосинтез"), color: "sun", side: "l", c: [{ t: T("Light reactions", "Световая фаза") }, { t: T("Calvin cycle", "Цикл Кальвина") }] },
      { t: T("Study plan", "План подготовки"), color: "sky", side: "l", c: [
        { t: T("Lecture notes", "Конспект лекций"), task: "done" },
        { t: T("Review flashcards", "Повторить карточки"), task: "todo", due: T("Today", "Сегодня"), soon: true },
        { t: T("Practice test", "Пробный тест"), task: "todo", due: T("Fri", "Пт") }] },
    ] },
    launch: { t: T("App launch", "Запуск приложения"), c: [
      { t: T("Audience", "Аудитория"), color: "mint", side: "r", c: [{ t: T("Students", "Студенты") }, { t: T("Freelancers", "Фрилансеры") }, { t: T("Small teams", "Небольшие команды") }] },
      { t: T("Product", "Продукт"), color: "violet", side: "r", c: [{ t: "MVP" }, { t: T("Onboarding", "Онбординг") }, { t: T("Pricing", "Цены") }] },
      { t: T("Marketing", "Маркетинг"), color: "pink", side: "l", c: [{ t: "Product Hunt" }, { t: T("Blog", "Блог") }, { t: T("Newsletter", "Рассылка") }] },
      { t: T("Launch", "Запуск"), color: "sun", side: "l", c: [
        { t: T("Beta test", "Бета-тест"), task: "done" },
        { t: T("Press kit", "Пресс-кит"), task: "todo", due: T("Today", "Сегодня"), soon: true },
        { t: T("Launch day", "День запуска"), task: "todo", due: T("Nov 14", "14 нояб.") }] },
    ] },
    lang: { t: T("Spanish in 3 months", "Испанский за 3 месяца"), c: [
      { t: T("Grammar", "Грамматика"), color: "violet", side: "r", c: [{ t: T("Ser vs estar", "Ser и estar") }, { t: T("Past tenses", "Прошедшие времена") }, { t: T("Subjunctive", "Сослагательное наклонение") }] },
      { t: T("Vocabulary", "Словарь"), color: "mint", side: "r", c: [{ t: T("Food", "Еда") }, { t: T("Travel", "Путешествия") }, { t: T("Work", "Работа") }] },
      { t: T("Practice", "Практика"), color: "sky", side: "l", c: [{ t: T("Conversation club", "Разговорный клуб") }, { t: T("Podcasts", "Подкасты") }, { t: T("Shows with subtitles", "Сериалы с субтитрами") }] },
      { t: T("Goals", "Цели"), color: "coral", side: "l", c: [
        { t: T("20 words a day", "20 слов в день"), task: "todo", due: T("Daily", "Каждый день"), soon: true },
        { t: T("A2 test", "Тест A2"), task: "todo", due: T("Dec 20", "20 дек.") }] },
    ] },
  };

  (function examples() {
    var canvas = document.querySelector(".ex-canvas");
    if (!canvas) return;
    var layer = canvas.querySelector(".map-layer");
    var tabs = document.querySelectorAll("[data-ex]");
    var stats = document.querySelector(".ex-stats");
    var timers = new Timers();
    var key = "exam", view = null, mode = "balanced";

    function relayout() {
      var W = canvas.clientWidth, pad = 20;
      var opts = { dx: function (d) { return d === 1 ? 46 : 30; }, gap: function (d) { return d === 1 ? 20 : 9; }, indent: 22, rowGap: 8 };
      var b;
      mode = "balanced";
      b = layout(view, mode, opts);
      if (b.w > W - pad * 2) { mode = "tree"; b = layout(view, mode, opts); }
      if (b.w > W - pad * 2) { mode = "list"; b = layout(view, mode, opts); }
      var H = Math.max(mode === "list" ? 0 : 440, b.h + pad * 2);
      canvas.style.height = H + "px";
      var ox = mode === "list" ? pad - b.minX : (W - b.w) / 2 - b.minX;
      var oy = (H - b.h) / 2 - b.minY;
      apply(view, mode, ox, oy);
    }

    function updateStats() {
      var n = view.list.length;
      var tasks = view.list.filter(function (m) { return m.d.task; }).length;
      stats.textContent = lang() === "ru" ? "Идей: " + n + " · задач: " + tasks : n + " ideas · " + tasks + " tasks";
    }

    function select(n) {
      var again = n && n.el.classList.contains("sel");
      clearSelection(view);
      if (!n || again) return;
      n.el.classList.add("sel");
      n.el.setAttribute("aria-pressed", "true");
      pulseBranch(n);
    }

    function render(next, animate) {
      key = next;
      timers.clear();
      view = createMap(layer, EXAMPLES[key], true);
      relayout();
      updateStats();
      if (!animate || reduce) {
        view.list.forEach(function (n) { show(n, true); });
        return;
      }
      view.list.forEach(function (n) {
        timers.at(80 + n.depth * 220 + n.i * 28, function () { show(n, true); });
      });
    }

    for (var i = 0; i < tabs.length; i++) {
      tabs[i].addEventListener("click", function () {
        var next = this.getAttribute("data-ex");
        for (var j = 0; j < tabs.length; j++) tabs[j].setAttribute("aria-selected", String(tabs[j] === this));
        if (next !== key) render(next, true);
      });
    }
    layer.addEventListener("click", function (event) {
      var el = event.target.closest && event.target.closest(".mnode");
      select(el ? el._node : null);
    });
    layer.addEventListener("keydown", function (event) {
      if (event.key !== "Enter" && event.key !== " ") return;
      var el = event.target.closest && event.target.closest(".mnode");
      if (!el) return;
      event.preventDefault();
      select(el._node);
    });

    render(key, false);
    var shown = false;
    view.list.forEach(function (n) { show(n, false); });
    if ("IntersectionObserver" in window && !reduce) {
      var io = new IntersectionObserver(function (entries) {
        entries.forEach(function (e) { if (e.isIntersecting && !shown) { shown = true; render(key, true); io.disconnect(); } });
      }, { threshold: 0.3 });
      io.observe(canvas);
    } else {
      view.list.forEach(function (n) { show(n, true); });
    }

    var timer;
    window.addEventListener("resize", function () { clearTimeout(timer); timer = setTimeout(relayout, 120); });
    document.addEventListener("minor:lang", function () {
      view.list.forEach(fill);
      relayout();
      updateStats();
    });
  })();
})();
