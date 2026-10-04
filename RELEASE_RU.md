# Minor AI 2.0: выпуск обновления по шагам

Порядок важен: некоторые шаги ждут проверки Apple по несколько дней (договор, банк, Small Business Program), поэтому их лучше начать сразу. Ключи и пароли вводите только сами, в своём терминале или в панели сервиса.

✅ — уже сделано (проверено 4 октября 2026). ⬜️ — сделать вам.

---

## Этап 1. Сервер и сервисы (≈ 30 минут)

1. ✅ **База и функции Supabase.** Все 17 миграций применены, функции развёрнуты уже после исправлений аудита. Если меняли что-то в `supabase/` после 4 октября, повторите:
   ```bash
   cd "$HOME/Downloads/Minor Ai" && supabase db push
   ```
   ```bash
   cd "$HOME/Downloads/Minor Ai" && supabase functions deploy --project-ref dgddfvotzutogrmzfscx --use-api
   ```
2. ✅ **Секреты** (все на месте, проверено вами 4 октября). Команда показывает только имена, не значения:
   ```bash
   cd "$HOME/Downloads/Minor Ai" && supabase secrets list --project-ref dgddfvotzutogrmzfscx
   ```
   Должны быть:
   - `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`;
   - `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY` — для отзыва входа через Apple при удалении аккаунта (требование App Review);
   - `APNS_KEY_ID`, `APNS_PRIVATE_KEY` — для пушей и защиты приглашений.

   Если APNs-ключа нет: developer.apple.com → Keys → «+» → отметить **Apple Push Notifications service** и **DeviceCheck** → скачать `.p8`, затем:
   ```bash
   cd "$HOME/Downloads/Minor Ai" && supabase secrets set --project-ref dgddfvotzutogrmzfscx APNS_KEY_ID=ВАШ_KEY_ID APNS_PRIVATE_KEY="$(cat ~/Downloads/AuthKey_ВАШ_KEY_ID.p8)"
   ```
3. ✅ **Настройки входа.** Повторный запуск безопасен (код из письма 15 минут, смена пароля после недавнего входа):
   ```bash
   cd "$HOME/Downloads/Minor Ai" && supabase config push
   ```
4. ⬜️ **Тариф Supabase Pro ($25 в месяц).** На бесплатном тарифе проект **засыпает после недели без активности** — для живого приложения это недопустимо. После перехода: Authentication → Attack Protection → **Prevent use of leaked passwords**.
5. ✅ **OpenAI и Anthropic:**
   - верификация организации в OpenAI (platform.openai.com → Settings → Organization → Verify) — без неё не работают картинки;
   - месячный лимит расходов в обеих консолях.
6. ✅ **Сайт.** Залить содержимое свежего `minorai-site.zip` на хостинг. В нём новые цены, страница приглашения `/invite/` и обновлённая политика конфиденциальности. Проверить, что открываются:
   - `https://minorai.site/`, `/privacy/`, `/support/`, `/join/`;
   - `https://minorai.site/invite/#c=ABCDEFGH`.

   Ящик `support@minorai.site` должен принимать почту.

---

## Этап 2. App Store Connect (≈ 1–2 часа, плюс ожидание проверок Apple)

