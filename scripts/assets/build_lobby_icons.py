"""Render checked-in Game-icons SVGs to iOS template images (requires cairosvg)."""
from pathlib import Path
import json
import xml.etree.ElementTree as ET
import cairosvg
ROOT = Path(__file__).resolve().parents[2]
manifest = json.loads((ROOT / 'art/lobby/icons/manifest.json').read_text())
for item in manifest['icons']:
    source = ROOT / 'art/lobby/icons' / item['source']
    tree = ET.fromstring(source.read_text())
    # Upstream places a black 512-square behind each white glyph. Remove only that rectangle.
    for node in list(tree):
        if node.tag.endswith('path') and node.get('d') == 'M0 0h512v512H0z':
            tree.remove(node)
    svg = ET.tostring(tree)
    folder = ROOT / 'App/Assets.xcassets' / (item['asset'] + '.imageset')
    folder.mkdir(parents=True, exist_ok=True)
    images = []
    for scale in (1, 2, 3):
        filename = f'icon@{scale}x.png'
        cairosvg.svg2png(bytestring=svg, write_to=str(folder / filename),
                        output_width=40 * scale, output_height=40 * scale)
        images.append({'filename': filename, 'idiom': 'universal', 'scale': f'{scale}x'})
    (folder / 'Contents.json').write_text(json.dumps({'images': images, 'info': {'author': 'xcode', 'version': 1},
        'properties': {'template-rendering-intent': 'template'}}, indent=2) + '\n')
