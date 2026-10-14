#!/usr/bin/env python3
"""Minor AI 3.0 — App Store preview: 886×1920, 30 fps, under 30 s, H.264 + AAC.

Cuts the footage recorded by record.sh (real app screens on the iPhone 16 simulator) at the
scene marks, speeds each scene to its slot, places the screen under a caption, draws the taps,
dissolves between scenes and ends on the logo with the subscription note.

Usage:
  python3 promo/app-preview-3.0/render.py <ru|en> <raw folder> [--stills]
The raw folder holds <lang>.mp4, <lang>.start and <lang>.marks from record.sh.
"""
from pathlib import Path
import math, subprocess, sys, wave
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
W, H, FPS = 886, 1920, 30
SRC_W, SRC_H = 1178, 2556
SCREEN_H = 1540
SCREEN_W = round(SCREEN_H * SRC_W / SRC_H)          # 710
SX, SY = (W - SCREEN_W) // 2, 330
RADIUS = 96
XF = 0.3                                              # dissolve between scenes
END = 2.6                                             # the end card
MINT = (47, 255, 158)
WHITE = (245, 248, 247)
MUTED = (150, 160, 156)
FONT = '/System/Library/Fonts/SFNS.ttf'
LOGO = ROOT / 'DesignSystem/assets/Logos/minor-mark@3x.png'

COPY = {
    'ru': {
        'c1': 'Помощник для учёбы\nи работы',
        'c2': 'Любая тема —\nготовая карта',
        'c3': 'Всё об идее —\nв одно касание',
        'c4': 'Из карты —\nв презентацию',
        'c5': 'Задачи\nна сегодня',
        'c6': 'Повторяйте\nпо карточкам',
        'tagline': 'Придай мыслям форму',
        'note': 'Часть функций доступна\nс подпиской Minor Plus',
    },
    'en': {
        'c1': 'Your AI partner\nfor study and work',
        'c2': 'Any topic,\na ready map',
        'c3': 'Every idea,\none tap away',
        'c4': 'From map\nto presentation',
        'c5': 'Tasks\nfor today',
        'c6': 'Review\nwith flashcards',
        'tagline': 'Give your thoughts shape',
        'note': 'Some features require\na Minor Plus subscription',
    },
}

# (caption, start mark, offset, end mark, offset, seconds on screen)
SEGMENTS = [
    ('c1', 'home', 1.4, 'newmap', 0.4, 3.0),
    ('c2', 'newmap', -0.4, 'creating', 0.0, 3.2),
    ('c2', 'creating', 0.0, 'map', 3.0, 4.2),
    ('c3', 'map', 3.2, 'more', 1.2, 4.2),
    ('c4', 'deck', 0.0, 'present', -0.2, 2.6),
    ('c4', 'present', -0.2, 'present', 6.0, 3.0),
    ('c5', 'today', 0.2, 'today', 5.4, 3.2),
    ('c6', 'study', 0.4, 'study', 8.2, 3.6),
]


def clamp(x): return min(1.0, max(0.0, x))
def ease(x): return 1 - (1 - clamp(x)) ** 3


_fonts = {}
def font(size, weight=700):
    key = (size, weight)
    if key not in _fonts:
        f = ImageFont.truetype(FONT, size)
        f.set_variation_by_axes([100, min(96, max(17, size)), 400, weight])
        _fonts[key] = f
    return _fonts[key]


def read_marks(raw, lang):
    start = float((raw / f'{lang}.start').read_text())
    marks, taps = {}, []
    for line in (raw / f'{lang}.marks').read_text().splitlines():
        p = line.split('|')
        if p[1] == 'mark':
            marks[p[2]] = float(p[3]) - start
        elif p[1] == 'tap':
            taps.append((float(p[4]) - start, float(p[2]), float(p[3])))
    return marks, taps