7. ✅ **Договор на платные приложения.** Business (Agreements, Tax, and Banking): **Paid Apps Agreement** в статусе **Active**, банк и налоговые формы заполнены. **Без этого подписки не продаются и не проходят ревью.**
8. ✅ **App Store Small Business Program**: developer.apple.com/app-store/small-business-program → Enroll. Комиссия станет 15% вместо 30%. Одобрение занимает несколько дней.
9. ✅ **Подписки** (Monetization → Subscriptions → группа «Minor»):
   - создать `com.minorailifegroup.MinorAI.proMonthlyPlan` и `com.minorailifegroup.MinorAI.proYearlyPlan`;
   - уровни в группе: **PRO выше Plus**;
   - цены (базовая страна США):

     | Продукт | Цена |
     |---|---|
     | `plusMonthlyPlan` | $12.99 |
     | `plusYearlyPlan` | $119.99 |
     | `proMonthlyPlan` | $24.99 |
     | `proYearlyPlan` | $219.99 |

   - при повышении цены у старых Plus: **Keep the current price for existing subscribers**;
   - у каждой подписки и у группы — название и описание на **английском и русском** (без слова «безлимит»). Например: «Minor Plus — Monthly / Minor Plus — на месяц», «More maps, presentations, AI and editing together».
   - у каждой подписки **Review Information**: скриншот экрана подписки (пейвол) и одна строка заметки;
   - `plusHalfYearPlan` → **Remove from Sale** (у тех, кто уже подписан, продолжит работать).
