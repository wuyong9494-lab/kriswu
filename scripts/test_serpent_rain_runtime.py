import copy
import json
import os
from pathlib import Path
import shutil
import tempfile
import unittest

from check_serpent_state_source import documents
from prepare_serpent_rain_runtime import bottle_binding, oracle, source_contract


class SerpentRainRuntimeTests(unittest.TestCase):
    def inputs(self):
        keys=('SERPENT_TRIGGER_SOURCE','SERPENT_NAMED_SETTINGS','SERPENT_BOTTLE_OUTPUT')
        if not all(os.environ.get(key) for key in keys): self.skipTest('Authenticated D13 source inputs required')
        return [Path(os.environ[key]) for key in keys]

    def test_source_ground_timers_bounds_and_no_ground_immunity_guard(self):
        source,named,_=self.inputs()
        contract=source_contract(source,named)
        self.assertEqual([contract[k] for k in ('cloudPeriod','cloudLifetime','groundDelay','groundLifetime',
            'groundPeriod','groundPoisonLifetime')],[20,600,180,900,60,1200])
        cases=oracle(contract)
        self.assertEqual(len(cases['contactCases']),168)
        self.assertEqual(len(cases['rainTicks']),29)
        self.assertEqual(len(cases['groundTicks']),15)
        self.assertFalse(contract['groundHasInvincibilityGuard'])
        self.assertFalse(contract['cloudMotionBound'])

    def test_bottle_binding_uses_authenticated_glb_and_rejects_changed_bytes(self):
        _,_,bottle=self.inputs()
        value=bottle_binding(bottle)
        self.assertEqual(len(value['samples']),49)
        self.assertNotEqual(value['samples'][0]['left'],value['samples'][48]['left'])
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            shutil.copyfile(bottle/'bottle-source-private.json',root/'bottle-source-private.json')
            raw=bytearray((bottle/'SF3_D13_Bottle_Source.glb').read_bytes());raw[-1]^=1
            (root/'SF3_D13_Bottle_Source.glb').write_bytes(raw)
            with self.assertRaises(ValueError):bottle_binding(root)

    def test_rain_priority_geometry_and_timer_mutations_fail_binary_reconstruction(self):
        source,_,_=self.inputs()
        original=json.loads((source/'serpent-lock-1403-source-v1.json').read_bytes())
        for mutation in ('randomPriority','halfWidth','groundTimer','invincibility'):
            with self.subTest(mutation=mutation),tempfile.TemporaryDirectory() as temporary:
                root=Path(temporary);(root/'original-sources').mkdir()
                shutil.copyfile(source/'receipt-private.json',root/'receipt-private.json')
                shutil.copyfile(source/'original-sources/lock_1403.bytes',root/'original-sources/lock_1403.bytes')
                d=copy.deepcopy(original);ts=d['sets'][0]['triggers']
                if mutation=='randomPriority':ts[9]['priority']=10
                elif mutation=='halfWidth':ts[5]['conditions'][-1]['expr'][2]=301
                elif mutation=='groundTimer':ts[14]['actions'][0]['a171'][3]=61
                else:ts[13]['conditions'].append({'Not':[{'expr':[1,1,'op22']}]})
                (root/'serpent-lock-1403-source-v1.json').write_text(json.dumps(d))
                with self.assertRaises(ValueError):documents(root,(1403,))


if __name__=='__main__':unittest.main()
