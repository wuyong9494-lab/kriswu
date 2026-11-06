"""Inventory every UI instance without inventing application state or labels.

Paths exactly match ArenaLobbyTimelineScene, including reused anonymous clips.
The inventory is private derived data, not a declaration of visual acceptance.
"""
from collections import Counter
from source_flash import require


def inventory(scene):
    result = {}
    for export, entry in scene['exports'].items():
        instances = []

        def walk(object_id, path, ancestry, blend=0):
            require(len(ancestry) < 48 and object_id not in ancestry, 'Cyclic UI instance')
            require(len(instances) < 100_000, 'UI instance budget exceeded')
            item = scene['objects'].get(str(object_id))
            require(item is not None, 'Missing UI instance')
            node = {'path': path, 'objectID': object_id, 'blendMode': blend}
            if 'textField' in item:
                node['textField'] = item['textField']
            if 'frameCount' in item:
                node['frameCount'] = item['frameCount']
                node['labels'] = [{'name': name, 'frameIndex': index}
                                  for index, name in enumerate(item.get('frameLabels', [])) if name]
            if 'scalingGrid' in item:
                node['scalingGrid'] = item['scalingGrid']
            instances.append(node)
            children = item.get('children', [])
            counts = Counter(c['name'] for c in children)
            for index, child in enumerate(children):
                name = child['name']
                segment = f'#{index}:{name}' if not name or counts[name] > 1 else name
                child_path = path + '/' + segment if path else segment
                walk(child['objectID'], child_path, ancestry | {object_id}, child['blendMode'])

        walk(entry['objectID'], '', set())
        result[export] = instances
    return {'schemaVersion': 1, 'sourceSCSHA256': scene['sourceSCSHA256'], 'exports': result}
