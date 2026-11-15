#!/usr/bin/env python3
"""Check only public production shader strings on an already equipped Mac.

No resource pack, keys, signing, simulator, application launch, component
download or workflow operation is permitted by this entry point. Linux may
prepare the exact extraction for review; preparation is never a shader pass.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
MORPH = 'App/Services/DuelTriadSourceMorph.swift'
SHADOW = 'App/Services/DuelSourceProjectedShadowRenderer.swift'
CLI = 'scripts/check_fighter_public_shaders.swift'
PROGRAM_NAMES = ('public-source-origin.metal', 'public-projected-shadow.metal')
LIMITATIONS = [
    'Only the two public complete MSL programs and four production Morph modifier strings are covered.',
    'Private generated Dog, stomp, sword and skill MSL programs are not inputs and are not checked.',
    'Synthetic macOS geometry and one-pixel input do not verify original media, full material composition or iPhone rendering.',
    'No simulator, game application, signed build, private asset release or TestFlight operation is performed.',
]


class CheckFailure(Exception):
    pass


class Unavailable(CheckFailure):
    pass


def require(condition, message):
    if not condition:
        raise CheckFailure(message)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def regular(path, maximum):
    info = path.lstat()
    require(stat.S_ISREG(info.st_mode) and 0 < info.st_size <= maximum and path.resolve() == path,
            'Expected a bounded regular public source file')
    return path.read_bytes()


def extract_sources(root):
    """Copy the actual Swift literals/functions; Swift evaluates the strings.

    Do not translate GLSL, unescape Swift strings, substitute shader bodies or
    parse a second hand-maintained copy. Deliberately narrow anchors fail when
    the production layout changes, requiring a new review of that boundary.
    """
    morph_raw = regular(root/MORPH, 128_000)
    shadow_raw = regular(root/SHADOW, 128_000)
    morph, shadow = morph_raw.decode(), shadow_raw.decode()
    anchor = 'let library = try device.makeLibrary(source: '
    end = ', options: options)'
    require(morph.count(anchor) == 1, 'Source-origin compiler anchor is missing or ambiguous')
    offset = morph.index(anchor) + len(anchor)
    finish = morph.index(end, offset)
    kernel = morph[offset:finish]
    require(kernel.startswith('"""\n') and kernel.endswith('"""') and kernel.count('"""') == 2
            and '\\(' not in kernel and 'kernel void triad_morph_source_origin(' in kernel,
            'Source-origin literal is no longer the reviewed complete MSL function')
    methods_anchor = '    private static func sourceUV() -> String {'
    require(morph.count(methods_anchor) == 1 and morph.endswith('\n}\n'),
            'Morph source function boundary differs')
    methods = morph[morph.index(methods_anchor):-2]
    require(methods.count('private static func ') == 3 and
            methods.count('private static func surface(constantSourceUV: Bool) -> String {') == 1 and
            methods.count('private static func fragment(constantSourceUV: Bool) -> String {') == 1,
            'Morph modifier functions differ from the bounded extraction contract')
    shadow_anchor = '    private static let program = #"""\n'
    require(shadow.count(shadow_anchor) == 1 and shadow.endswith('    """#\n}\n'),
            'Projected-shadow literal boundary differs')
    member = shadow[shadow.index(shadow_anchor):-2]
    require(member.count('#"""') == member.count('"""#') == 1 and '\\#(' not in member,
            'Projected-shadow program contains an unbound Swift expression')
    generated = ('import Foundation\n\n'
        '// Exact production slices; no source shader equation is rewritten.\n'
        'enum FighterPublicShaderSources {\n'
        '    private static let sourceOrigin = '+kernel+'\n\n'+member+'\n'+methods+'\n'
        '    static var programs: [String: String] {\n'
        '        ["public-source-origin.metal": sourceOrigin, "public-projected-shadow.metal": program]\n'
        '    }\n'
        '    static func modifiers(constant: Bool) -> (surface: String, fragment: String) {\n'
        '        (surface(constantSourceUV: constant), fragment(constantSourceUV: constant))\n'
        '    }\n'
        '}\n').encode()
    inputs = [dict(path=name, bytes=len(raw), sha256=digest(raw))
              for name, raw in ((MORPH, morph_raw), (SHADOW, shadow_raw))]
    slices = [dict(name=name, bytes=len(text.encode()), sha256=digest(text.encode())) for name, text in
              [('sourceOriginSwiftLiteral', kernel), ('projectedShadowSwiftMember', member), ('morphSwiftFunctions', methods)]]
    return generated, inputs, slices


