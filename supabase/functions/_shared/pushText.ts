// Texts of remote notifications, in the language each device uses (Russian or English).

export interface PushText {
  title: string;
  body: string;
}

export type Localized = (language: string) => PushText;

function isRussian(language: string): boolean {
  return language.toLowerCase().startsWith("ru");
}

// "1 день", "3 дня", "7 дней", "21 день".
export function ruDays(n: number): string {
  const tens = n % 100;
  const ones = n % 10;
  const word = tens >= 11 && tens <= 14 ? "дней" : ones === 1 ? "день" : ones >= 2 && ones <= 4 ? "дня" : "дней";
  return `${n} ${word}`;
}

function enDays(n: number): string {
  return n === 1 ? "1 day" : `${n} days`;
}

export const PUSH = {
  collabChanged: (map: string): Localized => (language) =>
    isRussian(language)
      ? { title: map, body: "Соавтор внёс изменения в карту." }
      : { title: map, body: "A collaborator made changes to this map." },

  collabJoined: (map: string): Localized => (language) =>
    isRussian(language)
      ? { title: map, body: "К вашей карте присоединился новый участник." }
      : { title: map, body: "Someone new joined your shared map." },

  roleChanged: (map: string, role: "editor" | "viewer"): Localized => (language) =>
    isRussian(language)
      ? { title: map, body: role === "editor" ? "Теперь вы можете редактировать эту карту." : "Теперь вы можете только просматривать эту карту." }
      : { title: map, body: role === "editor" ? "You can now edit this map." : "You can now only view this map." },

  friendJoined: (days: number, waiting: boolean): Localized => (language) =>
    isRussian(language)
      ? {
        title: "Ваш друг начал пользоваться Minor AI",
        body: waiting
          ? `+${ruDays(days)} Minor Plus сохранены и включатся, когда закончится ваша подписка.`
          : `Вам +${ruDays(days)} Minor Plus. Спасибо за приглашение!`,
      }
      : {
        title: "Your friend started using Minor AI",
        body: waiting
          ? `+${enDays(days)} of Minor Plus are saved and start when your subscription ends.`
          : `You got ${enDays(days)} of Minor Plus. Thanks for inviting!`,
      },

  friendSubscribed: (percent: number): Localized => (language) =>
    isRussian(language)
      ? { title: "Ваш друг оформил подписку", body: `Вам скидка ${percent}% на любую подписку Minor. Заберите её в «Пригласить друзей».` }
      : { title: "Your friend subscribed", body: `You get ${percent}% off any Minor subscription. Claim it in Invite Friends.` },

  allowance: (percent: number): Localized => (language) =>
    isRussian(language)
      ? { title: `Использовано ${percent}% лимита ИИ`, body: "Лимит обновится 1-го числа. Подробности — в Настройках → Лимиты." }
      : { title: `${percent}% of your AI allowance used`, body: "It renews on the 1st. See Settings → Limits for details." },

  test: (): Localized => (language) =>
    isRussian(language)
      ? { title: "Minor AI", body: "Уведомления работают." }
      : { title: "Minor AI", body: "Notifications are working." },
};
