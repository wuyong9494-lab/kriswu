#!/usr/bin/env python3
"""New offline gates for the cold-scene candidate and conditional failed-UI followup."""
import collections
import contextlib
import copy
import datetime
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
import zlib

PATH = Path(__file__).with_name('fighter_scene_assembly_followup.py')
spec = importlib.util.spec_from_file_location('scene_assembly_followup_under_test', PATH)
h = importlib.util.module_from_spec(spec); spec.loader.exec_module(h)
DEVICE = {'udid':'12345678-1234-1234-1234-123456789ABC','name':'synthetic owned simulator','physicalDevice':False}
MATRIX = [1.0 if i % 5 == 0 else 0.0 for i in range(16)]
TOTAL = 956 * 440


def png(color=(9, 7, 3, 255)):
    def chunk(kind, body):
        return struct.pack('>I',len(body)) + kind + body + struct.pack('>I',zlib.crc32(kind+body)&0xffffffff)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR',struct.pack('>IIBBBBB',956,440,8,6,0,0,0))
            + chunk(b'IDAT',zlib.compress((b'\0'+bytes(color)*956)*440)) + chunk(b'IEND',b''))


PNG = png()


def image_metadata(raw=PNG, *, opaque=TOTAL, black=0, transparent=0, visible=TOTAL):
    return {'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),'width':956,'height':440,'pixelCount':TOTAL,
            'opaquePixelCount':opaque,'opaqueBlackPixelCount':black,'transparentPixelCount':transparent,
            'visibleNonBlackPixelCount':visible}


