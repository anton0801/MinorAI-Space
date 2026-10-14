import React from 'react';
import {Composition} from 'remotion';
import {Preview} from './Preview';
import {FPS, H, TOTAL, W} from './timeline';

export const RemotionRoot: React.FC = () => {
	return (
		<>
			<Composition id="PreviewRU" component={Preview} durationInFrames={Math.round(TOTAL * FPS)} fps={FPS} width={W} height={H} defaultProps={{lang: 'ru' as const, withAudio: false}} />
			<Composition id="PreviewEN" component={Preview} durationInFrames={Math.round(TOTAL * FPS)} fps={FPS} width={W} height={H} defaultProps={{lang: 'en' as const, withAudio: false}} />
		</>
	);
};
