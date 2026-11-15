#!/usr/bin/env python3
"""Only new crash-buffer identity/budget checks; no native process or client.

Tombstone rows are synthetic Android 11 debuggerd format. They do not supply
or infer a cause for the actual anonymous Unity SIGILL in run 43704660391.
"""
from contextlib import contextmanager
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("android_system_crash_delta",
    Path(__file__).with_name("fighter_android_official_client.py"))
R = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(R)
PID = 5299
LAUNCHED = "2026-11-15T10:45:48.786922+00:00"
CAPTURED = "2026-11-15T10:46:50.000000+00:00"


def crash(*,pid=PID,package=R.PACKAGE,emitter=6001,stamp="2026-11-15 10:46:43+0000",
          tag="DEBUG",priority="F"):
    messages = [" ".join(["***"]*16),"Build fingerprint: 'synthetic'","Revision: '0'","ABI: 'arm'",
        "Timestamp: "+stamp,f"pid: {pid}, tid: 5383, name: UnityMain  >>> {package} <<<","uid: 10148",
        "signal 4 (SIGILL), code -6 (SI_TKILL), fault addr --------","",
        "backtrace:","    #00 pc 00028f44  <anonymous:37580000>"]
    return "\n".join(f"11-15 10:46:43.100 {emitter:5d} {emitter:5d} {priority} {tag:8s}: {message}"
                     for message in messages)+"\n"


def command_evidence(label,raw,code=0,*,timed=False,deadline=280.0,started=100.0,finished=101.0):
    if isinstance(raw,str):
        raw = raw.encode()
    (R.evidence()/(label+".log")).write_bytes(raw)
    receipt = {"exitCode":code,"elapsedSeconds":finished-started,"bytes":len(raw),"sha256":R.sha(raw),
        "scopeDeadlineProvided":True,"deadlineBasis":"command","deadlineReached":False,"scopeDeadlineExpired":False}
    if timed:
        receipt.update({"processStarted":True,"processStartedMonotonic":started,
            "processFinishedMonotonic":finished,"effectiveDeadlineMonotonic":min(started+10,deadline),
            "scopeDeadlineMonotonic":deadline})
    R.write_json(R.evidence()/(label+"-process.json"),receipt)
    return raw.decode(),code


@contextmanager
def fixture():
    with tempfile.TemporaryDirectory() as directory:
        owned = Path(directory)/"owned"
        (owned/"evidence").mkdir(parents=True)
        clock = [100.0]
        state = {"appPID":PID,"launchStartedAt":LAUNCHED,"emulator":{"monotonicStart":100.0},
            "executed":{"apkLaunches":1},"gates":{"normalLaunchObserved":True,"readableBootstrapCatalogObtained":False},
            "observation":{"stopReason":"app_process_unavailable","systemCrashDiagnostics":None,
                "gameTermsContinuation":R.new_game_terms_continuation()}}
        with patch.object(R,"work",return_value=owned),patch.object(R,"now",return_value=CAPTURED), \
                patch.object(R.time,"monotonic",side_effect=lambda:clock[0]),patch.object(R,"ACTIVE_EMULATOR_DEADLINE",None):
            command_evidence("app-pid-3",str(PID)+"\n")
            command_evidence("app-pid-4","",1)
            yield state,clock


