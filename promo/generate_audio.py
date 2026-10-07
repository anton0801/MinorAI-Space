"""Generate the commissioned soundtrack; key is read privately, never saved."""
from pathlib import Path
import getpass, json, urllib.request, urllib.error, ssl

OUT = Path(__file__).resolve().parent / 'assets'
KEY = getpass.getpass('ElevenLabs key (not saved): ')
jobs = [
    ('sweep.mp3', 'sound-generation', {'text': 'One short premium UI motion transition: silky stereo air whoosh accelerating inward, ending with a tight soft low thump and a tiny bright glass click. Clean, polished technology advertising sound design. No voice, no music, isolated sound with a brief decay.', 'duration_seconds': 1.0, 'prompt_influence': 0.55}),
    ('nodes.mp3', 'sound-generation', {'text': 'A cascade of five beautifully tactile soft digital glass bubble clicks, ascending gently in pitch, like little mind map nodes magnetically snapping into place. Crisp, delicate, premium futuristic user interface. No music or voices. Isolated clean sound.', 'duration_seconds': 1.5, 'prompt_influence': 0.55}),
    ('logo.mp3', 'sound-generation', {'text': 'Premium futuristic app sonic logo. A rounded deep soft impact followed immediately by two pure shimmering glass bell notes rising to a satisfying bright major resolution. Elegant wide stereo air and smooth short reverb tail, clean luxurious modern technology feel. No speech or vocals.', 'duration_seconds': 2.0, 'prompt_influence': 0.55}),
]
for name, endpoint, payload in jobs:
    target = OUT / name
    if target.exists():
        print(name, 'already generated', flush=True)
        continue
    print('Generating', name, flush=True)
    req = urllib.request.Request('https://api.elevenlabs.io/v1/' + endpoint, data=json.dumps(payload).encode(), headers={'xi-api-key': KEY, 'Content-Type': 'application/json'}, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=240, context=ssl.create_default_context(cafile='/etc/ssl/cert.pem')) as response:
            data = response.read()
            target.write_bytes(data)
            print(name, len(data), 'bytes', flush=True)
    except urllib.error.HTTPError as e:
        print('Generation failed:', e.code, e.read().decode()[:800], flush=True)
        raise SystemExit(1)
    except Exception as e:
        print('Request failed:', type(e).__name__, str(e), flush=True)
        raise SystemExit(1)
KEY = None
(OUT / 'audio-prompts.json').write_text(json.dumps([{'file': n, 'endpoint': e, 'request': p} for n,e,p in jobs], ensure_ascii=False, indent=2))
