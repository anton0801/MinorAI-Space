"""Fresh, isolated App Store captures. No network generation or real account."""
import subprocess, os, time, json, argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DEVICE = None  # Explicit fresh device required; never use 'booted'.
ENV = {**os.environ, 'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer'}
SCENES = {
    'map': ['-campaign', 'travel', '-demoMap', '-demoFit'],
    'create': ['-campaign', 'travel', '-mindMode'],
    'assistant': ['-campaign', 'podcast', '-demoChatMap'],
    'slides': ['-campaign', 'podcast', '-demoDeck'],
    'today': ['-campaign', 'podcast', '-demoToday'],
    'cards': ['-campaign', 'study', '-demoMap', '-demoStudy', '-demoCardBack'],
    'quiz': ['-campaign', 'study', '-demoMap', '-demoStudy', '-demoQuiz'],
    'sources': ['-campaign', 'study', '-demoMap', '-demoSourcesSheet', '-demoFit'],
    'diagram': ['-campaign', 'podcast', '-demoDeck', '-campaignSlide', '2'],
    'export': ['-campaign', 'podcast', '-demoDeck', '-demoExportSheet'],
    'presenter': ['-campaign', 'podcast', '-demoDeck', '-demoPresentDeck', '-demoPresenterView'],
    'study-presenter': ['-campaign', 'study', '-demoDeck', '-demoPresentDeck', '-demoPresenterView'],
    'study-map': ['-campaign', 'study', '-demoMap', '-demoFit'],
    'collaboration': ['-campaign', 'travel', '-demoMap', '-demoFit', '-demoCollab'],
    'library': ['-campaign', 'travel', '-demoInstall', '-sidebarMaps'],
    'plan': ['-campaign', 'podcast', '-demoMap', '-demoFit'],
    'task': ['-campaign', 'podcast', '-demoMap', '-demoFit', '-demoTask'],
}

def sim(*args):
    subprocess.run(['xcrun', 'simctl', *args], env=ENV, check=True)

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--scene', choices=SCENES)
    p.add_argument('--device', required=True, help='UUID of a dedicated screenshot simulator')
    a = p.parse_args()
    import uuid
    DEVICE = str(uuid.UUID(a.device)).upper()
    (ROOT / 'raw').mkdir(exist_ok=True)
    sim('status_bar', DEVICE, 'override', '--time', '9:41', '--batteryState', 'charged', '--batteryLevel', '100', '--cellularBars', '4', '--wifiBars', '3', '--operatorName', '')
    for name, flags in SCENES.items():
        if a.scene and name != a.scene:
            continue
        sim('launch', '--terminate-running-process', DEVICE, 'com.minorailifegroup.MinorAI', '-didOnboard', 'YES', '-auditSignedOut', '-demoPro', '-noResume', '-appLanguage', 'en', '-AppleLanguages', '(en)', '-AppleLocale', 'en_US', *flags)
        time.sleep(5)
        sim('io', DEVICE, 'screenshot', str(ROOT / 'raw' / f'{name}.png'))
        print('CAPTURED', name, flush=True)
    (ROOT / 'capture-manifest.json').write_text(json.dumps({'device': DEVICE, 'language': 'en', 'scenes': SCENES}, indent=2))
