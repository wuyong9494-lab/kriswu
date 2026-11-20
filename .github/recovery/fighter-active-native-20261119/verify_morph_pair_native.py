"""Unsigned iOS native validation for the 539 resource assembly only."""
import argparse
from collections import Counter
import json
import os
from pathlib import Path
import pwd
import re
import subprocess
import sys
from urllib.parse import unquote, urlsplit

import completion_native_preflight as pre
from completion_active_pack import active_inventory, inspect, RETIRED

KEY_NAMES=("FIGHTER_H17_D19_KEY","FIGHTER_LIU_MODEL_KEY","FIGHTER_PRESENTATION_KEY")
ADDED=("SiteTests/DuelOptionalResourceIsolationTests/testAbsentSerpentNeverAdvertisesRetiredHammerEvenIfAStaleCopyIsPresent",
       "SiteTests/DuelOptionalResourceIsolationInstalledTests/testActiveSerpentPairsDoNotNeedTheHistoricalHammerModel")
# Exact failures from run 44521506664; passing tests are not repeated.
TRACE_TARGETS = (
    'SiteTests/DuelOptionalResourceIsolationInstalledTests/testActiveSerpentPairsDoNotNeedTheHistoricalHammerModel',
    'SiteTests/DuelOptionalResourceIsolationInstalledTests/testBadOptionalProfilesPreserveUnrelatedPairsAndNeverRestoreLegacyLiu',
    'SiteTests/DuelOptionalResourceIsolationInstalledTests/testBadVictoryMorphBlocksOnlyItsActualPairAndCannotUseOldHammerTarget',
    'SiteTests/DuelOptionalResourceIsolationInstalledTests/testChangedOptionalModelIsRejectedBeforeAdvertisingItsHero',
    'SiteTests/DuelOptionalResourceIsolationInstalledTests/testFailedOptionalCombatMediaDoesNotLeavePartialMediaOrBlockOtherPairs',
    'SiteTests/DuelOptionalResourceIsolationInstalledTests/testRestartAfterARealModelFailureCannotReplaceTheFightWithLegacySimulation',
    'SiteTests/DuelRecoveredCharacterInstalledTests/testInstalledD15HoundAndSchemaFiveAudioBindTheActualContourActor',
    'SiteTests/DuelRecoveredCharacterInstalledTests/testInstalledD15VictoryMorphUsesNewSunOwnerAndActualContourGeometry',
    'SiteTests/DuelRecoveredCharacterInstalledTests/testInstalledRecoveredRosterUsesEachPersonsExactHeadAndSourceEquipment',
    'SiteTests/DuelRecoveredCharacterInstalledTests/testInstalledRecoveredSourceClipsHaveFiniteFirstMiddleAndLastNativePoses',
    'SiteTests/DuelSerpentMorphSourceTests/testActualD13GeometryInstallsCompleteMorphAndRestoresAfterHideAndCancellation',
    'SiteTests/DuelSerpentProfileSourceTests/testInstalledSelectedPairsPrepareOnlyTheirActualModelsAndContentIdentities',
)
NEW_REGRESSIONS = ('SiteTests/DuelTriadSourceMaterialTests/testD15ProgramsRequireTheAuthenticatedNamespaceAndMatchingEntryPoints', 'SiteTests/DuelSerpentMorphSourceTests/testExactHeadlessMorphRejectsMissingActiveAndNewlyAttachedDormantGeometry')
CONTRACT=("CODE_SIGNING_ALLOWED=NO","CODE_SIGNING_REQUIRED=NO","CODE_SIGN_IDENTITY=",
          "FIGHTER_ASSET_RELEASE_SHA256="+pre.RELEASE_SHA256,"FIGHTER_XUXIAO_PROFILE_SHA256=",
          "L12_INTERNAL_PREVIEW_CONDITION=")

def exact(ok,reason):
    if not ok: raise ValueError(reason)

SELECTED = ("SiteTests/DuelRecoveredCharacterInstalledTests/testInstalledWuYongPracticeAssemblesMorphAndProjectedShadowInBothOrders",)
MORPH_STAGES = set("assetOpen matchCatalog actorModel renderSurface firstFrame sourceMorph sourceEffects effectDraw frameDraw erlangSword erlangStomp erlangSkill triadEffectStep stage unspecified morphPairOrStage morphMask morphBind morphCaster morphShadowSetup morphAdvance".split())

