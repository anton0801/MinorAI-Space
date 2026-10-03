# Supabase для Minor AI: что это, где находится и что включить

## Что это такое

**Supabase** — облачный бэкенд, похожий на Firebase, но построенный на базе данных PostgreSQL. Это не ваш сервер и не программа на Mac: всё работает в облаке Supabase, а управляется через сайт [supabase.com](https://supabase.com).

Для Minor AI используются четыре части Supabase:

| Часть | Что делает для Minor AI |
|---|---|
| **Auth** (авторизация) | Аккаунты: почта с паролем, вход через Apple, коды подтверждения и сброса пароля |
| **Database** (PostgreSQL) | Тарифы, подписки App Store, счётчики использования и бюджет ИИ, ссылки на карты |
| **Edge Functions** (серверные функции) | `ai` ходит к OpenAI и Anthropic; `subscription` и `appstore-notifications` обрабатывают покупки; `account` удаляет аккаунт; `share` делает ссылки на карты |
| **Storage** (хранилище файлов) | Бакет `shared` с картинками карт, которыми поделились по ссылке |

Карты и чаты пользователей в Supabase **не хранятся**: они остаются на iPhone. На сервер уходят только аккаунт, тариф, счётчики и запросы к ИИ (они не сохраняются).

## Где находится

- **Проект:** «Minor Ai», ID (ref) `dgddfvotzutogrmzfscx`.
- **Организация:** Wave's Trading.
- **Регион:** eu-central-1 (Франкфурт, Германия).
- **Панель управления:** https://supabase.com/dashboard/project/dgddfvotzutogrmzfscx. Входите тем аккаунтом Supabase, в котором создан проект.
- **Адрес API:** `https://dgddfvotzutogrmzfscx.supabase.co`.
- **Ключи:**
  - Публичный ключ (`sb_publishable_…`) уже вшит в приложение. Он **не секретный**, так и задумано.
  - Секретные ключи — service role, OpenAI, Anthropic и Apple — живут только на сервере. Не вставляйте их никуда, кроме панели Supabase.

## Шаги по порядку

### 0. Подготовка (один раз, на Mac)

```bash
brew install supabase/tap/supabase
```

```bash
supabase login
```

### 1. Платный тариф Supabase Pro ($25 в месяц)

- [ ] Панель → Organization (Wave's Trading) → **Billing** → Pro.

Бесплатный проект засыпает после недели без запросов, у него меньше лимиты и нет ежедневных бэкапов. Для живого приложения нужен Pro.

### 2. Загрузить базу, функции и настройки

Порядок важен: сначала база, потом функции.

```bash
cd "$HOME/Downloads/Minor Ai" && supabase link --project-ref dgddfvotzutogrmzfscx
```

```bash
cd "$HOME/Downloads/Minor Ai" && supabase db push
```

```bash
cd "$HOME/Downloads/Minor Ai" && supabase functions deploy --project-ref dgddfvotzutogrmzfscx --use-api
```

```bash
cd "$HOME/Downloads/Minor Ai" && supabase config push --project-ref dgddfvotzutogrmzfscx
```

- [ ] `db push` создаёт:
  - лимиты на подписку;
  - месячный бюджет ИИ в долларах;
  - счётчик чтений ссылок;
  - поля для возвратов денег.
- [ ] `functions deploy` загружает 5 функций.
- [ ] `config push` включает такие настройки авторизации:
  - вход по почте с подтверждением кодом;
  - пароль от 8 символов, с буквами и цифрами;
  - анонимный вход выключен;
  - Sign in with Apple для `com.minorailifegroup.MinorAI`;
  - шаблоны писем с 6-значным кодом;
  - адрес сайта `https://minorai.site`.

Если `config push` не сработает, то же самое делается руками в панели:

- **Authentication → Sign In / Providers:**
  - **Email:** включён. Confirm email: **включено**. Минимальная длина пароля 8, требования «буквы и цифры».
  - **Anonymous sign-ins:** **выключено**.
  - **Apple:** включён. В Client IDs указать `com.minorailifegroup.MinorAI`. Секрет не нужен: вход идёт нативно из приложения.
- **Authentication → Emails → Templates:**
  - «Confirm signup»: вставить содержимое `supabase/templates/confirmation.html`, тема `Your Minor AI code: {{ .Token }}`.
  - «Reset password»: вставить `supabase/templates/recovery.html`, тема `Reset your Minor AI password: {{ .Token }}`.
- **Authentication → URL Configuration:** Site URL `https://minorai.site`.

### 3. Почта для писем с кодами — обязательно, иначе `config push` не пройдёт

Встроенная почта Supabase отправляет пару писем в час и только участникам проекта. Шаблоны писем с кодом на бесплатном тарифе без своей почты не меняются; ошибка «Email template modification is not available…» как раз об этом. SMTP уже прописан в `supabase/config.toml` под сервис Resend. Осталось:

- [ ] Зарегистрироваться на [resend.com](https://resend.com). Бесплатно до 3 000 писем в месяц.
- [ ] Resend → **Domains → Add Domain** → `minorai.site` → добавить показанные DNS-записи у регистратора домена (TXT для DKIM, MX и TXT для SPF) → дождаться статуса **Verified**. Обычно это от нескольких минут до часа.
- [ ] Resend → **API Keys → Create API Key** (доступ Sending) → скопировать ключ `re_…`.
- [ ] В своём терминале выполнить команду ниже. Она попросит вставить ключ: ввод скрыт и в историю команд не попадёт. Затем покажет изменения — подтвердите `y`.

```bash
cd "$HOME/Downloads/Minor Ai" && read -rs "SUPABASE_SMTP_PASS?Resend API key: " && export SUPABASE_SMTP_PASS && supabase config push --project-ref dgddfvotzutogrmzfscx
```

После этого письма приходят от `Minor AI <no-reply@minorai.site>` с 6-значным кодом, лимит — 60 писем в час.

- [ ] Не настраивайте SMTP вручную в панели: следующий `config push` всё равно перезапишет настройки из `config.toml`.
- [ ] **Не включайте CAPTCHA:** приложение её не поддерживает, и регистрация перестанет работать.

Если домена `minorai.site` ещё нет, можно временно прописать в `config.toml` SMTP Gmail: хост `smtp.gmail.com`, порт 587, логин — ваш Gmail, пароль — «пароль приложения» из настроек Google. Но тогда письма будут приходить с личной почты; для релиза лучше свой домен.

### 4. Секреты серверных функций

Панель → **Edge Functions → Secrets** (или команда `supabase secrets set` в вашем терминале):

| Секрет | Где взять |
|---|---|
| `OPENAI_API_KEY` | platform.openai.com → API keys. Нужен для GPT-6 Luna, GPT-6.1 Sol и GPT-6 Astra. |
| `ANTHROPIC_API_KEY` | console.anthropic.com → API Keys. Нужен для Claude Haiku, Sonnet, Opus и Fable. |
| `APPLE_TEAM_ID` | `7X47AV9RN8` |
| `APPLE_KEY_ID` | ID ключа .p8 (см. ниже) |
| `APPLE_PRIVATE_KEY` | Всё содержимое файла `.p8`, включая строки BEGIN и END |

Как получить ключ .p8: Apple Developer → **Certificates, IDs & Profiles → Keys → +** → отметить **Sign in with Apple** → Configure → App ID `com.minorailifegroup.MinorAI` → скачать `.p8`. Скачать его можно **только один раз**, сохраните файл. Этот ключ нужен, чтобы при удалении аккаунта отзывался вход через Apple; Apple этого требует.

- [ ] В консолях OpenAI и Anthropic поставить **лимит расходов и оповещения** (Usage limits / Spend limits). Это страховка от неожиданного счёта.
- [ ] `XCODE_TEST_USERS` в рабочем проекте **не задавать**.
- [ ] По желанию `MODEL_OVERRIDES`, если провайдер переименует модель, например `{"gpt-6-luna":"gpt-6.1-luna"}`.

### 5. Проверить, что всё на месте

- [ ] **Edge Functions:** 5 функций (`ai`, `subscription`, `appstore-notifications`, `account`, `share`). У `appstore-notifications` выключено «Verify JWT».
- [ ] **Table Editor:** есть таблицы `profiles`, `usage`, `device_usage`, `subscriptions`, `subscription_usage`, `shared_links`, `apple_tokens`.
- [ ] **Storage:** есть бакет `shared`.
- [ ] **Advisors → Security:** нет критичных предупреждений. Сообщения «RLS enabled, no policy» нормальны: доступ к этим таблицам только у сервера.

### 6. Проверить в приложении

- [ ] Создать аккаунт по почте → пришёл код → ввести → построить карту по теме → задать вопрос в чате.
- [ ] Выйти и войти снова; «Забыли пароль?» → код → новый пароль.
- [ ] Sign in with Apple на реальном iPhone.
- [ ] Покупка через Sandbox → тариф поменялся → «Восстановить покупки».

### 7. Связка с App Store

- [ ] App Store Connect → приложение → **App Information → App Store Server Notifications**: адрес `https://dgddfvotzutogrmzfscx.supabase.co/functions/v1/appstore-notifications`, версия 2, для Production и для Sandbox.

## Где потом смотреть, что происходит

- **Edge Functions → Logs:** ошибки функций, например кончились деньги у OpenAI или провайдер перегружен.
- **Table Editor → `usage` / `subscription_usage`:** сколько используют карт, чатов и бюджета ИИ (`spend_micros` — в миллионных долях доллара).
- **Authentication → Users:** зарегистрированные пользователи.
- **Database → Backups:** ежедневные бэкапы на тарифе Pro.
