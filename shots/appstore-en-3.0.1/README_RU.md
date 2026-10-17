# Minor AI 3.0.1 · скриншоты App Store · English (US), Deutsch, Español (España)

Все кадры сняты заново с текущего интерфейса 3.0.1 (симулятор iPhone 16, iOS 18.5). Размер 1320 × 2868, PNG, RGB без прозрачности: подходит для слота 6,9" в App Store Connect. Примеры взяты из жизни: поездка в Японию, подготовка к экзамену по фотосинтезу, кулинарный подкаст. «Launch plan» и «Minor AI» в примерах не используются.

## Немецкий и испанский

Те же наборы и тот же порядок лежат в `final-de/` (de-DE) и `final-es/` (es-ES). Само приложение пока переведено только на английский и русский. Поэтому кнопки и меню на скриншотах английские, как в реальной сборке. На языке витрины — подписи и примеры: карты, слайды, чат, тест, PDF. Карты от ИИ правда получаются на языке материала: сервер пишет «in the same language as the source».

Метаданные для этих локализаций лежат в `app-store-metadata/de-DE` и `app-store-metadata/es-ES`: подзаголовок, ключевые слова (≤ 100), описание, Promotional Text для основной страницы и каждой CPP. В конце описания одна строка честно говорит, что интерфейс пока английский.

Ключи по CPP, без пересечений:

| Страница | de-DE | es-ES |
|---|---|---|
| Mind maps | mindmap, brainstorming, notizen | esquema, resumen, ia |
| Study | lernen, karteikarten, quiz, vorlesung, pdf | estudiar, tarjetas, test, examen, apuntes, pdf |
| Presentations | präsentation | presentaciones |
| Tasks | planer, aufgaben | planificador, tareas |

## Что где

| Папка | Для чего | Кадров |
|---|---|---|
| `final/main-a` | Основная страница, стиль A (по вашему референсу) | 8 |
| `final/main-b` | Основная страница, стиль B: тёмный, в цветах приложения | 8 |
| `final/main-c` | Основная страница, стиль C: светлый, ключевой фрагмент увеличен | 8 |
| `final/cpp-mind-maps` | Custom Product Page «Mind maps» | 5 |
| `final/cpp-study` | Custom Product Page «Study» | 5 |
| `final/cpp-presentations` | Custom Product Page «Presentations» | 5 |
| `final/cpp-tasks` | Custom Product Page «Tasks» | 5 |

Немецкие и испанские наборы — в `final-de/` и `final-es/` с теми же папками. `board-*.png` — обзорные доски, не для загрузки. Номер в имени файла = порядок загрузки.

## A/B-тест основной страницы (Product Page Optimization)

В A, B и C одинаковые экраны, заголовки и порядок кадров, отличается только оформление. Поэтому тест покажет именно влияние стиля.

- Текущие скриншоты оставить как Original и добавить treatment: A, B или C. Apple допускает до трёх treatments. Если трафика немного, начните с одного варианта (A) против текущего и не дробите его на три.
- Основная метрика — конверсия в загрузку. Держите тест минимум 2 недели и не меняйте в это время цену, иконку и рекламу.
- Для Custom Product Pages PPO не работает. Их сравнивают через рекламу/ссылки, это разные аудитории.

## Ключевые слова

Сейчас в поле: `notes,study,flashcards,planner,tasks,pdf,outline,brainstorm,lecture,summary,quiz,voice,organizer` (96 символов). В нём нет слов про презентации, хотя это главное, ради чего приходят пользователи.

Предлагаю для версии 3.0.1 (98 из 100 символов):

```
presentation,study,flashcards,planner,tasks,notes,pdf,outline,brainstorm,lecture,quiz,deck,summary
```

Убраны `voice` и `organizer`, добавлены `presentation` и `deck`. Слова из названия и подзаголовка (mind, maps, slides, AI, chat) повторять не нужно, они уже индексируются. «PowerPoint» в ключи не добавлять: это чужая торговая марка, App Store отклоняет такие ключи.

Custom Product Page можно показывать в поиске по ключам из поля одобренной версии. Назначение без пересечений:

| Страница | Ключи |
|---|---|
| Mind maps | brainstorm, outline, notes, summary |
| Study | study, flashcards, quiz, lecture, pdf |
| Presentations | presentation, deck |
| Tasks | planner, tasks |

## Promotional Text (до 170 символов)

- **Основная (под обновление):** The all-new Minor AI: mind maps, slides and study in one place. Ask for a map, add your PDFs and videos, then present, review or plan what’s next.
- **Mind maps:** Turn any idea, PDF, link or video into a clear mind map. Ask AI for more ideas, add notes and tasks, and make it look the way you like.
- **Study:** Turn your lecture notes and PDFs into mind maps, flashcards and quizzes. See how ideas connect and know exactly what to review before the exam.
- **Presentations:** Turn a mind map into a presentation you can edit. Change the theme, use presenter mode with your notes and export to PowerPoint or PDF.
- **Tasks:** Turn the ideas in your maps into tasks with dates and reminders. See them all in Today, and let AI plan your day around them.

## Как пересобрать

1. Исходные экраны в `raw/` снимаются из Debug-сборки по `scenes.txt`. В каждой строке — флаги запуска с демо-данными `-campaign travel|study|podcast`, у всех `-appLanguage en -auditSignedOut -noResume -demoPlus -isolatedStore`. Время в статус-баре 9:41.
   Немецкие и испанские исходники (`raw-de/`, `raw-es/`) снимаются по `scenes-intl.txt` с добавкой `-campaignLang de` или `-campaignLang es`.
2. `python3 build.py` раскладывает всё по макетам и рендерит в `final/`; `python3 build.py --locale de` (или `es`) — в `final-de/` или `final-es/`. `python3 build.py main-b` пересобирает один набор, `--boards` — только доски. Тексты и кадрирование для стиля C задаются в `FRAMES` в начале `build.py`.

Демо-данные лежат в `Minor Ai/MindMap/DemoStory.swift` (`CampaignDemo`) и подключены в DemoMap, MapEditorView (`-demoZoom`), NextStepsSheet и ViewController. Код только под `#if DEBUG`, в релизную сборку не попадает.

Папка `shots/cpp-2026-10-15` обновлена 16 октября: отдельный EN-US комплект с новым интерфейсом, пастельным оформлением и A/B-тестом первого заголовка. Прежние превью на старом интерфейсе убраны в её `archive/previous-ui-drafts`. Не смешивать тест заголовка с тестом стилей A/B/C этой папки.