def run(command, label, maximum_seconds, *, work, environment, deadline, report):
    remaining = min(maximum_seconds, deadline-time.monotonic())
    require(remaining > 0, 'Public shader check exhausted its absolute time budget')
    log = work/(label+'.log')
    started = time.monotonic()
    with log.open('xb') as output:
        process = subprocess.Popen(command, cwd=ROOT, env=environment, stdout=output,
            stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=remaining)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL); process.wait(timeout=2)
            code = 124
    raw = log.read_bytes()
    report['commands'].append(dict(label=label, command=command, exitCode=code,
        seconds=round(time.monotonic()-started, 3), logBytes=len(raw), logSHA256=digest(raw)))
    if code:
        # These commands consume public sources and synthetic inputs only.
        # Preserve bounded compiler diagnostics so a failed first Mac run is
        # actionable without uploading the working directory or any assets.
        print(json.dumps(dict(failedPhase=label, exitCode=code,
            diagnosticTail=[line[:1000] for line in raw.decode('utf-8', errors='replace').splitlines()[-60:]])), flush=True)
    return code


def runtime_diagnostic(runtime):
    """Expose bounded synthetic readbacks even when the native check failed."""
    branches = runtime.get('morphBranches', [])
    phase_fields = ('phase', 'width', 'height', 'format', 'nonblackPixels', 'redPixels',
                    'greenPixels', 'centerPixelBGRA', 'pixelsSHA256', 'commandCompleted', 'commandError',
                    'depthConfiguration')
    def baseline_diagnostic(branch):
        baseline = branch.get('unmodifiedBaseline')
        if not isinstance(baseline, dict):
            return None
        return {key: baseline[key] for key in phase_fields if key in baseline} | dict(
            prepared=baseline.get('prepared') is True, passed=baseline.get('passed') is True,
            shaderModifierCount=baseline.get('shaderModifierCount'))
    def fixture_diagnostic(branch):
        fixture = branch.get('fixtureDiagnostics')
        if not isinstance(fixture, dict):
            return None
        # The native fixture caps this at three sources/vectors, one element,
        # three projected vertices and fixed-size transforms. The enclosing
        # runtime JSON still has the existing 32 KiB limit.
        fields = ('observedAfter', 'renderTime', 'viewport', 'sourceCount', 'elementCount', 'sources', 'elements',
                  'bounds', 'node', 'camera', 'insideFrustum', 'projectedInputVertices', 'material', 'renderer')
        return {key: fixture[key] for key in fields if key in fixture}
    def depth_diagnostic(branch):
        probe = branch.get('depthDisabledBaseline')
        if not isinstance(probe, dict):
            return None
        fields = phase_fields + ('diagnosticOnly', 'prepared', 'redObserved',
                                 'shaderModifierCount', 'readsDepth', 'writesDepth', 'skippedReason')
        value = {key: probe[key] for key in fields if key in probe}
        if 'error' in probe:
            value['error'] = str(probe['error'])[:2000]
        return value
    def occlusion_diagnostic(branch):
        probe = branch.get('depthOcclusion')
        if not isinstance(probe, dict):
            return None
        fields = ('required', 'prepared', 'passed', 'readsDepth', 'writesDepth', 'shaderModifierCount', 'skippedReason')
        value = {key: probe[key] for key in fields if key in probe}
        if 'error' in probe:
            value['error'] = str(probe['error'])[:2000]
        sample_fields = phase_fields + ('expectedNearColor', 'redRenderingOrder', 'greenRenderingOrder',
                                       'redPresentationPosition', 'greenPresentationPosition', 'positionsMatch')
        value['phases'] = [{key: phase[key] for key in sample_fields if key in phase}
                           for phase in probe.get('phases', [])[:2]]
        return value
    return dict(runtimeStatus=runtime.get('status'),
        runtimeReason=str(runtime.get('reason', ''))[:2000],
        runtimeLibrariesCompleted=len(runtime.get('runtimeLibraryFunctions', {})),
        sourceOriginPassed=runtime.get('sourceOriginSample', {}).get('passed') is True,
        morphBranchesObserved=len(branches),
        morphBranchesCompleted=sum(branch.get('passed') is True for branch in branches),
        morphBranches=[dict(branch=str(branch.get('branch', ''))[:80],
            activePhase=str(branch.get('activePhase', ''))[:120],
            prepared=branch.get('prepared') is True, passed=branch.get('passed') is True,
            unmodifiedBaseline=baseline_diagnostic(branch),
            fixtureDiagnostics=fixture_diagnostic(branch), depthDisabledBaseline=depth_diagnostic(branch),
            depthOcclusion=occlusion_diagnostic(branch),
            phases=[{key: phase[key] for key in phase_fields if key in phase}
                    for phase in branch.get('phases', [])[:3]]) for branch in branches[:2]])