def background():
    y = np.linspace(0, 1, H)[:, None]
    top, bottom = np.array([10, 11, 12]), np.array([6, 8, 8])
    img = (top * (1 - y) + bottom * y)[..., None].repeat(1, axis=2)
    img = np.broadcast_to(img.reshape(H, 1, 3), (H, W, 3)).astype(np.float32)
    glow = Image.new('RGB', (W, H), (0, 0, 0))
    d = ImageDraw.Draw(glow)
    d.ellipse((W * 0.45, -260, W * 1.35, 420), fill=(18, 70, 48))
    d.ellipse((-W * 0.5, H * 0.72, W * 0.5, H * 1.15), fill=(48, 30, 74))
    glow = np.asarray(glow.filter(ImageFilter.GaussianBlur(160)), dtype=np.float32)
    img = np.clip(img + glow * 0.9, 0, 255)
    base = Image.fromarray(img.astype(np.uint8)).convert('RGBA')
    # A soft shadow and a hairline around the screen.
    shadow = Image.new('L', (W, H), 0)
    ImageDraw.Draw(shadow).rounded_rectangle((SX, SY + 18, SX + SCREEN_W, SY + SCREEN_H + 18), RADIUS, fill=150)
    shadow = shadow.filter(ImageFilter.GaussianBlur(36))
    base.paste((0, 0, 0, 255), (0, 0), shadow)
    return base


def screen_mask():
    mask = Image.new('L', (SCREEN_W, SCREEN_H), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, SCREEN_W - 1, SCREEN_H - 1), RADIUS, fill=255)
    return mask


def caption_layer(text, alpha, rise):
    layer = Image.new('RGBA', (W, 320), (0, 0, 0, 0))
    if alpha <= 0:
        return layer
    d = ImageDraw.Draw(layer)
    lines = text.split('\n')
    size = 66
    while max(d.textlength(l, font=font(size)) for l in lines) > W - 96:
        size -= 2
    line_h = round(size * 1.16)
    block = line_h * len(lines)
    top = 170 - block / 2 + rise
    a = round(255 * clamp(alpha))
    d.rounded_rectangle((W / 2 - 26, top - 34, W / 2 + 26, top - 26), 4, fill=(*MINT, a))
    for i, l in enumerate(lines):
        d.text((W / 2, top + i * line_h + line_h / 2), l, font=font(size), fill=(*WHITE, a), anchor='mm')
    return layer


def tap_layer(taps_out, t):
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for (tt, x, y) in taps_out:
        p = (t - tt) / 0.5
        if p < 0 or p > 1:
            continue
        cx, cy = SX + x * SCREEN_W, SY + y * SCREEN_H
        r = 16 + 40 * ease(p)
        ring = round(200 * (1 - p))
        dot = round(110 * (1 - clamp(p * 1.6)))
        d.ellipse((cx - 22, cy - 22, cx + 22, cy + 22), fill=(255, 255, 255, dot))
        d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=(255, 255, 255, ring), width=4)
    return layer


