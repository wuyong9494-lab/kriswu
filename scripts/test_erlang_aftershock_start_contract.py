#!/usr/bin/env python3
"""Synthetic contract negatives; these do not replace restored-original checks."""
from __future__ import annotations
import copy
import unittest

from prepare_erlang_aftershock_start import EFFECT, SOURCE_EVENT, TIMER, source_lifecycle


def fixture():
    # Reconstructed field contract from the pre-interruption audit. It is not
    # a copied source receipt and does not prove the original cache is restored.
    return [
        dict(triggerIndex=42, events=[{'a18':['enum65537',SOURCE_EVENT]}],
             actions=[{'a171':[TIMER,'enum65537',1,100,None]}], conditions=['retained-source-conditions']),
        dict(triggerIndex=43, events=[{'a18':['enum65537',SOURCE_EVENT]}],
             actions=[{'a46':[EFFECT,None,'ground_locator',None,'enum65537',1,None,None,
                 None,None,True,[0.,0.,0.],None,[0.,4.,0.],None,None]}],
             conditions=['retained-base-costume-conditions']),
        dict(triggerIndex=45, events=[{'a44':['enum65537',TIMER]}],
             actions=[{'a49':[EFFECT,'enum65537',None,None,None]}],
             conditions=['retained-round-and-costume-conditions']),
    ]


class AftershockContractChecks(unittest.TestCase):
    def test_reconstructed_contract_never_becomes_runtime_authorization(self):
        rows=fixture(); evidence=source_lifecycle(rows)
        self.assertFalse(evidence['runtimeBound'])
        self.assertFalse(evidence['groundParentTransformVerified'])
        self.assertFalse(evidence['sourceAttachToLocal'])
        self.assertTrue(evidence['sourceLooped'])
        self.assertEqual(evidence['sourceFollow'],[0,0,0])
        self.assertEqual(evidence['sourceShiftCentimeters'],[0,4,0])
        self.assertEqual(evidence['sourceTriggers'],rows)
        rows[2]['conditions'].append('later-mutation')
        self.assertNotEqual(evidence['sourceTriggers'],rows)

    def test_loop_boolean_cannot_be_reinterpreted_as_local_attachment(self):
        # This was the concrete compact-array interpretation risk: field 7
        # attaches locally; field 10 requests the effect loop.
        wrong=fixture(); values=wrong[1]['actions'][0]['a46']
        values[7],values[10]=True,False
        with self.assertRaisesRegex(ValueError,'attachment differs'):
            source_lifecycle(wrong)
        for index,value in ((11,[1,1,1]),(13,[0,3,0]),(4,'enum65539')):
            wrong=fixture();wrong[1]['actions'][0]['a46'][index]=value
            with self.assertRaisesRegex(ValueError,'attachment differs'):
                source_lifecycle(wrong)

    def test_timer_destroy_and_trigger_identity_are_not_interchangeable(self):
        for ticks in (0,99,101,300):
            wrong=fixture();wrong[0]['actions'][0]['a171'][3]=ticks
            with self.assertRaisesRegex(ValueError,'duration differs'):
                source_lifecycle(wrong)
        wrong=fixture();wrong[2]['actions'][0]['a49'][2]=10
        with self.assertRaisesRegex(ValueError,'immediate destruction differs'):
            source_lifecycle(wrong)
        wrong=fixture();wrong[2]['events'][0]['a44'][1]='UNRELATED_TIMER'
        with self.assertRaisesRegex(ValueError,'stop event differs'):
            source_lifecycle(wrong)
        wrong=fixture();wrong.append(copy.deepcopy(wrong[0]))
        with self.assertRaisesRegex(ValueError,'ambiguous'):
            source_lifecycle(wrong)


if __name__=='__main__':
    unittest.main(verbosity=2)
