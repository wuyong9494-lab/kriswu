import copy
import json
import os
from pathlib import Path
import shutil
import tempfile
import unittest

from check_serpent_action_source import condition
from check_serpent_state_source import documents


class SerpentActionSourceTests(unittest.TestCase):
    def test_unsupported_condition_does_not_silently_match(self):
        with self.assertRaises(ValueError):
            condition([{'expr':[{'f999':[None]}, 1, 'op22']}], {}, False)
        with self.assertRaises(ValueError):
            condition([{'expr':[1, 1, 'op999']}], {}, False)
        with self.assertRaises(ValueError):
            condition([{'expr':[{'f29':[{'f74':['enum65537']}]}, 'Invincible', 'op22']}], {}, False)

    def test_invincibility_and_strict_greater_are_separate_original_conditions(self):
        self.assertTrue(condition([{'Not':[{'expr':[{'f29':[{'f74':['enum65538']}]},'Invincible','op22']}]}], {}, False))
        self.assertFalse(condition([{'Not':[{'expr':[{'f29':[{'f74':['enum65538']}]},'Invincible','op22']}]}], {}, True))
        self.assertFalse(condition([{'expr':[.2,.2,'op18']}], {}, False))
        self.assertTrue(condition([{'expr':[.2,.2,'op22']}], {}, False))

    def test_changed_priority_order_or_projection_fails_original_binary_reconstruction(self):
        root = os.environ.get('SERPENT_TRIGGER_SOURCE')
        if not root: self.skipTest('Authenticated D13 source tree not supplied')
        root = Path(root)
        name = 'serpent-lock-1381-source-v1.json'
        original = json.loads((root/name).read_bytes())
        for mutation in ('priority','index','projection','typed_fields','source_bytes'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as temporary:
                output = Path(temporary)
                (output/'original-sources').mkdir()
                shutil.copyfile(root/'receipt-private.json',output/'receipt-private.json')
                shutil.copyfile(root/'original-sources/lock_1381.bytes',output/'original-sources/lock_1381.bytes')
                document = copy.deepcopy(original)
                t = document['sets'][0]['triggers'][0]
                if mutation == 'priority': t['priority'] = 10
                elif mutation == 'index': t['triggerIndex'] = 1
                elif mutation == 'projection': t['actions'][0]['a171'][2] = 1
                elif mutation == 'typed_fields':
                    t['rawSourceFields'][2] = 10; t['priority'] = 10
                else: (output/'original-sources/lock_1381.bytes').write_bytes(b'changed')
                (output/name).write_text(json.dumps(document))
                with self.assertRaises(ValueError): documents(output, (1381,))


if __name__ == '__main__':
    unittest.main()
