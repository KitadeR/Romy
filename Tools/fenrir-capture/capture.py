#!/usr/bin/env python3
"""Re-capture the eight authorized screens without opening the regular trip store."""
import json
from pathlib import Path
import subprocess
import time
import sys
import re

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/fenrir/screenshots'
SIMULATOR = '587D7A86-D224-45A5-9A0D-741AF45DD4D0'
BUNDLE = 'com.KitadeR.Romy'
NAMES = ['01-create', '02-home', '03-before', '04-state', '05-compare', '06-detail-a', '07-preview', '08-after']
OUT.mkdir(parents=True, exist_ok=True)
selected = {int(value) for value in sys.argv[1:]} if len(sys.argv) > 1 else set(range(1, 9))
for number, name in enumerate(NAMES, 1):
    if number not in selected:
        continue
    subprocess.run(['xcodebuildmcp', 'simulator', 'stop', '--bundle-id', BUNDLE], cwd=ROOT, check=False, capture_output=True)
    args = json.dumps({'bundleId': BUNDLE, 'launchArgs': ['-fenrir-screen', str(number)]})
    subprocess.run(['xcodebuildmcp', 'simulator', 'launch-app', '--json', args], cwd=ROOT, check=True, capture_output=True)
    time.sleep(3)  # Map tiles / native sheets settle; this does not advance the frozen scenario clock.
    if number == 8:
        for distance in (0.8, 0.18):
            snapshot = subprocess.run(
                ['xcodebuildmcp', 'ui-automation', 'snapshot-ui'], cwd=ROOT,
                check=True, capture_output=True, text=True).stdout
            refs = re.findall(r'^  (e\d+)\|swipe\|scroll-view', snapshot, re.MULTILINE)
            if not refs:
                raise RuntimeError('Cannot locate the native itinerary scroll view')
            subprocess.run(
                ['xcodebuildmcp', 'ui-automation', 'swipe', '--within-element-ref', refs[-1],
                 '--direction', 'up', '--distance', str(distance)], cwd=ROOT,
                check=True, capture_output=True)
    # XcodeBuildMCP screenshot currently exports a reduced JPEG (368x800); preserve the native PNG for submission.
    subprocess.run(['xcrun', 'simctl', 'io', SIMULATOR, 'screenshot', str(OUT / f'{name}.png')], check=True, capture_output=True)
    print(f'{name}.png', flush=True)