def morph_failures(*sources):
    marks = re.compile(r"\bRIFT_MORPH_PAIR order=(wu-first|sun-first) stage=([A-Za-z]{1,32})\b")
    return [{"order": order, "stage": stage} for order, stage in
            sorted({(order, stage) for source in sources for order, stage in marks.findall(source)
                    if stage in MORPH_STAGES})]

def selectors(root):
    return SELECTED

def result_counts(summary,data,selected):
    exact(summary.get("result")=="Passed" and all(type(summary.get(k)) is int and summary[k]==v
          for k,v in dict(totalTestCount=len(selected),passedTests=len(selected),failedTests=0,skippedTests=0).items()),
          "Native count does not prove a full pass")
    seen=[]
    def walk(nodes):
        exact(isinstance(nodes,list),"Malformed result nodes")
        for row in nodes:
            if row.get("nodeType")=="Test Case":
                n=row["nodeIdentifier"].removesuffix("()")
                match=[k for k in selected if n in (k,k.split("/",1)[1])]
                exact(len(match)==1 and row["result"]=="Passed","Unexpected or nonpassing test")
                seen.extend(match)
            else:walk(row.get("children",[]))
    walk(data["testNodes"])
    exact(Counter(seen)==Counter(selected),"Missing or duplicate selected result")
    return len(seen)

def native_child_environment(environ, runner_name):
    exact(bool(re.fullmatch(r"[A-Za-z0-9_.-]+",runner_name)), "Invalid runner account name")
    env={k:environ[k] for k in ("PATH","HOME","LC_ALL","LANG","DEVELOPER_DIR","TMPDIR") if k in environ}
    env["USER"]=runner_name
    return env

def test_receipt(process, phase):
    # Only fixed tokens; never share subprocess output, paths or argument values.
    raw=process.stderr.lower()
    reason="unclassified"
    if any(word in raw for word in (b"invalid option",b"unknown option",b"unrecognized option",b"invalid argument",b"usage: xcodebuild")):
        reason="command-arguments"
    if b"unable to find a device matching" in raw or b"ineligible destination" in raw:
        reason="destination"
    if b"xctestrun" in raw and any(word in raw for word in (b"does not exist",b"could not load",b"cannot be read")):
        reason="test-plan"
    if b"failed to install" in raw or b"failed to launch" in raw:
        reason="test-host-install-or-launch"
    print(json.dumps({"lane":"iphone-native","phase":phase,"exit":process.returncode,"reason":reason}),flush=True)

def discovered_count(output,selected):
    found=Counter(line.strip().removesuffix("()") for line in output.decode("utf-8",errors="replace").splitlines())
    return sum(found[s]==1 for s in selected)


# Only source files already in the public repo, associated with a selected test.
FAILURE_SOURCES = {'DuelOptionalResourceIsolationInstalledTests': 'DuelOptionalResourceIsolationTests.swift', 'DuelRecoveredCharacterInstalledTests': 'DuelRecoveredCharacterInstalledTests.swift', 'DuelSerpentMorphSourceTests': 'DuelSerpentMorphSourceTests.swift', 'DuelSerpentProfileSourceTests': 'DuelSerpentProfileSourceTests.swift'}
FAILURE_STAGES = {
    "profile": ("resource unavailable (profile,", "missingserpentprofile"),
    "model": ("resource unavailable (model,",),
    "combat-media": ("resource unavailable (combatmedia,", "duelerlanglocalmediaload.failure"),
    "pair-morph": ("duelweaponassets.pairunavailability", "pair resource unavailable ("),
    "release-metadata": ("dedicated recovered-resource build must install its reviewed release pin",
                         "duelfighterassetreleaseloader.failure.missingrelease",
                         "duelfighterassetreleaseloader.failure.missingpin",
                         "duelfighterassetreleaseloader.failure.invalidpin"),
    "missing-file": ("nscocoaerrordomain code=260", "no such file or directory"),
    "metal-device": ("d13 morph acceptance requires actual metal",),
    "actor-catalog": ("authenticated recovered resources must be installed",),
    "morph-binding": ("dueltriadsourcemorphassets.failure", "dueltriadsourcevictimmorph"),
}
# Never echo the filenames from XCTest: translate known media roles into
# fixed codes. These keys correspond to loader components in the public code.
FAILURE_COMPONENTS = {
    "wu-companion": ("sf3_d15_companions.json", ".companions:"),
    "wu-hound-fx": ("sf3_d15_effects.json.gz", ".houndeffects:"),
    "wu-stomp-fx": ("sf3_d15_stompeffects.json.gz", ".stompeffects:"),
    "wu-sword-fx": ("sf3_d15_swordeffects.json.gz", ".swordeffects:"),
    "wu-skill-fx": ("sf3_d15_skilleffects.json.gz", ".skilleffects:"),
    "wu-audio": ("sf3_erlang_audio.json",),
    "liu-audio": ("sf3_serpent_audio.json",),
    "liu-d13-bottle": ("sf3_d13_bottle_",),
    "sun-wu-morph": ("sf3_h17_wumorph.json",),
    "sun-liu-morph": ("sf3_h17_serpentmorph.json",),
}
FAILURE_OPERATIONS = {"assert-equal": "xctassertequal", "assert-true": "xctasserttrue",
                      "assert-false": "xctassertfalse", "assert-nil": "xctassertnil",
                      "assert-not-nil": "xctassertnotnil", "unwrap": "xctunwrap",
                      "unexpected-throw": "threw error"}

