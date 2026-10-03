# Sheet

Нижняя шторка Minor: нейтральный лист `sheet` со скруглёнными верхними углами, заголовком по центру и круглой кнопкой закрытия.

## Анатомия
- Фон `sheet`, верхние углы 20 (`radius-20`), поля 20.
- Заголовок `title-3` 20 Bold по центру; у Premium Advantage — 18 Bold.
- Закрыть: `close-fill` 30, `xmark` 16 Bold, справа на уровне заголовка.
- Внутри: группы `SettingsGroup` с подписями `overline`.
- Внизу настроек: «By Neuvra» `caption` `text-signature`.

## Поведение
Выезжает снизу с масштаба 0.95 и прозрачности 0, пружина 0.6 / 0.8.

## Где используется
Settings, Premium Advantage. Новое: Export Map, карточка узла (там добавьте ручку 36 × 5 `fill-thumb` сверху и две высоты: половина экрана и весь экран).

## SwiftUI
Сейчас шторка — `Rectangle` высотой 850 с ручным позиционированием. Для новых шторок используйте `.sheet` с `.presentationDetents([.medium, .large])` и `.presentationBackground` (iOS 16.4+) цвета `sheet`.
