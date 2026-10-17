"""App Store screenshots for Minor AI 3.0.1: English (US), German and Spanish (Spain).

Lays out the fresh app captures (raw/ from scenes.txt; raw-de/, raw-es/ from scenes-intl.txt with
-campaignLang de|es) as 1320 x 2868 frames in three styles and renders them with headless Chromium.
The app's own interface is English in every language; the examples and the captions are translated.

  A  pastel, after the reference board: wordmark, keyword line, two-line headline, phone
  B  dark, in the app's own colors, centered type and a soft glow
  C  light editorial: headline, phone, and the key part of the screen enlarged beside it

  python3 build.py                     every English set -> final/
  python3 build.py --locale de         every German set   -> final-de/
  python3 build.py --locale es main-a  one Spanish set    -> final-es/
  python3 build.py --boards            only the overview boards
"""
from pathlib import Path
import json, subprocess, sys

ROOT = Path(__file__).resolve().parent
LOCALE = sys.argv[sys.argv.index('--locale') + 1] if '--locale' in sys.argv else 'en'
SUFFIX = '' if LOCALE == 'en' else f'-{LOCALE}'
RAW = ROOT / f'raw{SUFFIX}'
OUT = ROOT / f'final{SUFFIX}'
HTML = ROOT / 'layouts'
CHROME = Path.home() / 'Library/Caches/ms-playwright/chromium_headless_shell-1243/chrome-headless-shell-mac-arm64/chrome-headless-shell'
W, H = 1320, 2868
SHOT_W, SHOT_H = 1179, 2556

