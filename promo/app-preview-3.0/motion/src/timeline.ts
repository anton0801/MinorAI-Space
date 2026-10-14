// The preview's timeline, in seconds (30 fps, 886×1920). Shared with make_audio.py through
// timeline.json, so the music hits land on the cuts.
import {Easing} from 'remotion';

export const FPS = 30;
export const TOTAL = 29.0;
export const W = 886;
export const H = 1920;

// The floating screen: the recordings are 1180×2556 (iPhone 16 at 3×, scaled).
export const CW = 660;
export const CH = (CW * 2556) / 1180;
export const FULL = W / CW; // scale at which the screen fills the frame
export const REST_Y = 1150;

export type Lang = 'ru' | 'en';

export const SCENES = {
	splash: [0, 2.4],
	type: [2.4, 5.4],
	creating: [5.4, 6.9],
	map: [6.9, 9.4],
	panel: [9.4, 10.9],
	slides: [10.9, 13.4],
	deck: [13.4, 14.9],
	presenter: [14.9, 17.4],
	today: [17.4, 19.9],
	study: [19.9, 22.9],
	wall: [22.9, 24.9],
	end: [24.9, TOTAL],
} as const;

// A piece of the recording: shown at `at` (s), source `from`–`to` (s), sped up to fit `dur`.
export type Clip = {src: Lang; at: number; from: number; to: number; dur?: number};

export const CLIPS: Record<Lang, Clip[]> = {
	ru: [
		{src: 'ru', at: 0, from: 6.6, to: 9.0},
		{src: 'ru', at: 2.4, from: 14.1, to: 16.5},
		{src: 'ru', at: 4.8, from: 18.55, to: 19.15},
		{src: 'ru', at: 5.4, from: 19.15, to: 23.6, dur: 1.5},
		{src: 'ru', at: 6.9, from: 24.05, to: 26.4, dur: 2.5},
		{src: 'ru', at: 9.4, from: 26.4, to: 28.0, dur: 1.9},
		{src: 'ru', at: 13.4, from: 33.75, to: 35.95, dur: 1.5},
		{src: 'ru', at: 14.9, from: 41.9, to: 44.4},
		{src: 'ru', at: 17.4, from: 54.7, to: 57.7, dur: 2.5},
		{src: 'ru', at: 19.9, from: 66.6, to: 68.6},
		{src: 'ru', at: 21.9, from: 70.25, to: 71.25},
	],
	en: [
		// The launch splash has no text, so both languages share it.
		{src: 'ru', at: 0, from: 6.6, to: 9.0},
		{src: 'en', at: 2.4, from: 10.95, to: 13.35},
		{src: 'en', at: 4.8, from: 15.45, to: 16.05},
		{src: 'en', at: 5.4, from: 16.05, to: 20.5, dur: 1.5},
		{src: 'en', at: 6.9, from: 20.9, to: 23.3, dur: 2.5},
		{src: 'en', at: 9.4, from: 23.3, to: 25.2, dur: 1.9},
		{src: 'en', at: 13.4, from: 36.65, to: 38.85, dur: 1.5},
		{src: 'en', at: 14.9, from: 44.8, to: 47.3},
		{src: 'en', at: 17.4, from: 57.75, to: 60.75, dur: 2.5},
		{src: 'en', at: 19.9, from: 69.7, to: 71.7},
		{src: 'en', at: 21.9, from: 73.3, to: 74.3},
	],
};

// Taps drawn on the screen: when (s) and where (0…1 of the screen), as the UI test logged them.
export type Tap = {at: number; x: number; y: number};
export const TAPS: Record<Lang, Tap[]> = {
	ru: [
		{at: 5.27, x: 0.873, y: 0.319},
		{at: 9.5, x: 0.627, y: 0.279},
		{at: 13.57, x: 0.6, y: 0.462},
		{at: 14.56, x: 0.76, y: 0.462},
		{at: 15.42, x: 0.737, y: 0.915},
		{at: 17.94, x: 0.112, y: 0.558},
		{at: 20.45, x: 0.5, y: 0.92},
		{at: 22.2, x: 0.269, y: 0.914},
	],
	en: [
		{at: 5.28, x: 0.873, y: 0.319},
		{at: 9.46, x: 0.646, y: 0.286},
		{at: 13.55, x: 0.6, y: 0.462},
		{at: 14.55, x: 0.76, y: 0.462},
		{at: 15.42, x: 0.737, y: 0.915},
		{at: 17.94, x: 0.112, y: 0.558},
		{at: 20.4, x: 0.5, y: 0.92},
		{at: 22.15, x: 0.269, y: 0.914},
	],
};

