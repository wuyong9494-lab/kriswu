import copy
import unittest
from prepare_star_simulator import selection


class SimulatorSelectionTests(unittest.TestCase):
    def setUp(self):
        self.catalog = {
            "devicetypes": [{"name": "iPhone 17 Pro Max", "identifier": "exact-model"},
                            {"name": "iPhone 17", "identifier": "other-model"}],
            "runtimes": [{"identifier": "runtime.iOS-26-2", "version": "26.2", "isAvailable": True},
                         {"identifier": "runtime.iOS-26-10", "version": "26.10", "isAvailable": True},
                         {"identifier": "runtime.iOS-27", "version": "27.0", "isAvailable": False},
                         {"identifier": "runtime.watchOS-27", "version": "27.0", "isAvailable": True}],
        }

    def testSelectsExactModelAndNumericallyNewestAvailableIOS(self):
        self.assertEqual(selection(self.catalog), ("exact-model", "runtime.iOS-26-10"))

    def testCannotSubstituteAnotherPhoneOrUnavailableRuntime(self):
        missing_model = copy.deepcopy(self.catalog)
        missing_model["devicetypes"].pop(0)
        unavailable = copy.deepcopy(self.catalog)
        for runtime in unavailable["runtimes"]:
            runtime["isAvailable"] = False
        for catalog in (missing_model, unavailable, {}):
            with self.subTest(catalog=catalog), self.assertRaises(ValueError):
                selection(catalog)

    def testOldIOSAndAmbiguousModelDoNotQualify(self):
        old = copy.deepcopy(self.catalog)
        old["runtimes"] = [{"identifier": "runtime.iOS-18-6", "version": "18.6", "isAvailable": True}]
        duplicate = copy.deepcopy(self.catalog)
        duplicate["devicetypes"].append(dict(duplicate["devicetypes"][0]))
        for catalog in (old, duplicate):
            with self.assertRaises(ValueError):
                selection(catalog)
