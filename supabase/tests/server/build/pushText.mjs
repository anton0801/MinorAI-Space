// ../../functions/_shared/pushText.ts
function isRussian(language) {
  return language.toLowerCase().startsWith("ru");
}
function ruDays(n) {
  const tens = n % 100;
  const ones = n % 10;
  const word = tens >= 11 && tens <= 14 ? "\u0434\u043D\u0435\u0439" : ones === 1 ? "\u0434\u0435\u043D\u044C" : ones >= 2 && ones <= 4 ? "\u0434\u043D\u044F" : "\u0434\u043D\u0435\u0439";
  return `${n} ${word}`;
}
function enDays(n) {
  return n === 1 ? "1 day" : `${n} days`;
}
var PUSH = {
  collabChanged: (map) => (language) => isRussian(language) ? { title: map, body: "\u0421\u043E\u0430\u0432\u0442\u043E\u0440 \u0432\u043D\u0451\u0441 \u0438\u0437\u043C\u0435\u043D\u0435\u043D\u0438\u044F \u0432 \u043A\u0430\u0440\u0442\u0443." } : { title: map, body: "A collaborator made changes to this map." },
  collabJoined: (map) => (language) => isRussian(language) ? { title: map, body: "\u041A \u0432\u0430\u0448\u0435\u0439 \u043A\u0430\u0440\u0442\u0435 \u043F\u0440\u0438\u0441\u043E\u0435\u0434\u0438\u043D\u0438\u043B\u0441\u044F \u043D\u043E\u0432\u044B\u0439 \u0443\u0447\u0430\u0441\u0442\u043D\u0438\u043A." } : { title: map, body: "Someone new joined your shared map." },
  roleChanged: (map, role) => (language) => isRussian(language) ? { title: map, body: role === "editor" ? "\u0422\u0435\u043F\u0435\u0440\u044C \u0432\u044B \u043C\u043E\u0436\u0435\u0442\u0435 \u0440\u0435\u0434\u0430\u043A\u0442\u0438\u0440\u043E\u0432\u0430\u0442\u044C \u044D\u0442\u0443 \u043A\u0430\u0440\u0442\u0443." : "\u0422\u0435\u043F\u0435\u0440\u044C \u0432\u044B \u043C\u043E\u0436\u0435\u0442\u0435 \u0442\u043E\u043B\u044C\u043A\u043E \u043F\u0440\u043E\u0441\u043C\u0430\u0442\u0440\u0438\u0432\u0430\u0442\u044C \u044D\u0442\u0443 \u043A\u0430\u0440\u0442\u0443." } : { title: map, body: role === "editor" ? "You can now edit this map." : "You can now only view this map." },
  friendJoined: (days, waiting) => (language) => isRussian(language) ? {
    title: "\u0412\u0430\u0448 \u0434\u0440\u0443\u0433 \u043D\u0430\u0447\u0430\u043B \u043F\u043E\u043B\u044C\u0437\u043E\u0432\u0430\u0442\u044C\u0441\u044F Minor AI",
    body: waiting ? `+${ruDays(days)} Minor Plus \u0441\u043E\u0445\u0440\u0430\u043D\u0435\u043D\u044B \u0438 \u0432\u043A\u043B\u044E\u0447\u0430\u0442\u0441\u044F, \u043A\u043E\u0433\u0434\u0430 \u0437\u0430\u043A\u043E\u043D\u0447\u0438\u0442\u0441\u044F \u0432\u0430\u0448\u0430 \u043F\u043E\u0434\u043F\u0438\u0441\u043A\u0430.` : `\u0412\u0430\u043C +${ruDays(days)} Minor Plus. \u0421\u043F\u0430\u0441\u0438\u0431\u043E \u0437\u0430 \u043F\u0440\u0438\u0433\u043B\u0430\u0448\u0435\u043D\u0438\u0435!`
  } : {
    title: "Your friend started using Minor AI",
    body: waiting ? `+${enDays(days)} of Minor Plus are saved and start when your subscription ends.` : `You got ${enDays(days)} of Minor Plus. Thanks for inviting!`
  },
  friendSubscribed: (percent) => (language) => isRussian(language) ? { title: "\u0412\u0430\u0448 \u0434\u0440\u0443\u0433 \u043E\u0444\u043E\u0440\u043C\u0438\u043B \u043F\u043E\u0434\u043F\u0438\u0441\u043A\u0443", body: `\u0412\u0430\u043C \u0441\u043A\u0438\u0434\u043A\u0430 ${percent}% \u043D\u0430 \u043B\u044E\u0431\u0443\u044E \u043F\u043E\u0434\u043F\u0438\u0441\u043A\u0443 Minor. \u0417\u0430\u0431\u0435\u0440\u0438\u0442\u0435 \u0435\u0451 \u0432 \xAB\u041F\u0440\u0438\u0433\u043B\u0430\u0441\u0438\u0442\u044C \u0434\u0440\u0443\u0437\u0435\u0439\xBB.` } : { title: "Your friend subscribed", body: `You get ${percent}% off any Minor subscription. Claim it in Invite Friends.` },
  allowance: (percent) => (language) => isRussian(language) ? { title: `\u0418\u0441\u043F\u043E\u043B\u044C\u0437\u043E\u0432\u0430\u043D\u043E ${percent}% \u043B\u0438\u043C\u0438\u0442\u0430 \u0418\u0418`, body: "\u041B\u0438\u043C\u0438\u0442 \u043E\u0431\u043D\u043E\u0432\u0438\u0442\u0441\u044F 1-\u0433\u043E \u0447\u0438\u0441\u043B\u0430. \u041F\u043E\u0434\u0440\u043E\u0431\u043D\u043E\u0441\u0442\u0438 \u2014 \u0432 \u041D\u0430\u0441\u0442\u0440\u043E\u0439\u043A\u0430\u0445 \u2192 \u041B\u0438\u043C\u0438\u0442\u044B." } : { title: `${percent}% of your AI allowance used`, body: "It renews on the 1st. See Settings \u2192 Limits for details." },
  test: () => (language) => isRussian(language) ? { title: "Minor AI", body: "\u0423\u0432\u0435\u0434\u043E\u043C\u043B\u0435\u043D\u0438\u044F \u0440\u0430\u0431\u043E\u0442\u0430\u044E\u0442." } : { title: "Minor AI", body: "Notifications are working." }
};
export {
  PUSH,
  ruDays
};
