# SegmentedControl

Переключатель из двух сегментов: Monthly / Yearly и Plus / PRO на paywall, Maps / Chats в боковой панели.

## Анатомия
Дорожка 300 × 40, капсула (радиус 20), `track` + обводка `divider`. Бегунок 150 × 40 `fill-thumb`. Текст `control` 16 Medium: активный белый, у PRO — `pro`; неактивный `text-secondary`.

## Движение
Бегунок — пружина 0.4 / 0.8, цвет текста — easeInOut 0.3. Тактильный отклик selection.