# Copy for every frame. scene: raw capture; tone: color family; zoom: part of the screen
# (capture pixels) enlarged in style C.
FRAMES = {
    # Default product page
    'main-map': dict(scene='map-travel', tone='mint', eyebrow='AI MIND MAPS · SLIDES · STUDY',
                     h1=['Your ideas,', 'mapped by AI.'], detail='Plan trips, projects and classes — anything.',
                     zoom=(400, 560, 1179, 1180)),
    'main-chat': dict(scene='chat-travel', tone='lilac', eyebrow='YOUR AI ASSISTANT',
                      h1=['Just ask.', 'Get a map.'], detail='Describe what you need. Minor builds the map.',
                      zoom=(36, 826, 1143, 1790)),
    'main-sources': dict(scene='newmap', tone='blue', eyebrow='PDF · LINKS · YOUTUBE · VOICE',
                         h1=['Start from', 'anything.'], detail='A topic, a document, a video or a photo of your notes.',
                         zoom=(30, 1160, 1150, 1965)),
    'main-improve': dict(scene='proposal-travel', tone='mint', eyebrow='AI BRAINSTORMING',
                         h1=['Stuck? AI', 'adds ideas.'], detail='Review every suggestion before it’s added.',
                         zoom=(30, 1330, 1150, 2085)),
    'main-slides': dict(scene='deck-diagram', tone='lilac', eyebrow='AI PRESENTATION MAKER',
                        h1=['Map today.', 'Slides next.'], detail='Edit every slide. Export to PowerPoint or PDF.',
                        zoom=(30, 370, 1150, 1010)),
    'main-study': dict(scene='card-back', tone='blue', eyebrow='FLASHCARDS & QUIZZES',
                       h1=['Study what', 'matters.'], detail='Cards and quizzes made from your own maps.',
                       zoom=(30, 1880, 1150, 2440)),
    'main-today': dict(scene='today', tone='sand', eyebrow='TASKS & REMINDERS',
                       h1=['Ideas into', 'action.'], detail='Tasks from every map, together in Today.',
                       zoom=(30, 1225, 1150, 2112)),
    'main-present': dict(scene='presenter', tone='lilac', eyebrow='PRESENTER MODE',
                         h1=['Your notes.', 'Right on cue.'], detail='Your slide, your notes and what comes next.',
                         zoom=(30, 1390, 1150, 1850)),

    # Custom product page: Mind maps
    'maps-hero': dict(scene='map-travel', tone='mint', eyebrow='AI MIND MAP MAKER',
                      h1=['Mind maps.', 'Made with AI.'], detail='Turn any idea into a clear, editable map.'),
    'maps-sources': dict(scene='newmap', tone='mint', eyebrow='FROM YOUR OWN MATERIAL',
                         h1=['Start from', 'anything.'], detail='A topic, PDF, link, YouTube video or voice note.'),
    'maps-improve': dict(scene='proposal-travel', tone='mint', eyebrow='AI BRAINSTORMING',
                         h1=['Ask AI for', 'more ideas.'], detail='Review every suggestion before it’s added.'),
    'maps-panel': dict(scene='selected-travel', tone='mint', eyebrow='NOTES · TASKS · LINKS',
                       h1=['Every idea,', 'one tap away.'], detail='Add notes, tasks and links to any idea.'),
    'maps-design': dict(scene='mapdesign-travel', tone='mint', eyebrow='STYLES & THEMES',
                        h1=['Make it', 'yours.'], detail='Pick a style, a palette and a layout.'),

    # Custom product page: Study
    'study-hero': dict(scene='card-back', tone='blue', eyebrow='FLASHCARDS FROM YOUR NOTES',
                       h1=['Turn notes into', 'study cards.'], detail='Review with spaced repetition.'),
    'study-map': dict(scene='map-study', tone='blue', eyebrow='VISUAL STUDY NOTES',
                      h1=['See how ideas', 'connect.'], detail='A whole chapter as one clear map.'),
    'study-quiz': dict(scene='quiz', tone='blue', eyebrow='AI QUIZ MAKER',
                       h1=['Quiz yourself.', 'Learn why.'], detail='Every answer comes with an explanation.'),
    'study-pdf': dict(scene='sources-study', tone='blue', eyebrow='PDF & LECTURE NOTES',
                      h1=['Drop in your', 'lecture PDF.'], detail='Ideas link back to the page they came from.'),
    'study-result': dict(scene='quiz-result', tone='blue', eyebrow='TRACK YOUR PROGRESS',
                         h1=['Know what', 'to review.'], detail='See your score. Repeat your mistakes.'),

    # Custom product page: Presentations
    'slides-hero': dict(scene='deck-diagram', tone='lilac', eyebrow='AI PRESENTATION MAKER',
                        h1=['From idea', 'to slide deck.'], detail='Turn a mind map into editable slides.'),
    'slides-themes': dict(scene='themes', tone='lilac', eyebrow='THEMES & STYLES',
                          h1=['One tap.', 'A new look.'], detail='Change the theme, palette and fonts.'),
    'slides-present': dict(scene='presenter', tone='lilac', eyebrow='PRESENTER MODE',
                           h1=['Your notes.', 'Right on cue.'], detail='See your slide, notes and what’s next.'),
    'slides-export': dict(scene='export', tone='lilac', eyebrow='POWERPOINT & PDF EXPORT',
                          h1=['Take it to', 'PowerPoint.'], detail='Export a .pptx or PDF when you’re ready.'),
    'slides-templates': dict(scene='templates-decks', tone='lilac', eyebrow='SLIDE TEMPLATES',
                             h1=['Start from', 'a template.'], detail='Pitch decks, lectures and more.'),

    # Custom product page: Tasks
    'tasks-hero': dict(scene='today', tone='sand', eyebrow='TASKS FROM YOUR MIND MAPS',
                       h1=['Turn ideas', 'into action.'], detail='Every task from every map, in Today.'),
    'tasks-plan': dict(scene='planday', tone='sand', eyebrow='AI DAY PLANNER',
                       h1=['Plan your day', 'with AI.'], detail='Minor builds a schedule around your tasks.'),
    'tasks-next': dict(scene='nextsteps', tone='sand', eyebrow='NEXT STEPS',
                       h1=['Know what', 'to do next.'], detail='AI turns a branch into clear tasks.'),
    'tasks-dates': dict(scene='task', tone='sand', eyebrow='DUE DATES & REMINDERS',
                        h1=['Dates and', 'reminders.'], detail='Set a time. Get a reminder.'),
    'tasks-map': dict(scene='selected-podcast', tone='sand', eyebrow='VISUAL PROJECT PLANNER',
                      h1=['See the plan.', 'Do the work.'], detail='Tasks stay linked to the ideas behind them.'),
}