def segment_frames(raw, lang, src0, src1, seconds):
    """The segment's frames at screen size, sped to fill `seconds`."""
    speed = (src1 - src0) / seconds
    n = round(seconds * FPS)
    cmd = ['ffmpeg', '-v', 'error', '-ss', f'{src0:.3f}', '-i', str(raw / f'{lang}.mp4'), '-t', f'{src1 - src0 + 0.5:.3f}',
           '-vf', f'setpts=(PTS-STARTPTS)/{speed:.5f},fps={FPS},scale={SCREEN_W}:{SCREEN_H}:flags=lanczos',
           '-frames:v', str(n), '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-']
    data = subprocess.run(cmd, check=True, capture_output=True).stdout
    size = SCREEN_W * SCREEN_H * 3
    frames = [np.frombuffer(data[i * size:(i + 1) * size], dtype=np.uint8).reshape(SCREEN_H, SCREEN_W, 3) for i in range(len(data) // size)]
    while len(frames) < n:
        frames.append(frames[-1])
    return frames, speed


def end_card(lang, p):
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    logo = Image.open(LOGO).convert('RGBA')
    side = round(230 * (0.92 + 0.08 * ease(p / 0.6)))
    logo = logo.resize((side, side), Image.Resampling.LANCZOS)
    a = clamp(p / 0.35)
    if a < 1:
        logo.putalpha(logo.getchannel('A').point(lambda v: round(v * a)))
    img.alpha_composite(logo, (round(W / 2 - side / 2), round(H * 0.36 - side / 2)))
    d = ImageDraw.Draw(img)
    ta = round(255 * clamp((p - 0.15) / 0.4))
    d.text((W / 2, H * 0.36 + 200), 'Minor AI', font=font(92, 760), fill=(*WHITE, ta), anchor='mm')
    d.text((W / 2, H * 0.36 + 290), COPY[lang]['tagline'], font=font(44, 500), fill=(*MUTED, ta), anchor='mm')
    na = round(220 * clamp((p - 0.35) / 0.4))
    for i, line in enumerate(COPY[lang]['note'].split('\n')):
        d.text((W / 2, H - 230 + i * 44), line, font=font(32, 500), fill=(*MUTED, na), anchor='mm')
    return img


def render(lang, raw, stills=False):
    marks, taps = read_marks(raw, lang)
    bg = background()
    mask = screen_mask()
    # Where each scene sits on the output timeline (scenes overlap by XF to dissolve).
    plan, t = [], 0.0
    for i, (cap, a0, o0, a1, o1, secs) in enumerate(SEGMENTS):
        src0, src1 = marks[a0] + o0, marks[a1] + o1
        plan.append(dict(cap=cap, src0=src0, src1=src1, secs=secs, start=t))
        t += secs - XF
    end_start = t
    total = end_start + END
    print(f'{lang}: {total:.2f} s')
    # Taps on the output timeline.
    for seg in plan:
        speed = (seg['src1'] - seg['src0']) / seg['secs']
        seg['taps'] = [(seg['start'] + (tt - seg['src0']) / speed, x, y) for (tt, x, y) in taps if seg['src0'] <= tt <= seg['src1']]
    # Caption groups: a caption stays put across scenes that share it.
    groups = []
    for seg in plan:
        if groups and groups[-1]['cap'] == seg['cap']:
            groups[-1]['end'] = seg['start'] + seg['secs']
        else:
            groups.append(dict(cap=seg['cap'], start=seg['start'], end=seg['start'] + seg['secs']))

    def caption_at(tt):
        layer = Image.new('RGBA', (W, 320), (0, 0, 0, 0))
        for g in groups:
            if g['start'] - 0.01 <= tt <= g['end']:
                a_in = clamp((tt - g['start'] - 0.1) / 0.35)
                a_out = clamp((g['end'] - tt) / XF)
                rise = 18 * (1 - ease((tt - g['start'] - 0.1) / 0.45))
                layer.alpha_composite(caption_layer(COPY[lang][g['cap']], min(a_in, a_out), rise))
        return layer

    out_path = HERE / f'Minor-AI-App-Preview-3.0-{lang}.mp4'
    silent = HERE / f'.silent-{lang}.mp4'
    n_total = round(total * FPS)
    still_times = [1.5, 5.0, 9.5, 13.0, 16.5, 19.5, 22.5, 25.5, total - 0.8]
    encoder = None
    if not stills:
        encoder = subprocess.Popen(['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', str(FPS), '-i', '-',
                                    '-c:v', 'libx264', '-profile:v', 'high', '-level', '4.0', '-pix_fmt', 'yuv420p', '-preset', 'slow',
                                    # Apple's target for previews: 10–12 Mbps, so a constant 11.
                                    '-b:v', '11M', '-minrate', '11M', '-maxrate', '11M', '-bufsize', '22M', '-x264-params', 'nal-hrd=cbr:force-cfr=1',
                                    '-r', str(FPS), '-movflags', '+faststart', str(silent)],
                                   stdin=subprocess.PIPE)
    cache = {}

    def frames_of(i):
        if i not in cache:
            seg = plan[i]
            cache[i], _ = segment_frames(raw, lang, seg['src0'], seg['src1'], seg['secs'])
            for k in list(cache):
                if k < i - 1:
                    del cache[k]
        return cache[i]

    def scene_frame(i, tt):
        seg = plan[i]
        frames = frames_of(i)
        k = min(len(frames) - 1, max(0, round((tt - seg['start']) * FPS)))
        img = bg.copy()
        img.paste(Image.fromarray(frames[k]), (SX, SY), mask)
        ImageDraw.Draw(img).rounded_rectangle((SX, SY, SX + SCREEN_W - 1, SY + SCREEN_H - 1), RADIUS, outline=(255, 255, 255, 34), width=2)
        img.alpha_composite(tap_layer(seg['taps'], tt))
        return img

    stills_out = []
    for f in range(n_total):
        tt = f / FPS
        if stills and not any(abs(tt - s) < 0.5 / FPS for s in still_times):
            continue
        active = [i for i, seg in enumerate(plan) if seg['start'] <= tt < seg['start'] + seg['secs']]
        if tt >= end_start - XF and tt < end_start:
            active = [len(plan) - 1] if not active else active
        if active:
            i = active[-1]
            img = scene_frame(i, tt)
            if len(active) > 1:
                w = clamp((tt - plan[active[-1]]['start']) / XF)
                prev = scene_frame(active[0], tt)
                img = Image.blend(prev, img, w)
        else:
            img = None
        if tt >= end_start - XF:
            card = bg.copy()
            card.alpha_composite(end_card(lang, tt - end_start + XF))
            if img is None:
                img = card
            else:
                img = Image.blend(img, card, clamp((tt - (end_start - XF)) / XF))
        img = img.copy()
        img.alpha_composite(caption_at(tt), (0, 0))
        rgb = img.convert('RGB')
        if stills:
            stills_out.append(rgb)
        else:
            encoder.stdin.write(rgb.tobytes())
    if stills:
        sheet = Image.new('RGB', (len(stills_out) * 300 + (len(stills_out) - 1) * 10, 650), (40, 40, 40))
        for i, im in enumerate(stills_out):
            sheet.paste(im.resize((300, 650)), (i * 310, 0))
        path = HERE / f'.stills-{lang}.jpg'
        sheet.save(path, quality=85)
        print(path)
        return
    encoder.stdin.close()
    encoder.wait()
    # Original music bed and sound cues, then the final file.
    cues = [p['start'] for p in plan[1:]] + [end_start - XF]
    nodes_at = plan[2]['start'] + (marks['map'] - plan[2]['src0']) * plan[2]['secs'] / (plan[2]['src1'] - plan[2]['src0'])
    wav = HERE / f'.audio-{lang}.wav'
    make_audio(wav, total, cues, nodes_at, end_start)
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(silent), '-i', str(wav), '-map', '0:v:0', '-map', '1:a:0', '-c:v', 'copy',
                    '-c:a', 'aac', '-b:a', '256k', '-ar', '48000', '-ac', '2', '-shortest', '-movflags', '+faststart', str(out_path)], check=True)
    silent.unlink(missing_ok=True)
    wav.unlink(missing_ok=True)
    print(out_path)


