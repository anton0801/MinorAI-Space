import React from 'react';
import {Audio} from '@remotion/media';
import {AbsoluteFill, staticFile, useCurrentFrame} from 'remotion';
import {Backdrop, Burst, Grain} from './Backdrop';
import {Card} from './Card';
import {EndCard} from './EndCard';
import {Headline} from './Headline';
import {SlideRing} from './SlideRing';
import {Wall} from './Wall';
import {FPS, HEADLINES, Lang, REST_Y, SCENES, W, ease, kf} from './timeline';

export type PreviewProps = {lang: Lang; withAudio: boolean};

export const Preview: React.FC<PreviewProps> = ({lang, withAudio}) => {
	const frame = useCurrentFrame();
	const t = frame / FPS;
	const energy = kf(t, [
		[0, 0],
		[2.2, 0],
		[2.9, 1, ease.out],
		[6.85, 1],
		[6.95, 1.9, ease.linear],
		[8, 1.1, ease.out],
		[10.85, 1.1],
		[11.05, 1.8, ease.out],
		[12.5, 1.1],
		[22.9, 1.2],
		[24.85, 0.5],
		[25.0, 1.6, ease.out],
		[27, 0.9],
	]);
	return (
		<AbsoluteFill style={{backgroundColor: '#040605'}}>
			<Backdrop energy={energy} />
			<SlideRing lang={lang} start={SCENES.slides[0]} end={SCENES.deck[1] - 0.2} />
			<Wall lang={lang} start={SCENES.wall[0]} end={SCENES.wall[1]} />
			<Burst t={t - 2.4} x={W / 2} y={REST_Y} scale={0.8} seed={3} />
			<Burst t={t - 6.9} x={W / 2} y={REST_Y} seed={7} layer="rings" />
			<Burst t={t - 10.95} x={W / 2} y={1190} scale={0.7} seed={11} />
			<Card lang={lang} />
			<Burst t={t - 6.9} x={W / 2} y={REST_Y} seed={7} layer="sparks" />
			<Burst t={t - 24.9} x={W / 2} y={760} scale={0.9} seed={19} />
			{HEADLINES[lang].map((h, i) => (
				<Headline key={i} h={h} />
			))}
			<EndCard lang={lang} start={SCENES.end[0]} />
			<Grain />
			{/* Fade from and to black at the very ends. */}
			<AbsoluteFill style={{backgroundColor: '#000', opacity: kf(t, [[0, 1], [0.25, 0], [28.4, 0], [29, 1, ease.inOut]])}} />
			{withAudio ? <Audio src={staticFile(`audio-${lang}.wav`)} /> : null}
		</AbsoluteFill>
	);
};
