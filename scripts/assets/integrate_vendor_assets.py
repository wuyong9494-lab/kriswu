#!/usr/bin/env python3
"""Build the game's pinned runtime selection from all eleven licensed packs."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'art/vendor'
DEST = ROOT / 'App/ArenaVendor'

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def build():
    DEST.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((SOURCE / 'manifest.json').read_text())
    packs = {p['id']: p for p in manifest['packs']}
    records = []

    def put(pack, relative, name, usage, audio=False):
        src = SOURCE / pack / relative
        expected = next(f['sha256'] for f in packs[pack]['files'] if f['path'] == relative)
        assert digest(src) == expected, f'Changed source: {src}'
        dst = DEST / name
        if audio:
            subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(src), '-map_metadata', '-1',
                            '-vn', '-ac', '1', '-ar', '44100', '-af', 'volume=0.65',
                            '-c:a', 'pcm_s16le', str(dst)], check=True)
        else:
            shutil.copy2(src, dst)
        records.append(dict(pack=pack, source=relative, sourceSHA256=expected,
                            file=name, sha256=digest(dst), bytes=dst.stat().st_size, usage=usage))
        return dst

    # Keep the original characters and their clip timing; mount the source axe on
    # the same right-hand bone and transform as the authored embedded weapon.
    axe = put('kaykit-adventurers', 'Assets/gltf/axe_2handed.gltf', 'vendor_axe.gltf', 'barbarian.hand')
    put('kaykit-adventurers', 'Assets/gltf/axe_2handed.bin', 'vendor_axe.bin', 'barbarian.hand')
    put('kaykit-adventurers', 'Assets/gltf/barbarian_texture.png', 'vendor_axe_texture.png', 'barbarian.hand')
    data = json.loads(axe.read_text())
    data['buffers'][0]['uri'] = 'vendor_axe.bin'
    data['images'][0]['uri'] = 'vendor_axe_texture.png'
    axe.write_text(json.dumps(data, separators=(',', ':')) + '\n')
    for r in records:
        if r['file'] == axe.name:
            r.update(sha256=digest(axe), bytes=axe.stat().st_size,
                     conversion='Rename dependency URIs only; geometry unchanged')
    for source, name in [('crates_stacked.gltf.glb', 'crates'), ('barrel_large.gltf.glb', 'barrel')]:
        put('kaykit-dungeon-remastered', 'Assets/gltf/' + source, f'vendor_{name}.glb', 'arena.blockedCell')
    for source, name in [('plant_bushSmall.glb', 'bush'), ('rock_smallA.glb', 'rock'), ('tree_oak.glb', 'tree')]:
        put('kenney-nature-kit', 'Models/GLTF format/' + source, f'vendor_{name}.glb', 'arena.border')
    for color in ['Blue', 'Yellow']:
        put('kenney-ui-pack', f'PNG/{color}/Double/button_rectangle_depth_flat.png',
            f'vendor_button_{color.lower()}.png', 'lobby.menuButton')
    for icon in ['cross', 'checkmark', 'arrowLeft', 'star']:
        put('kenney-game-icons', f'PNG/White/2x/{icon}.png', f'vendor_icon_{icon}.png', 'menu.navigation')
    for particle in ['spark_01', 'smoke_01']:
        put('kenney-particle-pack', f'PNG (Transparent)/{particle}.png', f'vendor_{particle}.png', 'combat.pooledParticles')
    audio = [
        ('kenney-ui-audio', 'Audio/click4.ogg', 'ui_click', 'menu.press'),
        ('kenney-ui-audio', 'Audio/switch2.ogg', 'ui_toggle', 'menu.toggle'),
        ('kenney-interface-sounds', 'Audio/select_001.ogg', 'ui_select', 'hero.select'),
        ('kenney-interface-sounds', 'Audio/confirmation_001.ogg', 'ui_confirm', 'match.start'),
        ('kenney-interface-sounds', 'Audio/back_001.ogg', 'ui_back', 'menu.back'),
        ('kenney-impact-sounds', 'Audio/impactSoft_heavy_000.ogg', 'hit', 'combat.hit'),
        ('kenney-impact-sounds', 'Audio/footstep_grass_000.ogg', 'step_grass', 'player.grassFootstep'),
        ('kenney-impact-sounds', 'Audio/footstep_concrete_000.ogg', 'step_stone', 'player.groundFootstep'),
        ('kenney-rpg-audio', 'Audio/knifeSlice.ogg', 'slash', 'combat.melee'),
        ('kenney-rpg-audio', 'Audio/bookFlip1.ogg', 'magic', 'combat.cast'),
        ('kenney-music-jingles', 'Audio/Pizzicato jingles/jingles_PIZZI00.ogg', 'win', 'match.victory'),
        ('kenney-music-jingles', 'Audio/Pizzicato jingles/jingles_PIZZI03.ogg', 'lose', 'match.defeat'),
    ]
    for pack, source, name, usage in audio:
        put(pack, source, f'vendor_{name}.wav', usage, audio=True)
    used = {r['pack'] for r in records}
    assert used == set(packs), f'Missing runtime pack: {set(packs) - used}'
    result = dict(schemaVersion=1, packCount=len(used), files=records,
                  packs=[{k: p[k] for k in ('id', 'name', 'author', 'source', 'license')} for p in packs.values()])
    (DEST / 'arena-vendor-runtime.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    notices = '\n\n'.join(p['name'] + '\n' + p['source'] + '\n' +
                           (SOURCE / 'licenses' / (p['id'] + '.txt')).read_text() for p in packs.values())
    (DEST / 'ArenaVendor-LICENSES.txt').write_text(notices)
    print(json.dumps({'packs': len(used), 'runtimeFiles': len(records), 'bytes': sum(r['bytes'] for r in records)}))

if __name__ == '__main__':
    build()