# German (de-DE, informal "du") and Spanish (es-ES, "tú"): eyebrow, headline, detail per frame.
COPY = {
    'de': {
        'main-map': ('KI-MINDMAPS · FOLIEN · LERNEN', ['Deine Ideen.', 'Als KI-Mindmap.'], 'Reisen, Projekte, Lernstoff – alles auf einer Karte.'),
        'main-chat': ('DEIN KI-ASSISTENT', ['Einfach fragen.', 'Karte bekommen.'], 'Beschreib, was du brauchst. Minor baut die Karte.'),
        'main-sources': ('PDF · LINKS · YOUTUBE · SPRACHE', ['Aus allem', 'wird eine Karte.'], 'Ein Thema, ein Dokument, ein Video oder ein Foto deiner Notizen.'),
        'main-improve': ('KI-BRAINSTORMING', ['Keine Idee?', 'Die KI hilft.'], 'Du prüfst jeden Vorschlag, bevor er dazukommt.'),
        'main-slides': ('KI-PRÄSENTATIONEN', ['Erst die Karte.', 'Dann die Folien.'], 'Jede Folie bearbeiten. Als PowerPoint oder PDF exportieren.'),
        'main-study': ('KARTEIKARTEN & QUIZ', ['Lerne, was', 'wirklich zählt.'], 'Karteikarten und Quiz aus deinen eigenen Karten.'),
        'main-today': ('AUFGABEN & ERINNERUNGEN', ['Von der Idee', 'zur Aufgabe.'], 'Aufgaben aus allen Karten – gesammelt in „Today“.'),
        'main-present': ('PRÄSENTATIONSMODUS', ['Deine Notizen.', 'Immer im Blick.'], 'Folie, Notizen und was als Nächstes kommt.'),
        'maps-hero': ('KI-MINDMAP-APP', ['Mindmaps.', 'Mit KI erstellt.'], 'Mach aus jeder Idee eine klare, editierbare Karte.'),
        'maps-sources': ('AUS DEINEM MATERIAL', ['Aus allem', 'wird eine Karte.'], 'Thema, PDF, Link, YouTube-Video oder Sprachnotiz.'),
        'maps-improve': ('KI-BRAINSTORMING', ['Mehr Ideen?', 'Frag die KI.'], 'Du prüfst jeden Vorschlag, bevor er dazukommt.'),
        'maps-panel': ('NOTIZEN · AUFGABEN · LINKS', ['Jede Idee,', 'ein Tipp entfernt.'], 'Notizen, Aufgaben und Links für jede Idee.'),
        'maps-design': ('STILE & FARBEN', ['Ganz nach', 'deinem Stil.'], 'Wähle Stil, Farbpalette und Layout.'),
        'study-hero': ('KARTEIKARTEN AUS DEINEN NOTIZEN', ['Aus Notizen', 'werden Lernkarten.'], 'Lernen mit verteilter Wiederholung.'),
        'study-map': ('VISUELLE LERNNOTIZEN', ['Sieh, wie alles', 'zusammenhängt.'], 'Ein ganzes Kapitel auf einer Karte.'),
        'study-quiz': ('KI-QUIZ', ['Teste dich.', 'Versteh, warum.'], 'Zu jeder Antwort gibt es eine Erklärung.'),
        'study-pdf': ('PDF & VORLESUNGSSKRIPT', ['Lade dein', 'Skript als PDF.'], 'Jede Idee verweist auf die Seite, aus der sie stammt.'),
        'study-result': ('DEIN LERNSTAND', ['Wisse, was du', 'wiederholen musst.'], 'Sieh dein Ergebnis und wiederhole deine Fehler.'),
        'slides-hero': ('KI-PRÄSENTATIONEN', ['Von der Idee', 'zur Präsentation.'], 'Aus einer Mindmap werden bearbeitbare Folien.'),
        'slides-themes': ('DESIGNS & STILE', ['Ein Tipp.', 'Ein neuer Look.'], 'Design, Farben und Schriften ändern.'),
        'slides-present': ('PRÄSENTATIONSMODUS', ['Deine Notizen.', 'Immer im Blick.'], 'Folie, Notizen und was als Nächstes kommt.'),
        'slides-export': ('POWERPOINT- & PDF-EXPORT', ['Ab nach', 'PowerPoint.'], 'Als .pptx oder PDF exportieren, wenn du so weit bist.'),
        'slides-templates': ('FOLIENVORLAGEN', ['Starte mit', 'einer Vorlage.'], 'Pitch-Decks, Vorlesungen und mehr.'),
        'tasks-hero': ('AUFGABEN AUS DEINEN MINDMAPS', ['Aus Ideen', 'werden Taten.'], 'Alle Aufgaben aus allen Karten – in „Today“.'),
        'tasks-plan': ('KI-TAGESPLANER', ['Plane deinen Tag', 'mit KI.'], 'Minor plant deinen Tag rund um deine Aufgaben.'),
        'tasks-next': ('NÄCHSTE SCHRITTE', ['Wisse, was', 'als Nächstes kommt.'], 'Die KI macht aus einem Ast klare Aufgaben.'),
        'tasks-dates': ('TERMINE & ERINNERUNGEN', ['Termine und', 'Erinnerungen.'], 'Uhrzeit festlegen. Erinnerung bekommen.'),
        'tasks-map': ('VISUELLE PROJEKTPLANUNG', ['Plan sehen.', 'Loslegen.'], 'Aufgaben bleiben mit ihren Ideen verbunden.'),
    },
    'es': {
        'main-map': ('MAPAS MENTALES · DIAPOSITIVAS · ESTUDIO', ['Tus ideas,', 'en un mapa.'], 'Viajes, proyectos, apuntes: la IA lo ordena todo.'),
        'main-chat': ('TU ASISTENTE CON IA', ['Pídelo.', 'Y ya tienes mapa.'], 'Describe lo que necesitas. Minor crea el mapa.'),
        'main-sources': ('PDF · ENLACES · YOUTUBE · VOZ', ['Empieza con', 'lo que tengas.'], 'Un tema, un documento, un vídeo o una foto de tus apuntes.'),
        'main-improve': ('LLUVIA DE IDEAS CON IA', ['¿Sin ideas?', 'La IA te ayuda.'], 'Revisa cada sugerencia antes de añadirla.'),
        'main-slides': ('CREADOR DE PRESENTACIONES', ['Del mapa', 'a las diapositivas.'], 'Edita cada diapositiva. Exporta a PowerPoint o PDF.'),
        'main-study': ('TARJETAS Y TESTS', ['Estudia lo', 'que importa.'], 'Tarjetas y tests creados a partir de tus mapas.'),
        'main-today': ('TAREAS Y RECORDATORIOS', ['De la idea', 'a la acción.'], 'Las tareas de todos tus mapas, juntas en «Today».'),
        'main-present': ('MODO PRESENTADOR', ['Tus notas,', 'siempre a mano.'], 'Tu diapositiva, tus notas y lo que viene después.'),
        'maps-hero': ('CREADOR DE MAPAS MENTALES CON IA', ['Mapas mentales.', 'Hechos con IA.'], 'Convierte cualquier idea en un mapa claro y editable.'),
        'maps-sources': ('A PARTIR DE TU MATERIAL', ['Empieza con', 'lo que tengas.'], 'Un tema, PDF, enlace, vídeo de YouTube o nota de voz.'),
        'maps-improve': ('LLUVIA DE IDEAS CON IA', ['¿Más ideas?', 'Pídeselas a la IA.'], 'Revisa cada sugerencia antes de añadirla.'),
        'maps-panel': ('NOTAS · TAREAS · ENLACES', ['Cada idea,', 'a un toque.'], 'Añade notas, tareas y enlaces a cualquier idea.'),
        'maps-design': ('ESTILOS Y COLORES', ['Hazlo', 'a tu estilo.'], 'Elige el estilo, la paleta y el diseño.'),
        'study-hero': ('TARJETAS A PARTIR DE TUS APUNTES', ['De tus apuntes', 'a tarjetas.'], 'Repasa con repetición espaciada.'),
        'study-map': ('APUNTES VISUALES', ['Mira cómo', 'se conecta todo.'], 'Un tema entero en un solo mapa.'),
        'study-quiz': ('TESTS CON IA', ['Ponte a prueba.', 'Entiende el porqué.'], 'Cada respuesta viene con su explicación.'),
        'study-pdf': ('PDF Y APUNTES DE CLASE', ['Sube el PDF', 'de tu clase.'], 'Cada idea enlaza con la página de la que sale.'),
        'study-result': ('TU PROGRESO', ['Descubre qué', 'repasar.'], 'Mira tu nota y repasa tus errores.'),
        'slides-hero': ('CREADOR DE PRESENTACIONES CON IA', ['De la idea', 'a la presentación.'], 'Convierte un mapa mental en diapositivas editables.'),
        'slides-themes': ('TEMAS Y ESTILOS', ['Un toque.', 'Otro estilo.'], 'Cambia el tema, los colores y las fuentes.'),
        'slides-present': ('MODO PRESENTADOR', ['Tus notas,', 'siempre a mano.'], 'Tu diapositiva, tus notas y lo que viene después.'),
        'slides-export': ('EXPORTA A POWERPOINT Y PDF', ['Llévalo a', 'PowerPoint.'], 'Exporta en .pptx o PDF cuando quieras.'),
        'slides-templates': ('PLANTILLAS DE DIAPOSITIVAS', ['Empieza con', 'una plantilla.'], 'Presentaciones de empresa, clases y más.'),
        'tasks-hero': ('TAREAS DESDE TUS MAPAS MENTALES', ['Convierte ideas', 'en acciones.'], 'Las tareas de todos tus mapas, en «Today».'),
        'tasks-plan': ('PLANIFICADOR DIARIO CON IA', ['Planifica tu día', 'con IA.'], 'Minor organiza tu día en torno a tus tareas.'),
        'tasks-next': ('PRÓXIMOS PASOS', ['Sabrás qué', 'hacer después.'], 'La IA convierte una rama en tareas claras.'),
        'tasks-dates': ('FECHAS Y RECORDATORIOS', ['Fechas y', 'recordatorios.'], 'Pon una hora y recibe un aviso.'),
        'tasks-map': ('PLANIFICACIÓN VISUAL DE PROYECTOS', ['Ve el plan.', 'Hazlo realidad.'], 'Las tareas siguen unidas a sus ideas.'),
    },
}
TAGLINE = {'en': 'IDEAS INTO ACTION', 'de': 'IDEEN IN AKTION', 'es': 'IDEAS EN ACCIÓN'}
LANGUAGE = {'en': 'English (US)', 'de': 'Deutsch (DE)', 'es': 'Español (España)'}


