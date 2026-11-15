#!/usr/bin/env python3
"""New extraction/status boundary checks; no Apple compilation or rendering."""
import contextlib
import copy
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import check_fighter_public_shaders as check


def depth_occlusion_fixture():
    phases = []
    for near, red_position, green_position in (
        ('red', [0, 0, 0], [0, 0, -.5]), ('green', [0, 0, -.5], [0, 0, 0])
    ):
        phases.append(dict(phase='authored-uv-depth-occlusion-'+near+'-near',
            expectedNearColor=near, redRenderingOrder=0, greenRenderingOrder=1,
            redPresentationPosition=red_position, greenPresentationPosition=green_position,
            positionsMatch=True, commandCompleted=True, commandError=None,
            redPixels=288 if near == 'red' else 0, greenPixels=288 if near == 'green' else 0,
            nonblackPixels=288, pixelsSHA256=('1' if near == 'red' else '2')*64,
            depthConfiguration=dict(usesReverseZ=True, clearDepth=0, depthPixelFormat=252,
                                    loadAction='clear', storeAction='dontCare')))
    return dict(required=True, prepared=True, passed=True, readsDepth=True,
                writesDepth=True, shaderModifierCount=0, phases=phases)


class PublicShaderExtractionChecks(unittest.TestCase):
    def test_reverse_depth_requires_two_ordered_occlusion_readbacks(self):
        emitted = dict(programs=[], modifiers=[])
        runtime = dict(status='passed', **emitted, morphBranches=[dict(branch=name, passed=True,
            unmodifiedBaseline=dict(passed=True)) for name in ('authored-uv', 'constant-no-uv')])
        runtime['morphBranches'][0]['depthOcclusion'] = depth_occlusion_fixture()
        self.assertTrue(check.runtime_checks_passed(runtime, emitted))
        mutations = {
            'missing': lambda branch: branch.pop('depthOcclusion'),
            'budget skipped': lambda branch: branch.update(depthOcclusion=dict(required=True,
                prepared=False, passed=False, phases=[], skippedReason='insufficient-native-budget')),
            'reads disabled': lambda branch: branch['depthOcclusion'].update(readsDepth=False),
            'writes disabled': lambda branch: branch['depthOcclusion'].update(writesDepth=False),
            # Red is always submitted first and green last. Neither unconditional
            # first-draw nor last-draw color can satisfy the two depth swaps.
            'last draw wins': lambda branch: branch['depthOcclusion']['phases'][0].update(redPixels=0, greenPixels=288),
            'first draw wins': lambda branch: branch['depthOcclusion']['phases'][1].update(redPixels=288, greenPixels=0),
            'order changed': lambda branch: branch['depthOcclusion']['phases'][1].update(redRenderingOrder=2),
            'positions not swapped': lambda branch: branch['depthOcclusion']['phases'][1].update(redPresentationPosition=[0, 0, 0]),
            'not reverse Z': lambda branch: branch['depthOcclusion']['phases'][0]['depthConfiguration'].update(usesReverseZ=False),
            'wrong clear depth': lambda branch: branch['depthOcclusion']['phases'][0]['depthConfiguration'].update(clearDepth=1),
            'partial capture': lambda branch: branch['depthOcclusion']['phases'].pop(),
            'command failed': lambda branch: branch['depthOcclusion']['phases'][0].update(commandCompleted=False),
            'same readback': lambda branch: branch['depthOcclusion']['phases'][1].update(pixelsSHA256='1'*64),
        }
        for reason, mutate in mutations.items():
            with self.subTest(reason=reason):
                failed = copy.deepcopy(runtime)
                branch = failed['morphBranches'][0]
                mutate(branch)
                # The previously useful disabled-depth control can never fill
                # a missing or failed required depth check.
                branch['depthDisabledBaseline'] = dict(diagnosticOnly=True, prepared=True,
                    redObserved=True, redPixels=288, readsDepth=False, writesDepth=False)
                self.assertFalse(check.runtime_checks_passed(failed, emitted))

    def test_occlusion_diagnostic_preserves_bounded_partial_failure(self):
        probe = depth_occlusion_fixture()
        probe.update(passed=False, error='x'*3000, unrelated='not an occlusion field')
        probe['phases'][1].update(redPixels=288, greenPixels=0, unrelated='not a phase field')
        probe['phases'].append(dict(unrelated='third readback must not be projected'))
        runtime = dict(status='failed', morphBranches=[dict(branch='authored-uv',
            passed=False, depthOcclusion=probe)])
        result = check.runtime_diagnostic(runtime)
        observed = result['morphBranches'][0]['depthOcclusion']
        self.assertEqual(result['runtimeStatus'], 'failed')
        self.assertFalse(result['morphBranches'][0]['passed'])
        self.assertFalse(observed['passed'])
        self.assertEqual(len(observed['phases']), 2)
        self.assertEqual(len(observed['error']), 2000)
        self.assertEqual(observed['phases'][0]['depthConfiguration'], probe['phases'][0]['depthConfiguration'])
        self.assertEqual(observed['phases'][1]['greenPixels'], 0)
        self.assertNotIn('unrelated', observed)
        self.assertNotIn('unrelated', observed['phases'][1])
        probe['phases'] = probe['phases'][:1]
        partial = check.runtime_diagnostic(runtime)['morphBranches'][0]['depthOcclusion']
        self.assertEqual(len(partial['phases']), 1)
        self.assertFalse(partial['passed'])

    def test_fixture_diagnostics_preserve_actual_geometry_and_failed_depth_control(self):
        fixture = dict(observedAfter='unmodified-baseline', renderTime=0, viewport=[0, 0, 32, 32],
            sources=[dict(semantic='vertex', vectorCount=3, bytesPerComponent=4, dataOffset=0,
                          dataStride=12, decodeStatus='decoded', vectors=[[-.75, -.75, 0], [.75, -.75, 0], [0, .75, 0]])],
            elements=[dict(bytesPerIndex=2, primitiveCount=1, indices=[0, 1, 2])],
            insideFrustum=True, projectedInputVertices=[[4, 4, .29], [28, 4, .29], [16, 28, .29]],
            renderer=dict(colorPixelFormat=80, depthPixelFormat=252, pointOfViewMatchesCamera=True),
            unrelated='not a fixture field')
        probe = dict(diagnosticOnly=True, prepared=True, shaderModifierCount=0,
            readsDepth=False, writesDepth=False, redObserved=False,
            redPixels=0, nonblackPixels=0, centerPixelBGRA=[0, 0, 0, 255],
            error='x'*3000, unrelated='not a depth-control field')
        runtime = dict(status='failed', morphBranches=[dict(branch='authored-uv', passed=False,
            unmodifiedBaseline=dict(passed=False), fixtureDiagnostics=fixture, depthDisabledBaseline=probe)])
        diagnostic = check.runtime_diagnostic(runtime)['morphBranches'][0]
        observed = diagnostic['fixtureDiagnostics']
        self.assertEqual(observed['sources'], fixture['sources'])
        self.assertEqual(observed['elements'][0]['indices'], [0, 1, 2])
        self.assertEqual(observed['projectedInputVertices'], fixture['projectedInputVertices'])
        self.assertTrue(observed['insideFrustum'])
        self.assertNotIn('unrelated', observed)
        depth = diagnostic['depthDisabledBaseline']
        self.assertFalse(depth['redObserved'])
        self.assertEqual(depth['centerPixelBGRA'], [0, 0, 0, 255])
        self.assertEqual(len(depth['error']), 2000)
        self.assertNotIn('unrelated', depth)
        self.assertFalse(diagnostic['passed'])
        runtime['morphBranches'][0]['depthDisabledBaseline'] = dict(diagnosticOnly=True, prepared=False,
            redObserved=False, skippedReason='insufficient-native-budget-after-original-readbacks')
        skipped = check.runtime_diagnostic(runtime)['morphBranches'][0]
        self.assertEqual(skipped['depthDisabledBaseline']['skippedReason'],
                         'insufficient-native-budget-after-original-readbacks')
        self.assertNotIn('commandCompleted', skipped['depthDisabledBaseline'])
        self.assertFalse(skipped['passed'])

    def test_successful_depth_control_never_replaces_original_pixel_gates(self):
        emitted = dict(programs=[], modifiers=[])
        runtime = dict(status='passed', **emitted, morphBranches=[dict(branch=name, passed=True,
            unmodifiedBaseline=dict(passed=True), depthDisabledBaseline=dict(
                diagnosticOnly=True, prepared=True, redObserved=True, redPixels=288, nonblackPixels=288))
            for name in ('authored-uv', 'constant-no-uv')])
        runtime['morphBranches'][0]['depthOcclusion'] = depth_occlusion_fixture()
        self.assertTrue(check.runtime_checks_passed(runtime, emitted))
        for field in ('baseline', 'morph'):
            with self.subTest(original_failed=field):
                value = copy.deepcopy(runtime)
                if field == 'baseline':
                    value['morphBranches'][0]['unmodifiedBaseline']['passed'] = False
                else:
                    value['morphBranches'][0]['passed'] = False
                self.assertFalse(check.runtime_checks_passed(value, emitted))

    def test_failed_native_readback_is_reported_without_becoming_a_pass(self):
        phases = [dict(phase='authored-uv-'+name, width=32, height=32, format='bgra8Unorm',
                       nonblackPixels=0, redPixels=0, greenPixels=0,
                       centerPixelBGRA=[0, 0, 0, 255], pixelsSHA256='0'*64,
                       commandCompleted=True, commandError=None) for name in ('base', 'edge', 'discard')]
        baseline = dict(phase='authored-uv-unmodified-baseline', width=32, height=32,
            format='bgra8Unorm', nonblackPixels=288, redPixels=288, greenPixels=0,
            centerPixelBGRA=[0, 0, 255, 255], pixelsSHA256='1'*64, commandCompleted=True,
            commandError=None, shaderModifierCount=0, prepared=True, passed=True)
        runtime = dict(status='failed', reason='authored-uv synthetic pixel assertion failed',
            runtimeLibraryFunctions={'shadow': ['vertex', 'fragment'], 'origin': ['kernel']},
            sourceOriginSample=dict(passed=True),
            morphBranches=[dict(branch='authored-uv', prepared=True, passed=False,
                activePhase='authored-uv-pixel-assertions', unmodifiedBaseline=baseline, phases=phases)])
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
            self.assertEqual(diagnostic['morphBranches'][0]['unmodifiedBaseline'], baseline)
            self.assertEqual(diagnostic['morphBranches'][0]['phases'], phases)
            self.assertIn('authored-uv-pixel-assertions', summary.read_text())
            self.assertFalse(report['iOSDeviceRenderingObserved'])

    def test_runtime_diagnostic_is_bounded_and_keeps_failed_phase(self):
        phase = dict(phase='authored-uv-edge', centerPixelBGRA=[0, 0, 0, 255],
                     redPixels=0, greenPixels=0, unrelated='not a synthetic readback field')
        baseline = dict(phase='authored-uv-unmodified-baseline', centerPixelBGRA=[0, 0, 0, 255],
            redPixels=0, greenPixels=0, shaderModifierCount=0, prepared=True, passed=False,
            unrelated='must not be exposed')
        branches = [dict(branch='authored-uv', activePhase='authored-uv-edge', prepared=True,
                         passed=False, unmodifiedBaseline=baseline, phases=[phase]*5),
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
        observed = diagnostic['morphBranches'][0]['unmodifiedBaseline']
        self.assertFalse(observed['passed'])
        self.assertEqual(observed['centerPixelBGRA'], [0, 0, 0, 255])
        self.assertNotIn('unrelated', observed)
        self.assertIsNone(diagnostic['morphBranches'][1]['unmodifiedBaseline'])

    def test_baseline_and_both_original_morph_results_are_required(self):
        emitted = dict(programs=[dict(name='synthetic-program-identity')],
                       modifiers=[dict(name='synthetic-modifier-identity')])
        runtime = dict(status='passed', **emitted,
            morphBranches=[dict(branch=name, passed=True,
                unmodifiedBaseline=dict(passed=True)) for name in ('authored-uv', 'constant-no-uv')])
        runtime['morphBranches'][0]['depthOcclusion'] = depth_occlusion_fixture()
        self.assertTrue(check.runtime_checks_passed(runtime, emitted))
        for branch in range(2):
            with self.subTest(branch=branch):
                missing = copy.deepcopy(runtime)
                del missing['morphBranches'][branch]['unmodifiedBaseline']
                self.assertFalse(check.runtime_checks_passed(missing, emitted))
                missing['morphBranches'][branch]['unmodifiedBaseline'] = None
                self.assertFalse(check.runtime_checks_passed(missing, emitted))
                black = copy.deepcopy(runtime)
                black['morphBranches'][branch]['unmodifiedBaseline']['passed'] = False
                self.assertFalse(check.runtime_checks_passed(black, emitted))
                failed_morph = copy.deepcopy(runtime)
                failed_morph['morphBranches'][branch]['passed'] = False
                self.assertFalse(check.runtime_checks_passed(failed_morph, emitted))

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