// When the app types the topic (for the key clicks in the music).
export const TYPING: Record<Lang, [number, number, number]> = {
	// start (s), end (s), characters
	ru: [2.4 + (14.6 - 14.1), 2.4 + (16.33 - 14.1), 33],
	en: [2.4 + (11.43 - 10.95), 2.4 + (12.77 - 10.95), 25],
};

export type Headline = {at: number; to: number; eyebrow?: string; lines: [string, string]; size?: number};

export const HEADLINES: Record<Lang, Headline[]> = {
	ru: [
		{at: 2.55, to: 5.3, eyebrow: '01 · Тема', lines: ['Введите', 'любую тему']},
		{at: 5.4, to: 6.85, eyebrow: '02 · ИИ', lines: ['ИИ строит', 'карту']},
		{at: 6.95, to: 9.35, eyebrow: '03 · Карта', lines: ['Вся тема', 'на одной карте'], size: 64},
		{at: 9.42, to: 10.85, eyebrow: '04 · Идеи', lines: ['Раскройте', 'каждую идею'], size: 70},
		{at: 10.95, to: 14.85, eyebrow: '05 · Слайды', lines: ['Презентация', 'из карты'], size: 70},
		{at: 14.95, to: 17.35, eyebrow: '06 · Выступление', lines: ['Выступайте', 'с подсказками'], size: 64},
		{at: 17.45, to: 19.85, eyebrow: '07 · План', lines: ['Задачи', 'на сегодня']},
		{at: 19.95, to: 22.85, eyebrow: '08 · Учёба', lines: ['Учите', 'с карточками'], size: 70},
		{at: 22.95, to: 24.75, lines: ['Всё в одном', 'приложении'], size: 72},
	],
	en: [
		{at: 2.55, to: 5.3, eyebrow: '01 · Topic', lines: ['Type', 'any topic']},
		{at: 5.4, to: 6.85, eyebrow: '02 · AI', lines: ['AI builds', 'your map']},
		{at: 6.95, to: 9.35, eyebrow: '03 · Map', lines: ['Your topic,', 'all mapped']},
		{at: 9.42, to: 10.85, eyebrow: '04 · Ideas', lines: ['Go deeper', 'on any idea']},
		{at: 10.95, to: 14.85, eyebrow: '05 · Slides', lines: ['Slides from', 'your map']},
		{at: 14.95, to: 17.35, eyebrow: '06 · Present', lines: ['Present with', 'speaker notes'], size: 66},
		{at: 17.45, to: 19.85, eyebrow: '07 · Plan', lines: ['Your tasks', 'for today']},
		{at: 19.95, to: 22.85, eyebrow: '08 · Study', lines: ['Learn with', 'flashcards']},
		{at: 22.95, to: 24.75, lines: ['All in', 'one app']},
	],
};

export const END_TEXT: Record<Lang, {tagline: string; note: string}> = {
	ru: {tagline: 'Карты, слайды и учёба с ИИ', note: 'Часть функций доступна с подпиской Minor Plus'},
	en: {tagline: 'Maps, slides and study with AI', note: 'Some features require a Minor Plus subscription'},
};

export const ease = {
	out: Easing.bezier(0.16, 1, 0.3, 1),
	inOut: Easing.bezier(0.65, 0, 0.35, 1),
	in: Easing.bezier(0.7, 0, 0.84, 0),
	back: Easing.bezier(0.34, 1.56, 0.64, 1),
	linear: (x: number) => x,
};

// Keyframes: [time, value, easing into this key]. Holds before the first and after the last.
export type Key = [number, number, ((x: number) => number)?];
export const kf = (t: number, keys: Key[]): number => {
	if (t <= keys[0][0]) return keys[0][1];
	for (let i = 1; i < keys.length; i++) {
		const [t1, v1, e] = keys[i];
		const [t0, v0] = keys[i - 1];
		if (t <= t1) {
			const p = t1 === t0 ? 1 : (t - t0) / (t1 - t0);
			return v0 + (v1 - v0) * (e ?? ease.inOut)(p);
		}
	}
	return keys[keys.length - 1][1];
};

// Deterministic pseudo-random numbers.
export const rand = (seed: number) => {
	const x = Math.sin(seed * 12.9898 + 78.233) * 43758.5453;
	return x - Math.floor(x);
};
