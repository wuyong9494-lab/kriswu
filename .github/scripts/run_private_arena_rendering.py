#!/usr/bin/env python3
"""Require actual private-resource Metal rendering before signing or upload.

Raw logs, original pixels, the test product and xcresult stay on the runner.
Only an allowlisted aggregate report can be uploaded by the promotion workflow.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


def summary_counts(summary):
    expected = {'totalTestCount':2,'passedTests':2,'failedTests':0,'skippedTests':0}
    counts = {key:summary.get(key) for key in expected}
    passed = all(type(counts[key]) is int and counts[key] == value for key,value in expected.items())
    return counts, passed and summary.get('result') == 'Passed'


def run(source, report):
    assert (source/'Tests/PrivateResourceValidation/ArenaPrivateValidation/manifest.json').is_file()
    subprocess.run(['xcodegen','generate','--spec','project-private-resources.yml'],cwd=source,check=True)
    for attempt in range(2):
        try:
            devices = json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','-j'],timeout=180))['devices']
            break
        except (subprocess.TimeoutExpired,subprocess.CalledProcessError):
            if attempt == 1: raise
    candidates = [(runtime,d) for runtime,values in devices.items() for d in values
                  if '.iOS-' in runtime and d.get('isAvailable') and d['name'].startswith('iPhone')]
    assert candidates, 'No available iPhone simulator for private rendering'
    _,device = max(candidates,key=lambda pair:(pair[1]['name']=='iPhone 17 Pro Max',
                       tuple(map(int,re.findall(r'\d+',pair[0]))),pair[1]['name']))
    aggregate = {'device':device['name'],'passed':False}
    try:
        if device['state'] != 'Booted':
            subprocess.run(['xcrun','simctl','boot',device['udid']],check=True,timeout=120)
        subprocess.run(['xcrun','simctl','bootstatus',device['udid'],'-b'],check=True,timeout=240)
        with tempfile.TemporaryDirectory(prefix='private-metal-',dir=os.environ.get('RUNNER_TEMP')) as folder:
            private = Path(folder)
            result = private/'rendering.xcresult'
            command = ['xcodebuild','test','-project','ShiftReminder.xcodeproj','-scheme','ArenaResourceValidation',
                       '-configuration','Debug','-destination','platform=iOS Simulator,id='+device['udid'],
                       '-derivedDataPath',str(private/'products'),'-resultBundlePath',str(result),
                       '-parallel-testing-enabled','NO',
                       '-only-testing:ArenaResourceTests/ArenaPrivateResourceRenderingTests','CODE_SIGNING_ALLOWED=NO']
            with (private/'rendering.log').open('w') as log:
                completed = subprocess.run(command,cwd=source,stdout=log,stderr=subprocess.STDOUT,timeout=1200)
            if result.exists():
                summary = json.loads(subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary',
                                                             '--path',str(result)],timeout=120))
                counts,passed = summary_counts(summary)
                aggregate.update(counts)
                aggregate['passed'] = passed and completed.returncode == 0
                if aggregate['passed']:
                    aggregate.update({'backgrounds':8,'controls':10})
            assert aggregate['passed'], 'Private Metal validation did not pass both required tests without skips'
    finally:
        report.write_text(json.dumps(aggregate,sort_keys=True,indent=2)+'\n')
        print(json.dumps(aggregate,sort_keys=True),flush=True)
        subprocess.run(['xcrun','simctl','shutdown',device['udid']],check=False,timeout=60)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--report',type=Path,required=True)
    args = parser.parse_args()
    run(args.source.resolve(),args.report.resolve())