def report_fixture(image=None):
    image = image or image_metadata(); label = h.FRAME_LABELS[0]
    zero = dict.fromkeys(('simulationAdvanceCalls','explicitDrawStateCalls','activeSceneRebindCalls',
        'freshRendererCreationCalls','freshAssociationCalls','explicitPrepareCalls','snapshotCalls','projectorDetachCalls'),0)
    camera_values = {'exists':True,'fieldOfView':24.0,'near':0.1,'far':350.0,'orthographicScale':3.6,
                     'usesOrthographicProjection':False,'categoryMask':-1,'projectionTransform':MATRIX[:]}
    projector = {'available':True,'tick':0,'aspect':956/440,'sourceCameraPosition':[1.,2.,3.],
        'sourceView':MATRIX[:],'sourceProjection':MATRIX[:],'sourceShadowMatrix':MATRIX[:],
        'casterCount':13,'triangleCount':74855,'factors':[0.,0.]}
    common = {'label':label,'frame':0,'animationTick':0,'sourceLiveTick':0,'rendererRoute':'surface.captureFrame',
        'sourceProjectorInstalled':True,'projectorEncodedForCapture':True,'surfaceSubmittedFrames':0,
        'surfaceLastSubmittedTick':None,'submittedPackets':0,'requestedSurfaceSamples':2,'resolvedSurfaceSamples':4}
    sample = {**common,'displayLinkCallbacks':0,'sourceIntroActive':True,'sourceStance':'firstBirth',
        'sourceStanceTick':0,'weaponReady':False,'branchesReady':False,'sourceEffectIDs':[],
        **dict.fromkeys(('sameActiveSurface','sameActiveRenderer','sameScene','samePointOfView','sameOriginalProjector',
            'sameFrameDriver','renderCallbackInstalled','lateGeometryProviderInstalled','simulationInvariant','identityInvariant'),True),
        'rendererUsesReverseZ':False,'rendererAutoenablesDefaultLighting':False,'rendererIsPlaying':False,
        'rendererFailure':'','surfaceFailure':'','sourcePreparationFailure':'','projectorLastFrame':projector,
        'camera':{'modelWorldTransform':MATRIX[:],'presentationWorldTransform':MATRIX[:],
                  'metalProjection':MATRIX[:],'model':copy.deepcopy(camera_values),'presentation':copy.deepcopy(camera_values)},
        'fighters':[{'index':i,'hero':('ember','liu')[i],'x':2580 if i==0 else 6500,'y':0,'health':1000,
                     'clip':('h17_fight_start_stance_birth','dual_hammers_stance_idle')[i],'clipTick':0} for i in range(2)],
        'sceneInventory':[{'name':name,'geometries':1,'skinners':1,'hidden':False,'opacity':1.0}
                          for name in ('duel.stage.palace','duel.actor.0','duel.actor.1')],
        'viewport':{'pointsWidth':956.,'pointsHeight':440.,'captureWidth':956,'captureHeight':440,
                    'drawableWidth':2868.,'drawableHeight':1320.,'viewScale':3.,'surfaceScale':3.}}
    capture = {**common,'pngSHA256':image['sha256'],'bytes':image['bytes'],'width':956,'height':440,
        'pixelsRequireReview':True,'simulationAndModelCameraUnchanged':True,
        'isolation':'first complete offscreen encoding after cold World assembly; original projector always installed; no registration workaround'}
    construction = {**dict.fromkeys(('sceneAssemblyCompleted','initialPoseAppliedBeforeSurface','samePacketRenderer',
        'originalProjectorInstalled','renderCallbackInstalled','lateGeometryProviderInstalled','frameDriverInstalled'),True),
        'surfaceCreationAttempts':1,'surfaceSubviewCount':1,'originalProjectorHasEncodedFrame':False,
        'surfaceSubmittedFrames':0,'surfaceLastSubmittedTick':None,'frame':0,'animationTick':0,
        'sourceLiveTick':0,'displayLinkCallbacks':0,'sessionPaused':False,'worldWindowAbsent':True,'worldBoundsEmpty':True}
    before = {'surfaceSubmittedFrames':0,'surfaceLastSubmittedTick':None,'projectorLastFrameAvailable':False,
        'sourceProjectorInstalled':True,'displayLinkCallbacks':0,'frame':0,'animationTick':0,'sourceLiveTick':0,
        'submittedPackets':0,'sourceEffectIDs':[], 'sameActiveSurface':True,'sameActiveRenderer':True,
        'sameScene':True,'samePointOfView':True}
    stats = {key:image[key] for key in ('width','height','pixelCount','opaquePixelCount','opaqueBlackPixelCount',
        'transparentPixelCount','visibleNonBlackPixelCount')}
    stats.update(source='decoded-original-png',representation='sRGB-RGBA8-premultipliedLast-byteOrder32Big',
        criterion='alpha > 0 and at least one RGB channel > 0',opaqueOutputExpected=True,
        nonBlackRegressionPassed=image['visibleNonBlackPixelCount']>0)
    cleanup = {**dict.fromkeys(('worldSceneReleased','worldSurfaceReleased','worldPacketRendererReleased','surfaceSceneDetached',
        'surfacePointOfViewDetached','surfaceDelegateDetached','sourceProjectorDetached','renderCallbackCleared','lateGeometryProviderCleared'),True),
        'objectDeallocationVerified':False,'activeClocksBefore':0,'activeClocksAfter':0}
    report = {'schemaVersion':1,'schema':h.REPORT_SCHEMA,'scope':h.SCOPE,'releaseSHA256':h.RELEASE_SHA,
        'diagnosticCompleted':True,'lastPhase':'captured-before-regression-assertions','elapsedSeconds':1.0,
        'expectedSimulationFrames':[0],**zero,'captureFrameCalls':1,'stateInvariant':True,'identityInvariant':True,
        'combatStateInjected':False,'liveDisplayLinkAdvancesSelected':False,'sourcePacketsExpectedZero':True,
        'sceneKitLightsChanged':False,'firstCompleteOffscreenEncodingSelected':True,
        'normalDrawablePresentationValidated':False,'uiExecutionStatus':'not_selected','physicalDeviceValidated':False,
        'liveUIValidated':False,'audiblePlaybackVerified':False,'performanceVerified':False,'pixels':'PENDING',
        'panguEquipmentActivated':False,'captureTimingIncludesGPUReadbackWait':True,'captureLabels':[label],
        'construction':construction,'beforeFirstCapture':before,'pixelStatistics':stats,
        'nonBlackRegressionPassed':stats['nonBlackRegressionPassed'],'samples':[sample],'captures':[capture],
        'cleanup':cleanup,'timings':[{'phase':phase,'seconds':0.01} for phase in
            ('construct-session','construct-world','mount-layout','cold-first-offscreen-capture','decode-png-pixel-statistics')]}
    return report,{label:image}


def result_fixture(selector=None):
    selector=selector or h.SELECTOR
    summary={'totalTestCount':1,'passedTests':1,'failedTests':0,'skippedTests':0,'result':'Passed',
        'devicesAndConfigurations':[{'device':{'deviceId':DEVICE['udid'],'deviceName':DEVICE['name'],
            'modelName':'iPhone 17 Pro Max','platform':'iOS Simulator'},'passedTests':1,'failedTests':0,'skippedTests':0}]}
    data={'testNodes':[{'nodeType':'Test Case','nodeIdentifier':selector+'()','result':'Passed'}]}
    return summary,data