def depth_occlusion_passed(branch):
    probe = branch.get('depthOcclusion')
    if not isinstance(probe, dict) or not all(probe.get(key) is True
        for key in ('required', 'prepared', 'passed', 'readsDepth', 'writesDepth')):
        return False
    phases = probe.get('phases', [])
    if probe.get('shaderModifierCount') != 0 or len(phases) != 2:
        return False
    for phase, color, red_position, green_position in zip(phases, ('red', 'green'),
            ([0, 0, 0], [0, 0, -.5]), ([0, 0, -.5], [0, 0, 0])):
        config = phase.get('depthConfiguration', {})
        if (phase.get('expectedNearColor') != color or phase.get('positionsMatch') is not True
                or phase.get('redPresentationPosition') != red_position
                or phase.get('greenPresentationPosition') != green_position
                or phase.get('redRenderingOrder') != 0 or phase.get('greenRenderingOrder') != 1
                or phase.get('commandCompleted') is not True or phase.get('commandError') is not None
                or config.get('usesReverseZ') is not True or config.get('clearDepth') != 0
                or config.get('depthPixelFormat') != 252 or config.get('loadAction') != 'clear'
                or phase.get(color+'Pixels', 0) <= 20
                or phase.get(('green' if color == 'red' else 'red')+'Pixels') != 0):
            return False
    return (isinstance(phases[0].get('pixelsSHA256'), str)
            and isinstance(phases[1].get('pixelsSHA256'), str)
            and phases[0]['pixelsSHA256'] != phases[1]['pixelsSHA256'])