10. ⬜️ (Можно после выпуска) **Коды скидок 30%** для награды за приглашение: `CHECKLIST_RU.md`, раздел 1е. Пока кодов нет, пригласивший увидит «Скидки временно закончились».
11. ✅ **Новая версия 2.0** (страница приложения → «+» рядом с iOS App → 2.0):
    - **все тексты** (название, подзаголовок, рекламный текст, описание, ключевые слова, What's New) на 5 языках — в `APPSTORE_TEXT.md`, длина проверена;
    - **скриншоты** — по `SCREENSHOTS_RU.md` (английский и русский; остальные языки возьмут английские);
    - **языки**: английский, русский, испанский, французский, итальянский. Немецкий удалить, если он есть;
    - Copyright: например, «© 2026 Regina Danilova».
12. ✅ **App Review Information:**
    - Sign-in required: **Yes**. Создайте отдельный тестовый аккаунт по почте (не ваш личный), подтвердите почту, впишите почту и пароль;
    - заметка для проверяющего — текст ниже;
    - контакты для связи.
13. ✅ **In-App Purchases and Subscriptions** на странице версии: отметить **все 4 подписки**. Новые PRO проверяются вместе с версией.
14. ✅ Ссылки на политику и поддержку, App Privacy, возрастной рейтинг 13+, адрес App Store Server Notifications (вы сделали раньше). ⬜️ Проверьте, что в App Privacy отмечены **Device ID** и **Other User Content** (синхронизация и совместные карты).

---

## Этап 3. Сборка в Xcode (≈ 20 минут)

15. ⬜️ **Подпись.** Signing & Capabilities у трёх таргетов **Minor Ai**, **MinorWidgets**, **MinorShare**: **Team** — команда, которой принадлежит приложение (Regina Danilova), *Automatically manage signing* включено. У **Minor Ai** должны быть:
    - Sign in with Apple;
    - Push Notifications;
    - App Groups (`group.com.minorailifegroup.MinorAI`).

    У двух расширений должны быть App Groups с той же группой.
16. ✅ **Версия 2.0, сборка 1** — задано на уровне проекта, одинаково для приложения и расширений. Если сборку 1 уже загружали, увеличьте Current Project Version в настройках **проекта** (не таргета).
17. ✅ **Экспортное шифрование.** В `Info.plist` уже стоит «не использует нестандартное шифрование», вопрос при загрузке не появится.
18. ⬜️ **Загрузка сборки:**
    1. Вверху Xcode выбрать **Any iOS Device (arm64)**.
    2. Product → **Archive**. Release-сборка проверена 4 октября, уже с заставкой: собирается без ошибок. **Перед архивом освободите минимум 5 ГБ на диске**: при заполненном диске архив обрывается.
    3. В Organizer: **Distribute App → App Store Connect → Upload**.
    4. Через 10–30 минут сборка появится в App Store Connect → TestFlight.

---

## Этап 4. Проверка через TestFlight на своём iPhone (≈ 1 час)

19. ⬜️ TestFlight → Internal Testing → добавьте себя → установите сборку из приложения TestFlight. Покупки в TestFlight бесплатные (sandbox).
20. ⬜️ Пройдите короткий список. Это то, что не удалось проверить в симуляторе:
    - **Вход:** регистрация по почте (код приходит), вход и выход, «Забыли пароль?», вход через Apple.
    - **ИИ:** карта по теме и по ссылке, раскрыть идею, чат с `@картой`, картинка.
    - **Подписка:**
      - купить Plus на месяц → «Настройки → Лимиты» показывает Plus;
      - перейти на PRO;
      - удалить и поставить приложение → «Восстановить покупки».
    - **Презентация:** создать из карты → «Дизайн» → экспорт в PowerPoint → открыть файл.
    - **Вдвоём со вторым аккаунтом** (второй iPhone или друг):
      - совместная карта: ссылка, роли «редактор» и «наблюдатель», правки видны у обоих, приходит **пуш** об изменении;
      - код приглашения на втором iPhone: пришли 3 дня Plus.
    - **Без сети:** авиарежим → отправить сообщение → «Повторить» после включения сети.
    - **Выход и вход:** «Выйти» → карты пропали с телефона → войти снова → карты вернулись.
    - **Удаление аккаунта:** «Удалить аккаунт» на отдельном тестовом аккаунте.
    - **Мелочи:** виджет «Сегодня», «Поделиться» из Safari → Minor, напоминание о задаче.
    - **Заставка:** закрыть приложение из переключателя и открыть снова. Анимация длится около 2,5 секунды, касание её пропускает. С включённым «Уменьшением движения» вместо неё короткое затухание.

---

## Этап 5. Отправка на ревью

21. ⬜️ На странице версии выбрать загруженную сборку, проверить, что отмечены 4 подписки → **Add for Review → Submit**. В «Version Release» лучше выбрать **Manually release this version**: после одобрения вы сами нажмёте «Выпустить».
22. ⬜️ **После выпуска** первые дни поглядывать:
    - Supabase → Logs функций `ai` и `subscription` (ошибки 5xx);
    - расходы в OpenAI и Anthropic;
    - что в таблице `subscriptions` появляются покупки (значит, уведомления App Store доходят).

---

## Тексты

**What's New (EN):**
> Minor AI 2.0 is a new app built around mind maps.
> • Turn a topic, link, YouTube video, PDF, voice note or photo of your notes into a clear mind map
> • An AI assistant that knows your maps: ask about them, change them, plan your day
> • Presentations from your maps with designs, animations and PowerPoint export
> • Edit maps together as editors or viewers
> • Today: tasks and reminders from all your maps, study cards, a home screen widget
> • Your maps sync across your devices

**What's New (RU):**
> Minor AI 2.0 — новое приложение вокруг интеллект-карт.
> • Карта из темы, ссылки, видео YouTube, PDF, голосовой заметки или фото конспекта
> • ИИ-помощник, который знает ваши карты: спросите, поменяйте, спланируйте день
> • Презентации из карт: дизайн, анимации, экспорт в PowerPoint
> • Совместные карты: редакторы и наблюдатели
> • «Сегодня»: задачи и напоминания из всех карт, карточки для учёбы, виджет
> • Карты синхронизируются между вашими устройствами

**Заметка для App Review (на английском):**
> Minor AI turns notes, links, videos and voice into mind maps and presentations with AI.
> Sign-in (email or Sign in with Apple) is required for AI features, because plans and monthly AI limits are kept on our server and shared across the user's devices. A demo account is provided above. Subscriptions can also be bought without signing in.
> Subscriptions: Minor Plus and Minor PRO, monthly and yearly, in one group. Purchases, Restore Purchases and the current plan are in Settings; the AI limits used are in Settings → Limits.
> Account deletion: Settings → Delete Account (also revokes Sign in with Apple).
> AI requests go to OpenAI and Anthropic only after the user agrees on the first use (Settings → AI Data Sharing).
