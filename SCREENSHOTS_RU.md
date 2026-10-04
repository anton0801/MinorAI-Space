# Скриншоты для App Store (инструкция для Codex)

## Что нужно Apple

- **iPhone 6,9"** (iPhone 16 Pro Max): **1320 × 2868**, вертикально, PNG или JPEG **без прозрачности**. Этого размера достаточно: меньшие экраны Apple подставит сама. iPad не нужен, приложение только для iPhone.
- От 3 до 10 скриншотов **на каждый язык**: английский и русский.
- Первые 3 видны в поиске, поэтому они самые важные.

## Какие экраны снимать (в этом порядке)

| № | Экран | Флаги запуска | Подпись EN | Подпись RU |
|---|---|---|---|---|
| 1 | Карта крупным планом | `-demoMap -demoFit` | Any idea, mapped in seconds | Любая идея — карта за секунды |
| 2 | Создание карты из источника | `-mindMode` | From a topic, link, YouTube, PDF or voice | Из темы, ссылки, YouTube, PDF или голоса |
| 3 | ИИ-помощник работает с картой | `-demoAgent` | An AI assistant that knows your maps | ИИ-помощник, который знает ваши карты |
| 4 | Презентация с дизайном | `-demoDesign` | Slides from your map, with PowerPoint export | Презентация из карты с экспортом в PowerPoint |
| 5 | «Сегодня»: задачи и напоминания | `-mindMode -demoToday` | Tasks and reminders from all your maps | Задачи и напоминания из всех карт |
| 6 | Учёба по карточкам | `-demoMap -demoStudy` | Learn with flashcards and quizzes | Учитесь по карточкам и тестам |
| 7 | Совместная работа | `-demoMap -demoCollab` | Edit maps together | Редактируйте карты вместе |
| 8 | Голосовой режим | `-demoChat -demoVoice` | Just talk to Minor | Просто говорите с Minor |

**Ко всем запускам добавлять:**
- `-didOnboard YES` — без онбординга;
- `-auditSignedOut` — не трогает сохранённый вход;
- `-demoPro` — убирает кнопку «Получить Plus» и замки Plus;
- `-appLanguage en` или `-appLanguage ru`.

Если кадр 7 или 8 выглядит пусто, его можно заменить на `-demoPresentDeck` (показ презентации) или `-sidebarMaps` (список карт).

## Шаги для Codex

1. **Отдельный чистый симулятор.** Не используйте «iPhone 16» (`3E4D8171…`): он вошёл в настоящий аккаунт. На него нужно около 2 ГБ свободного места.
   ```bash
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl create "Minor Shots" com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max com.apple.CoreSimulator.SimRuntime.iOS-18-5
   ```
2. **Сборка Debug и установка.** Флаги `-demo…` работают только в Debug:
   ```bash
   cd "$HOME/Downloads/Minor Ai" && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "Minor Ai.xcodeproj" -scheme "Minor Ai" -destination "platform=iOS Simulator,name=Minor Shots" -configuration Debug build
   ```
   Затем: `xcrun simctl boot "Minor Shots"` и `xcrun simctl install "Minor Shots" <путь к Minor Ai.app из DerivedData>`.
3. **Чистая строка статуса** (9:41, полная батарея):
   ```bash
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl status_bar "Minor Shots" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 --operatorName ""
   ```
4. **Снимок каждого экрана.** В zsh для нескольких флагов из переменной нужен `${=flags}`:
   ```bash
   xcrun simctl launch --terminate-running-process "Minor Shots" com.minorailifegroup.MinorAI -didOnboard YES -auditSignedOut -demoPro -appLanguage en -demoMap -demoFit
   sleep 5
   xcrun simctl io "Minor Shots" screenshot shots/en-01-map.png
   ```
5. **Русская версия.** Демо-контент (карта «Launch plan», презентация, чат) сейчас **на английском**. Для русских скриншотов попросите Codex добавить в `Minor Ai/MindMap/DemoMap.swift` русские варианты, которые выбираются по `AppLanguage.current`. Только внутри `#if DEBUG`, в выпуск это не попадёт.
6. **Оформление кадра** (по желанию; голые скриншоты Apple тоже принимает):
   - холст 1320 × 2868, фон в цветах приложения: тёмный `#121212` с лёгким свечением акцента `#2FFF9E`;
   - подпись из таблицы сверху: жирный шрифт, примерно 90–100 px, белый, 1–2 строки;
   - под подписью скриншот, уменьшенный примерно до 85%, со скруглёнными углами (~60 px) и мягкой тенью;
   - экспорт PNG **без альфа-канала**: например, `sips -s format png` после сведения с непрозрачным фоном.
7. **Проверить перед загрузкой:**
   - время 9:41;
   - нет кнопки «Получить Plus», отладочных надписей и личных данных;
   - русские подписи и интерфейс не обрезаны;
   - в демо-карте цены новые ($12.99 и $24.99).
8. **Загрузка:** App Store Connect → версия 2.0 → **Previews and Screenshots** → iPhone 6.9" Display. Для каждого языка (English, Russian) свой набор.
