"""Targeted source-only checks; no Unity/Metal/App process is started.

The three original-input checks require two explicit private input directories:
ERLANG_AVATAR_SOURCE_DIR and ERLANG_AVATAR_MATERIAL_DIR. Without them those
checks are reported as skipped, never as original-input passes.
"""
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import tempfile
import unittest

from erlang_avatar_source_state import (
    AvatarUniformScheduler, MaterialCapture, NORMAL_MATERIAL, RETEXT_MATERIAL,
    SOURCE_LOCKS, load_source_contract,
)


def update(scheduler, clock, *, live=("armor-pass",), callback=None,
           pause=False, suspended=False):
    return scheduler.update(shared_clock=clock, pause_flag=pause,
                            suspended_flag=suspended, live_material_ids=live,
                            on_write=callback)


@unittest.skipUnless(os.environ.get("ERLANG_AVATAR_SOURCE_DIR")
                     and os.environ.get("ERLANG_AVATAR_MATERIAL_DIR"),
                     "Original private source directories were not supplied")
class OriginalSourceContractChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = Path(os.environ["ERLANG_AVATAR_SOURCE_DIR"])
        cls.material_directory = Path(os.environ["ERLANG_AVATAR_MATERIAL_DIR"])
        cls.contracts = {(c.source_lock, c.trigger_index): c
                         for c in load_source_contract(cls.directory)}

    def test_actual_original_selectors_and_separate_removal(self):
        self.assertEqual(len(self.contracts), 8)
        for index, material in [(2, NORMAL_MATERIAL), (3, RETEXT_MATERIAL),
                                (26, NORMAL_MATERIAL), (27, RETEXT_MATERIAL)]:
            command = self.contracts["1432", index]
            self.assertEqual([c.mesh_type for c in command.commands], [2, 1, 0, 3])
            self.assertEqual([c.mesh_name_prefix for c in command.commands],
                             [None, None, "head_", None])
            self.assertEqual({c.material_name for c in command.commands}, {material})
            self.assertEqual({c.operation for c in command.commands}, {"append_or_reuse"})
            self.assertEqual({c.target_value for c in command.commands}, {1.0})
            self.assertEqual({c.duration_logical_units for c in command.commands},
                             {0 if index in (2, 3) else 20})
            self.assertEqual({c.duration_was_source_null for c in command.commands},
                             {index in (2, 3)})
        for index in (59, 60, 61, 62):
            command = self.contracts["1454", index]
            self.assertEqual(command.priority, 404)
            self.assertEqual([c.mesh_type for c in command.commands], [1, 2, 0, 3])
            self.assertTrue(all(c.operation == "remove" and c.target_value is None
                                and c.duration_logical_units is None for c in command.commands))
        # Read actual events and conditions, not synthetic event labels. Normal
        # uses NOT(all four retext items); retext uses all four item conditions.
        fields = json.loads((self.directory / "d15-lock-1432-source-fields-private.json").read_text())
        triggers = {t["triggerIndex"]: t for t in fields["sets"][0]["triggers"]}
        self.assertEqual(triggers[26]["events"], [{"a18": ["enum65537", "D15_Explosion_FX"]}])
        self.assertEqual(triggers[2]["events"], [{"a2": ["enum65537"]}])
        for normal, retext in [(2, 3), (26, 27)]:
            four = triggers[normal]["conditions"][0]["Not"][0]["And"]
            self.assertEqual(four, triggers[retext]["conditions"][:4])
            self.assertEqual([c["expr"][0]["f239"][1] for c in four],
                             ["Armor", "Helmet", "Weapon", "Ranged"])
            self.assertEqual({c["expr"][1] for c in four}, {101741.0})

    def test_actual_fresh_normal_one_to_one_and_direct_entry(self):
        material_file = self.material_directory / "normal-avatar.material.json"
        raw_file = self.material_directory / "normal-avatar.material.raw"
        self.assertEqual(hashlib.sha256(material_file.read_bytes()).hexdigest(),
                         "9e1b674cb13871c2343f9056a75d348d82ab4e1f6b52d0f42f3144d7620c37e3")
        self.assertEqual(hashlib.sha256(raw_file.read_bytes()).hexdigest(),
                         "a0fa93408bb0cc520ec64cb8b77d460c8562837dc808198a9e7f072bf3729cbc")
        material = json.loads(material_file.read_text())
        captured = dict(material["m_SavedProperties"]["m_Floats"])["_Transparent"]
        self.assertEqual(captured, 1.0)
        scheduler = AvatarUniformScheduler()
        direct = self.contracts["1432", 2].commands[0]
        writes = scheduler.enqueue(captures=[MaterialCapture("armor-pass", captured)],
                                   shared_clock=100.75, target_value=direct.target_value,
                                   duration_logical_units=direct.duration_logical_units)
        self.assertEqual([w.value for w in writes], [1.0])
        self.assertEqual(scheduler.active_job_count, 0)
        timed = self.contracts["1432", 26].commands[0]
        self.assertEqual(scheduler.enqueue(
            captures=[MaterialCapture("armor-pass", captured)], shared_clock=100.75,
            target_value=timed.target_value, duration_logical_units=timed.duration_logical_units), ())
        self.assertEqual([w.value for w in update(scheduler, 105.75).writes], [1.0])
        self.assertEqual([w.value for w in update(scheduler, 120.75).writes], [1.0])
        # No matching source renderer produces no substitute personal-head write.
        self.assertEqual(scheduler.enqueue(captures=[], shared_clock=123,
                                           target_value=1, duration_logical_units=0), ())

    def test_changed_source_identity_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for lock in SOURCE_LOCKS:
                for name in (f"lock_{lock}.bytes", f"d15-lock-{lock}-source-fields-private.json"):
                    shutil.copyfile(self.directory / name, directory / name)
            file = directory / "d15-lock-1432-source-fields-private.json"
            data = file.read_bytes()
            changed = data.replace(b"mtl_Erlang_triplanar_Avatar", b"mtl_Erlang_triplanar_AvataX", 1)
            self.assertNotEqual(data, changed)
            self.assertEqual(len(data), len(changed))
            file.write_bytes(changed)
            with self.assertRaisesRegex(ValueError, "Source identity differs"):
                load_source_contract(directory)