def frame(key):
    """A frame's layout with its copy in the current language."""
    item = dict(FRAMES[key])
    if LOCALE in COPY:
        item['eyebrow'], item['h1'], item['detail'] = COPY[LOCALE][key]
    return item


MAIN = ['main-map', 'main-chat', 'main-sources', 'main-improve', 'main-slides', 'main-study', 'main-today', 'main-present']
SETS = {
    'main-a': ('A', MAIN),
    'main-b': ('B', MAIN),
    'main-c': ('C', MAIN),
    'cpp-mind-maps': ('A', ['maps-hero', 'maps-sources', 'maps-improve', 'maps-panel', 'maps-design']),
    'cpp-study': ('A', ['study-hero', 'study-map', 'study-quiz', 'study-pdf', 'study-result']),
    'cpp-presentations': ('A', ['slides-hero', 'slides-themes', 'slides-present', 'slides-export', 'slides-templates']),
    'cpp-tasks': ('A', ['tasks-hero', 'tasks-plan', 'tasks-next', 'tasks-dates', 'tasks-map']),
}

# Style A: the reference's pastels. B: glow colors on the app's dark. C: accents on warm white.
PASTEL = {
    'mint':  dict(bg='#C6F8DF', bg2='#E3FCEF', ink='#0F2C22', muted='#43665A', accent='#1C6B49', line='#9ED5BA'),
    'blue':  dict(bg='#D6E9FD', bg2='#ECF5FE', ink='#152F43', muted='#4F6A80', accent='#2F6A93', line='#B1CAE0'),
    'lilac': dict(bg='#E7DDFB', bg2='#F4EFFD', ink='#33214A', muted='#6E5E80', accent='#6B47A0', line='#CDBDE6'),
    'sand':  dict(bg='#F2E6D2', bg2='#FAF4EA', ink='#382D20', muted='#776753', accent='#8A6236', line='#DCCCB2'),
}
GLOW = {'mint': '#38F0A5', 'lilac': '#A07CFF', 'blue': '#5CB6FF', 'sand': '#FFB45E'}
ACCENT_C = {'mint': '#0D9466', 'lilac': '#6B45D6', 'blue': '#1F74D0', 'sand': '#C06A12'}


