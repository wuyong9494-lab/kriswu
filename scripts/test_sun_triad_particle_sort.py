"""Synthetic birth-clock fixtures; no source game assets are embedded here."""
import unittest
from types import SimpleNamespace

from sun_triad_particle_sort import occurrences, source_queue, take_occurrence


class SourceParticleOrderingTests(unittest.TestCase):
    def testPrewarmKeepsOldAgeButTheRecurringParticleStartsAtZero(self):
        particle = SimpleNamespace(index=3, life=4.)
        rows = occurrences([(particle, 0., 6.)], 1., 0., 2., None)
        self.assertEqual(rows[(3, 0., None)], [{"duration": 2., "age": 2.}])
        self.assertEqual(rows[(3, 4., 6.)], [{"duration": 4., "age": 0.}])

    def testExpiredPrewarmParticleIsAbsentUntilItsNextBirth(self):
        particle = SimpleNamespace(index=0, life=1.)
        rows = occurrences([(particle, 0., 5.)], 1., 0., 2., None)
        self.assertEqual(dict(rows), {(0, 3., 5.): [{"duration": 1., "age": 0.}]})

    def testSimulationSpeedAndDurationOverrideUsePlaybackSeconds(self):
        particle = SimpleNamespace(index=0, life=8.)
        rows = occurrences([(particle, 2., 12.)], 2., .5, 2., 3.)
        self.assertEqual(dict(rows), {(0, 0., None): [{"duration": 3., "age": .5}]})

    def testBirthMatchingRejectsAmbiguousMissingOrChangedSourceClocks(self):
        particle = SimpleNamespace(index=2, life=3.)
        track = {"name": "emitter_123_2_17", "delay": 0., "duration": 3.}
        rows = occurrences([(particle, 0., None)], 1., 0., 0., None)
        self.assertEqual(take_occurrence(track, rows, "emitter_123"), 0.)
        with self.assertRaises(ValueError):
            take_occurrence(track, rows, "emitter_123")
        rows = occurrences([(particle, 0., None)] * 2, 1., 0., 0., None)
        with self.assertRaises(ValueError):
            take_occurrence(track, rows, "emitter_123")
        rows = occurrences([(particle, 0., None)], 1., 0., 0., None)
        with self.assertRaises(ValueError):
            take_occurrence(dict(track, duration=2.), rows, "emitter_123")

    def testMaterialOverrideWinsAndUnknownShaderQueuesCannotBeGuessed(self):
        self.assertEqual(source_queue(-1, "Transparent"), 3000)
        self.assertEqual(source_queue(-1, "Transparent+3"), 3003)
        self.assertEqual(source_queue(3003, "Transparent"), 3003)
        for custom, tag in [(-2, "Transparent"), (-1, "Unknown"), (-1, "Overlay+2000"), (True, "Transparent")]:
            with self.assertRaises(ValueError):
                source_queue(custom, tag)


if __name__ == "__main__":
    unittest.main()