def safe_test_line(row, selector):
    expected = FAILURE_SOURCES.get(selector.split("/")[1])
    if not expected:
        return None
    # Consume only structured source URL metadata, never text captured by XCTest.
    # Strip all directories, and accept only a numeric line from < 2,000 lines.
    for field in ("sourceURL", "sourceUrl", "documentLocationInCreatingWorkspace"):
        value = row.get(field)
        if isinstance(value, dict):
            value = value.get("url")
        if not isinstance(value, str) or len(value) > 4096:
            continue
        try:
            parsed = urlsplit(value)
        except ValueError:
            continue
        if parsed.scheme != "file" or unquote(parsed.path.rsplit("/", 1)[-1]) != expected:
            continue
        match = re.fullmatch(r"StartingLineNumber=([0-9]{1,4})(?:&[a-zA-Z0-9=&]+)?", parsed.fragment)
        if match and 1 <= (line := int(match.group(1))) <= 2000:
            return line
    return None

def failed_test_receipt(summary,data,selected):
    # Only known public source selectors and fixed categories go to CI output.
    # Never emit the xcresult, failure message, attachment, or paths.
    fixed = {
        "assertion": ("xctassert", "xctunwrap", "assertion"),
        "timeout": ("time limit", "timed out", "timeout"),
        "crash": ("crashed", "crash", "signal ", "exited unexpectedly"),
        "launch": ("failed to launch", "failed to install", "runner exited"),
        "resource": ("resource", "fixture", "asset"),
    }
    names={a:key for key in selected for a in (key,key.split("/",1)[1])}
    exact(len(names)==2*len(selected),"Native operation stopped: ambiguous selectors")
    def match(n):
        return names.get(n.removesuffix("()")) if isinstance(n,str) else None
    failed=set()
    pending=list(data.get("testNodes",[]))
    while pending:
        row=pending.pop()
        pending.extend(row.get("children",[]))
        if row.get("nodeType")=="Test Case" and row.get("result") in ("Failed","Failure"):
            key=match(row.get("nodeIdentifier"))
            if key: failed.add(key)
    kinds, evidence = {}, {}
    for row in summary.get("testFailures",[]) or []:
        if not isinstance(row,dict): continue
        key=next((k for field in ("testIdentifierString","testIdentifier","nodeIdentifier")
                  if (k:=match(row.get(field)))),None)
        if not key: continue
        msg=row.get("failureText",row.get("message",""))
        keys={tag for tag,patterns in fixed.items()
                 if isinstance(msg,str) and any(p in msg.casefold() for p in patterns)}
        if keys: kinds.setdefault(key,set()).update(keys)
        normalized = msg.casefold() if isinstance(msg, str) else ""
        stages = tuple(tag for tag, patterns in FAILURE_STAGES.items() if any(p in normalized for p in patterns))
        operations = tuple(tag for tag, pattern in FAILURE_OPERATIONS.items() if pattern in normalized)
        components = tuple(tag for tag, patterns in FAILURE_COMPONENTS.items() if any(p in normalized for p in patterns))
        line = safe_test_line(row, key)
        if stages or operations or components or line is not None:
            evidence.setdefault(key, set()).add((stages, operations, components, line or 0))
        failed.add(key)
    rows=[]
    for key in sorted(failed):
        row={"selector":key,"categories":sorted(kinds.get(key,{"unclassified"}))}
        if key in evidence:
            row["details"] = [{"stages": list(stages), "operations": list(operations),
                               **({"sourceLine": line} if line else {}),
                               **({"components": list(components)} if components else {})}
                              for stages, operations, components, line in sorted(evidence[key])[:16]]
        rows.append(row)
    return {"identifiedFailures":len(rows),"failures":rows}