def shot(scene):
    # Layouts sit in layouts/, next to raw/: they stay small and editable.
    return f'../{RAW.name}/{scene}.png'


def phone(src, x, y, screen_w, glow=None):
    """An iPhone 16 outline around a capture: black bezel, titanium edge, side buttons."""
    bezel = round(screen_w * 0.024)
    screen_h = round(screen_w * SHOT_H / SHOT_W)
    radius = round(screen_w * 0.143)
    w, h = screen_w + 2 * bezel, screen_h + 2 * bezel
    shadow = f'0 0 0 {round(w*0.004)+2}px #2A2C31, 0 0 0 {round(w*0.007)+3}px #8E939B, 0 0 0 {round(w*0.009)+4}px #3B3E44'
    shadow += f', 0 {round(h*0.03)}px {round(h*0.05)}px rgba(10,10,20,.28), 0 {round(h*0.008)}px {round(h*0.012)}px rgba(10,10,20,.18)'
    if glow:
        shadow += f', 0 0 {round(w*0.25)}px {glow}55'
    button = lambda side, top, height: (
        f'<div style="position:absolute;{side}:-{round(w*0.0145)}px;top:{round(h*top)}px;width:{round(w*0.008)}px;height:{round(h*height)}px;'
        f'border-radius:4px;background:linear-gradient(90deg,#5d6168,#a3a8af 50%,#5d6168)"></div>')
    return (f'<div class="phone" style="position:absolute;left:{x}px;top:{y}px;width:{w}px;height:{h}px;border-radius:{radius+bezel}px;'
            f'background:#050506;box-shadow:{shadow}">'
            + button('left', .165, .035) + button('left', .225, .062) + button('left', .3, .062) + button('right', .25, .095)
            + f'<img src="{src}" style="position:absolute;left:{bezel}px;top:{bezel}px;width:{screen_w}px;height:{screen_h}px;border-radius:{radius}px;display:block"></div>'), (w, h, bezel, screen_h)


