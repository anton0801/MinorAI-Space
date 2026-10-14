import React from 'react';
import {AbsoluteFill, useCurrentFrame} from 'remotion';
import {C, display, text} from './fonts';
import {FPS, Headline as H, ease, kf} from './timeline';

// Kinetic headline: the eyebrow chip slides in, each word rises out of a mask with a blur,
// the second line glows in the brand gradient; everything lifts away just before the cut.
export const Headline: React.FC<{h: H}> = ({h}) => {
	const frame = useCurrentFrame();
	const t = frame / FPS;
	if (t < h.at - 0.05 || t > h.to + 0.05) return null;
	const local = t - h.at;
	const out = kf(t, [[h.to - 0.22, 0], [h.to, 1, ease.in]]);
	const size = h.size ?? 78;
	let wordIndex = 0;
	return (
		<AbsoluteFill style={{pointerEvents: 'none'}}>
			<div
				style={{
					position: 'absolute',
					top: 128,
					left: 0,
					right: 0,
					display: 'flex',
					flexDirection: 'column',
					alignItems: 'center',
					opacity: 1 - out,
					translate: `0px ${-out * 40}px`,
					filter: `blur(${out * 14}px)`,
				}}
			>
				{h.eyebrow ? (
					<div
						style={{
							display: 'flex',
							alignItems: 'center',
							gap: 14,
							padding: '12px 26px 12px 20px',
							borderRadius: 100,
							background: 'rgba(255,255,255,0.07)',
							border: '1.5px solid rgba(255,255,255,0.14)',
							fontFamily: text,
							fontWeight: 600,
							fontSize: 25,
							letterSpacing: '0.14em',
							textTransform: 'uppercase',
							color: 'rgba(255,255,255,0.86)',
							marginBottom: 30,
							opacity: kf(local, [[0, 0], [0.25, 1, ease.out]]),
							translate: `0px ${kf(local, [[0, 24], [0.35, 0, ease.out]])}px`,
						}}
					>
						<div
							style={{
								width: 12,
								height: 12,
								borderRadius: 6,
								backgroundColor: C.mint,
								boxShadow: `0 0 16px ${C.mint}, 0 0 4px #fff`,
								opacity: 0.6 + 0.4 * Math.abs(Math.sin(local * 5)),
							}}
						/>
						{h.eyebrow}
					</div>
				) : null}
				{h.lines.map((line, li) => (
					<div
						key={li}
						style={{
							display: 'flex',
							gap: size * 0.28,
							fontFamily: display,
							fontWeight: 800,
							fontSize: size,
							lineHeight: 1.12,
							letterSpacing: '-0.035em',
							whiteSpace: 'nowrap',
						}}
					>
						{line.split(' ').map((word) => {
							const delay = 0.05 + wordIndex++ * 0.07;
							const p = kf(local, [[delay, 0], [delay + 0.5, 1, ease.out]]);
							const accent = li === 1;
							return (
								<div key={word + wordIndex} style={{overflow: 'hidden', padding: '0 0.04em 0.12em', margin: '0 -0.04em -0.12em'}}>
									<div
										style={{
											translate: `0px ${(1 - p) * 105}%`,
											filter: `blur(${(1 - p) * 10}px)`,
											color: accent ? 'transparent' : '#fff',
											backgroundImage: accent
												? `linear-gradient(100deg, ${C.lime} 0%, ${C.mint} ${35 + 20 * Math.sin(local * 2)}%, ${C.teal} 75%, ${C.lime} 100%)`
												: undefined,
											backgroundSize: accent ? '200% 100%' : undefined,
											backgroundPosition: accent ? `${(local * 40) % 200}% 0%` : undefined,
											WebkitBackgroundClip: accent ? 'text' : undefined,
											backgroundClip: accent ? 'text' : undefined,
											textShadow: accent ? undefined : '0 6px 40px rgba(0,0,0,0.5)',
										}}
									>
										{word}
									</div>
								</div>
							);
						})}
					</div>
				))}
			</div>
		</AbsoluteFill>
	);
};
