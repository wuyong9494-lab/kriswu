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

import completion_native_preflight as pre
from completion_active_pack import active_inventory, inspect, RETIRED
from stage_completion_bottle_oracle import NAME as ORACLE, DIGEST as ORACLE_SHA

KEY_NAMES=("FIGHTER_H17_D19_KEY","FIGHTER_LIU_MODEL_KEY","FIGHTER_PRESENTATION_KEY")
ADDED=("SiteTests/DuelOptionalResourceIsolationTests/testAbsentSerpentNeverAdvertisesRetiredHammerEvenIfAStaleCopyIsPresent",
       "SiteTests/DuelOptionalResourceIsolationInstalledTests/testActiveSerpentPairsDoNotNeedTheHistoricalHammerModel")
CONTRACT=("CODE_SIGNING_ALLOWED=NO","CODE_SIGNING_REQUIRED=NO","CODE_SIGN_IDENTITY=",
          "FIGHTER_ASSET_RELEASE_SHA256="+pre.RELEASE_SHA256,"FIGHTER_XUXIAO_PROFILE_SHA256=",
          "L12_INTERNAL_PREVIEW_CONDITION=")

def exact(ok,reason):
    if not ok: raise ValueError(reason)

def selectors(root):
    plan,_=pre.metadata(root)
    selected=(*plan["nativeSelectors"],*ADDED)
    exact(len(selected)==len(set(selected))==29,"Native selector inventory differs")
    return selected

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
            oracle=host/"PlugIns/SiteTests.xctest"/ORACLE
            pre.snapshot(oracle,maximum=16_000,size=9607,sha256=ORACLE_SHA)
            exact(list(host.rglob(ORACLE))==[oracle],"Oracle appeared outside its test bundle")
            print(json.dumps({"lane":"iphone-native","debugAppBuilt":True,"debugVerifiedAppFiles":539,"testOnlyOracleVerified":True}),flush=True)
            xctestruns=list(products.glob("ShiftReminder_*.xctestrun"))
            exact(len(xctestruns)==1,"Expected one generated native XCTest run file")
            selected=selectors(root)
            result=work/"native-active.xcresult"
            execution=run(["/usr/bin/xcodebuild","test-without-building","-xctestrun",str(xctestruns[0]),
                 "-destination","platform=iOS Simulator,id="+udid,"-parallel-testing-enabled","NO","-test-iterations","1",
                 "-resultBundlePath",str(result),*["-only-testing:"+s for s in selected]],"native-tests",1200,allow_failed=True)
            prefix=["/usr/bin/xcrun","xcresulttool","get","test-results"]
            summary=jout([*prefix,"summary","--path",str(result)],"native-result-summary")
            counts={k:summary.get(k) if type(summary.get(k)) is int else None for k in
                    ("totalTestCount","passedTests","failedTests","skippedTests")}
            print(json.dumps({"lane":"iphone-native","testExit":execution.returncode,**counts}),flush=True)
            exact(execution.returncode==0,"Native operation stopped: native-tests")
            data=jout([*prefix,"tests","--path",str(result)],"native-result-tests")
            passed=result_counts(summary,data,selected)
            return dict(debugAppBuilt=True,debugVerifiedAppFiles=539,nativePassed=passed,skipped=0,
                        simulator="iPhone 17 Pro Max / iOS 26.5",testOnlyOracleVerified=True,ipadSimulatorTested=False,
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
