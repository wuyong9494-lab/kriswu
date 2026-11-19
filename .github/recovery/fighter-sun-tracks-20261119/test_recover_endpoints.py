import hashlib
import tempfile
import unittest
from pathlib import Path

import numpy as np
from recover_endpoints import (fitting_endpoint, pinned, COORD_SCALE, animation_samples,
                               endpoint_candidates, compare_target_tracks)
from sun_triad_assets import Writer, RIGHT, matrix, world_poses


class Endpoints(unittest.TestCase):
    def fixture(self, duplicate=False):
        rng = np.random.default_rng(1904)
        count = 75
        world = np.zeros((count, 3, 4, 4))
        for frame in range(count):
            for joint in range(3):
                world[frame, joint] = matrix(rng.normal(0, .1, 3), rng.normal(size=4), [1, 1, 1])
        if duplicate:
            world[:, 2] = world[:, 1]
        local = np.array([-14.7253, .0129, 92.06])
        values = np.round(world[:, 1, :3, :3] @ (local * COORD_SCALE) + world[:, 1, :3, 3], 7)
        training = (np.arange(count) // 15) % 3 != 1
        return world, values, training, local

    def test_fits_signed_centimeter_binding(self):
        world, values, training, local = self.fixture()
        index, fitted, error = fitting_endpoint(world, values, training)
        self.assertEqual(index, 1)
        np.testing.assert_array_equal(fitted, local)
        self.assertLess(error, 5.1e-8)

    def test_ambiguous_joint_is_not_accepted(self):
        world, values, training, _ = self.fixture(duplicate=True)
        with self.assertRaisesRegex(ValueError, "Ambiguous joint fit"):
            fitting_endpoint(world, values, training)

    def test_rejects_bad_holdout(self):
        world, values, training, _ = self.fixture()
        values[np.flatnonzero(~training)[0], 2] += .001
        with self.assertRaisesRegex(ValueError, "No verified joint fit"):
            fitting_endpoint(world, values, training)

    def test_archived_tie_can_diverge_on_one_new_tick(self):
        world, values, training, _ = self.fixture(duplicate=True)
        fits, unresolved = endpoint_candidates(world, values, training)
        self.assertEqual(len(fits), 2)
        self.assertFalse(unresolved)
        variant = world[:3].copy()
        variant[1, 2, 0, 3] += .00001
        rows = compare_target_tracks(fits, unresolved, {"unchanged": world[:3], "oneTick": variant})
        self.assertEqual(rows, [{"name":"unchanged","ticks":3,"sameTrack":True},
                                {"name":"oneTick","ticks":3,"sameTrack":False}])

    def test_unresolved_plausible_joint_prevents_consensus(self):
        world, values, training, _ = self.fixture(duplicate=True)
        fits, _ = endpoint_candidates(world, values, training)
        with self.assertRaisesRegex(ValueError, "Not all plausible"):
            compare_target_tracks(fits, [0], {"new":world[:3]})

    def test_baked_odd_tick_reads_key_not_interpolation(self):
        w = Writer()
        w.g["nodes"] = [{"name":"joint"}]
        t = w.acc([0, 1/60, 2/60], "SCALAR")
        p = w.acc([[0,0,0], [0,3,0], [0,2,0]], "VEC3")
        q = w.acc([[0,0,0,1]]*3, "VEC4")
        anim = dict(extras=dict(bakedSamples=3, simulationHz=60),
                    samplers=[dict(input=t,output=i) for i in (p,q)],
                    channels=[dict(sampler=i,target=dict(node=0,path=k)) for i,k in enumerate(("translation","rotation"))])
        _, rest, parents = world_poses(w.g["nodes"])
        odd, = list(animation_samples(w.g, w.b, anim, 2, [1], rest, parents))
        np.testing.assert_array_equal(odd[0,:3,3], [0,3,0])

    def test_input_identity_checked_before_parsing(self):
        with tempfile.TemporaryDirectory() as d:
            f = Path(d)/"candidate"
            f.write_bytes(b"sample")
            self.assertEqual(pinned(f, (6, hashlib.sha256(b"sample").hexdigest())), f)
            with self.assertRaisesRegex(ValueError, "hash differs"):
                pinned(f, (6, hashlib.sha256(b"tamper").hexdigest()))

    def test_odd_tick_uses_original_hierarchy_and_basis(self):
        w = Writer()
        w.g["nodes"] = [{"name":"parent", "translation":[1,0,2], "children":[1]}, {"name":"joint"}]
        time = w.acc([0,1/30], "SCALAR")
        p = w.acc([[0,0,0],[0,2,0]], "VEC3")
        q = w.acc([[0,0,0,1],[0,0,0,1]], "VEC4")
        anim = dict(samplers=[dict(input=time,output=i) for i in (p,q)],
                    channels=[dict(sampler=i,target=dict(node=1,path=k)) for i,k in enumerate(("translation","rotation"))])
        _, rest, parents = world_poses(w.g["nodes"])
        a, h, b = list(animation_samples(w.g, w.b, anim, 2, [0,1,2], rest, parents))
        np.testing.assert_array_equal(a[1,:3,3], (RIGHT @ [1,0,2,1])[:3])
        np.testing.assert_array_equal(h[1,:3,3], (RIGHT @ [1,1,2,1])[:3])
        np.testing.assert_array_equal(b[1,:3,3], (RIGHT @ [1,2,2,1])[:3])


if __name__ == "__main__":
    unittest.main()
