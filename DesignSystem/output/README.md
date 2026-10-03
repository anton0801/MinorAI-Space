# Minor Ai · Mind Map

Готовый набор дизайна: **22 HTML-композиции**, **26 наборов .imageset**, **78 PNG**, галерея на шесть тем. Все изменения находятся в `DesignSystem/output/`.

## Просмотр

Откройте [index.html](index.html) в браузере. Галерея работает локально без сборки и внешних шрифтов. Сохраняйте её внутри исходной DesignSystem: экраны используют `../../tokens.css`, `../../components/bundle.css`, `../../components/bundle.js`.

В галерее можно выбрать тему, кадр 393×852 / 375×667 / 430×932 и раздел. Название над кадром открывает отдельный HTML. В отдельном файле параметры `?theme=vio&width=430&height=932` меняют тему и размер. По умолчанию — Classic, 393×852, безопасные зоны 59/34.

## Экраны

21 обязательное состояние и дополнительная раскладка List для доступности:

| Файл | Состояние |
| --- | --- |
| [01-home.html](screens/01-home.html) | Home · First Map |
| [02-create.html](screens/02-create.html) | Start a Map |
| [02-create-youtube.html](screens/02-create-youtube.html) | Start a Map · YouTube |
| [02-create-voice.html](screens/02-create-voice.html) | Start a Map · Listening |
| [02-create-limit.html](screens/02-create-limit.html) | Start a Map · Free Limit |
| [02-create-offline.html](screens/02-create-offline.html) | Start a Map · Offline |
| [03-generating.html](screens/03-generating.html) | Building Your Map |
| [03-generating-error.html](screens/03-generating-error.html) | Building Your Map · Error |
| [04-editor.html](screens/04-editor.html) | Launch plan · Overview |
| [04-editor-node-selected.html](screens/04-editor-node-selected.html) | Launch plan · Node Selected |
| [04-editor-editing.html](screens/04-editor-editing.html) | Launch plan · Editing |
| [04-editor-focus.html](screens/04-editor-focus.html) | Launch plan · Focus |
| [04-editor-search.html](screens/04-editor-search.html) | Launch plan · Search |
| [04-editor-zoomed-out.html](screens/04-editor-zoomed-out.html) | Launch plan · 40% |
| [04-editor-40-plus-nodes.html](screens/04-editor-40-plus-nodes.html) | Launch plan · 43 Nodes |
| [04-editor-outline.html](screens/04-editor-outline.html) | Launch plan · List |
| [05-node-card.html](screens/05-node-card.html) | Pricing · Node Card |
| [06-node-chat.html](screens/06-node-chat.html) | Pricing · Chat |
| [07-your-maps.html](screens/07-your-maps.html) | Your Maps |
| [07-your-maps-empty.html](screens/07-your-maps-empty.html) | Your Maps · Empty |
| [08-export.html](screens/08-export.html) | Export Map |
| [09-paywall.html](screens/09-paywall.html) | Minor Plus · Mind Map |

## Решения

- Главный экран сохраняет тёмный фон, системную типографику, пилюлю Minor Plus, водяной знак, карточку ввода и глобус. Подсказка новичку стоит непосредственно над полем.
- Основная карта содержит 23 узла: корень, 6 веток и 16 листьев. Обзор показывает свёрнутые ветки с точными счётчиками. Выбор Pricing раскрывает 4 листа; Focus и поиск приглушают остальные ветки до 35%.
- Вариант большой карты содержит 43 узла, а отдельный вариант 40% — исходные 23. Ниже 50% исчезает сетка, листья становятся цветными полосками высотой 6 экранных px; подписи веток сохраняют размер не ниже 8 px.
- Панели привязаны к безопасным зонам. На коротком экране источники, списки и содержимое шторок прокручиваются, поле остаётся доступным. В состоянии лимита RECENT скрыт, чтобы счётчик и действие покупки читались сразу.
- Шторка узла занимает ровно половину кадра. Заметка, источник, AI-действия и Delete Node доступны во внутренней прокрутке. Delete Node находится после группы AI-действий.
- Клавиатура — иллюстрация состояния из существующих нейтральных токенов. Это не точная копия системной клавиатуры iOS.
- Новых цветов, шрифтов, радиусов и теней нет. Уточнения — в [NEW_TOKENS.md](NEW_TOKENS.md).
- Строки управления и ошибок взяты из DESIGN.md. Контент карты и примеры ответа составлены из его демонстрационных названий и цен. Буквы клавиатуры и домен youtube.com — содержимое соответствующих состояний, не новый UI-копирайтинг.
- В тарифах принято предложение из раздела 4.9: все источники доступны в Plus; Xmind/MindNode и Share Link — в PRO. В исходном SourceTile YouTube/Voice помечены PRO, что противоречит этому предложению. Чтобы не закреплять противоречие, плитки показаны без PRO-меток. Доступ к платным источникам остаётся предметом продуктовой логики.
- Paywall начинается с Unlimited mind maps. Plus/PRO и Monthly/Yearly переключают цену из исходной системы. Переход из PRO-формата экспорта предварительно выбирает PRO.
- Частицы используются только в нижней трети paywall. Reduce Motion отключает непрерывное движение.

