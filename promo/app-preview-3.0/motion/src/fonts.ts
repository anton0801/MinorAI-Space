import {loadFont as loadUnbounded} from '@remotion/google-fonts/Unbounded';
import {loadFont as loadInter} from '@remotion/google-fonts/Inter';

export const display = loadUnbounded('normal', {weights: ['600', '700', '800'], subsets: ['latin', 'cyrillic']}).fontFamily;
export const text = loadInter('normal', {weights: ['500', '600', '700'], subsets: ['latin', 'cyrillic']}).fontFamily;

export const C = {
	bg: '#040605',
	lime: '#B6FF5C',
	mint: '#3DF5B4',
	teal: '#22C7E8',
	violet: '#7D6BFF',
};
