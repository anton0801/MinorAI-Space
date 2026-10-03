# GenerationStatus

Индикатор построения карты: логотип с дышащим свечением и список шагов. **Новое.**

## Анатомия
- Логотип `minor-mark` 110 белым; под ним круг свечения `glow-solid`, размытие 30, прозрачность 0.22 → 0.4, 2.4 с на цикл.
- Карточка шагов: радиус 16, `surface` + `stroke`, отступы 20 × 18, интервал 14. Шаг — круг 22 + текст `subhead` 15.
- Готово: круг `send-fill` с `checkmark` и временем справа 12 `text-tertiary`. Сейчас: обводка `glow-solid` и пульсирующая точка 8. Дальше: обводка `stroke`, текст `text-tertiary`.

## Шаги
Reading “…” → Finding the main ideas → Building branches → Adding details.