## Ассеты

Каждый набор содержит `name.svg`, `name.png`, `name@2x.png`, `name@3x.png` и `Contents.json` с universal 1x/2x/3x. SVG не содержит встроенных растров. У PNG иконок приложения фон непрозрачный RGB; остальные PNG имеют прозрачность.

| Набор | Размер @1x |
| --- | --- |
| [app-icon-classic](assets/app-icon-classic.imageset/app-icon-classic.svg) | 1024×1024 |
| [app-icon-glow](assets/app-icon-glow.imageset/app-icon-glow.svg) | 1024×1024 |
| [app-icon-cosmos](assets/app-icon-cosmos.imageset/app-icon-cosmos.svg) | 1024×1024 |
| [menu-white](assets/menu-white.imageset/menu-white.svg) | 25×25 |
| [menu-gray](assets/menu-gray.imageset/menu-gray.svg) | 25×25 |
| [mind-globe-white](assets/mind-globe-white.imageset/mind-globe-white.svg) | 30×30 |
| [mind-globe-gray](assets/mind-globe-gray.imageset/mind-globe-gray.svg) | 30×30 |
| [star-white](assets/star-white.imageset/star-white.svg) | 20×20 |
| [star-gray](assets/star-gray.imageset/star-gray.svg) | 15×15 |
| [bulb-white](assets/bulb-white.imageset/bulb-white.svg) | 20×20 |
| [bulb-gray](assets/bulb-gray.imageset/bulb-gray.svg) | 15×15 |
| [rocket-white](assets/rocket-white.imageset/rocket-white.svg) | 20×20 |
| [rocket-gray](assets/rocket-gray.imageset/rocket-gray.svg) | 15×15 |
| [particle-node-white-15](assets/particle-node-white-15.imageset/particle-node-white-15.svg) | 15×15 |
| [particle-node-white-20](assets/particle-node-white-20.imageset/particle-node-white-20.svg) | 20×20 |
| [particle-node-gray-15](assets/particle-node-gray-15.imageset/particle-node-gray-15.svg) | 15×15 |
| [particle-node-gray-20](assets/particle-node-gray-20.imageset/particle-node-gray-20.svg) | 20×20 |
| [particle-branch-white-15](assets/particle-branch-white-15.imageset/particle-branch-white-15.svg) | 15×15 |
| [particle-branch-white-20](assets/particle-branch-white-20.imageset/particle-branch-white-20.svg) | 20×20 |
| [particle-branch-gray-15](assets/particle-branch-gray-15.imageset/particle-branch-gray-15.svg) | 15×15 |
| [particle-branch-gray-20](assets/particle-branch-gray-20.imageset/particle-branch-gray-20.svg) | 20×20 |
| [particle-spark-white-15](assets/particle-spark-white-15.imageset/particle-spark-white-15.svg) | 15×15 |
| [particle-spark-white-20](assets/particle-spark-white-20.imageset/particle-spark-white-20.svg) | 20×20 |
| [particle-spark-gray-15](assets/particle-spark-gray-15.imageset/particle-spark-gray-15.svg) | 15×15 |
| [particle-spark-gray-20](assets/particle-spark-gray-20.imageset/particle-spark-gray-20.svg) | 20×20 |
| [no-maps-yet](assets/no-maps-yet.imageset/no-maps-yet.svg) | 160×120 |