SR = 48000


def make_audio(path, duration, cues, nodes_at, logo_at):
    n = int(duration * SR)
    bed = np.zeros((n, 2))
    rng = np.random.default_rng(30)

    def place(dst, sound, at, gain=1.0, pan=0.0):
        s = round(at * SR)
        if sound.ndim == 1:
            sound = np.stack([sound * math.sqrt((1 - pan) / 2), sound * math.sqrt((1 + pan) / 2)], axis=1)
        e = min(len(dst), s + len(sound))
        if e > s:
            dst[s:e] += sound[:e - s] * gain

    def synth(freq, dur, kind='pluck'):
        t = np.arange(round(dur * SR)) / SR
        if kind == 'pluck':
            sig = np.sin(2 * np.pi * freq * t) + .22 * np.sin(4 * np.pi * freq * t) + .08 * np.sin(6 * np.pi * freq * t)
            env = (1 - np.exp(-t * 380)) * np.exp(-t * 5.2)
        elif kind == 'bass':
            sig = np.sin(2 * np.pi * freq * t) + .2 * np.sin(4 * np.pi * freq * t)
            env = (1 - np.exp(-t * 170)) * np.exp(-t * 4.0)
        else:
            sig = np.sin(2 * np.pi * freq * t) + .35 * np.sin(2 * np.pi * freq * 1.002 * t)
            env = np.minimum(1, t / .4) * np.exp(-t * .6) * np.minimum(1, (dur - t) / .5)
        return sig * env

    # An original D-major figure with a soft pulse; the bass moves every two bars.
    notes = [587.33, 440.0, 739.99, 659.25, 587.33, 880.0, 739.99, 493.88]
    bass = [73.42, 73.42, 61.74, 61.74, 55.0, 55.0, 65.41, 65.41]
    beat = 0.5
    for i, at in enumerate(np.arange(0, logo_at, beat)):
        s = synth(notes[i % len(notes)], .95)
        place(bed, s, float(at), .055, -.35 if i % 2 == 0 else .35)
        place(bed, s, float(at + .1875), .016, .6 if i % 2 == 0 else -.6)
        t = np.arange(int(.19 * SR)) / SR
        kick = np.sin(2 * np.pi * (48 * t + 52 * .023 * (1 - np.exp(-t / .023)))) * (1 - np.exp(-t * 850)) * np.exp(-t * 23)
        place(bed, kick, float(at), .11 if i % 2 == 0 else .06)
        tick = np.diff(rng.standard_normal(round(.035 * SR)), prepend=0) * np.exp(-np.arange(round(.035 * SR)) / SR * 180)
        place(bed, tick, float(at + .25), .008, .3 if i % 2 else -.3)
        if i % 2 == 0:
            place(bed, synth(bass[(i // 2) % len(bass)], .9, 'bass'), float(at), .06)
    for f in [293.66, 369.99, 440.0, 587.33]:
        place(bed, synth(f, duration - logo_at + .2, 'pad'), logo_at, .017)
    mix = bed.copy()

    def decode(name):
        raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(ROOT / 'promo/assets' / name), '-f', 'f32le', '-ac', '2', '-ar', str(SR), '-'],
                             check=True, capture_output=True).stdout
        a = np.frombuffer(raw, dtype='<f4').reshape(-1, 2).astype(np.float64)
        energy = np.max(np.abs(a), axis=1)
        hits = np.flatnonzero(energy > max(.008, energy.max() * .025))
        if len(hits):
            a = a[max(0, int(hits[0]) - int(.012 * SR)):]
        return a / max(np.max(np.abs(a)), 1e-8)

    sweep, nodes, logo = decode('sweep.mp3'), decode('nodes.mp3'), decode('logo.mp3')
    for c in cues[:-1]:
        place(mix, sweep, c - .05, .10)
    place(mix, nodes, nodes_at, .16)
    place(mix, logo, logo_at, .36)
    mix *= np.minimum(1, np.arange(n) / SR / .02)[:, None]
    mix *= np.clip((duration - np.arange(n) / SR) / .6, 0, 1)[:, None]
    mix *= .88 / max(float(np.max(np.abs(mix))), 1e-9)
    pre = path.with_suffix('.pre.wav')
    with wave.open(str(pre), 'wb') as f:
        f.setnchannels(2); f.setsampwidth(2); f.setframerate(SR)
        f.writeframes((np.clip(mix, -1, 1) * 32767).astype('<i2').tobytes())
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(pre), '-af', 'loudnorm=I=-16:TP=-2:LRA=8,aresample=48000', '-ar', str(SR),
                    '-c:a', 'pcm_s16le', str(path)], check=True)
    pre.unlink(missing_ok=True)


if __name__ == '__main__':
    lang, raw = sys.argv[1], Path(sys.argv[2])
    render(lang, raw, stills='--stills' in sys.argv)
