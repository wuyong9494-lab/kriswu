#!/usr/bin/env python3
"""New bounded Terms action checks: synthetic pixels and mocked commands only.

No SDK/APK acquisition, native process, emulator, real input or old success
suite is executed. Synthetic checkbox deltas never assert a selected state.
"""
from contextlib import contextmanager
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image

SPEC = importlib.util.spec_from_file_location("terms_continuation_delta",
    Path(__file__).with_name("fighter_android_official_client.py"))
R = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(R)
PID = 5123
RESUMED = "  mResumedActivity: ActivityRecord{abc123 u0 "+R.TERMS_ACTIVITY+" t5}\n"
WINDOW = "  mCurrentFocus=Window{def456 u0 "+R.TERMS_ACTIVITY+"}\n"
ACTIVITY = RESUMED+WINDOW
WINDOW_DIAGNOSTIC = "WINDOW MANAGER WINDOWS (dumpsys window windows)\n  mTopFocusedDisplayId=0\n"


def png(*, inner=False, outside=False, width=1920):
    picture = Image.new("RGBA",(width,1080),(41,45,49,255))
    if inner:
        picture.putpixel((428,869),(214,171,0,255))
    if outside:
        picture.putpixel((1444,874),(255,255,255,255))
    stream = io.BytesIO()
    picture.save(stream,format="PNG")
    return stream.getvalue()


def reference(raw):
    with Image.open(io.BytesIO(raw)) as picture:
        rgba = bytearray(picture.tobytes())
    for y in range(851,888):
        rgba[(y*1920+410)*4:(y*1920+447)*4] = bytes(37*4)
    return {"bytes":len(raw),"outsideInteriorRGBASHA256":hashlib.sha256(rgba).hexdigest()}


@contextmanager
def fixture(base):
    with tempfile.TemporaryDirectory() as directory:
        owned = Path(directory)/"owned"
        (owned/"evidence").mkdir(parents=True)
        clock = [100.0]
        state = {"appPID":PID,"activity":R.TERMS_ACTIVITY,
            "apk":{"sha256":R.APK_RECEIVED_SHA256},
            "installedABISelection":{"installedABIConfirmed":True,"requestedABI":R.INSTALL_ABI},
            "termsImageDecoder":{"ready":True},"executed":{"apkLaunches":1},
            "emulator":{"monotonicStart":100.0},
            "observation":{"gameTermsContinuation":R.new_game_terms_continuation()}}
        (owned/"evidence/screen-00.png").write_bytes(base)
        state["observation"]["gameTermsContinuation"]["triggerSnapshot"] = {
            "index":0,"file":"screen-00.png","bytes":len(base),"sha256":R.sha(base),"packagePID":PID}
        with patch.object(R,"work",return_value=owned), \
                patch.object(R.time,"monotonic",side_effect=lambda:clock[0]), \
                patch.object(R,"ACTIVE_EMULATOR_DEADLINE",None), \
                patch.object(R,"TERMS_REFERENCES",{R.sha(base):reference(base)}):
            yield state,clock


def write_command(label,raw,code=0,deadline=280.0):
    if isinstance(raw,str):
        raw = raw.encode()
    (R.evidence()/(label+".log")).write_bytes(raw)
    receipt = {"exitCode":code,"elapsedSeconds":0.0,"bytes":len(raw),"sha256":R.sha(raw),
        "scopeDeadlineProvided":True,"deadlineBasis":"scope","deadlineReached":False,
        "scopeDeadlineExpired":False}
    if label.endswith("-input"):
        receipt.update({"processStarted":True,"processStartedMonotonic":100.0,
            "processFinishedMonotonic":100.0,"effectiveDeadlineMonotonic":deadline,
            "scopeDeadlineMonotonic":deadline})
    R.write_json(R.evidence()/(label+"-process.json"),receipt)
    return raw.decode(errors="replace"),code


def fake_adb(base,changed,*,bad_pid=None,bad_focus=None,input_code=0):
    calls = []
    def invoke(tools,args,label,timeout,**kwargs):
        calls.append((args,label,kwargs))
        is_input = label.endswith("-input")
        assert kwargs["deadline"] == (105.0 if is_input else 280.0)
        if is_input:
            return write_command(label,"",input_code,kwargs["deadline"])
        if label.endswith("screenshot"):
            return write_command(label,base if "-agree-" in label else changed)
        if "-pid-" in label:
            return write_command(label,(bad_pid if bad_pid is not None and label.endswith("pid-after") else str(PID))+"\n")
        if "-activity-" in label:
            return write_command(label,ACTIVITY if bad_focus is None else RESUMED+bad_focus)
        if "-window-" in label:
            return write_command(label,WINDOW_DIAGNOSTIC)
        raise AssertionError(label)
    return invoke,calls


