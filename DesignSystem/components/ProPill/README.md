# ProPill

Пилюля «Minor Plus» по центру верхней панели: вход в paywall.

## Анатомия
- 130 × 35, капсула (радиус 25), заливка `surface`, обводка `stroke` 1px.
- Логотип `minor-mark` 28 + «Minor Plus» `callout` 16 белым, интервал 5, содержимое сдвинуто влево на 4.

## Поведение
Тап открывает paywall: материал `.dark`, главный экран уезжает вверх на 50, пружина 0.8 / 0.9.

## Делать / не делать
- Показывайте только пользователям без подписки. С подпиской на этом месте — название раздела или ничего.
- Не меняйте текст на «Upgrade» или «Buy»: пилюля — название продукта.

## SwiftUI
`RoundedRectangle(cornerRadius: 25).fill(theme.chatRectangle).frame(width: 130, height: 35).overlay(RoundedRectangle(cornerRadius: 25).stroke(theme.chatStroke, lineWidth: 1))`.
