# SourceTile

Плитка источника на экране создания карты. **Новое.**

## Анатомия
Сетка 2 колонки, интервал 12, поля 16. Плитка: радиус 16, `surface` + `stroke`, отступ 14, высота от 84. Иконка 22 белым, название `subhead-medium` 15, описание `caption` 12 `text-tertiary`.

## Источники
Topic (`textformat`), Document (`doc.text`), Link (`link`), YouTube (`play.rectangle`), Voice (`mic`), From Chat (`bubble.left`).

## Состояния
- Выбрана: обводка `accent`.
- Только PRO (без подписки): в правом верхнем углу `lock.fill` + «PRO» 12 Semibold `pro`; тап открывает paywall.