def runtime_checks_passed(runtime, emitted):
    branches = runtime.get('morphBranches', [])
    return (runtime.get('status') == 'passed'
            and runtime.get('programs') == emitted['programs']
            and runtime.get('modifiers') == emitted['modifiers']
            and len(branches) == 2
            and [branch.get('branch') for branch in branches] == ['authored-uv', 'constant-no-uv']
            and depth_occlusion_passed(branches[0])
            and all(branch.get('passed') is True
                    and isinstance(branch.get('unmodifiedBaseline'), dict)
                    and branch.get('unmodifiedBaseline', {}).get('passed') is True
                    for branch in branches))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--prepare-only', action='store_true')
    args = parser.parse_args()
    work = args.output.absolute()
    require(work.parent.resolve() == work.parent and work.parent.is_dir() and not work.exists(),
            'Use a new output directory beneath a real existing parent')
    require(not work.is_relative_to(ROOT), 'Generated shader inputs and logs must stay outside the checkout')
    work.mkdir(mode=0o700)
    report = dict(schemaVersion=1, status='failed', scope='public-production-shaders-only', commands=[],
        limitations=LIMITATIONS, privateProgramsChecked=0, privateResourcesLoaded=False,
        simulatorLaunched=False, applicationLaunched=False, signedBuild=False,
        toolchainDownloaded=False, iOSDeviceRenderingObserved=False)
    deadline = time.monotonic() + 240
    try:
        generated, inputs, slices = extract_sources(ROOT)
        cli = regular(ROOT/CLI, 64_000)
        report.update(inputs=inputs + [dict(path=CLI, bytes=len(cli), sha256=digest(cli))], sourceSlices=slices,
            extractedSwiftSHA256=digest(generated))
        (work/'ExtractedProductionShaders.swift').write_bytes(generated)
        (work/'ShaderCheckMain.swift').write_bytes(cli)
        if args.prepare_only:
            report['status'] = 'prepared'
            report['reason'] = 'Exact public-source extraction only; no Apple compiler or GPU was invoked.'
        else:
            if sys.platform != 'darwin':
                raise Unavailable('The public shader check requires macOS; no remote operation was attempted.')
            environment = dict(os.environ)
            # Match the already installed Xcode used by the source compile.
            # Neither xcode-select nor a component download is invoked.
            developer = Path(environment.get('DEVELOPER_DIR', '/Applications/Xcode_26.6.app/Contents/Developer'))
            if not developer.is_dir():
                raise Unavailable('The selected installed Xcode developer directory is absent.')
            environment['DEVELOPER_DIR'] = str(developer)
            environment['LC_ALL'] = 'C'
            report['developerDirectory'] = str(developer)
            def command(parts, label, timeout):
                return run(parts, label, timeout, work=work, environment=environment,
                    deadline=deadline, report=report)
            for parts, label in [(['/usr/bin/xcrun', '--find', 'swiftc'], 'swiftc-path'),
                                 (['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-version'], 'macosx-sdk')]:
                if command(parts, label, 15):
                    raise Unavailable('Installed Swift compiler or macOS SDK unavailable; no component was downloaded.')
            offline_available = True
            for parts, label in [(['/usr/bin/xcrun', '--find', 'metal'], 'metal-path'),
                                 (['/usr/bin/xcrun', '--sdk', 'iphoneos', 'metal', '--version'], 'metal-version'),
                                 (['/usr/bin/xcrun', '--sdk', 'iphoneos', '--show-sdk-version'], 'iphoneos-sdk')]:
                if command(parts, label, 15):
                    offline_available = False
            report['offlineMetalAvailable'] = offline_available
            executable = work/'public-shader-check'
            code = command(['/usr/bin/xcrun', '--sdk', 'macosx', 'swiftc', '-swift-version', '6',
                '-strict-concurrency=complete', '-framework', 'Foundation', '-framework', 'Metal',
                '-framework', 'SceneKit', str(work/'ExtractedProductionShaders.swift'),
                str(work/'ShaderCheckMain.swift'), '-o', str(executable)], 'compile-macos-check', 60)
            require(code == 0, 'The macOS public shader check did not compile')
            require(command([str(executable), '--emit', str(work)], 'emit-production-strings', 10) == 0,
                    'The compiled production strings could not be emitted')
            emitted = json.loads(regular(work/'emitted-source-manifest.json', 16_384))
            require({x['name'] for x in emitted['programs']} == set(PROGRAM_NAMES)
                    and len(emitted['programs']) == 2 and len(emitted['modifiers']) == 4,
                    'The emitted public shader scope differs')
            for program in emitted['programs']:
                source = regular(work/program['name'], 128_000)
                require(len(source) == program['bytes'] and digest(source) == program['sha256'],
                        'An emitted production shader changed before compilation')
                if not offline_available:
                    continue
                stem = Path(program['name']).stem
                require(command(['/usr/bin/xcrun', '--sdk', 'iphoneos', 'metal', '-fno-fast-math', '-c',
                    str(work/program['name']), '-o', str(work/(stem+'.ir'))], 'compile-'+stem, 30) == 0,
                    'Apple Metal compilation failed for '+program['name'])
                require(command(['/usr/bin/xcrun', '--sdk', 'iphoneos', 'metal', str(work/(stem+'.ir')),
                    '-o', str(work/(stem+'.metallib'))], 'link-'+stem, 20) == 0,
                    'Apple Metal library linking failed for '+program['name'])
            report['offlineMetalPrograms'] = emitted['programs'] if offline_available else []
            report['offlineTargetSDK'] = 'iphoneos' if offline_available else None
            code = command([str(executable), '--check', str(work)], 'macos-metal-and-morph', 60)
            runtime = json.loads(regular(work/'runtime-result.json', 32_768))
            report['runtime'] = runtime
            print(json.dumps(runtime_diagnostic(runtime)), flush=True)
            if code == 3 and runtime.get('status') == 'unavailable':
                raise Unavailable(runtime.get('reason', 'A macOS Metal device is unavailable.'))
            require(code == 0 and runtime_checks_passed(runtime, emitted),
                    'The bounded native Metal/SceneKit checks did not pass')
            if not offline_available:
                raise Unavailable('The macOS runtime checks passed, but the offline Metal compiler or iPhoneOS SDK is unavailable; no component was downloaded.')
            report['status'] = 'passed'
    except Unavailable as error:
        report.update(status='unavailable', reason=str(error))
    except (CheckFailure, OSError, ValueError, KeyError) as error:
        report.update(status='failed', reason=str(error)[:2000])
    encoded = json.dumps(report, indent=2, sort_keys=True)+'\n'
    (work/'public-shader-result.json').write_text(encoded)
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary:
        with open(summary, 'a', encoding='utf-8') as handle:
            handle.write('## Public shader checks\n\nSynthetic public-source scope; private character effect programs and iPhone rendering are not covered.\n\n```json\n'+encoded+'```\n')
    print(json.dumps({k:report[k] for k in ('status', 'scope', 'privateProgramsChecked')} |
        {'report': str(work/'public-shader-result.json'), 'reason': report.get('reason')}))
    return 0 if report['status'] in ('prepared', 'passed') else 3 if report['status'] == 'unavailable' else 1


if __name__ == '__main__':
    sys.exit(main())
