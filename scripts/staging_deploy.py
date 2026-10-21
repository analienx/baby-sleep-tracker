#!/usr/bin/env python3
"""Little Rest Spark staging: safe GitHub build, APK verification and installation.

Configure is a local OPERATOR action; do not run it through RDC. No secrets are
printed, placed in CLI arguments, committed or uploaded as build artifacts.
"""
from __future__ import annotations

import argparse
import base64
from datetime import datetime, timezone, timedelta
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

REPO = 'analienx/baby-sleep-tracker'
BRANCH = 'feat/spark-personal-cloud-light-ui'
WORKFLOW = 'spark-staging-android.yml'
PKG = 'com.analienx.baby_sleep_tracker.staging'
PREVIEW = 'com.analienx.baby_sleep_tracker'
VARIABLE = 'LITTLE_REST_STAGING_ENABLED'
SOURCES = {
    'LITTLE_REST_STAGING_CONFIG_B64': 'personal-staging.json',
    'LITTLE_REST_STAGING_P12_B64': 'signing/little-rest-staging.p12',
    'LITTLE_REST_STAGING_P12_PASSWORD': 'signing/staging-signing-password.txt',
}
DEFAULT_PRIVATE = Path(r'C:\Workspace\artifacts\baby-sleep-tracker\firebase-staging')
DEFAULT_OUT = Path(r'C:\Workspace\artifacts\baby-sleep-tracker\android-spark-staging')


class Blocked(RuntimeError):
    pass


def call(*argv, stdin=None):
    proc = subprocess.run(argv, input=stdin, text=True, capture_output=True,
                          encoding='utf-8', errors='replace', check=False)
    if proc.returncode:
        # Do not print arbitrary stderr; some CLIs may echo confidential values.
        raise Blocked(f'{Path(argv[0]).name} operation failed (exit {proc.returncode}).')
    return proc.stdout.strip()


def gh_json(*args):
    return json.loads(call('gh', *args))


def doctor(required=False):
    if shutil.which('gh') is None:
        raise Blocked('GitHub CLI missing.')
    call('gh', 'auth', 'status')
    names = {x['name'] for x in gh_json('secret', 'list', '-R', REPO, '--json', 'name')}
    vars_ = {x['name']: x['value'] for x in gh_json('variable', 'list', '-R', REPO,
                                                  '--json', 'name,value')}
    missing = sorted(set(SOURCES) - names)
    enabled = vars_.get(VARIABLE) == 'true'
    print(f'Actions secrets configured: {len(SOURCES)-len(missing)}/{len(SOURCES)}; staging enabled: {enabled}')
    for key in missing:
        print('Missing secret name:', key)
    print('ADB installed:', bool(shutil.which('adb')))
    if required and (missing or not enabled):
        raise Blocked('Configuration incomplete. Run configure directly on Zephyrus.')
    return not missing and enabled


def configure(root):
    """One-time, *manually invoked* local setup; never agent-execute via RDC."""
    paths = {name: root / relative for name, relative in SOURCES.items()}
    for name, path in paths.items():
        if not path.is_file() or path.stat().st_size == 0:
            raise Blocked(f'Missing/nonempty private input for {name}: {path}')
    config = json.loads(paths['LITTLE_REST_STAGING_CONFIG_B64'].read_text(encoding='utf-8-sig'))
    if config.get('FIREBASE_PROJECT_ID') != 'little-rest-stage-jh-261020':
        raise Blocked('Local Firebase project mismatch.')
    if config.get('FIREBASE_ANDROID_APP_ID') != '1:256303473837:android:87f5a15b2bc10e226d9224':
        raise Blocked('Local Firebase Android staging app ID mismatch.')
    call('gh', 'auth', 'status')
    for name, path in paths.items():
        raw = path.read_bytes()
        value = (raw.decode('utf-8-sig').strip() if name.endswith('_PASSWORD')
                 else base64.b64encode(raw).decode('ascii'))
        if not value:
            raise Blocked(f'Empty value for {name}')
        # gh encrypts locally. Passing via stdin avoids secrets in process argv.
        call('gh', 'secret', 'set', name, '-R', REPO, stdin=value)
        print('Configured secret name:', name)
    call('gh', 'variable', 'set', VARIABLE, '-R', REPO, '--body', 'true')
    doctor(required=True)


def branch_sha():
    obj = gh_json('api', f'repos/{REPO}/git/ref/heads/{BRANCH}')
    sha = obj['object']['sha']
    if not re.fullmatch('[0-9a-f]{40}', sha):
        raise Blocked('Invalid branch SHA')
    return sha


def trigger():
    doctor(required=True)
    sha = branch_sha()
    before = datetime.now(timezone.utc) - timedelta(seconds=12)
    try:
        call('gh', 'workflow', 'run', WORKFLOW, '-R', REPO, '--ref', BRANCH)
    except Blocked as exc:
        raise Blocked('Manual dispatch unavailable: GitHub requires the workflow on '
                      'the default branch. Do not merge unapproved feature code. '
                      'Use a verified successful push run or reviewed dispatcher.') from exc
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline:
        runs = gh_json('run', 'list', '-R', REPO, '--workflow', WORKFLOW,
                       '--branch', BRANCH, '--limit', '30', '--json',
                       'databaseId,headSha,event,createdAt')
        eligible = [r for r in runs if r['headSha'] == sha and
                    r['event'] == 'workflow_dispatch' and
                    datetime.fromisoformat(r['createdAt'].replace('Z', '+00:00')) >= before]
        if eligible:
            return max(eligible, key=lambda x: x['databaseId'])['databaseId']
        time.sleep(4)
    raise Blocked('Cannot resolve dispatched run; inspect Actions before retrying.')


