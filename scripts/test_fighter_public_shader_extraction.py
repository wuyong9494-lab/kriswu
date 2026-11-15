#!/usr/bin/env python3
"""New extraction/status boundary checks; no Apple compilation or rendering."""
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import check_fighter_public_shaders as check


class PublicShaderExtractionChecks(unittest.TestCase):
    def test_failed_native_readback_is_reported_without_becoming_a_pass(self):
        phases = [dict(phase='authored-uv-'+name, width=32, height=32, format='bgra8Unorm',
                       nonblackPixels=0, redPixels=0, greenPixels=0,
                       centerPixelBGRA=[0, 0, 0, 255], pixelsSHA256='0'*64,
                       commandCompleted=True, commandError=None) for name in ('base', 'edge', 'discard')]
        runtime = dict(status='failed', reason='authored-uv synthetic pixel assertion failed',
            runtimeLibraryFunctions={'shadow': ['vertex', 'fragment'], 'origin': ['kernel']},
            sourceOriginSample=dict(passed=True),
            morphBranches=[dict(branch='authored-uv', prepared=True, passed=False,
                activePhase='authored-uv-pixel-assertions', phases=phases)])
        with tempfile.TemporaryDirectory(prefix='fighter-public-shader-failed-readback-') as temporary:
            parent = Path(temporary).resolve()
            output, summary = parent/'result', parent/'summary.md'
            def mocked_run(command, label, maximum_seconds, *, work, environment, deadline, report):
                code = 1 if label == 'macos-metal-and-morph' else 0
                report['commands'].append(dict(label=label, exitCode=code))
                if label == 'emit-production-strings':
                    programs = []
                    for name in check.PROGRAM_NAMES:
                        raw = b'// synthetic test fixture; never compiled\n'
                        (work/name).write_bytes(raw)
                        programs.append(dict(name=name, bytes=len(raw), sha256=check.digest(raw)))
                    (work/'emitted-source-manifest.json').write_text(json.dumps(
                        dict(programs=programs, modifiers=[dict(name=str(i)) for i in range(4)])))
                elif label == 'macos-metal-and-morph':
                    (work/'runtime-result.json').write_text(json.dumps(runtime))
                return code
            stdout = io.StringIO()
            with patch.object(check.sys, 'argv', ['check', '--output', str(output)]), \
                 patch.object(check.sys, 'platform', 'darwin'), \
                 patch.dict(check.os.environ, DEVELOPER_DIR=str(parent), GITHUB_STEP_SUMMARY=str(summary)), \
                 patch.object(check, 'run', side_effect=mocked_run), \
                 patch.object(check.subprocess, 'Popen', side_effect=AssertionError('Native command was attempted')), \
                 contextlib.redirect_stdout(stdout):
                code = check.main()
            report = json.loads((output/'public-shader-result.json').read_bytes())
            diagnostic = json.loads(stdout.getvalue().splitlines()[0])
            self.assertEqual(code, 1)
            self.assertEqual(report['status'], 'failed')
            self.assertEqual(report['runtime'], runtime)
            self.assertEqual(diagnostic['runtimeReason'], runtime['reason'])
            self.assertEqual(diagnostic['runtimeLibrariesCompleted'], 2)
            self.assertEqual(diagnostic['morphBranchesObserved'], 1)
            self.assertEqual(diagnostic['morphBranchesCompleted'], 0)
            self.assertTrue(diagnostic['sourceOriginPassed'])
            self.assertEqual(diagnostic['morphBranches'][0]['phases'], phases)
            self.assertIn('authored-uv-pixel-assertions', summary.read_text())
            self.assertFalse(report['iOSDeviceRenderingObserved'])

    def test_runtime_diagnostic_is_bounded_and_keeps_failed_phase(self):
        phase = dict(phase='authored-uv-edge', centerPixelBGRA=[0, 0, 0, 255],
                     redPixels=0, greenPixels=0, unrelated='not a synthetic readback field')
        branches = [dict(branch='authored-uv', activePhase='authored-uv-edge', prepared=True,
                         passed=False, phases=[phase]*5),
                    dict(branch='constant-no-uv', passed=True, phases=[]),
                    dict(branch='unrelated', passed=False, phases=[])]
        diagnostic = check.runtime_diagnostic(dict(status='failed', reason='x'*3000,
                                                   morphBranches=branches))
        self.assertEqual(len(diagnostic['runtimeReason']), 2000)
        self.assertEqual(len(diagnostic['morphBranches']), 2)
        self.assertEqual(len(diagnostic['morphBranches'][0]['phases']), 3)
        self.assertEqual(diagnostic['morphBranchesCompleted'], 1)
        self.assertEqual(diagnostic['morphBranches'][0]['activePhase'], 'authored-uv-edge')
        self.assertFalse(diagnostic['morphBranches'][0]['passed'])
        self.assertNotIn('unrelated', diagnostic['morphBranches'][0]['phases'][0])

    def test_changed_production_boundaries_fail_closed(self):
        originals = {name: (check.ROOT/name).read_bytes() for name in (check.MORPH, check.SHADOW)}
        changes = [
            (check.MORPH, b'let library = try device.makeLibrary(source: ',
             b'let library = try device.makeLibrary(source: let library = try device.makeLibrary(source: '),
            (check.MORPH, b'private static func sourceUV()', b'private static func renamedSourceUV()'),
            (check.SHADOW, b'#include <metal_stdlib>', b'#include <metal_stdlib>\n\\#(unboundExpression)'),
        ]
        for name, old, new in changes:
            with self.subTest(name=name, change=old.decode()):
                altered = dict(originals)
                self.assertIn(old, altered[name])
                altered[name] = altered[name].replace(old, new, 1)
                reads = []
                def read(path, maximum):
                    key = str(path.relative_to(check.ROOT))
                    reads.append(key)
                    return altered[key]
                with patch.object(check, 'regular', side_effect=read):
                    with self.assertRaises(check.CheckFailure):
                        check.extract_sources(check.ROOT)
                self.assertEqual(reads, [check.MORPH, check.SHADOW])

    def check_status(self, prepare):
        with tempfile.TemporaryDirectory(prefix='fighter-public-shader-boundary-') as temporary:
            output = Path(temporary).resolve()/'result'
            args = ['check_fighter_public_shaders.py', '--output', str(output)]
            if prepare:
                args.append('--prepare-only')
            with patch.object(check.sys, 'argv', args), patch.object(check.sys, 'platform', 'linux'), \
                 patch.object(check.subprocess, 'Popen', side_effect=AssertionError('Native command was attempted')), \
                 contextlib.redirect_stdout(io.StringIO()):
                code = check.main()
            report = json.loads((output/'public-shader-result.json').read_bytes())
            self.assertEqual(code, 0 if prepare else 3)
            self.assertEqual(report['status'], 'prepared' if prepare else 'unavailable')
            self.assertEqual(report['commands'], [])
            self.assertEqual(report['privateProgramsChecked'], 0)
            self.assertFalse(report['iOSDeviceRenderingObserved'])
            self.assertEqual([item['path'] for item in report['inputs']], [check.MORPH, check.SHADOW, check.CLI])
            for item in report['inputs']:
                raw = (check.ROOT/item['path']).read_bytes()
                self.assertEqual((len(raw), check.digest(raw)), (item['bytes'], item['sha256']))
            self.assertEqual(check.digest((output/'ExtractedProductionShaders.swift').read_bytes()),
                             report['extractedSwiftSHA256'])

    def test_preparation_is_not_a_shader_pass(self):
        self.check_status(True)

    def test_missing_platform_is_unavailable_without_native_commands(self):
        self.check_status(False)


if __name__ == '__main__':
    unittest.main(verbosity=2)