FIT = '''<script>
// A headline line too long for the column shrinks both lines to the size that fits, so they stay even.
const lines = [...document.querySelectorAll('h1 span')];
let size = parseFloat(getComputedStyle(lines[0]).fontSize);
while (lines.some(l => l.scrollWidth > l.parentElement.clientWidth) && size > 60) { size -= 2; lines.forEach(l => l.style.fontSize = size + 'px'); }
</script>'''

BASE_CSS = '''*{box-sizing:border-box}html,body{margin:0;width:1320px;height:2868px;overflow:hidden}
body{font-family:-apple-system,"SF Pro Display",BlinkMacSystemFont,"Helvetica Neue",sans-serif;-webkit-font-smoothing:antialiased;position:relative}
h1{margin:0;font-weight:800}h1 span{display:block;white-space:nowrap}'''


def style_a(frame, icon):
    t = PASTEL[frame['tone']]
    img = shot(frame['scene'])
    device, (pw, ph, _, _) = phone(img, 0, 0, 936)
    x, y = (W - pw) // 2, 706
    device = device.replace('left:0px;top:0px', f'left:{x}px;top:{y}px', 1)
    return f'''<!doctype html><html lang="{LOCALE}"><meta charset="utf-8"><style>{BASE_CSS}
body{{background:radial-gradient(ellipse 900px 1300px at 50% 1750px,{t['bg2']} 0%,{t['bg']} 70%);color:{t['ink']}}}
.brand{{position:absolute;left:96px;right:96px;top:84px;display:flex;align-items:center;justify-content:space-between}}
.brand b{{display:flex;align-items:center;gap:20px;font-size:40px;font-weight:700;letter-spacing:-1px}}
.brand img{{width:66px;height:66px;border-radius:16px;box-shadow:0 2px 6px rgba(0,0,0,.18)}}
.brand span{{font-size:25px;letter-spacing:3px;font-weight:600;color:{t['muted']}}}
.eyebrow{{position:absolute;top:204px;left:98px;right:96px;font-size:28px;font-weight:700;letter-spacing:3.4px;color:{t['accent']}}}
h1{{position:absolute;top:254px;left:90px;right:70px;font-size:142px;line-height:1.0;letter-spacing:-5.6px}}
h1 span:last-child{{color:{t['accent']}}}
.detail{{position:absolute;left:98px;right:90px;top:560px;font-size:37px;line-height:1.3;letter-spacing:-.5px;color:{t['muted']};margin:0}}
.rail{{position:absolute;left:98px;top:690px;bottom:72px;border-left:2px solid {t['line']}}}
.rail::before{{content:'';width:12px;height:12px;border-radius:50%;background:{t['accent']};position:absolute;left:-7px;top:0}}
</style><body>
<div class="brand"><b><img src="{icon}">Minor AI</b><span>{TAGLINE[LOCALE]}</span></div>
<div class="eyebrow">{frame['eyebrow']}</div>
<h1><span>{frame['h1'][0]}</span><span>{frame['h1'][1]}</span></h1>
<p class="detail">{frame['detail']}</p><div class="rail"></div>
{device}{FIT}</body></html>'''


