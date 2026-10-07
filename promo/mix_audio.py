"""Local original music bed + ElevenLabs SFX, synchronized to render.py."""
from pathlib import Path
import numpy as np
import subprocess, wave, json

OUT=Path(__file__).resolve().parent
SR=48000
N=10*SR
mix=np.zeros((N,2),dtype=np.float64)
bed=np.zeros_like(mix)
rng=np.random.default_rng(61)

def place(dst, sound, at, gain=1, pan=0):
    start=round(at*SR)
    if sound.ndim==1:sound=np.stack([sound*np.sqrt((1-pan)/2),sound*np.sqrt((1+pan)/2)],axis=1)
    end=min(len(dst),start+len(sound))
    if end>start:dst[start:end]+=sound[:end-start]*gain

def synth(freq,dur,kind='pluck'):
    t=np.arange(round(dur*SR))/SR
    if kind=='pluck':
        signal=(np.sin(2*np.pi*freq*t)+.22*np.sin(2*np.pi*freq*2*t)+.08*np.sin(2*np.pi*freq*3*t))
        env=(1-np.exp(-t*380))*np.exp(-t*5.7)
    elif kind=='bass':
        signal=np.sin(2*np.pi*freq*t)+.2*np.sin(2*np.pi*freq*2*t)
        env=(1-np.exp(-t*170))*np.exp(-t*4.5)
    else:
        signal=np.sin(2*np.pi*freq*t)+.35*np.sin(2*np.pi*freq*1.002*t)
        env=np.minimum(1,t/.35)*np.exp(-t*.75)*np.minimum(1,(dur-t)/.4)
    return signal*env

# A small original D-major motif. It gives the transitions a pulse without narration.
notes=[587.33,440.,739.99,659.25,587.33,880.,739.99,440.]
for i,at in enumerate(np.arange(.0,7.4,.5)):
    freq=notes[i%len(notes)]
    sound=synth(freq,.95)
    place(bed,sound,float(at),.066,(-.35 if i%2==0 else .35))
    place(bed,sound,float(at+.1875),.019,(.60 if i%2==0 else -.60))
for i,at in enumerate(np.arange(.0,7.4,.5)):
    t=np.arange(int(.19*SR))/SR
    phase=2*np.pi*(48*t+52*.023*(1-np.exp(-t/.023)))
    kick=np.sin(phase)*(1-np.exp(-t*850))*np.exp(-t*23)
    place(bed,kick,float(at),.13 if i%2==0 else .075)
    tick=rng.standard_normal(round(.035*SR));tick=np.diff(tick,prepend=0)
    tick*=np.exp(-np.arange(len(tick))/SR*180)
    place(bed,tick,float(at+.25),.009,.3 if i%2 else -.3)
for i,at in enumerate([0,1,2,3,4,5,6]):
    place(bed,synth(73.416 if i<4 else 55,.8,'bass'),at,.065)
for f in [293.665,369.994,440.]:
    place(bed,synth(f,2.9,'pad'),7.05,.019,0)
bed*=np.minimum(1,np.arange(N)/SR/.025)[:,None]
bed*=np.clip((10-np.arange(N)/SR)/.45,0,1)[:,None]
mix+=bed

def decode(name):
    raw=subprocess.check_output(['ffmpeg','-v','error','-i',str(OUT/'assets'/name),'-f','f32le','-ac','2','-ar',str(SR),'-'])
    a=np.frombuffer(raw,dtype='<f4').reshape(-1,2).astype(np.float64)
    # Remove only lead silence so each transient lands on its edit.
    energy=np.max(np.abs(a),axis=1)
    hits=np.flatnonzero(energy>max(.008,energy.max()*.025))
    if len(hits):a=a[max(0,int(hits[0])-int(.012*SR)):]
    peak=np.max(np.abs(a))
    return a/max(peak,1e-8)

sweep=decode('sweep.mp3');nodes=decode('nodes.mp3');logo=decode('logo.mp3')
events=[('sweep',1.54,.25),('nodes',2.26,.22),('sweep',4.03,.27),('sweep',4.60,.12),('logo',7.10,.42)]
for name,t,g in events:place(mix,{'sweep':sweep,'nodes':nodes,'logo':logo}[name],t,g)
mix*=np.minimum(1,np.arange(N)/SR/.012)[:,None]
mix*=np.clip((10-np.arange(N)/SR)/.32,0,1)[:,None]
peak=float(np.max(np.abs(mix)))
mix*=.88/max(peak,1e-9)

def wav(path,a):
    with wave.open(str(path),'wb') as f:
        f.setnchannels(2);f.setsampwidth(2);f.setframerate(SR)
        f.writeframes((np.clip(a,-1,1)*32767).astype('<i2').tobytes())
wav(OUT/'assets'/'original-music-bed.wav',bed)
wav(OUT/'assets'/'mix-premaster.wav',mix)
subprocess.run(['ffmpeg','-hide_banner','-loglevel','warning','-y','-i',str(OUT/'assets'/'mix-premaster.wav'),'-af','loudnorm=I=-16:TP=-2:LRA=8,aresample=48000,alimiter=limit=0.82:level=false:latency=true','-ar',str(SR),'-c:a','pcm_s24le',str(OUT/'soundtrack.wav')],check=True)
(OUT/'audio-cues.json').write_text(json.dumps({'duration':10,'sample_rate':SR,'music':'Original locally synthesized instrumental bed','sfx_provider':'ElevenLabs','events':[{'asset':n+'.mp3','at':t,'gain':g} for n,t,g in events]},indent=2))
print('10-second stereo soundtrack ready. Music: original local synthesis; effects: ElevenLabs.',flush=True)