def checked_run(run_id):
    r = gh_json('run', 'view', str(run_id), '-R', REPO, '--json',
                'status,conclusion,headSha,headBranch,workflowName,url')
    if (r['status'], r['conclusion'], r['headBranch'], r['workflowName']) != (
            'completed', 'success', BRANCH, 'Spark staging Android'):
        raise Blocked('Run is not a successful staging build on the expected branch.')
    return r


def download(run_id, out):
    data = checked_run(run_id)
    artifact = f"little-rest-spark-staging-debug-{data['headSha']}"
    raw = gh_json('api', f'repos/{REPO}/actions/runs/{run_id}/artifacts')
    matches = [a for a in raw.get('artifacts', []) if a['name'] == artifact and not a['expired']]
    if len(matches) != 1:
        raise Blocked('Matching signed staging artifact missing or ambiguous.')
    folder = out / str(run_id)
    if folder.exists() and list(folder.rglob('*.apk')):
        raise Blocked('Destination already contains an APK; refusing overwrite.')
    folder.mkdir(parents=True, exist_ok=True)
    call('gh', 'run', 'download', str(run_id), '-R', REPO,
         '--name', artifact, '--dir', str(folder))
    apks = list(folder.rglob('*.apk'))
    if len(apks) != 1 or apks[0].name != 'app-debug.apk':
        raise Blocked('Unexpected APK download contents.')
    print('Verified artifact SHA256:', hashlib.sha256(apks[0].read_bytes()).hexdigest())
    return apks[0]


def adb_one():
    if shutil.which('adb') is None:
        raise Blocked('adb unavailable.')
    lines = call('adb', 'devices', '-l').splitlines()[1:]
    all_devices = [line.split()[:2] for line in lines if len(line.split()) >= 2]
    if len(all_devices) != 1 or all_devices[0][1] != 'device':
        raise Blocked('Exactly one authorized Android device required.')
    return all_devices[0][0]


def present(serial, package):
    return 'package:' in call('adb', '-s', serial, 'shell', 'pm', 'path', package)


def aapt():
    if shutil.which('aapt'):
        return shutil.which('aapt')
    bases = [Path(v) for v in (os.getenv('ANDROID_HOME'), os.getenv('ANDROID_SDK_ROOT')) if v]
    if os.getenv('LOCALAPPDATA'):
        bases.append(Path(os.environ['LOCALAPPDATA']) / 'Android' / 'Sdk')
    paths = [p for base in bases for p in (base / 'build-tools').glob('*/aapt.exe')]
    return str(sorted(paths)[-1]) if paths else None


def install(apk, run_id):
    run_info = checked_run(run_id)  # require GitHub's aapt package assertion
    if apk.name != 'app-debug.apk' or not apk.is_file():
        raise Blocked('APK name or path unexpected.')
    tool = aapt()
    if tool:
        if f"package: name='{PKG}'" not in call(tool, 'dump', 'badging', str(apk)):
            raise Blocked('APK not identified as isolated staging package.')
    else:
        print('Local aapt unavailable; trusting successful GitHub package assertion.')
    serial = adb_one()
    if not present(serial, PREVIEW):
        raise Blocked('Existing preview absent: refusing to alter this device.')
    call('adb', '-s', serial, 'install', '-r', str(apk))
    if not present(serial, PKG) or not present(serial, PREVIEW):
        raise Blocked('Package verification failed; do not clear application data.')
    # The Gradle applicationId has a .staging suffix, but Flutter's Kotlin
    # MainActivity can retain the original Java package namespace. Resolve the
    # installed launcher component rather than guessing it from applicationId.
    resolved = call('adb', '-s', serial, 'shell', 'cmd', 'package',
                    'resolve-activity', '--brief', PKG)
    lines = [s.strip() for s in resolved.splitlines() if s.strip()]
    component = lines[-1] if lines else ''
    if not component.startswith(PKG + '/') or 'MainActivity' not in component:
        raise Blocked('Cannot determine the isolated staging launcher component.')
    call('adb', '-s', serial, 'shell', 'am', 'start', '-W', '-n', component)
    print('Separate Spark staging app installed and launched:', run_info['url'])
    print('Use synthetic records only until privacy review and physical QA pass.')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('doctor', help='Read-only environment preflight')
    cfg = sub.add_parser('configure', help='ONE-TIME direct local operator step')
    cfg.add_argument('--private-dir', type=Path, default=DEFAULT_PRIVATE)
    dep = sub.add_parser('deploy', help='Trigger, verify, download and install')
    dep.add_argument('--run-id', type=int, help='Use existing successful staging workflow run')
    dep.add_argument('--output', type=Path, default=DEFAULT_OUT)
    dep.add_argument('--no-install', action='store_true')
    args = parser.parse_args(argv)
    try:
        if args.command == 'doctor':
            return 0 if doctor() else 2
        if args.command == 'configure':
            configure(args.private_dir)
        elif args.command == 'deploy':
            run_id = args.run_id if args.run_id else trigger()
            if not args.run_id:
                print('Watching GitHub staging run', run_id)
                call('gh', 'run', 'watch', str(run_id), '-R', REPO, '--exit-status')
            apk = download(run_id, args.output)
            if not args.no_install:
                install(apk, run_id)
        return 0
    except (Blocked, ValueError, OSError, KeyError, json.JSONDecodeError) as e:
        print('DEPLOYMENT BLOCKED:', e, file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
