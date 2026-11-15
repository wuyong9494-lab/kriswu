#!/usr/bin/env python3
"""Only the new two-capture/first-commit contract checks; historical twenty checks are not imported or executed."""
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

PATH = Path(__file__).with_name('fighter_active_renderer_preparation.py')
spec = importlib.util.spec_from_file_location('first_submit_preparation_under_test', PATH)
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



def base_frame_fixture(image=None, preparation=None):
    image = image or image_metadata(); label = h.FRAME_LABELS[0]
    prep = {'api':'SCNSceneRenderer.prepare(_:completionHandler:)','automatic':True,'target':'surface.sceneRenderer',
        'requestCount':1,'completionCount':1,'objectCount':1,'prepareSuccess':True,'completionIdentityMatched':True,
        'rendererMatchesOriginalSurface':True,'sceneMatchesOriginalScene':True,'hasPreparedSourceMusicScene':True,
        'sourceMusicReady':True,'testingMusicPrepareInstalled':False,'testingPrepareInstalled':False,
        'waitDeadlineSeconds':15,'waitTimedOut':False,'prepareCallsByTest':0,'synchronousPrepareCallsByTest':0,'completionCallsByTest':0}
    if preparation:prep.update(preparation)
    ready=(prep['target']=='surface.sceneRenderer' and prep['requestCount']==1 and prep['completionCount']==1 and prep['objectCount']==1
        and all(prep[k] is True for k in ('prepareSuccess','completionIdentityMatched','rendererMatchesOriginalSurface',
            'sceneMatchesOriginalScene','hasPreparedSourceMusicScene','sourceMusicReady')))
    zero=dict.fromkeys(('simulationAdvanceCalls','explicitDrawStateCalls','sceneRebindCalls','freshRendererCreationCalls',
        'snapshotCalls','projectorDetachCalls','prepareCallsByTest','synchronousPrepareCallsByTest','completionCallsByTest'),0)
    projector={'available':True,'tick':0,'aspect':956/440,'sourceCameraPosition':[1.,2.,3.],
        'sourceView':MATRIX[:],'sourceProjection':MATRIX[:],'sourceShadowMatrix':MATRIX[:],
        'casterCount':13,'triangleCount':74855,'factors':[0.,0.]}
    common={'label':label,'frame':0,'animationTick':0,'sourceLiveTick':0,'rendererRoute':'surface.captureFrame',
        'sourceProjectorInstalled':True,'projectorEncodedForCapture':True,'surfaceSubmittedFrames':0,
        'surfaceLastSubmittedTick':None,'submittedPackets':0,'requestedSurfaceSamples':2,'resolvedSurfaceSamples':4}
    sample={**common,'gamePaused':True,'displayLinkCallbacks':0,'sourceIntroActive':True,'sourceStance':'firstBirth',
        'sourceStanceTick':0,'sourceEffectIDs':[],
        **dict.fromkeys(('sameActiveSurface','sameActiveRenderer','sameScene','samePointOfView','hostStillOwnsScene',
            'hostStillOwnsPointOfView','modelObjectIdentityUnchanged','simulationInvariant'),True),
        'rendererUsesReverseZ':False,'rendererAutoenablesDefaultLighting':False,'rendererIsPlaying':False,
        'hostRendersContinuously':False,'hostIsPlaying':False,
        'rendererFailure':'','surfaceFailure':'','sourcePreparationFailure':'','projectorLastFrame':projector,
        'preparation':copy.deepcopy(prep),
        'camera':{'modelWorldTransform':MATRIX[:],'presentationWorldTransform':MATRIX[:],
            'metalProjection':MATRIX[:],'fieldOfView':24.0,'near':0.1,'far':350.0,'categoryMask':-1,'usesOrthographicProjection':False},
        'lights':[{'type':'directional','castsShadow':True,'intensity':1000.0,'categoryMask':-1,'modelWorldTransform':MATRIX[:]}],
        'fighters':[{'index':i,'hero':('ember','liu')[i],'x':2580 if i==0 else 6500,'y':0,'health':1000,
            'clip':('h17_fight_start_stance_birth','dual_hammers_stance_idle')[i],'clipTick':0} for i in range(2)],
        'sceneInventory':[{'name':name,'geometries':1,'skinners':1,'hidden':False,'opacity':1.0,
            'modelWorldTransform':MATRIX[:],'presentationWorldTransform':MATRIX[:]}
            for name in ('duel.stage.palace','duel.actor.0','duel.actor.1')],
        'viewport':{'pointsWidth':956.,'pointsHeight':440.,'captureWidth':956,'captureHeight':440}}
    capture={**common,'pngSHA256':image['sha256'],'bytes':image['bytes'],'width':956,'height':440,
        'pixelsRequireReview':True,'simulationAndModelCameraUnchanged':True}
    setup={'pausedBeforeWorldConstruction':True,'gamePaused':True,'testingMusicPrepareInstalled':False,'testingPrepareInstalled':False,
        'hostAndSurfaceShareScene':True,'hostAndSurfaceSharePointOfView':True,'surfaceSubmittedFrames':0,
        'surfaceLastSubmittedTick':None,'projectorLastFrameAvailable':False,'displayLinkCallbacks':0,
        'activeClocksBefore':0,'activeClocksAfterMount':0,'preparationRequestCountAfterMount':prep['requestCount']}
    before={'surfaceSubmittedFrames':0,'surfaceLastSubmittedTick':None,'projectorLastFrameAvailable':False,
        'frame':0,'animationTick':0,'displayLinkCallbacks':0,'sourceMusicReady':prep['sourceMusicReady'],
        'hasPreparedSourceMusicScene':prep['hasPreparedSourceMusicScene']}
    stats={key:image[key] for key in ('width','height','pixelCount','opaquePixelCount','opaqueBlackPixelCount',
        'transparentPixelCount','visibleNonBlackPixelCount')}
    cleanup={**dict.fromkeys(('worldSceneReleased','worldSurfaceReleased','worldPacketRendererReleased','surfaceSceneDetached',
        'surfacePointOfViewDetached','surfaceDelegateDetached','sourceProjectorDetached','renderCallbackCleared','lateGeometryProviderCleared'),True),
        'sourceMusicReadyAfterShutdown':False,'objectDeallocationVerified':False,'activeClocksBefore':0,'activeClocksAfter':0}
    report={'schemaVersion':1,'schema':h.REPORT_SCHEMA,'scope':h.SCOPE,'releaseSHA256':h.RELEASE_SHA,
        'diagnosticCompleted':True,'lastPhase':'captured-before-regression-assertions','elapsedSeconds':1.0,
        'expectedSimulationFrames':[0],**zero,'captureFrameCalls':1,'stateInvariant':True,'modelObjectIdentityInvariant':True,
        'gamePausedForIsolation':True,'presentationOnlyUnpauseCalls':1,
        'combatStateInjected':False,'liveDisplayLinkAdvancesSelected':False,'sourcePacketsExpectedZero':True,
        'sceneKitLightsChanged':False,'normalDrawablePresentationValidated':False,'uiFlowExecutedByThisMethod':False,
        'physicalDeviceValidated':False,'liveUIValidated':False,'audiblePlaybackVerified':False,'performanceVerified':False,
        'pixels':'PENDING','panguEquipmentActivated':False,'captureTimingIncludesGPUReadbackWait':True,'captureLabels':[label],
        'pixelDecode':'Original PNG decoded as sRGB RGBA8, byteOrder32Big/premultipliedLast, copy blend, no resizing',
        'setup':setup,'preparation':prep,'beforeFirstCapture':before,'pixelStatistics':stats,
        'readinessRegressionPassed':ready,'nonBlackRegressionPassed':image['visibleNonBlackPixelCount']>0 and image['opaquePixelCount']==TOTAL,
        'samples':[sample],'captures':[capture],'cleanup':cleanup,
        'timings':[{'phase':phase,'seconds':0.01} for phase in ('construct-paused-session','construct-world',
            'mount-production-automatic-preparation','await-production-automatic-completion',label+'-synchronous-capture')]}
    return report,{label:image}