def style_b(frame, icon):
    glow = GLOW[frame['tone']]
    img = shot(frame['scene'])
    device, (pw, ph, _, _) = phone(img, 0, 0, 960, glow=glow)
    x, y = (W - pw) // 2, 690
    device = device.replace('left:0px;top:0px', f'left:{x}px;top:{y}px', 1)
    return f'''<!doctype html><html lang="{LOCALE}"><meta charset="utf-8"><style>{BASE_CSS}
body{{background:#0C0912;color:#F6F3FA}}
.bg{{position:absolute;inset:0;background:
  radial-gradient(ellipse 760px 900px at 50% 1500px,{glow}38 0%,transparent 70%),
  radial-gradient(ellipse 900px 520px at 50% 120px,{glow}1F 0%,transparent 75%),
  radial-gradient(circle,rgba(255,255,255,.075) 1.6px,transparent 2.2px) 0 0/44px 44px}}
.brand{{position:absolute;top:88px;left:0;right:0;display:flex;justify-content:center;align-items:center;gap:16px;font-size:34px;font-weight:650;color:#CFC8DA}}
.brand img{{width:52px;height:52px;border-radius:13px;box-shadow:0 0 0 1.5px rgba(255,255,255,.18)}}
.eyebrow{{position:absolute;top:194px;left:60px;right:60px;text-align:center;font-size:27px;font-weight:700;letter-spacing:4px;color:{glow}}}
h1{{position:absolute;top:246px;left:60px;right:60px;text-align:center;font-size:146px;line-height:1.0;letter-spacing:-5.8px}}
h1 span:last-child{{background:linear-gradient(92deg,{glow},#FFFFFF 120%);-webkit-background-clip:text;color:transparent;padding-bottom:10px}}
.detail{{position:absolute;left:90px;right:90px;top:556px;text-align:center;font-size:37px;line-height:1.3;color:#A79FB4;margin:0}}
</style><body><div class="bg"></div>
<div class="brand"><img src="{icon}">Minor AI</div>
<div class="eyebrow">{frame['eyebrow']}</div>
<h1><span>{frame['h1'][0]}</span><span>{frame['h1'][1]}</span></h1>
<p class="detail">{frame['detail']}</p>
{device}{FIT}</body></html>'''


def style_c(frame, icon):
    accent = ACCENT_C[frame['tone']]
    img = shot(frame['scene'])
    screen_w = 820
    device, (pw, ph, bezel, screen_h) = phone(img, 0, 0, screen_w)
    x, y = W - pw - 70, 760
    device = device.replace('left:0px;top:0px', f'left:{x}px;top:{y}px', 1)
    # The enlarged part: the same capture, cropped, in a floating card over the phone's left side.
    zx0, zy0, zx1, zy1 = frame['zoom']
    card_w = 1020
    scale = card_w / (zx1 - zx0)
    card_h = round((zy1 - zy0) * scale)
    in_phone = y + bezel + zy0 * screen_w / SHOT_W
    card_y = round(min(max(in_phone - 60, 820), H - card_h - 120))
    card = (f'<div class="zoom" style="left:60px;top:{card_y}px;width:{card_w}px;height:{card_h}px;'
            f'background:url({img}) -{round(zx0*scale)}px -{round(zy0*scale)}px/{round(SHOT_W*scale)}px {round(SHOT_H*scale)}px no-repeat"></div>')
    return f'''<!doctype html><html lang="{LOCALE}"><meta charset="utf-8"><style>{BASE_CSS}
body{{background:#F4F1EA;color:#121212}}
.brand{{position:absolute;left:96px;top:86px;display:flex;align-items:center;gap:18px;font-size:36px;font-weight:700;letter-spacing:-.8px}}
.brand img{{width:58px;height:58px;border-radius:14px}}
.eyebrow{{position:absolute;top:204px;left:98px;display:flex;align-items:center;gap:16px;font-size:27px;font-weight:700;letter-spacing:3.2px;color:{accent}}}
.eyebrow::before{{content:'';width:46px;height:5px;border-radius:3px;background:{accent}}}
h1{{position:absolute;top:258px;left:90px;right:60px;font-size:150px;line-height:.98;letter-spacing:-6.4px}}
h1 span:last-child{{color:{accent}}}
.detail{{position:absolute;left:98px;right:120px;top:570px;font-size:38px;line-height:1.3;color:#5B5750;margin:0}}
.zoom{{position:absolute;border-radius:44px;box-shadow:0 0 0 2px rgba(255,255,255,.10),0 50px 90px rgba(20,14,30,.38),0 14px 30px rgba(20,14,30,.22);z-index:3}}
</style><body>
<div class="brand"><img src="{icon}">Minor AI</div>
<div class="eyebrow">{frame['eyebrow']}</div>
<h1><span>{frame['h1'][0]}</span><span>{frame['h1'][1]}</span></h1>
<p class="detail">{frame['detail']}</p>
{device}{card}{FIT}</body></html>'''


STYLES = {'A': style_a, 'B': style_b, 'C': style_c}


def render(html_path, png_path, w=W, h=H):
    result = subprocess.run([str(CHROME), '--no-sandbox', '--hide-scrollbars', '--force-device-scale-factor=1',
                             f'--user-data-dir={ROOT}/.chrome', '--virtual-time-budget=3000', f'--window-size={w},{h}',
                             f'--screenshot={png_path}', html_path.as_uri()], capture_output=True, text=True)
    if result.returncode or not png_path.exists():
        raise RuntimeError(result.stderr[-2000:])