class TermsContinuationDelta(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.base,cls.changed,cls.outside = png(),png(inner=True),png(inner=True,outside=True)

    def test_first_screen_is_exact_and_delta_is_strictly_inside_original_empty_box(self):
        with fixture(self.base):
            initial = R.terms_image_check(self.base)
            delta = R.terms_image_check(self.changed,initial["initialReferenceSHA256"])
            self.assertEqual(delta["changedInteriorPixels"],1)
            self.assertTrue(delta["checkboxVisualDeltaObserved"])
            self.assertFalse(delta["checkedStateVerified"])
            for raw,initial_ref,reason in ((self.changed,None,"unreviewed_initial"),
                    (self.base+bytes(1),None,"unreviewed_initial"),
                    (self.base,R.sha(self.base),"delta_missing"),
                    (self.outside,R.sha(self.base),"outside_checkbox"),
                    (png(width=1919),None,"format_mismatch")):
                with self.subTest(reason=reason),self.assertRaisesRegex(R.Blocked,reason):
                    R.terms_image_check(raw,initial_ref)

    def test_second_image_cannot_switch_to_another_known_reference(self):
        alternate = png(outside=True)
        with fixture(self.base):
            R.TERMS_REFERENCES[R.sha(alternate)] = reference(alternate)
            with self.assertRaisesRegex(R.Blocked,"outside_checkbox"):
                R.terms_image_check(self.outside,R.sha(self.base))

    def test_foreground_rejects_overlay_ambiguity_wrong_user_and_failed_process(self):
        parsed = R.consent_foreground(ACTIVITY,0)
        self.assertTrue(parsed["foregroundVerified"])
        self.assertEqual(parsed["foregroundEvidenceSource"],
                         "activity_dump_unique_mResumedActivity_and_mCurrentFocus")
        for activity,code in ((ACTIVITY+WINDOW,0),(ACTIVITY+RESUMED,0),(RESUMED,0),
                (ACTIVITY.replace("u0","u10"),0),
                (RESUMED+WINDOW.replace(R.TERMS_ACTIVITY,"com.android.permissioncontroller/.GrantPermissionsActivity"),0),
                (ACTIVITY,False),(ACTIVITY,1),(WINDOW_DIAGNOSTIC,0)):
            with self.subTest(activity=activity,code=code):
                self.assertFalse(R.consent_foreground(activity,code)["foregroundVerified"])

    def test_two_completed_commands_keep_all_semantic_claims_false(self):
        with fixture(self.base) as (state,clock):
            invoke,calls = fake_adb(self.base,self.changed)
            with patch.object(R,"adb_command",side_effect=invoke):
                self.assertTrue(R.continue_known_game_terms({},state,PID,deadline=280.0))
            result = state["observation"]["gameTermsContinuation"]
            self.assertEqual(result["inputAttempts"],{"agree":1,"continue":1})
            self.assertEqual(result["inputReservations"],{"agree":1,"continue":1})
            self.assertTrue(result["twoInputCommandsCompleted"])
            self.assertEqual([args for args,label,_ in calls if label.endswith("-input")],
                [["shell","input","tap",428,869],["shell","input","tap",1444,874]])
            for key in ("checkedStateVerified","termsAccepted","userConsentConfirmed","clientInitialized"):
                self.assertIs(result[key],False)
            for action in result["actions"]:
                self.assertEqual(len(action["identityEvidence"]),6)
                self.assertTrue(action["input"]["called"] and action["input"]["returned"])
                self.assertEqual(action["input"]["inputDeadlineMonotonic"],105.0)
            self.assertEqual(json.loads((R.evidence()/"consent-actions.json").read_text()),result)

    def test_changed_pid_or_foreground_prevents_the_first_input(self):
        for changes in ({"bad_pid":"5124"},{"bad_pid":"5123 5124"},{"bad_focus":"mCurrentFocus=null\n"}):
            with self.subTest(changes=changes),fixture(self.base) as (state,clock):
                invoke,calls = fake_adb(self.base,self.changed,**changes)
                with patch.object(R,"adb_command",side_effect=invoke):
                    self.assertFalse(R.continue_known_game_terms({},state,PID,deadline=280.0))
                self.assertFalse(any(label.endswith("-input") for _,label,_ in calls))
                self.assertEqual(state["observation"]["gameTermsContinuation"]["inputAttempts"],{"agree":0,"continue":0})

    def test_changed_continue_text_stops_after_one_input_without_widening_the_mask(self):
        with fixture(self.base) as (state,clock):
            invoke,calls = fake_adb(self.base,self.outside)
            with patch.object(R,"adb_command",side_effect=invoke):
                self.assertFalse(R.continue_known_game_terms({},state,PID,deadline=280.0))
            result = state["observation"]["gameTermsContinuation"]
            self.assertEqual(result["inputAttempts"],{"agree":1,"continue":0})
            self.assertEqual(result["stopReason"],"terms_pixels_outside_checkbox_changed")
            self.assertTrue((R.evidence()/"consent-before-continue.png").is_file())

    def test_failed_input_is_preserved_and_is_never_retried(self):
        with fixture(self.base) as (state,clock):
            invoke,calls = fake_adb(self.base,self.changed,input_code=1)
            with patch.object(R,"adb_command",side_effect=invoke):
                self.assertFalse(R.continue_known_game_terms({},state,PID,deadline=280.0))
                count = len(calls)
                self.assertFalse(R.continue_known_game_terms({},state,PID,deadline=280.0))
                self.assertEqual(len(calls),count)
            result = state["observation"]["gameTermsContinuation"]
            action = result["actions"][0]
            self.assertTrue(action["input"]["called"] and action["input"]["returned"])
            self.assertFalse(action["input"]["completed"])
            self.assertEqual(result["inputAttempts"],{"agree":1,"continue":0})

    def test_slow_intent_write_expires_freshness_before_any_adb_call(self):
        with fixture(self.base) as (state,clock):
            action = {"step":"agree","phase":"preflight_verified",
                "sourceFreshScreenshot":{"captureStartedMonotonic":100.0}}
            state["observation"]["gameTermsContinuation"]["actions"].append(action)
            original = R.save_consent
            def slow_save(value):
                original(value)
                clock[0] = 106.0
            with patch.object(R,"save_consent",side_effect=slow_save), \
                    patch.object(R,"adb_command") as adb, self.assertRaises(R.ScopedDeadlineExpired):
                R.consent_input_once({},state,action,deadline=280.0)
            adb.assert_not_called()
            result = state["observation"]["gameTermsContinuation"]
            self.assertEqual(result["inputReservations"]["agree"],1)
            self.assertEqual(result["inputAttempts"]["agree"],0)
            self.assertFalse(action["input"]["attempted"] or action["input"]["called"])

    def test_absolute_input_deadline_survives_slow_log_open_before_popen(self):
        with fixture(self.base) as (state,clock):
            original_open = Path.open
            def slow_open(path,*args,**kwargs):
                result = original_open(path,*args,**kwargs)
                if path.name == "consent-agree-input.log":
                    clock[0] = 106.0
                return result
            with patch.object(Path,"open",slow_open),patch.object(R.subprocess,"Popen") as process, \
                    self.assertRaises(R.ScopedDeadlineExpired):
                R.command(["never-execute"],"consent-agree-input",5,deadline=105.0)
            process.assert_not_called()
            self.assertFalse((R.evidence()/"consent-agree-input-process.json").exists())

    def test_failed_image_receipt_preserves_actual_dimensions(self):
        with fixture(self.base) as (state,clock):
            invoke,calls = fake_adb(png(width=1919),self.changed)
            with patch.object(R,"adb_command",side_effect=invoke):
                self.assertFalse(R.continue_known_game_terms({},state,PID,deadline=280.0))
            result = state["observation"]["gameTermsContinuation"]
            self.assertEqual(result["actions"][0]["sourceFreshScreenshot"]["width"],1919)
            self.assertFalse(any(label.endswith("-input") for _,label,_ in calls))

    def test_remaining_observation_uses_same_budget_without_old_marker_or_relaunch(self):
        with fixture(self.base) as (state,clock):
            def snapshot(tools,index,**kwargs):
                self.assertEqual(kwargs["deadline"],280.0)
                (R.evidence()/f"screen-{index:02d}.png").write_bytes(self.base)
                return "account_or_captcha_prompt" if index == 1 else None
            def continuation(tools,value,pid,**kwargs):
                self.assertEqual(kwargs["deadline"],280.0)
                result = value["observation"]["gameTermsContinuation"]
                result["twoInputCommandsCompleted"] = True
                result["actions"] = [{"identity":{"expectedPID":PID}}]
                return True
            def adb(tools,args,label,timeout,**kwargs):
                self.assertEqual(kwargs["deadline"],280.0)
                self.assertIn(args,(["shell","cat","/proc/net/dev"],["shell","pidof",R.PACKAGE]))
                return str(PID),0
            with patch.object(R,"snapshot",side_effect=snapshot), \
                    patch.object(R,"adb_command",side_effect=adb),patch.object(R,"guest_bytes",return_value=0), \
                    patch.object(R,"continue_known_game_terms",side_effect=continuation), \
                    patch.object(R,"observe_unconfirmed_terms",return_value={"reason":"new_terms_or_privacy_prompt"}) as marker, \
                    patch.object(R.time,"sleep"):
                R.observe_client({},state)
            marker.assert_called_once()
            self.assertEqual(state["executed"]["apkLaunches"],1)
            result = state["observation"]["postInputObservation"]
            self.assertEqual(len(result["samples"]),1)
            self.assertFalse(result["clientInitialized"] or result["normalUIVerified"])
            self.assertEqual(state["observation"]["stopReason"],"account_or_captcha_prompt")

    def test_splash_marker_waits_for_an_exact_reviewed_normal_snapshot(self):
        with fixture(self.base) as (state,clock):
            captures = []
            def snapshot(tools,index,**kwargs):
                self.assertEqual(kwargs["deadline"],280.0)
                captures.append(index)
                (R.evidence()/f"screen-{index:02d}.png").write_bytes(self.changed if index == 0 else self.base)
                return None if index == 0 else "new_terms_or_privacy_prompt"
            def continuation(tools,value,pid,**kwargs):
                self.assertEqual(kwargs["deadline"],280.0)
                result = value["observation"]["gameTermsContinuation"]
                self.assertEqual(result["triggerSnapshot"],{"index":1,"file":"screen-01.png",
                    "bytes":len(self.base),"sha256":R.sha(self.base),"packagePID":PID})
                result["stopReason"] = "test_preflight_stop"
                result["phase"] = "stopped_without_retry"
                return False
            def adb(tools,args,label,timeout,**kwargs):
                self.assertEqual(kwargs["deadline"],280.0)
                self.assertIn(args,(["shell","cat","/proc/net/dev"],["shell","pidof",R.PACKAGE]))
                return str(PID),0
            with patch.object(R,"snapshot",side_effect=snapshot), \
                    patch.object(R,"adb_command",side_effect=adb),patch.object(R,"guest_bytes",return_value=0), \
                    patch.object(R,"continue_known_game_terms",side_effect=continuation) as enter, \
                    patch.object(R,"observe_unconfirmed_terms",return_value={"reason":"new_terms_or_privacy_prompt"}), \
                    patch.object(R.time,"sleep",side_effect=lambda seconds:clock.__setitem__(0,clock[0]+seconds)):
                R.observe_client({},state)
            self.assertEqual(captures,[0,1])
            enter.assert_called_once()
            self.assertEqual(state["executed"]["apkLaunches"],1)
            self.assertEqual(state["observation"]["elapsedSeconds"],10.0)

    def test_marker_and_xml_on_unknown_frames_never_enter_the_input_path(self):
        with fixture(self.base) as (state,clock):
            captures = []
            def snapshot(tools,index,**kwargs):
                self.assertEqual(kwargs["deadline"],280.0)
                captures.append(index)
                (R.evidence()/f"screen-{index:02d}.png").write_bytes(self.changed)
                return "new_terms_or_privacy_prompt"
            def adb(tools,args,label,timeout,**kwargs):
                self.assertEqual(kwargs["deadline"],280.0)
                self.assertIn(args,(["shell","cat","/proc/net/dev"],["shell","pidof",R.PACKAGE]))
                return str(PID),0
            with patch.object(R,"snapshot",side_effect=snapshot), \
                    patch.object(R,"adb_command",side_effect=adb),patch.object(R,"guest_bytes",return_value=0), \
                    patch.object(R,"continue_known_game_terms") as enter, \
                    patch.object(R,"observe_unconfirmed_terms",return_value={"reason":"new_terms_or_privacy_prompt"}), \
                    patch.object(R.time,"sleep",side_effect=lambda seconds:clock.__setitem__(0,clock[0]+seconds)):
                R.observe_client({},state)
            enter.assert_not_called()
            self.assertEqual(captures,list(range(12)))
            self.assertEqual(state["observation"]["limitSeconds"],180)
            result = state["observation"]["gameTermsContinuation"]
            self.assertIsNone(result["triggerSnapshot"])
            self.assertEqual(result["inputReservations"],{"agree":0,"continue":0})
            self.assertEqual(result["actions"],[])
            self.assertEqual(state["observation"]["stopReason"],"bounded_observation_complete")

    def test_review_gate_and_fixed_dependency_are_before_the_only_runtime_step(self):
        text = (Path(__file__).parents[1]/"workflows/fighter-android-official-client.yml").read_text()
        self.assertIn("environment: fighter-private-assets",text)
        self.assertIn(R.MESSAGE,text)
        self.assertIn("--isolated install --no-index --no-deps --only-binary=:all: --require-hashes",text)
        self.assertIn("42d63be3af4f9b951b199b0a9d23365d37ab14687e6d77b74940432c8515c4ca",text)
        self.assertLess(text.index("python3.12 -m venv"),text.index("id: observe"))
        self.assertEqual(text.count("fighter_android_official_client.py run"),1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
