# Задача для Codex №2: правки и недостающие экраны

Скопируй всё ниже линии в Codex. Пункты в квадратных скобках можно поменять.

---

Продолжаем работу в `DesignSystem/output/`. Правила те же, что в `DesignSystem/CODEX_PROMPT.md`: только токены и компоненты из `DESIGN.md`, кадр 393 × 852 с проверкой на 375 и 430, тексты интерфейса на английском, код приложения не трогать. Новые экраны добавь в `output/index.html` и `output/README.md`, скриншоты — в `output/qa/`.

## 1. Исправить

1. **Редактор, ряд чипов** (`04-editor.html` и все состояния редактора с чипами Node / Layout / Focus / Export). Под чипами лежит непрозрачная прямоугольная подложка с прямыми углами: она обрезает свечение темы и выглядит как чужой блок. Убери её. Чипы должны стоять прямо над холстом, как `NodeActionBar`.
2. **Создание карты без сети** (`02-create-offline.html`). Баннер ошибки перекрывает вторую карточку в RECENT. Баннер должен стоять над полем ввода с отступом 8 и не перекрывать содержимое: список RECENT заканчивается выше баннера (оставь одну карточку или сделай прокрутку).
3. **Paywall** (`09-paywall.html`).
   - Частицы рисуются поверх сегментов и ссылок (одна лежит на «Privacy Policy»). Частицы должны быть **под** всеми контролами и текстом, а вокруг текста — без частиц хотя бы 8pt.
   - Список преимуществ слишком короткий, а между ним и сегментами пустота. Список меняется переключателем Plus / PRO:
     - Plus: Unlimited mind maps · All sources: YouTube, voice and documents up to 300 pages · Export to PDF · Chat with any node.
     - PRO: Everything in Plus · Export to Xmind and MindNode · Share links to your maps · The most capable AI model.
   - Рядом с «Terms & Conditions | Privacy Policy» добавь «Restore Purchases» (12, тот же стиль). Без этой кнопки Apple не пропустит приложение.
4. **Тарифы источников.** В дизайн-системе противоречие (его заметил ты): SourceTile помечает YouTube и Voice как PRO, а раздел про paywall отдаёт все источники в Plus. Правило: **[Free — Topic, Link, Document до 10 страниц, From Chat. Plus и PRO — всё, включая YouTube и Voice.]** Для пользователя без подписки на плитках YouTube и Voice: `lock.fill` + «Plus», 12 Semibold, цвет `text-secondary`. Жёлтый `pro` остаётся только для PRO. Тап по плитке открывает paywall с выбранным Plus. Обнови `02-create*.html`.
5. **Your Maps.** У строящейся карты («Pitch deck · Building… 60%») миниатюра должна быть без деталей: только белый корень и одна линия-призрак `glow-solid`; шеврона справа нет.

## 2. Новые экраны

### 10. Вход (`10-sign-in.html`)
Нужен, чтобы карты, лимиты и подписка жили на сервере и не терялись при переустановке.
- Когда показывается: [при первом запуске, после онбординга].
- Фон: `bg`, свечение снизу, логотип 110 с дыханием, как на экране генерации.
- Заголовок «Save Your Maps» (`title-2`), текст «Sign in to keep your maps on all your devices.» (`subhead`, `text-secondary`).
- Кнопка **Sign in with Apple**: белый стиль Apple (белая капсула высотой 50, чёрные логотип Apple и текст). В приложении это будет системная `SignInWithAppleButton`; в макете нарисуй её как можно ближе к оригиналу, но не придумывай свой вариант.
- Под ней текстовая кнопка «Not Now» (`body-lg`, `text-secondary`) [— работа без аккаунта, лимиты считаются на устройстве].
- Внизу 12 `text-tertiary`: «By continuing you agree to the Terms and Privacy Policy.»

### 11. Онбординг (`11-onboarding-1…3.html`) [по желанию]
Три экрана, точки-индикатор (активная белая, остальные `stroke`), белая кнопка «Continue» внизу, «Skip» справа сверху.
1. «Think in Maps» / «Type a topic and Minor builds a mind map in seconds.» Иллюстрация — живая мини-карта на холсте из компонентов `MindNode` и `Connector`.
2. «Start From Anything» / «Drop a PDF, paste a link or a YouTube video, or just talk.» — плитки источников веером.
3. «Go Deeper With AI» / «Tap any idea and Minor expands it into new branches.» — узел в состоянии генерации с призраками детей.

### 12. Настройки (`12-settings.html`)
Обновлённая шторка Settings вместо текущей:
- ACCOUNT: строка с почтой Apple ID (`text-secondary` справа); Subscription — «Minor Plus · Renews Nov 2» справа, тап открывает системное управление подписками; Restore Purchases.
- PREMIUM: Upgrade to PRO (только без PRO); Chat Themes (раскрывает кружки тем, как сейчас).
- GENERAL: App Language; Privacy Policy; Terms of Use.
- Отдельной группой: Log Out.
- Отдельной группой, текст `danger`: Delete Account. Apple требует удаление аккаунта внутри приложения.
- API Keys убрать (остаётся только в режиме разработчика, в макете не показывать).
- Внизу «By Neuvra» и версия «Version 2.0» (`caption`, `text-tertiary`).
- Второе состояние `12-settings-delete.html`: системный alert «Delete your account?» / «Your maps and chats will be permanently deleted. This can’t be undone.» / кнопки «Delete Account» (красная) и «Cancel».

### 13. Экран запуска (`13-launch.html`)
Фон `bg` темы Classic и знак Minor 110 при прозрачности 0.2 в той же точке, что водяной знак главного экрана, чтобы переход в приложение был бесшовным. Больше ничего.

### 14. Скриншоты для App Store [по желанию] (`output/app-store/`)
5 кадров 1290 × 2796: сверху заголовок 2 строки (`title-2`, увеличенный пропорционально) и под ним экран в рамке телефона. Темы кадров разные:
1. «Turn Any Topic Into a Mind Map» — редактор, Classic.
2. «Start From a PDF, Link or Video» — создание карты, Aqua.
3. «Expand Any Idea With AI» — узел в генерации, Vio.
4. «Ask About Any Branch» — чат по узлу, Rosa.
5. «Export to PDF, Xmind and More» — экспорт, Flam.

## Как сдать работу

Допиши `output/README.md`: что исправлено (до / после), какие экраны добавлены, что требует моего решения.
