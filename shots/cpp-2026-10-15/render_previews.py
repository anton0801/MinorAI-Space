"""Export exact-size PNGs from local campaign HTML layouts."""
from pathlib import Path
import subprocess, json, argparse

ROOT = Path(__file__).resolve().parent
CHROME = Path.home() / 'Library/Caches/ms-playwright/chromium_headless_shell-1243/chrome-headless-shell-mac-arm64/chrome-headless-shell'
OUT = ROOT / 'artwork'
OUT.mkdir(exist_ok=True)

def render(source, dest, w, h):
    result = subprocess.run([str(CHROME), '--no-sandbox', '--disable-gpu', '--hide-scrollbars', '--user-data-dir=/tmp/minor-cpp-chrome', '--virtual-time-budget=1000', f'--window-size={w},{h}', f'--screenshot={dest}', source.as_uri()], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stderr)
    if not dest.exists():
        raise RuntimeError(f'No screenshot produced: {dest}')
    print(dest.name, flush=True)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--all', action='store_true')
    args = parser.parse_args()
    data=json.loads((ROOT/'campaign.json').read_text())
    heroes=['maps-hero', 'study-hero', 'slides-hero', 'tasks-hero']
    for key in data['cards'] if args.all else heroes:
        render(ROOT/'layouts'/f'{key}.html', OUT/f'{key}.png', 1320, 2868)
    board='''<!doctype html><html lang="en"><meta charset="utf-8"><style>
*{box-sizing:border-box}body{margin:0;background:#f5f3ed;color:#20362a;font:16px -apple-system,BlinkMacSystemFont,sans-serif;padding:38px 40px}h1{font-size:35px;letter-spacing:-1.4px;margin:0 0 9px}p{color:#627066;margin:0 0 25px}.grid{display:flex;gap:20px}figure{margin:0;width:325px}img{width:325px;display:block;border-radius:10px}figcaption{font-size:16px;padding-top:13px;font-weight:600}.status{margin-top:22px;color:#716337;font-size:14px}
</style><h1>Minor AI · Four ways in.</h1><p>English (US) · Custom Product Pages · Minor AI 3.0.1</p><div class="grid">'''
    for key,label in zip(heroes,['01 · Mind maps','02 · Study','03 · Presentations','04 · Tasks']):
        board+=f'<figure><img src="{key}.png"><figcaption>{label}</figcaption></figure>'
    board+='</div><div class="status">Fresh app captures · Real-life examples · 1320 × 2868 · English (US)</div></html>'
    (OUT/'overview.html').write_text(board)
    render(OUT/'overview.html', OUT/'overview.png', 1440, 940)