class NativeTimeout(Exception):
    pass

def runner(root,work,xcodegen):
    exact(sys.platform=="darwin" and all(k not in os.environ for k in KEY_NAMES),"Use an unsigned macOS runner without resource keys")
    root,work=root.resolve(strict=True),work.resolve(strict=True)
    exact(not (work.is_relative_to(root) or root.is_relative_to(work)),"DerivedData must not overlap source")
    env=native_child_environment(os.environ,pwd.getpwuid(os.getuid()).pw_name)
    def run(args,name,timeout=3900,allow_failed=False):
        try:
            p=subprocess.run(args,cwd=root,env=env,timeout=timeout,capture_output=True)
        except subprocess.TimeoutExpired:
            raise NativeTimeout(name) from None
        (work/(name+".log")).write_bytes(p.stdout+p.stderr)
        if not allow_failed:exact(p.returncode==0,"Native operation stopped: "+name)
        return p
    def jout(args,name):
        return json.loads(run(args,name,120).stdout)
    app_stage=root/"App/Resources/FighterPrivate"
    inspect(root,staged=app_stage)
    os.umask(0o077)
    version=run(["/usr/bin/xcodebuild","-version"],"version",60).stdout.decode()
    exact(version.startswith("Xcode 26.6\n"),"Expected the reviewed Xcode 26.6")
    run([str(xcodegen),"generate","--spec",str(root/"project.yml"),"--project",str(root)],"xcodegen",90)
    print(json.dumps({"projectGenerated":True,"acceptanceLanes":["iphone-native"]}),flush=True)
    proj=root/"ShiftReminder.xcodeproj"
    base=["/usr/bin/xcodebuild","-project",str(proj),"-scheme","ShiftReminder","-sdk","iphonesimulator"]
    arch=run(["/usr/bin/uname","-m"],"simulator-runner-arch",30).stdout.strip()
    exact(arch==b"arm64","Native operation stopped: simulator requires arm64 runner")
    def test_debug():
        sim=jout(["/usr/bin/xcrun","simctl","list","-j"],"sim-available")
        runtimes=[r["identifier"] for r in sim["runtimes"] if r.get("isAvailable") and r["version"]=="26.5" and ".iOS-" in r["identifier"]]
        types=[t["identifier"] for t in sim["devicetypes"] if t["name"]=="iPhone 17 Pro Max"]
        exact(len(runtimes)==len(types)==1,"Expected the reviewed iPhone 17 Pro Max / iOS 26.5 runtime")
        udid=run(["/usr/bin/xcrun","simctl","create","Rift active resource native",types[0],runtimes[0]],"sim-create",60).stdout.decode().strip()
        exact(bool(re.fullmatch(r"[0-9a-fA-F-]{36}",udid)),"Invalid created simulator identifier")
        try:
            run(["/usr/bin/xcrun","simctl","boot",udid],"sim-boot-request",90)
            print(json.dumps({"lane":"iphone-native","simulatorBootRequested":True}),flush=True)
            run(["/usr/bin/xcrun","simctl","bootstatus",udid],"sim-bootstatus",720)
            print(json.dumps({"lane":"iphone-native","simulatorBooted":True}),flush=True)
            test_dd=work/"debug-test-derived"
            run([*base,"build-for-testing","-configuration","Debug","-destination","generic/platform=iOS Simulator",
                 "-derivedDataPath",str(test_dd),*CONTRACT,"ARCHS=arm64"],"debug-build-for-testing",2400)
            products=test_dd/"Build/Products"
            host=products/"Debug-iphonesimulator/ShiftReminder.app"
            active, content_sha=active_inventory(root)
            pre.app_resources(host, active, forbidden_names=[RETIRED["name"]],compiled_sha256=content_sha)
            print(json.dumps({"lane":"iphone-native","debugAppBuilt":True,"debugVerifiedAppFiles":539}),flush=True)
            xctestruns=list(products.glob("ShiftReminder_*.xctestrun"))
            exact(len(xctestruns)==1,"Expected one generated native XCTest run file")
            selected=selectors(root)
            args=["/usr/bin/xcodebuild","test-without-building","-xctestrun",str(xctestruns[0]),
                  "-destination","id="+udid,"-parallel-testing-enabled","NO"]
            only=["-only-testing:"+s for s in selected]
            discovery=work/"selected-tests.txt"
            enumeration=run([*args,"-enumerate-tests","-test-enumeration-style","flat",
                             "-test-enumeration-format","text","-test-enumeration-output-path",str(discovery),*only],
                            "native-enumeration",300,allow_failed=True)
            if enumeration.returncode:
                test_receipt(enumeration,"native-enumeration")
            exact(enumeration.returncode==0,"Native operation stopped: native-enumeration")
            exact(discovery.is_file() and discovery.stat().st_size<=1_000_000,
                  "Native operation stopped: test enumeration output")
            matched=discovered_count(discovery.read_bytes(),selected)
            print(json.dumps({"lane":"iphone-native","enumeratedSelectedTests":matched,"required":len(selected)}),flush=True)
            exact(matched==len(selected),"Native operation stopped: missing or duplicate selected test")
            result=work/"native-active.xcresult"
            execution=run([*args,"-resultBundlePath",str(result),*only],"native-tests",1200,allow_failed=True)
            if execution.returncode:
                test_receipt(execution,"native-tests")
            exact(result.is_dir(),"Native operation stopped: missing test result bundle")
            prefix=["/usr/bin/xcrun","xcresulttool","get","test-results"]
            summary=jout([*prefix,"summary","--path",str(result)],"native-result-summary")
            counts={k:summary.get(k) if type(summary.get(k)) is int else None for k in
                    ("totalTestCount","passedTests","failedTests","skippedTests")}
            print(json.dumps({"lane":"iphone-native","testExit":execution.returncode,**counts}),flush=True)
            data=jout([*prefix,"tests","--path",str(result)],"native-result-tests")
            if execution.returncode!=0:
                print(json.dumps({"lane":"iphone-native","morphFailureStages":morph_failures(
                    json.dumps(summary),json.dumps(data), (execution.stdout+execution.stderr).decode("utf-8", errors="replace"))}),flush=True)
                receipt=failed_test_receipt(summary,data,selected)
                print(json.dumps({"lane":"iphone-native","kind":"failure-diagnostics",**receipt}),flush=True)
            exact(execution.returncode==0,"Native operation stopped: native-tests")
            passed=result_counts(summary,data,selected)
            return dict(debugAppBuilt=True,debugVerifiedAppFiles=539,nativePassed=passed,skipped=0,
                        simulator="iPhone 17 Pro Max / iOS 26.5",ipadSimulatorTested=False,
                        physicalDeviceTested=False,uiTested=False,testflightUploaded=False)
        finally:
            try:
                run(["/usr/bin/xcrun","simctl","delete",udid],"sim-delete",100,allow_failed=True)
            except (NativeTimeout, OSError):
                print(json.dumps({"lane":"iphone-native","simulatorCleanupWarning":True}),flush=True)

    return test_debug()

if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    for name in ("repo","work","xcodegen"):p.add_argument(name,type=Path)
    a=p.parse_args()
    try: print(json.dumps(runner(a.repo,a.work,a.xcodegen)))
    except Exception as exc:
        reason = ("Timeout at "+str(exc)) if isinstance(exc,NativeTimeout) else type(exc).__name__
        if isinstance(exc,pre.CheckError):
            reason=exc.code
        if type(exc) is ValueError and str(exc).startswith("Native operation stopped: "):
            reason=str(exc)
        print(json.dumps({"lane":"iphone-native","success":False,"reason":reason}),flush=True)
        raise SystemExit(1) from None