def result_fixture(selector=None):
    selector=selector or h.SELECTOR
    summary={'totalTestCount':1,'passedTests':1,'failedTests':0,'skippedTests':0,'result':'Passed',
        'devicesAndConfigurations':[{'device':{'deviceId':DEVICE['udid'],'deviceName':DEVICE['name'],
            'modelName':'iPhone 17 Pro Max','platform':'iOS Simulator'},'passedTests':1,'failedTests':0,'skippedTests':0}]}
    data={'testNodes':[{'nodeType':'Test Case','nodeIdentifier':selector+'()','result':'Passed'}]}
    return summary,data


def report_fixture(colors=((9, 7, 3, 255), (3, 7, 9, 255)), preparation=None):
    report, _ = base_frame_fixture()
    prep=report['preparation'];prep.update({'commitCountAtRequest':1,'normalSubmittedFramesAtRequest':0})
    if preparation:prep.update(preparation)
    ready=(prep['target']=='surface.sceneRenderer' and prep['requestCount']==1 and prep['completionCount']==1 and prep['objectCount']==1
        and all(prep[k] is True for k in ('prepareSuccess','completionIdentityMatched','rendererMatchesOriginalSurface',
            'sceneMatchesOriginalScene','hasPreparedSourceMusicScene','sourceMusicReady')))
    pre=copy.deepcopy(prep);pre.update({'target':'not-started','requestCount':0,'completionCount':0,'objectCount':0,
        'prepareSuccess':None,'completionIdentityMatched':None,'rendererMatchesOriginalSurface':False,'sceneMatchesOriginalScene':False,
        'hasPreparedSourceMusicScene':False,'sourceMusicReady':False,'commitCountAtRequest':None,'normalSubmittedFramesAtRequest':None})
    sample_template,capture_template=report['samples'][0],report['captures'][0]
    samples,captures,images,stats=[],[],{},{}
    for index,label in enumerate(h.FRAME_LABELS):
        color=colors[index];raw=png(color);black=not any(color[:3]);alpha=color[3]
        image=image_metadata(raw,opaque=TOTAL if alpha==255 else 0,black=TOTAL if alpha==255 and black else 0,
            transparent=TOTAL if alpha==0 else 0,visible=TOTAL if alpha>0 and not black else 0)
        images[label]=image
        stats[label]={k:image[k] for k in ('width','height','pixelCount','opaquePixelCount','opaqueBlackPixelCount',
            'transparentPixelCount','visibleNonBlackPixelCount')}
        extra={'label':label,'captureOrdinal':index+1,'firstCompleteOffscreenEncoding':index==0,
            'preparationPhase':('before-prepare','after-real-completion')[index],'sourceFrameCommitCount':index+1,
            'presentationKickAttemptCount':0}
        sample=copy.deepcopy(sample_template);sample.update(extra)
        sample.update({'preparation':copy.deepcopy(pre if index==0 else prep),'firstCommitObservedForCurrentOwners':True,
            'queuedPreparationWorkPending':index==0})
        capture=copy.deepcopy(capture_template);capture.update(extra)
        capture.update({'pngSHA256':image['sha256'],'bytes':image['bytes']})
        samples.append(sample);captures.append(capture)
    report['setup'].update({'preparationRequestCountAfterMount':0,'sourceFrameCommitCount':0,
        'firstCommitObservedForCurrentOwners':False,'presentationKickScheduleCount':1,
        'presentationKickAttemptCount':0,'queuedPreparationWorkPending':True})
    report['beforeFirstCapture'].update({'sourceMusicReady':False,'hasPreparedSourceMusicScene':False,
        'preparationRequestCount':0,'preparationCompletionCount':0,'sourceFrameCommitCount':0,
        'firstCommitObservedForCurrentOwners':False,'presentationKickAttemptCount':0})
    report['beforeSecondCapture']={**report['beforeFirstCapture'],'projectorLastFrameAvailable':True,
        'sourceMusicReady':prep['sourceMusicReady'],'hasPreparedSourceMusicScene':prep['hasPreparedSourceMusicScene'],
        'preparationRequestCount':prep['requestCount'],'preparationCompletionCount':prep['completionCount'],
        'sourceFrameCommitCount':1,'firstCommitObservedForCurrentOwners':True}
    report['firstCommit']={'sourceFrameCommitCount':2,'firstCommitObservedForCurrentOwners':True,
        'presentationKickScheduleCount':1,'presentationKickAttemptCount':0,'queuedPreparationWorkPending':False,
        'normalSubmittedFrames':0,'normalLastSubmittedTick':None,'callbackMeansCommandBufferCommit':True,
        'callbackMeansGPUCompletion':False,'callbackMeansDisplayedDrawable':False}
    report.update({'captureFrameCalls':2,'captureLabels':list(h.FRAME_LABELS),'samples':samples,'captures':captures,
        'pixelStatistics':stats,'readinessRegressionPassed':ready,'firstCaptureOccurredBeforePrepare':True,
        'firstCommitOrderingPassed':prep['commitCountAtRequest']==1 and prep['normalSubmittedFramesAtRequest']==0,
        'nonBlackRegressionPassed':all(v['opaquePixelCount']==TOTAL and v['visibleNonBlackPixelCount']>0 for v in stats.values()),
        'timings':[{'phase':phase,'seconds':0.01} for phase in ('construct-paused-session','construct-world',
            'mount-production-first-submit-deferral','await-production-automatic-completion',
            *(label+'-synchronous-capture' for label in h.FRAME_LABELS))]})
    report['cleanup'].update({'queuedPreparationWorkCleared':True,'firstCommitIdentityCleared':True})
    return report,images