def build(names):
    from PIL import Image
    icon = '../assets/icon.png'
    manifest = {}
    for name in names:
        style, keys = SETS[name]
        (OUT / name).mkdir(parents=True, exist_ok=True)
        HTML.mkdir(exist_ok=True)
        for n, key in enumerate(keys, 1):
            page = HTML / f'{LOCALE}-{name}-{n:02d}-{key}.html'
            page.write_text(STYLES[style](frame(key), icon))
            png = OUT / name / f'{n:02d}-{key}.png'
            render(page, png)
            Image.open(png).convert('RGB').save(png)  # App Store: RGB, no alpha
            manifest.setdefault(name, []).append(dict(file=f'{name}/{png.name}', scene=FRAMES[key]['scene'], headline=' '.join(frame(key)['h1'])))
            print(png.relative_to(ROOT), flush=True)
    return manifest


TITLES = {
    'main-a': ('Default page · A', 'Pastel, after the reference'),
    'main-b': ('Default page · B', 'Dark, in the app’s colors'),
    'main-c': ('Default page · C', 'Light, with the key part enlarged'),
    'cpp-mind-maps': ('Custom page · Mind maps', 'ai mind map · brainstorm · outline'),
    'cpp-study': ('Custom page · Study', 'flashcards · quiz · lecture · pdf'),
    'cpp-presentations': ('Custom page · Presentations', 'presentation · slides · deck'),
    'cpp-tasks': ('Custom page · Tasks', 'planner · tasks'),
}


def boards():
    """Overview boards: one per set, and the four custom pages' first frames side by side."""
    css = ('*{box-sizing:border-box}body{margin:0;background:#F5F3ED;color:#1E3328;font:16px -apple-system,sans-serif;padding:44px 44px 40px}'
           'h1{font-size:38px;letter-spacing:-1.4px;margin:0 0 8px}p{color:#5F6B63;margin:0 0 28px;font-size:19px}'
           '.row{display:flex;gap:18px}figure{margin:0;width:300px}img{width:300px;display:block;border-radius:12px;box-shadow:0 1px 3px rgba(0,0,0,.12)}'
           'figcaption{font-size:16px;padding-top:12px;font-weight:600}')
    pages = {}
    for name, (style, keys) in SETS.items():
        title, sub = TITLES[name]
        figs = ''.join(f'<figure><img src="{name}/{n:02d}-{k}.png"><figcaption>{n:02d} · {" ".join(frame(k)["h1"])}</figcaption></figure>' for n, k in enumerate(keys, 1))
        pages[f'board-{name}'] = (f'<h1>Minor AI · {title}</h1><p>{sub} · {LANGUAGE[LOCALE]} · 1320 × 2868 · fresh captures of version 3.0.1</p><div class="row">{figs}</div>', 44 * 2 + len(keys) * 318 - 18, 850)
    heroes = [('cpp-mind-maps', 'maps-hero', '01 · Mind maps'), ('cpp-study', 'study-hero', '02 · Study'),
              ('cpp-presentations', 'slides-hero', '03 · Presentations'), ('cpp-tasks', 'tasks-hero', '04 · Tasks')]
    figs = ''.join(f'<figure><img src="{s}/01-{k}.png" style="width:325px"><figcaption>{t}</figcaption></figure>' for s, k, t in heroes)
    pages['board-four-ways-in'] = (f'<h1>Minor AI · Four ways in.</h1><p>{LANGUAGE[LOCALE]} · Custom Product Pages · Minor AI 3.0.1</p><div class="row" style="gap:20px">{figs}</div>', 1440, 940)
    for name, (body, w, h) in pages.items():
        page = OUT / f'{name}.html'
        page.write_text(f'<!doctype html><html lang="{LOCALE}"><meta charset="utf-8"><style>{css}</style><body>{body}</body></html>')
        render(page, OUT / f'{name}.png', w, h)
        page.unlink()
        print(f'final/{name}.png', flush=True)


if __name__ == '__main__':
    names = [a for a in sys.argv[1:] if a in SETS] or ([] if '--boards' in sys.argv else list(SETS))
    manifest = build(names)
    boards()
    path = OUT / 'manifest.json'
    old = json.loads(path.read_text()) if path.exists() else {}
    old.update(manifest)
    path.write_text(json.dumps(old, indent=2, ensure_ascii=False))