class SourceTimingChecks(unittest.TestCase):
    def test_nonzero_clock_delayed_first_callback_and_integer_quantization(self):
        scheduler = AvatarUniformScheduler()
        self.assertEqual(scheduler.enqueue(captures=[MaterialCapture("armor-pass", 0.25)],
            shared_clock=100.75, target_value=1, duration_logical_units=20), ())
        # First observation may be ten logical units later: do not insert an
        # invented progress-zero callback or count observed display frames.
        first = update(scheduler, 110.125)
        self.assertEqual(first.clock_integer, 110)
        self.assertEqual([w.value for w in first.writes], [0.625])
        self.assertEqual(first.completed_jobs, ())
        same_integer = update(scheduler, 110.875)
        self.assertEqual([w.value for w in same_integer.writes], [0.625])
        final = update(scheduler, 125.5)
        self.assertEqual([w.value for w in final.writes], [1.0])
        self.assertEqual(final.completed_jobs, (1,))
        self.assertEqual(scheduler.active_job_count, 0)

    def test_reentrant_pending_is_discarded_while_existing_job_survives(self):
        scheduler = AvatarUniformScheduler()
        scheduler.enqueue(captures=[MaterialCapture("armor-pass", 0)],
                          shared_clock=100, target_value=1, duration_logical_units=20)
        inside = []
        def enqueue_during_write(write):
            self.assertEqual(scheduler.enqueue(
                captures=[MaterialCapture("armor-pass", write.value)], shared_clock=105,
                target_value=0.75, duration_logical_units=20), ())
            inside.append((scheduler.active_job_count, scheduler.pending_job_count))
        first = update(scheduler, 105, callback=enqueue_during_write)
        self.assertEqual([w.job_id for w in first.writes], [1])
        self.assertEqual(inside, [(1, 1)])
        self.assertEqual(first.discarded_pending_job_ids, (2,))
        self.assertEqual(scheduler.active_job_count, 1)
        self.assertEqual(scheduler.pending_job_count, 0)
        second = update(scheduler, 110)
        self.assertEqual([(w.job_id, w.value) for w in second.writes], [(1, 0.5)])
        self.assertEqual(second.discarded_pending_job_ids, ())

    def test_completion_removes_old_job_and_discards_new_pending(self):
        scheduler = AvatarUniformScheduler()
        scheduler.enqueue(captures=[MaterialCapture("armor-pass", 0)], shared_clock=100,
                          target_value=1, duration_logical_units=5)
        def enqueue_during_completion_write(write):
            scheduler.enqueue(captures=[MaterialCapture("new-pass", 0.25)], shared_clock=105,
                              target_value=1, duration_logical_units=20)
        result = update(scheduler, 105, callback=enqueue_during_completion_write)
        self.assertEqual(result.completed_jobs, (1,))
        self.assertEqual([w.job_id for w in result.writes], [1])
        self.assertEqual(result.discarded_pending_job_ids, (2,))
        self.assertEqual(scheduler.active_job_count, 0)
        self.assertEqual(scheduler.pending_job_count, 0)
        later = update(scheduler, 106, live=("armor-pass", "new-pass"))
        self.assertEqual(later.writes, ())
        self.assertEqual(later.completed_jobs, ())
        self.assertEqual(later.discarded_pending_job_ids, ())

    def test_both_pause_flags_destroyed_skip_and_write_before_completion(self):
        scheduler = AvatarUniformScheduler()
        scheduler.enqueue(captures=[MaterialCapture("destroyed-pass", 0.2),
                                    MaterialCapture("detached-but-live-pass", 0.4)],
                          shared_clock=200, target_value=1, duration_logical_units=20)
        for pause, suspended in [(True, False), (False, True)]:
            result = update(scheduler, 250, live=("detached-but-live-pass",),
                            pause=pause, suspended=suspended)
            self.assertEqual(result.writes, ())
            self.assertEqual(result.completed_jobs, ())
            self.assertEqual(scheduler.active_job_count, 1)
        inside = []
        result = update(scheduler, 250, live=("detached-but-live-pass",),
                        callback=lambda write: inside.append(scheduler.active_job_count))
        self.assertEqual([(w.material_id, w.value) for w in result.writes],
                         [("detached-but-live-pass", 1.0)])
        self.assertEqual(inside, [1])
        self.assertEqual(result.completed_jobs, (1,))
        self.assertEqual(scheduler.active_job_count, 0)

    def test_unsupported_numeric_and_nested_update_do_not_claim_source_success(self):
        scheduler = AvatarUniformScheduler()
        for clock in (math.nan, math.inf, 2**31, True):
            with self.assertRaises(ValueError):
                scheduler.enqueue(captures=[], shared_clock=clock,
                                  target_value=1, duration_logical_units=20)
        with self.assertRaises(ValueError):
            scheduler.enqueue(captures=[], shared_clock=10, target_value=1,
                              duration_logical_units=-1)
        with self.assertRaises(TypeError):
            scheduler.enqueue(shared_clock=10, target_value=1, duration_logical_units=20)
        scheduler.enqueue(captures=[MaterialCapture("armor-pass", 1)], shared_clock=10,
                          target_value=1, duration_logical_units=20)
        with self.assertRaises(RuntimeError):
            update(scheduler, 11, callback=lambda write: update(scheduler, 11))
        with self.assertRaises(RuntimeError):
            update(scheduler, 12)


if __name__ == "__main__":
    unittest.main()