def files_fixture(directory):
    report,_=report_fixture();directory.mkdir()
    (directory/'a.png').write_bytes(png((9,7,3,255)));(directory/'b.png').write_bytes(png((3,7,9,255)))
    (directory/'report.json').write_text(json.dumps(report))
    attachments=[{'exportedFileName':name,'suggestedHumanReadableName':label+suffix,
        'deviceId':DEVICE['udid'],'deviceName':DEVICE['name']} for name,label,suffix in
        (('a.png',h.FRAME_LABELS[0],'.png'),('b.png',h.FRAME_LABELS[1],'.png'),('report.json',h.REPORT_LABEL,'.json'))]
    (directory/'manifest.json').write_text(json.dumps([{'testIdentifier':h.SELECTOR,'attachments':attachments}]))


class FirstSubmitSourceDeltaChecks(unittest.TestCase):
    def test_new_scope_reselects_only_the_prior_failed_native_under_new_source(self):
        self.assertEqual(h.SCOPE, 'installed-first-submit-preparation-one')
        self.assertEqual(h.SOURCE_BASELINE, 'f52c293da885f24ebae7640055161380aba4a5f7')
        self.assertEqual(h.COMMIT_MESSAGE, 'Verify first-submit preparation and APK signer continuation 20261115')
        self.assertEqual(h.CHECKS, '.github/scripts/test_fighter_first_submit_preparation.py')
        prior=h.reselected_failed_native_evidence()
        self.assertEqual(prior['runID'],'43678506116')
        self.assertEqual((prior['passedMethods'],prior['failedMethods'],prior['skippedMethods']),(0,1,0))
        self.assertEqual(prior['selector'],h.SELECTOR)
        self.assertTrue(prior['reselectedAtNewSource']);self.assertFalse(prior['countsBelongToCurrentRun'])
        self.assertEqual([row['identifier'] for row in h.selected_inventory()],[h.SELECTOR])
        self.assertEqual([row['identifier'] for row in h.ui_inventory()],[h.UI_SELECTOR])

    def test_exact_three_android_noninputs_do_not_exempt_sdk_or_old_twenty_checks(self):
        paths={row['path'] for row in h.co_published_non_inputs()}
        self.assertEqual(paths,{'.github/scripts/fighter_android_official_client.py',
            '.github/scripts/test_fighter_android_apk_signature.py','.github/workflows/fighter-android-official-client.yml'})
        def row(path, mark='1'):return ('100644 blob '+mark*40+'\t'+path+'\n').encode()
        retained=('.github/scripts/fighter_android_sdk_install.py',
            '.github/scripts/test_fighter_android_sdk_registration_preflight.py',
            '.github/scripts/test_fighter_active_renderer_preparation.py')
        stable=b''.join(row(path) for path in retained)
        app=row(h.WORLD_SOURCE)+row('App/Keep.swift');tests=row(h.SWIFT_TEST)+row('Tests/Keep.swift')
        scripts=stable+row(h.HELPER)+row(h.CHECKS)+b''.join(row(path) for path in sorted(paths) if path.startswith('.github/scripts/'))
        workflows=row(h.WORKFLOW)+row('.github/workflows/keep.yml')+b''.join(row(path) for path in sorted(paths) if path.startswith('.github/workflows/'))
        with patch.multiple(h,OTHER_APP_SHA=h.sha(row('App/Keep.swift')),OTHER_TESTS_SHA=h.sha(row('Tests/Keep.swift')),
                OTHER_CI_SCRIPTS_SHA=h.sha(stable),OTHER_WORKFLOWS_SHA=h.sha(row('.github/workflows/keep.yml'))):
            h.validate_source_trees(h.REVIEWED_ENTRIES,app,tests,scripts,workflows)
            for path in retained:
                with self.assertRaises(ValueError):
                    h.validate_source_trees(h.REVIEWED_ENTRIES,app,tests,scripts.replace(row(path),row(path,'2')),workflows)

    def test_two_capture_source_and_new_check_bytes_form_final_pin_closure(self):
        for path,pin in ((h.SWIFT_TEST,h.SWIFT_TEST_SHA),(h.WORLD_SOURCE,h.WORLD_SOURCE_SHA),(h.UI_TEST,h.UI_TEST_SHA)):
            self.assertEqual(h.digest(h.ROOT/path),pin)
        self.assertEqual(h.CHECKS_SHA,h.digest(Path(__file__)))
        old=h.ROOT/'.github/scripts/test_fighter_active_renderer_preparation.py'
        self.assertEqual(h.digest(old),'40786c7b10ad0f3c4feab1acc557594604057115d192c5e64a61b47a893e3083')
        normalized,pin=h.normalized_workflow((h.ROOT/h.WORKFLOW).read_bytes())
        self.assertEqual(h.sha(normalized),h.WORKFLOW_CANONICAL_SHA);self.assertEqual(pin,h.digest(PATH))
        for item in h.co_published_non_inputs():
            self.assertEqual(h.digest(h.ROOT/item['path']),item['sha256'])
            self.assertEqual((h.ROOT/item['path']).stat().st_size,item['bytes'])

    def test_changed_entry_keeps_native_ui_deadlines_and_stage_only_secret_scope(self):
        import ast
        source=PATH.read_text();tree=ast.parse(source)
        method=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='execute_method')
        limit=next(call.args[2] for call in ast.walk(method) if isinstance(call,ast.Call)
            and isinstance(call.func,ast.Name) and call.func.id=='run_logged')
        self.assertIsInstance(limit,ast.IfExp)
        self.assertEqual((ast.literal_eval(limit.body),ast.literal_eval(limit.orelse)),(720,360))
        workflow=(h.ROOT/h.WORKFLOW).read_text()
        self.assertIn(h.COMMIT_MESSAGE,workflow)
        self.assertIn("steps.native.outcome == 'success' && steps.native_export.outcome == 'success'",workflow)
        self.assertEqual(workflow.count('${{ secrets.'),3)
        stage=workflow[workflow.index('      - name: Authenticate'):workflow.index('      - name: Build')]
        self.assertEqual(stage.count('${{ secrets.'),3)
        self.assertEqual(workflow.count('actions/upload-artifact@v4'),1)
        self.assertIn('fighter-first-submit-preparation-${{ github.run_id }}',workflow)
        self.assertNotIn('workflow_dispatch:',workflow)