class SystemCrashDiagnosticsDelta(unittest.TestCase):
    def test_only_the_current_package_crash_matches_unrelated_system_rows(self):
        log = crash(pid=7777,package="other.app",emitter=6100)+crash()
        matches = R.matching_system_crashes(log,PID,LAUNCHED,CAPTURED)
        self.assertEqual(len(matches),1)
        actual = matches[0]
        self.assertEqual((actual["pid"],actual["systemEmitterPID"],actual["signalName"]),(PID,6001,"SIGILL"))
        self.assertEqual(actual["backtraceFrameCount"],1)
        self.assertFalse(actual["completeBacktraceProven"])
        self.assertFalse(actual["rootCauseProven"])

    def test_wrong_identity_old_time_missing_header_and_app_rows_are_not_system_claims(self):
        for raw in (crash(pid=5300),crash(package=R.PACKAGE+":worker"),crash(emitter=PID),
                    crash(stamp="2026-11-15 10:45:47+0000"),crash(stamp="2026-11-15 10:46:51+0000"),
                    crash(stamp="2026-02-30 10:46:43+0000"),crash(tag="CRASH"),crash(priority="W"),
                    "\n".join(crash().splitlines()[1:]),crash().replace("11-15 10:46:43.100","99-99 25:00:00.000")):
            with self.subTest(raw=raw[:60]):
                self.assertEqual(R.matching_system_crashes(raw,PID,LAUNCHED,CAPTURED),[])
        self.assertEqual(R.matching_system_crashes(crash(),PID,LAUNCHED,None),[])
        self.assertEqual(R.matching_system_crashes(crash()+"\x00",PID,LAUNCHED,CAPTURED),[])

    def test_exact_read_only_request_hash_join_and_once_guard(self):
        with fixture() as (state,_):
            def adb(tools,args,label,timeout,**kwargs):
                self.assertEqual(args,["logcat","-b","crash","-d","-v","threadtime","-t","512"])
                self.assertEqual(label,R.SYSTEM_CRASH_LABEL)
                self.assertEqual(timeout,10)
                self.assertEqual(kwargs,{"ok":(0,1),"maximum":2*R.MIB,"deadline":280.0})
                return command_evidence(label,crash(),timed=True)
            with patch.object(R,"adb_command",side_effect=adb) as command:
                R.collect_system_crash_diagnostics({},state,4,3,deadline=280.0)
                record = state["observation"]["systemCrashDiagnostics"]
                R.collect_system_crash_diagnostics({},state,4,3,deadline=280.0)
            self.assertEqual(command.call_count,1)
            self.assertEqual(record["phase"],"captured_matching_crash")
            self.assertTrue(record["commandCompleted"])
            self.assertEqual(record["matchingCrashBlocks"],1)
            self.assertEqual(record["log"]["sha256"],R.sha(crash().encode()))
            self.assertEqual([r["uniquePackagePID"] for r in record["pidEvidence"]],[PID,None])
            self.assertFalse(record["clientInitialized"])
            self.assertEqual(state["observation"]["stopReason"],"app_process_unavailable")
            self.assertEqual(state["executed"],{"apkLaunches":1})
            self.assertEqual(state["observation"]["gameTermsContinuation"]["inputReservations"],{"agree":0,"continue":0})

    def test_two_matching_blocks_are_retained_without_a_unique_crash_claim(self):
        with fixture() as (state,_):
            raw = crash()+crash(emitter=6002)
            with patch.object(R,"adb_command",side_effect=lambda *a,**kw:command_evidence(R.SYSTEM_CRASH_LABEL,raw,timed=True)):
                R.collect_system_crash_diagnostics({},state,4,3,deadline=280.0)
            result = state["observation"]["systemCrashDiagnostics"]
            self.assertTrue(result["commandCompleted"])
            self.assertEqual(result["matchingCrashBlocks"],2)
            self.assertIsNone(result["matchedCrash"])
            self.assertEqual(result["phase"],"captured_without_unique_match")
            self.assertEqual((R.evidence()/(R.SYSTEM_CRASH_LABEL+".log")).read_text(),raw)

    def test_missing_receipt_timeout_wrong_hash_and_late_finish_never_promote_raw(self):
        for mode in ("missing_receipt","timeout","wrong_hash","late_finish","nonzero_exit"):
            with self.subTest(mode=mode),fixture() as (state,_):
                def adb(*args,**kwargs):
                    label = R.SYSTEM_CRASH_LABEL
                    value = command_evidence(label,crash(),1 if mode == "nonzero_exit" else 0,timed=True)
                    receipt_path = R.evidence()/(label+"-process.json")
                    receipt = json.loads(receipt_path.read_text())
                    if mode == "missing_receipt":
                        receipt_path.unlink()
                    else:
                        if mode == "wrong_hash": receipt["sha256"] = "0"*64
                        if mode == "late_finish": receipt["processFinishedMonotonic"] = 281.0
                        if mode == "timeout": receipt.update({"exitCode":-9,"deadlineReached":True,"scopeDeadlineExpired":True})
                        R.write_json(receipt_path,receipt)
                    if mode == "timeout": raise R.ScopedDeadlineExpired("scoped_operation_deadline")
                    return value
                with patch.object(R,"adb_command",side_effect=adb):
                    R.collect_system_crash_diagnostics({},state,4,3,deadline=280.0)
                result = state["observation"]["systemCrashDiagnostics"]
                self.assertFalse(result["commandCompleted"])
                self.assertIsNone(result["matchedCrash"])
                self.assertEqual(result["phase"],"read_incomplete_or_unknown")
                self.assertEqual(result["readRequests"],1)
                self.assertEqual(result["log"]["sha256"],R.sha(crash().encode()))
                self.assertEqual(state["observation"]["stopReason"],"app_process_unavailable")

    def test_no_prior_pid_or_expired_observation_never_calls_adb(self):
        for mode in ("no_prior_pid","wrong_prior_pid","expired","emulator_expired"):
            with self.subTest(mode=mode),fixture() as (state,clock):
                prior = None if mode == "no_prior_pid" else 3
                if mode == "wrong_prior_pid": command_evidence("app-pid-3","7777\n")
                if mode == "expired": clock[0] = 280.0
                with patch.object(R,"adb_command") as adb, \
                        patch.object(R,"ACTIVE_EMULATOR_DEADLINE",99.0 if mode == "emulator_expired" else None):
                    R.collect_system_crash_diagnostics({},state,4,prior,deadline=280.0)
                adb.assert_not_called()
                result = state["observation"]["systemCrashDiagnostics"]
                self.assertEqual(result["readRequests"],0)
                self.assertEqual(result["phase"],"skipped")
                self.assertEqual(state["observation"]["stopReason"],"app_process_unavailable")

    def test_process_receipt_uses_absolute_deadline_and_slow_open_cannot_dispatch(self):
        for slow in (False,True):
            with self.subTest(slow=slow),fixture() as (state,clock):
                clock[0] = 279.0 if slow else 100.0
                original_open = Path.open
                def open_file(path,*args,**kwargs):
                    opened = original_open(path,*args,**kwargs)
                    if slow and path.name == R.SYSTEM_CRASH_LABEL+".log" and args and args[0] == "xb": clock[0] = 281.0
                    return opened
                class CompleteProcess:
                    returncode = 0
                    def poll(self): return self.returncode
                def popen(args,**kwargs):
                    kwargs["stdout"].write(crash().encode())
                    kwargs["stdout"].flush()
                    clock[0] += 1
                    return CompleteProcess()
                def adb(tools,args,label,timeout,**kwargs):
                    return R.command(["mock-adb",*args],label,timeout,**kwargs)
                with patch.object(Path,"open",side_effect=open_file,autospec=True), \
                        patch.object(R.subprocess,"Popen",side_effect=popen) as process, \
                        patch.object(R,"adb_command",side_effect=adb):
                    R.collect_system_crash_diagnostics({},state,4,3,deadline=280.0)
                result = state["observation"]["systemCrashDiagnostics"]
                self.assertEqual(process.call_count,0 if slow else 1)
                self.assertEqual(result["commandCompleted"],not slow)
                if not slow:
                    receipt = json.loads((R.evidence()/(R.SYSTEM_CRASH_LABEL+"-process.json")).read_text())
                    self.assertTrue(receipt["processStarted"])
                    self.assertEqual(receipt["scopeDeadlineMonotonic"],280.0)
                    self.assertEqual(receipt["effectiveDeadlineMonotonic"],110.0)
                else:
                    self.assertFalse(result["processReceiptAvailable"])
                    self.assertEqual(result["phase"],"read_incomplete_or_unknown")

    def test_observer_collects_only_after_unique_pid_disappears_without_expanding_180_seconds(self):
        with fixture() as (state,clock):
            labels = []
            def adb(tools,args,label,timeout,**kwargs):
                labels.append(label)
                self.assertEqual(kwargs["deadline"],280.0)
                if label.startswith("guest-network-"):
                    return command_evidence(label,"lo: 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0\n")
                if label == "app-pid-0": return command_evidence(label,str(PID)+"\n")
                if label == "app-pid-1": return command_evidence(label,"",1)
                self.assertEqual(label,R.SYSTEM_CRASH_LABEL)
                return command_evidence(label,crash(),timed=True,started=clock[0],finished=clock[0]+1)
            def snapshot(tools,index,*,deadline):
                self.assertEqual(deadline,280.0)
                (R.evidence()/f"screen-{index:02d}.png").write_bytes(b"synthetic-unreviewed-image")
                return None
            def sleep(seconds): clock[0] += seconds
            with patch.object(R,"adb_command",side_effect=adb),patch.object(R,"snapshot",side_effect=snapshot) as snap, \
                    patch.object(R,"observe_unconfirmed_terms",return_value=None),patch.object(R.time,"sleep",side_effect=sleep):
                R.observe_client({},state)
            self.assertEqual(labels,["guest-network-0","app-pid-0","guest-network-1","app-pid-1",R.SYSTEM_CRASH_LABEL])
            self.assertEqual(snap.call_count,2)
            observation = state["observation"]
            self.assertEqual(observation["limitSeconds"],180)
            self.assertEqual(observation["stopReason"],"app_process_unavailable")
            self.assertEqual(observation["systemCrashDiagnostics"]["previousUniquePIDSampleIndex"],0)
            self.assertTrue(observation["systemCrashDiagnostics"]["commandCompleted"])
            self.assertEqual(observation["gameTermsContinuation"]["inputReservations"],{"agree":0,"continue":0})
            self.assertEqual(state["executed"],{"apkLaunches":1})
            self.assertEqual(json.loads((R.evidence()/"result.json").read_text())["observation"],observation)


if __name__ == "__main__":
    unittest.main(verbosity=2)
