import hashlib
import json
import os
import stat
from pathlib import Path
import tempfile
import unittest

import build_fighter_network_rules as rules


class FighterNetworkRulesTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name) / "checkout"
        for relative in reversed(rules.REQUIRED):
            self.put(relative, b"// public Swift fixture\n")

    def put(self, relative, data):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def test_repeated_generation_and_sort_order_are_deterministic(self):
        first = rules.build_manifest(self.root)
        self.assertEqual(first, rules.build_manifest(self.root))
        self.assertEqual([item["path"] for item in first["files"]], sorted(rules.REQUIRED))
        self.assertEqual(first["fingerprint"], rules.fingerprint(first["files"], first["build"]))

    def test_dirty_bytes_new_sources_deletions_and_renames_change_identity(self):
        original = rules.build_manifest(self.root)["fingerprint"]
        path = self.root / "Sources/ShiftCore/DuelGame.swift"
        path.write_bytes(path.read_bytes() + b"// local uncommitted change\n")
        self.assertNotEqual(original, rules.build_manifest(self.root)["fingerprint"])
        self.put("Sources/ShiftCore/DuelGame.swift", b"// public Swift fixture\n")
        added = self.put("Sources/ShiftCore/DuelFuture.swift", b"// future rules\n")
        first = rules.build_manifest(self.root)["fingerprint"]
        self.assertNotEqual(original, first)
        added.rename(added.with_name("DuelRenamed.swift"))
        self.assertNotEqual(first, rules.build_manifest(self.root)["fingerprint"])
        added.with_name("DuelRenamed.swift").unlink()
        self.assertEqual(original, rules.build_manifest(self.root)["fingerprint"])

    def test_assets_and_secrets_are_not_read(self):
        before = rules.build_manifest(self.root)
        self.put("App/Resources/FighterPrivate/secret.glb", b"private asset")
        self.put(".env", b"SECRET=must-not-appear")
        self.assertEqual(before, rules.build_manifest(self.root))
        serialized = json.dumps(before)
        self.assertNotIn(str(self.root), serialized)
        self.assertNotIn("private asset", serialized)
        self.assertNotIn("SECRET", serialized)

    def test_all_main_app_core_shared_sources_and_project_settings_are_covered(self):
        previous = rules.build_manifest(self.root)["fingerprint"]
        for path in ["App/Services/NotificationService.swift", "App/Nested/Renderer.generated.swift", "App/AppStore+Duty.swift",
                     "Sources/ShiftCore/Other.swift", "Shared/Nested/Settings.swift", "project.yml"]:
            self.put(path, b"// changed source or settings")
            current = rules.build_manifest(self.root)["fingerprint"]
            self.assertNotEqual(previous, current, path)
            previous = current

    def test_xcode_context_is_bounded_allowlisted_and_bound_to_digest(self):
        environment = {key: "1" for key in rules.BUILD_ENVIRONMENT}
        environment["TARGET_NAME"] = "ShiftReminder"
        environment["SECRET"] = "never-record-this"
        context = rules.xcode_build_context(environment)
        self.assertNotIn("SECRET", context)
        first = rules.build_manifest(self.root, context)
        environment["CONFIGURATION"] = "Release"
        self.assertNotEqual(first["fingerprint"], rules.build_manifest(
            self.root, rules.xcode_build_context(environment))["fingerprint"])
        for key, value in [("TARGET_NAME", "ShiftWidget"), ("SDK_VERSION", ""),
                           ("CONFIGURATION", "/Users/private"), ("CONFIGURATION", "x" * 257)]:
            changed = dict(environment, **{key: value})
            with self.assertRaises(ValueError):
                rules.xcode_build_context(changed)

    def test_missing_required_sources_and_empty_files_fail_closed(self):
        path = self.root / rules.REQUIRED[-1]
        path.unlink()
        with self.assertRaises(ValueError):
            rules.build_manifest(self.root)
        self.put(rules.REQUIRED[-1], b"")
        with self.assertRaises(ValueError):
            rules.build_manifest(self.root)

    def test_symlink_source_and_parent_are_rejected(self):
        path = self.root / rules.REQUIRED[-1]
        path.unlink()
        target = self.put("outside.swift", b"// symlink target")
        path.symlink_to(target)
        with self.assertRaises(ValueError):
            rules.build_manifest(self.root)
        path.unlink()
        self.put(rules.REQUIRED[-1], b"// restored")
        folder = self.root / "App/Views"
        folder.rename(self.root / "App/SavedViews")
        folder.symlink_to(self.root / "App/SavedViews", target_is_directory=True)
        with self.assertRaises(ValueError):
            rules.build_manifest(self.root)

    def test_optional_symlinked_source_directory_is_not_silently_omitted(self):
        outside = Path(self.directory.name) / "external"
        outside.mkdir()
        (outside / "Future.swift").write_text("// future source")
        (self.root / "App/NewSources").symlink_to(outside, target_is_directory=True)
        with self.assertRaises(ValueError):
            rules.build_manifest(self.root)

    def test_output_updates_without_a_commit_and_preserves_unchanged_mtime(self):
        output = Path(self.directory.name) / "App.app/FighterNetworkRules.json"
        first = rules.write_manifest(self.root, output)
        stamp = output.stat().st_mtime_ns
        self.assertEqual(first, rules.write_manifest(self.root, output))
        self.assertEqual(stamp, output.stat().st_mtime_ns)
        self.put("App/Views/DuelView.swift", b"// dirty local view")
        second = rules.write_manifest(self.root, output)
        self.assertNotEqual(first["fingerprint"], second["fingerprint"])
        self.assertEqual(json.loads(output.read_text()), second)

    @unittest.skipUnless(os.name == "posix", "POSIX file modes")
    def test_manifest_mode_is_0644_even_with_restrictive_umask_or_old_output(self):
        output = Path(self.directory.name) / "App.app/FighterNetworkRules.json"
        output.parent.mkdir()
        directory_mode = stat.S_IMODE(output.parent.stat().st_mode)
        previous_umask = os.umask(0o077)
        try:
            rules.write_manifest(self.root, output)
        finally:
            os.umask(previous_umask)
        self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o644)
        original = output.read_bytes()
        output.chmod(0o600)
        rules.write_manifest(self.root, output)
        self.assertEqual(output.read_bytes(), original)
        self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o644)
        self.assertEqual(stat.S_IMODE(output.parent.stat().st_mode), directory_mode)
        self.assertFalse(output.with_name("." + output.name + ".tmp").exists())

    def test_atomic_scratch_uses_declared_path_and_recovers_interrupted_output(self):
        output = Path(self.directory.name) / "App.app/FighterNetworkRules.json"
        output.parent.mkdir()
        temporary = output.with_name("." + output.name + ".tmp")
        temporary.write_bytes(b"interrupted partial output")
        result = rules.write_manifest(self.root, output)
        self.assertEqual(json.loads(output.read_text()), result)
        self.assertFalse(temporary.exists())
        self.assertEqual(list(output.parent.iterdir()), [output])

    def test_unchanged_output_cleans_stale_scratch_without_changing_manifest_mtime(self):
        output = Path(self.directory.name) / "App.app/FighterNetworkRules.json"
        rules.write_manifest(self.root, output)
        stamp = output.stat().st_mtime_ns
        temporary = output.with_name("." + output.name + ".tmp")
        temporary.write_bytes(b"leftover interrupted build")
        rules.write_manifest(self.root, output)
        self.assertFalse(temporary.exists())
        self.assertEqual(output.stat().st_mtime_ns, stamp)

    def test_atomic_scratch_refuses_symlink_without_touching_its_target(self):
        output = Path(self.directory.name) / "App.app/FighterNetworkRules.json"
        output.parent.mkdir()
        target = Path(self.directory.name) / "untouched"
        target.write_bytes(b"must remain unchanged")
        temporary = output.with_name("." + output.name + ".tmp")
        temporary.symlink_to(target)
        with self.assertRaises((OSError, ValueError)):
            rules.write_manifest(self.root, output)
        self.assertEqual(target.read_bytes(), b"must remain unchanged")
        self.assertTrue(temporary.is_symlink())
        self.assertFalse(output.exists())

    def test_project_hook_declares_only_required_inputs_and_atomic_outputs(self):
        # Keep this assertion dependency-free; production generator uses only stdlib.
        project = (Path(__file__).resolve().parents[1] / "project.yml").read_text()
        hook = project.split("    postBuildScripts:\n", 1)[1].split("    scheme:\n", 1)[0]
        inputs = hook.split("        inputFiles:\n", 1)[1].split("        outputFiles:\n", 1)[0]
        outputs = hook.split("        outputFiles:\n", 1)[1]
        declared_inputs = [line.strip()[3:-1] for line in inputs.splitlines() if line.strip().startswith('- "')]
        declared_outputs = [line.strip()[3:-1] for line in outputs.splitlines() if line.strip().startswith('- "')]
        self.assertEqual(declared_inputs, ["$(SRCROOT)/scripts/build_fighter_network_rules.py",
                                          "$(SRCROOT)/project.yml", "$(SRCROOT)/App",
                                          "$(SRCROOT)/Sources/ShiftCore", "$(SRCROOT)/Shared"])
        base = "$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/"
        self.assertEqual(declared_outputs, [base + "FighterNetworkRules.json", base + ".FighterNetworkRules.json.tmp"])
        self.assertIn("basedOnDependencyAnalysis: false", hook)
        self.assertIn("showEnvVars: false", hook)
        self.assertIn("python3 -I -B -S", hook)
        self.assertNotIn("ENABLE_USER_SCRIPT_SANDBOXING", project)

    def test_cross_language_framing_vector(self):
        files = [{"path": "Sources/ShiftCore/DuelGame.swift", "bytes": 3,
                  "sha256": hashlib.sha256(b"abc").hexdigest()}]
        self.assertEqual(rules.fingerprint(files),
                         "8ef062dbd8f73824c5187478e4b9f4b2a437cbdb9369d4d631337bb4f6be5a7d")
        self.assertEqual(rules.fingerprint(files, {"mode": "xcode", "TARGET_NAME": "ShiftReminder"}),
                         "bec0e4cab282b0353e4166fe90e4b44f895dfe3cd24f7b242759c4e2887fe476")

    def test_source_size_limit(self):
        self.put(rules.REQUIRED[0], b"x" * (rules.MAX_SOURCE_BYTES + 1))
        with self.assertRaises(ValueError):
            rules.build_manifest(self.root)


if __name__ == "__main__":
    unittest.main()