class FirstSubmitTwoImageDeltaChecks(unittest.TestCase):
    def test_both_originals_and_actual_first_commit_are_narrow_evidence_not_display_acceptance(self):
        report,images=report_fixture();value=h.validate_report(report,images)
        self.assertTrue(value['firstSubmitSequenceVerified']);self.assertTrue(value['actualPreparationReady'])
        self.assertTrue(value['beforePreparationOpaqueNonblackPassed']);self.assertTrue(value['afterPreparationOpaqueNonblackPassed'])
        self.assertTrue(value['firstSubmitPreparationRegressionPassed'])
        self.assertEqual(value['firstCompleteOffscreenEncodingByLabel'],{h.FRAME_LABELS[0]:True,h.FRAME_LABELS[1]:False})
        self.assertEqual(value['originalPNGHashes'],{label:image['sha256'] for label,image in images.items()})
        self.assertEqual(value['captureFrameCalls'],2);self.assertEqual(value['normalSubmittedFrames'],0)
        self.assertFalse(value['callbackMeansGPUCompletion']);self.assertFalse(value['normalDrawablePresentationValidated'])
        self.assertEqual(value['pixels'],'PENDING')
        # The real preparation may change presentation; unchanged model state is the invariant.
        report['samples'][1]['camera']['presentationWorldTransform'][0]=2.0
        self.assertTrue(h.validate_report(report,images)['firstSubmitPreparationRegressionPassed'])

    def test_either_black_original_false_readiness_or_wrong_commit_retains_complete_failure(self):
        for colors,preparation in ((((0,0,0,255),(3,7,9,255)),None),(((9,7,3,255),(0,0,0,255)),None),
                (((9,7,3,255),(0,0,0,0)),None),(((9,7,3,255),(3,7,9,255)),{'sourceMusicReady':False}),
                (((9,7,3,255),(3,7,9,255)),{'commitCountAtRequest':0})):
            report,images=report_fixture(colors,preparation);value=h.validate_report(report,images)
            self.assertTrue(value['structureVerified']);self.assertFalse(value['firstSubmitPreparationRegressionPassed'])
            self.assertEqual(set(value['originalPNGHashes']),set(h.FRAME_LABELS))
        report,images=report_fixture(((9,7,3,255),(0,0,0,255)))
        report['nonBlackRegressionPassed']=True
        with self.assertRaises(ValueError):h.validate_report(report,images)
        report,images=report_fixture(preparation={'sourceMusicReady':False});report['readinessRegressionPassed']=True
        with self.assertRaises(ValueError):h.validate_report(report,images)

    def test_prior_prepare_fake_second_first_frame_and_swapped_pixels_cannot_satisfy_contract(self):
        for mutation in ('old_single','a_prepared','prior_frame','b_first','swap_hash','swap_stats','gpu_completed',
                'normal_frame','extra_kick','request_bool','ordering_claim','camera_changed','clock','partial'):
            report,images=report_fixture()
            if mutation=='old_single':report['captures']=report['captures'][:1];report['captureFrameCalls']=1
            elif mutation=='a_prepared':report['samples'][0]['preparation']['requestCount']=1
            elif mutation=='prior_frame':report['beforeFirstCapture']['projectorLastFrameAvailable']=True
            elif mutation=='b_first':report['captures'][1]['firstCompleteOffscreenEncoding']=True
            elif mutation=='swap_hash':report['captures'][1]['pngSHA256']=report['captures'][0]['pngSHA256']
            elif mutation=='swap_stats':report['pixelStatistics'][h.FRAME_LABELS[1]]['visibleNonBlackPixelCount']-=1
            elif mutation=='gpu_completed':report['firstCommit']['callbackMeansGPUCompletion']=True
            elif mutation=='normal_frame':report['firstCommit']['normalSubmittedFrames']=1
            elif mutation=='extra_kick':report['samples'][1]['presentationKickAttemptCount']=1
            elif mutation=='request_bool':report['preparation']['commitCountAtRequest']=True
            elif mutation=='ordering_claim':report['firstCommitOrderingPassed']=False
            elif mutation=='camera_changed':report['samples'][1]['camera']['modelWorldTransform'][0]=2.0
            elif mutation=='clock':report['samples'][1]['displayLinkCallbacks']=1
            else:report['diagnosticCompleted']=False;report['lastPhase']='automatic-preparation-not-completed'
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):h.validate_report(report,images)

    def test_both_owned_attachments_and_combined_native_gate_are_required_for_failed_ui_followup(self):
        with tempfile.TemporaryDirectory() as td:
            directory=Path(td)/'native-attachments';files_fixture(directory)
            receipt=h.attachment_inventory(directory,DEVICE)
            self.assertEqual(len(receipt['files']),3)
            self.assertTrue(receipt['preparationObservations']['firstSubmitPreparationRegressionPassed'])
            manifest=json.loads((directory/'manifest.json').read_text())
            manifest[0]['attachments'][1]['deviceId']='foreign';(directory/'manifest.json').write_text(json.dumps(manifest))
            with self.assertRaises(ValueError):h.attachment_inventory(directory,DEVICE)
            manifest[0]['attachments'][1]['deviceId']=DEVICE['udid'];(directory/'manifest.json').write_text(json.dumps(manifest))
            (directory/'b.png').unlink()
            with self.assertRaises(ValueError):h.attachment_inventory(directory,DEVICE)
        with tempfile.TemporaryDirectory() as td,patch.object(h,'work',return_value=Path(td)), \
                patch.dict(os.environ,{'GITHUB_RUN_ID':'123','GITHUB_SHA':'a'*40}):
            root=Path(td);(root/'native-ok.txt').write_text('passed');summary,data=result_fixture()
            for name,value in (('simulator.json',DEVICE),('native-process.json',{'exitCode':0,'selectedCount':1,'iterations':1,'exports':{'summary':0,'tests':0}}),
                    ('native-summary.json',summary),('native-tests.json',data)):
                (root/name).write_text(json.dumps(value))
            valid={'firstSubmitPreparationRegressionPassed':True,'firstSubmitSequenceVerified':True,'actualPreparationReady':True,
                'bothOpaqueNonblackFramesPassed':True,'beforePreparationOpaqueNonblackPassed':True,'afterPreparationOpaqueNonblackPassed':True}
            for broken in (None,*valid):
                observation=dict(valid)
                if broken:observation[broken]=False
                receipt={'preparationObservations':observation};(root/'attachments-ok.json').write_text(json.dumps(receipt))
                with patch.object(h,'attachment_inventory',return_value=receipt),patch.object(h,'runtime_summary',return_value={'verified':True}):
                    if broken:
                        with self.subTest(broken=broken),self.assertRaises(ValueError):h.require_native_ready_for_ui()
                    else:
                        self.assertTrue(h.require_native_ready_for_ui()['nativeBothOriginalNonblackFramesVerified'])
            (root/'native-ok.txt').unlink()
            with self.assertRaises(ValueError):h.require_native_ready_for_ui()
            state=h.ui_execution_state(False)
            self.assertEqual(state['status'],'blocked_by_native');self.assertEqual(state['observedMethods'],0)
            self.assertNotIn('passedMethods',state)


if __name__ == '__main__':
    unittest.main(verbosity=2)
