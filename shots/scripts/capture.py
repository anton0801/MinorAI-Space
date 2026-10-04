#!/usr/bin/env python3
"""Capture only the dedicated Minor Shots simulator; never resolves `booted`."""
import os, subprocess, time, argparse
from PIL import Image
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
DEVICE='89F72117-04E2-4B4D-A1F4-8A669E1AEC8A'
BUNDLE='com.minorailifegroup.MinorAI'
ENV={**os.environ,'DEVELOPER_DIR':'/Applications/Xcode.app/Contents/Developer'}
SCENES=[('01-map',['-demoMap','-demoFit']),('02-sources',['-mindMode']),('03-assistant',['-demoAgent']),('04-slides',['-demoDesign']),('05-today',['-mindMode','-demoToday']),('06-study',['-demoMap','-demoStudy']),('07-together',['-demoMap','-demoFit','-demoCollab']),('08-present',['-demoPresentDeck'])]
def sim(*args):
    return subprocess.run(['xcrun','simctl',*args],env=ENV,check=True)
if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--language',choices=['en','ru'],required=True)
    parser.add_argument('--scene')
    a=parser.parse_args()
    sim('status_bar',DEVICE,'override','--time','9:41','--batteryState','charged','--batteryLevel','100','--cellularBars','4','--wifiBars','3','--operatorName','')
    for slug,flags in SCENES:
        if a.scene and not slug.startswith(a.scene): continue
        sim('launch','--terminate-running-process',DEVICE,BUNDLE,'-didOnboard','YES','-auditSignedOut','-demoPro','-appLanguage',a.language,*flags)
        time.sleep(6)
        out=ROOT/'raw'/a.language/f'{slug}.png'
        out.parent.mkdir(parents=True,exist_ok=True)
        sim('io',DEVICE,'screenshot',str(out))
        with Image.open(out) as captured:
            assert captured.size == (1320,2868)
            if 'A' in captured.getbands():
                assert captured.getchannel('A').getextrema() == (255,255)
            captured.convert('RGB').save(out,optimize=True)
        print(out,flush=True)
