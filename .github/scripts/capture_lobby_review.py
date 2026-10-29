"""Capture the real built lobby, never a mockup. Intended for the macOS CI host."""
import json
import os
import pathlib
import signal
import subprocess
import time

OUT = pathlib.Path('shots')
OUT.mkdir(exist_ok=True)
APP = pathlib.Path('build/Build/Products/Debug-iphonesimulator/ShiftReminder.app').resolve()
APP_ID = 'com.kriswu.shiftreminder'

def sim(*args, timeout=150):
    result = subprocess.run(['xcrun', 'simctl', *args], check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
    return result.stdout.strip()

inventory = json.loads(sim('list', 'devices', 'available', '-j'))['devices']
entries = [(runtime, d) for runtime, devices in inventory.items() if 'iOS' in runtime for d in devices]
source = next((item for item in entries if item[1]['udid'] == os.environ['DEVICE']), None)
if source is None:
    raise SystemExit('Build simulator is not available for review')
phone = source
small = next((item for item in entries if item[0] == phone[0] and 'iPhone SE' in item[1]['name']), None)
if small is None:
    small = next((item for item in entries if item[0] == phone[0] and item[1]['name'] in ('iPhone 16e', 'iPhone 16', 'iPhone 17')), None)
tablet = next((item for item in entries if item[0] == phone[0] and item[1]['name'].startswith('iPad')), None)
if small is None or tablet is None:
    raise SystemExit('Full lobby review needs an available small iPhone and iPad; refusing to silently omit them')

for label, (runtime, definition), heroes in [('phone', phone, range(13)), ('small', small, [1]), ('tablet', tablet, [1])]:
    device = sim('create', 'Lobby Review ' + label, definition['deviceTypeIdentifier'], runtime)
    try:
        sim('boot', device)
        sim('bootstatus', device, '-b')
        sim('install', device, str(APP))
        data = pathlib.Path(sim('get_app_container', device, APP_ID, 'data'))
        marker = data / 'Documents/arena-capture-ready.json'
        def launch(hero, still):
            subprocess.run(['xcrun', 'simctl', 'terminate', device, APP_ID], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
            marker.unlink(missing_ok=True)
            sim('launch', device, APP_ID, '-demo', '-screen', 'arena', '-arena.previewBrawler', str(hero), '-arena.rangerStill', 'YES' if still else 'NO')
            deadline = time.monotonic() + 120
            while time.monotonic() < deadline:
                if marker.exists():
                    evidence = json.loads(marker.read_text())
                    if evidence.get('brawler') == hero and evidence.get('windowWidth', 0) > evidence.get('windowHeight', 0) > 0:
                        return evidence
                time.sleep(0.5)
            raise RuntimeError('Actual lobby failed to load: ' + label + '/' + str(hero))
        for hero in heroes:
            evidence = launch(hero, True)
            time.sleep(1)
            stem = OUT / f'lobby-{label}-{hero}'
            stem.with_suffix('.json').write_text(json.dumps(evidence, indent=2))
            sim('io', device, 'screenshot', str(stem.with_suffix('.png')))
            subprocess.run(['/tmp/check-arena-capture', str(stem.with_suffix('.png'))], check=True, timeout=30)
        if label == 'phone':
            launch(1, False)
            video = subprocess.Popen(['xcrun', 'simctl', 'io', device, 'recordVideo', '--codec=h264', str(OUT / 'lobby-motion.mp4')], stdout=subprocess.DEVNULL)
            try:
                time.sleep(12)
            finally:
                video.send_signal(signal.SIGINT)
                video.wait(timeout=30)
            if video.returncode:
                raise RuntimeError('Live lobby recording failed')
    finally:
        subprocess.run(['xcrun', 'simctl', 'shutdown', device], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
        subprocess.run(['xcrun', 'simctl', 'delete', device], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)

(OUT / 'lobby-source.json').write_text(json.dumps({'sha': os.environ['GITHUB_SHA'], 'build': os.environ['GITHUB_RUN_NUMBER'], 'heroes': 13, 'surfaces': ['phone', 'small', 'tablet']}, indent=2))