Дополнительно: [minor-mark-traced.svg](assets/minor-mark-traced.svg) — исходный знак, перенесённый из alpha-контура `minor-mark@3x.png` в настоящий вектор с сохранением отверстий и пропорций. Контур упрощён с допуском 0.7 пикселя исходника 2100×2100.

Существующие menu, mind-globe, star, bulb и rocket восстановлены вручную как чистые линейные SVG, с регулярным весом и скруглёнными концами. Это оптическая реконструкция, не побитовая копия PNG: исходный globe был заливочным, новая версия линейная согласно заданию. Частицы node, branch, spark используют тот же вес; каждая есть в двух цветах и двух размерах.

### Выбор иконки

1. **app-icon-classic** — рекомендуемый вариант: исходный белый знак на Classic без эффектов.
2. **app-icon-glow** — тот же масштаб и фоновое свечение Classic.
3. **app-icon-cosmos** — увеличенный знак на фоне Cosmos, более плотное заполнение.

Скругление углов не запечено в файлы. Все три — квадратные 1024×1024 с увеличениями 2048 и 3072 по требованию @2x/@3x. Для AppIcon в Xcode используйте выбранный PNG 1024×1024 в существующем AppIcon.appiconset; подготовленные .imageset предназначены для просмотра/импорта обычных изображений. Каталог приложения не менялся.

## Что работает в прототипе

Переходы между основными состояниями, ввод темы и переход к генерации, отмена генерации, перетаскивание холста мышью/одним указателем, выбор узла, List, Focus, поиск, цвет выбранной ветки, Add to Map → Added, переключатели оплаты, выбор PRO из экспорта, копирование краткого outline и скачивание демонстрационного Markdown.

Генерация намеренно не завершает состояние сама: оно должно оставаться доступным для просмотра. Expand открывает готовую композицию на 43 узла. Состояния сохранения и ответа иллюстративны. AI, запись микрофона, покупка, системный выбор файла, реальный PNG/PDF-экспорт, Settings и юридические страницы не подключены. Карта не является полноценным редактором; изменения не сохраняются. Пример Markdown содержит названия веток. Это дизайн-артефакты, не реализация приложения.

## Проверка

[qa/REPORT.md](qa/REPORT.md) — результаты и границы проверки. В qa также лежат скриншоты всех 22 экранов в Classic, дополнительные узкие кадры и JSON-отчёты.

Скрипты воспроизведения: `scripts/build.py` создаёт HTML, `scripts/assets.py` создаёт SVG и каталоги Xcode, `scripts/render-assets.cjs` растрирует через sharp, `scripts/gallery.py` создаёт галерею, `scripts/check.cjs` проверяет размеры, `scripts/verify.cjs` — темы и основные переходы. Пути к bundled Node-пакетам и Chromium в проверочных скриптах соответствуют текущей машине; на другой машине их нужно настроить.

## Что требует выбора / что не включено

- Нужно выбрать одну из трёх иконок приложения; рекомендую Classic.
- Перед реализацией нужно подтвердить тарифные права источников из-за противоречия в исходной системе. Дизайн использует вариант Plus для всех источников.
- Необязательные четыре кадра App Store не создавались. Все обязательные экраны и ассеты подготовлены.
- Проверка выполнена в Chromium на macOS. Реальные SF Symbols, Dynamic Type, VoiceOver, системная клавиатура, мультитач и поведение SwiftUI потребуют проверки при реализации на устройстве.

## Служебные файлы

- `manifest.json` — полный перечень экранов.
- `assets/manifest.json` — перечень и размеры ассетов.
- `screens.css`, `screens.js` — общий слой композиций и демонстрационных переходов.
- `gallery.css`, `gallery.js` — галерея и её переключатели.
- `qa/source-hashes.json` — контрольные суммы 184 исходных файлов; изменений вне output нет.