def files_fixture(directory, *, owner=None, device=None):
    report,_=report_fixture();directory.mkdir()
    (directory/'frame.png').write_bytes(PNG);(directory/'report.json').write_text(json.dumps(report))
    d=device or DEVICE
    attachments=[{'exportedFileName':name,'suggestedHumanReadableName':label+suffix,
        'deviceId':d['udid'],'deviceName':d['name']} for name,label,suffix in
        (('frame.png',h.FRAME_LABELS[0],'.png'),('report.json',h.REPORT_LABEL,'.json'))]
    (directory/'manifest.json').write_text(json.dumps([{'testIdentifier':owner or h.SELECTOR,'attachments':attachments}]))


class AssemblyFollowupChecks(unittest.TestCase):
    def test_01_exact_new_native_and_unchanged_failed_ui_source_pins(self):
        self.assertEqual(h.SOURCE_BASELINE,'09f2f3c2ea1c8ad0283e920d442995a5faa1b254')
        self.assertEqual(len(h.selected_inventory()),1);self.assertEqual(len(h.ui_inventory()),1)
        self.assertEqual(h.digest(h.ROOT/h.SWIFT_TEST),h.SWIFT_TEST_SHA)
        self.assertEqual(h.digest(h.ROOT/h.WORLD_SOURCE),h.WORLD_SOURCE_SHA)
        self.assertEqual(h.digest(h.ROOT/h.UI_TEST),h.UI_TEST_SHA)
        self.assertTrue(all(row['selectedAgain'] is False and row['countsBelongToCurrentRun'] is False for row in h.preserved_prior_evidence()))

    def test_02_world_is_the_only_allowed_app_change_and_old_inputs_remain_fixed(self):
        def row(path,mark='1'):return ('100644 blob '+mark*40+'\t'+path+'\n').encode()
        app=row('App/Keep.swift')+row(h.WORLD_SOURCE);tests=row('Tests/Keep.swift')+row(h.SWIFT_TEST)
        scripts=row('.github/scripts/keep.py')+row(h.HELPER)+row(h.CHECKS);workflows=row('.github/workflows/keep.yml')+row(h.WORKFLOW)
        with patch.multiple(h,OTHER_APP_SHA=h.sha(row('App/Keep.swift')),OTHER_TESTS_SHA=h.sha(row('Tests/Keep.swift')),
                OTHER_CI_SCRIPTS_SHA=h.sha(row('.github/scripts/keep.py')),OTHER_WORKFLOWS_SHA=h.sha(row('.github/workflows/keep.yml'))):
            h.validate_source_trees(h.REVIEWED_ENTRIES,app,tests,scripts,workflows)
            h.validate_source_trees(h.REVIEWED_ENTRIES,row('App/Keep.swift')+row(h.WORLD_SOURCE,'2'),tests,scripts,workflows)
            for changed in (row('App/Keep.swift','2')+row(h.WORLD_SOURCE),app+row('App/Extra.swift')):
                with self.assertRaises(ValueError):h.validate_source_trees(h.REVIEWED_ENTRIES,changed,tests,scripts,workflows)
            with self.assertRaises(ValueError):h.validate_source_trees(h.REVIEWED_ENTRIES,app,tests+row('Tests/Extra.swift'),scripts,workflows)

    def test_03_exact_source_byte_pin_rejects_unreviewed_world(self):
        with tempfile.TemporaryDirectory() as td,patch.object(h,'ROOT',Path(td)):
            p=Path(td)/'candidate.swift';p.write_bytes(b'original')
            h.pinned('candidate.swift',h.sha(b'original'));p.write_bytes(b'changed')
            with self.assertRaises(ValueError):h.pinned('candidate.swift',h.sha(b'original'))

    def test_04_one_build_requires_both_and_only_existing_test_targets(self):
        targets=[{'BlueprintName':'SiteTests','IsUITestBundle':False,'CommandLineArguments':['-demo']},
                 {'BlueprintName':'ArenaFlowTests','IsUITestBundle':True}]
        bundles={'SiteTests.xctest','ArenaFlowTests.xctest'};h.verify_compiled_targets(targets,bundles)
        for mutation in ('extra','skip','no_demo','missing_ui'):
            t=copy.deepcopy(targets)
            if mutation=='extra':t.append({'BlueprintName':'Other'})
            elif mutation=='skip':t[0]['SkipTestIdentifiers']=['oldMethod']
            elif mutation=='no_demo':t[0]['CommandLineArguments']=[]
            else:t=t[:1]
            with self.assertRaises(ValueError):h.verify_compiled_targets(t,bundles)

    def test_05_exact_push_attempt_and_source_are_required(self):
        head='a'*40
        env={'GITHUB_SHA':head,'GITHUB_REPOSITORY':h.REPOSITORY,'GITHUB_REF':h.BRANCH,
             'GITHUB_WORKFLOW_REF':h.REPOSITORY+'/'+h.WORKFLOW+'@'+h.BRANCH,'GITHUB_WORKFLOW_SHA':head,
             'GITHUB_RUN_ATTEMPT':'1','GITHUB_RUN_ID':'123','GITHUB_EVENT_NAME':'push'}
        event={'repository':{'full_name':h.REPOSITORY},'ref':h.BRANCH,'head_commit':{'id':head,'message':h.COMMIT_MESSAGE}}
        h.validate_event(env,event,head)
        for field,value in (('GITHUB_RUN_ATTEMPT','2'),('GITHUB_EVENT_NAME','workflow_dispatch'),('GITHUB_SHA','b'*40)):
            changed=dict(env);changed[field]=value
            with self.assertRaises(ValueError):h.validate_event(changed,event,head)

    def test_06_one_real_pass_per_scope_rejects_skipped_extra_or_wrong_device(self):
        for selector in (h.SELECTOR,h.UI_SELECTOR):
            summary,data=result_fixture(selector);h.verify_results(summary,data,DEVICE,selector)
            for mutation in ('skipped','duplicate','old_method','wrong_device'):
                s,d=copy.deepcopy(summary),copy.deepcopy(data)
                if mutation=='skipped':s['passedTests']=0;s['skippedTests']=1;d['testNodes'][0]['result']='Skipped'
                elif mutation=='duplicate':d['testNodes'].append(copy.deepcopy(d['testNodes'][0]))
                elif mutation=='old_method':d['testNodes'][0]['nodeIdentifier']='SiteTests/Old/testOld()'
                else:s['devicesAndConfigurations'][0]['device']['deviceId']='foreign'
                with self.assertRaises(ValueError):h.verify_results(s,d,DEVICE,selector)

    def test_07_native_failure_blocks_ui_without_zero_pass_claim(self):
        with tempfile.TemporaryDirectory() as td,patch.object(h,'work',return_value=Path(td)):
            with self.assertRaises(ValueError):h.require_native_ready_for_ui()
            state=h.ui_execution_state(False)
            self.assertEqual(state['status'],'blocked_by_native');self.assertEqual(state['observedMethods'],0)
            self.assertEqual(state['expectedMethods'],0);self.assertNotIn('passed',state)

    def test_08_ui_invocation_is_once_exact_selector_and_unchanged_360_seconds(self):
        with tempfile.TemporaryDirectory() as td,patch.object(h,'work',return_value=Path(td)), \
                patch.object(h,'identity'),patch.object(h,'no_resource_keys'),patch.object(h,'require_native_ready_for_ui'):
            root=Path(td);(root/'build-ok.txt').write_text('verified');(root/'xctestrun-path.txt').write_text('/synthetic/test.xctestrun')
            (root/'simulator.json').write_text(json.dumps(DEVICE));commands=[];summary,data=result_fixture(h.UI_SELECTOR)
            def run(command,label,timeout,**kw):
                commands.append((command,label,timeout))
                if kw.get('output_name'):
                    (root/kw['output_name']).write_text(json.dumps(summary if kw['output_name'].endswith('summary.json') else data))
                if label=='selected-ui':(root/'ui.xcresult').mkdir();(root/'ui.xcresult/Info.plist').write_text('present')
                return 0
            with patch.object(h,'run_logged',side_effect=run):h.execute_method('ui')
            selected=[row for row in commands if row[1]=='selected-ui'];self.assertEqual(len(selected),1)
            command,_,timeout=selected[0];self.assertEqual(timeout,360)
            self.assertEqual([x for x in command if x.startswith('-only-testing:')],['-only-testing:'+h.UI_SELECTOR])
            self.assertNotIn('-test-iterations',command)
            with self.assertRaises(FileExistsError):h.execute_method('ui')

    def test_09_real_png_stats_separate_nonblack_black_and_transparent(self):
        self.assertEqual(h.png_pixels(PNG),image_metadata())
        raw=png((0,0,0,255));self.assertEqual(h.png_pixels(raw),image_metadata(raw,black=TOTAL,visible=0))
        raw=png((0,0,0,0));self.assertEqual(h.png_pixels(raw),image_metadata(raw,opaque=0,transparent=TOTAL,visible=0))

    def test_10_png_crc_and_truncation_cannot_supply_pixel_gate(self):
        corrupted=bytearray(PNG);corrupted[-5]^=1
        for value in (bytes(corrupted),PNG[:-1],b'',b'not a PNG'):
            with self.assertRaises(ValueError):h.png_pixels(value)

    def test_11_complete_nonblack_frame_is_narrow_regression_not_visual_or_drawable_pass(self):
        report,images=report_fixture();result=h.validate_report(report,images)
        self.assertTrue(result['coldFrameRegressionPassed']);self.assertEqual(result['pixels'],'PENDING')
        self.assertFalse(result['normalDrawablePresentationValidated']);self.assertEqual(result['normalSubmittedFrames'],0)

    def test_12_complete_black_or_transparent_failure_remains_exportable_but_blocks_regression(self):
        for color,kwargs in (((0,0,0,255),{'black':TOTAL,'visible':0}),((0,0,0,0),{'opaque':0,'transparent':TOTAL,'visible':0})):
            raw=png(color);report,images=report_fixture(image_metadata(raw,**kwargs));result=h.validate_report(report,images)
            self.assertTrue(result['structureVerified']);self.assertFalse(result['coldFrameRegressionPassed'])

    def test_13_first_gpu_frame_requires_no_prior_draw_encode_registration_or_clock(self):
        for mutation in ('draw','capture_twice','prior_submit','prior_projector','fresh','prepare','rebind','clock','no_projector','claimed_pixels'):
            report,images=report_fixture()
            if mutation=='draw':report['explicitDrawStateCalls']=1
            elif mutation=='capture_twice':report['captureFrameCalls']=2
            elif mutation=='prior_submit':report['beforeFirstCapture']['surfaceSubmittedFrames']=1
            elif mutation=='prior_projector':report['beforeFirstCapture']['projectorLastFrameAvailable']=True
            elif mutation=='fresh':report['freshRendererCreationCalls']=1
            elif mutation=='prepare':report['explicitPrepareCalls']=1
            elif mutation=='rebind':report['activeSceneRebindCalls']=1
            elif mutation=='clock':report['samples'][0]['displayLinkCallbacks']=1
            elif mutation=='no_projector':report['samples'][0]['sourceProjectorInstalled']=False
            else:report['pixelStatistics']['visibleNonBlackPixelCount']-=1
            with self.assertRaises(ValueError):h.validate_report(report,images)

    def test_14_native_original_attachments_require_exact_method_device_and_hash(self):
        for mutation in ('valid','wrong_method','wrong_device','missing'):
            with tempfile.TemporaryDirectory() as td:
                directory=Path(td)/'attachments';files_fixture(directory,
                    owner='SiteTests/Old/testOld' if mutation=='wrong_method' else None,
                    device={'udid':'foreign','name':DEVICE['name']} if mutation=='wrong_device' else None)
                if mutation=='missing':(directory/'frame.png').unlink()
                if mutation=='valid':self.assertTrue(h.attachment_inventory(directory,DEVICE)['assemblyObservations']['coldFrameRegressionPassed'])
                else:
                    with self.assertRaises(ValueError):h.attachment_inventory(directory,DEVICE)

    def test_15_each_scope_runtime_is_full_nonempty_owned_and_known_errors_fail(self):
        started=datetime.datetime(2026,11,15,2,0,0,tzinfo=datetime.timezone.utc);finished=started+datetime.timedelta(seconds=2)
        event={'processImagePath':'/synthetic/ShiftReminder.app/ShiftReminder','eventMessage':'frame submitted','timestamp':'2026-11-15 02:00:01+00:00'}
        with tempfile.TemporaryDirectory() as td,patch.object(h,'simulator_name',return_value=DEVICE['name']):
            p=Path(td)/'runtime.json';p.write_text(json.dumps([event]))
            for scope in ('native','ui'):
                value=h.verify_runtime_log(p,collection_code=0,device=DEVICE,started=started,finished=finished,scope=scope)
                self.assertEqual(value['invocationScope'],scope);self.assertTrue(value['knownDiagnosticsAbsent'])
            for raw,code in ((b'[]',0),(b'{',0),(json.dumps([event]).encode(),1)):
                p.write_bytes(raw)
                with self.assertRaises(ValueError):h.verify_runtime_log(p,collection_code=code,device=DEVICE,started=started,finished=finished)
            event['eventMessage']=next(iter(h.METAL_DIAGNOSTICS.values()));p.write_text(json.dumps([event]))
            self.assertFalse(h.verify_runtime_log(p,collection_code=0,device=DEVICE,started=started,finished=finished)['knownDiagnosticsAbsent'])

    def test_16_ui_eligibility_requires_nonblack_attachment_and_full_native_log(self):
        with tempfile.TemporaryDirectory() as td,patch.object(h,'work',return_value=Path(td)), \
                patch.dict(os.environ,{'GITHUB_RUN_ID':'123','GITHUB_SHA':'a'*40}):
            root=Path(td);(root/'native-ok.txt').write_text('passed');s,d=result_fixture()
            for name,value in (('simulator.json',DEVICE),('native-process.json',{'exitCode':0,'selectedCount':1,'iterations':1,'exports':{'summary':0,'tests':0}}),('native-summary.json',s),('native-tests.json',d)):
                (root/name).write_text(json.dumps(value))
            receipt={'assemblyObservations':{'coldFrameRegressionPassed':True}};(root/'attachments-ok.json').write_text(json.dumps(receipt))
            with patch.object(h,'attachment_inventory',return_value=receipt),patch.object(h,'runtime_summary',return_value={'verified':True}):
                self.assertTrue(h.require_native_ready_for_ui()['nativeOriginalNonblackFrameVerified'])
            for nonblack,runtime in ((False,True),(True,False)):
                receipt={'assemblyObservations':{'coldFrameRegressionPassed':nonblack}};(root/'attachments-ok.json').write_text(json.dumps(receipt))
                with patch.object(h,'attachment_inventory',return_value=receipt),patch.object(h,'runtime_summary',return_value={'verified':runtime}):
                    with self.assertRaises(ValueError):h.require_native_ready_for_ui()

    def test_17_both_manifests_and_mandatory_sets_precede_automatic_files_in_shared_budget(self):
        class Shared:
            EXPECTED_ATTACHMENTS={'ui':{}}
            @staticmethod
            def attachment_label(*args):return []
        with tempfile.TemporaryDirectory() as td,patch.object(h,'work',return_value=Path(td)),patch.object(h,'resource_tools',return_value=Shared()):
            root=Path(td);must=[]
            for scope,count in (('native',2),('ui',7)):
                directory=root/(scope+'-attachments');directory.mkdir();(directory/'manifest.json').write_text('[]');rows=[]
                for i in range(count):
                    name='required-'+str(i)+'.png';(directory/name).write_bytes(b'original');rows.append({'file':name});must.append(directory/name)
                must.append(directory/'manifest.json')
                (root/('attachments-ok.json' if scope=='native' else 'ui-attachments-ok.json')).write_text(json.dumps({'files':rows}))
            for i in range(270):(root/'native-attachments'/('automatic-'+str(i)+'.txt')).write_text('record')
            selected=h.bounded_attachments();self.assertTrue(set(must)<={p for p,_ in selected});self.assertEqual(len(selected),256)
            policy=json.loads((root/'attachment-seal-policy.json').read_text())
            self.assertTrue(all(policy['scopes'][scope]['completeValidatedMandatorySetSealed'] for scope in ('native','ui')))

    def test_18_workflow_has_one_upload_stage_only_keys_and_conditional_ui_not_dispatch(self):
        workflow=(h.ROOT/h.WORKFLOW).read_text()
        self.assertEqual(workflow.count('actions/upload-artifact@v4'),1);self.assertNotIn('workflow_dispatch:',workflow)
        self.assertIn("steps.native.outcome == 'success' && steps.native_export.outcome == 'success'",workflow)
        stage=workflow[workflow.index('      - name: Authenticate'):workflow.index('      - name: Build')]
        self.assertEqual(stage.count('${{ secrets.'),3);self.assertEqual(workflow.count('${{ secrets.'),3)
        normalized,pin=h.normalized_workflow(workflow.encode())
        self.assertEqual(h.sha(normalized),h.WORKFLOW_CANONICAL_SHA);self.assertEqual(pin,h.digest(PATH))
        self.assertEqual(h.CHECKS_SHA,h.digest(Path(__file__)))


if __name__=='__main__':
    unittest.main(verbosity=2)
