#!/usr/bin/env python3
"""Run Flutter checks from a path without apostrophes (Flutter loader limitation)."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--flutter', default='flutter', help='Flutter executable')
parser.add_argument('--build', action='store_true', help='Also export a web build to app/build/web')
parser.add_argument('--test', help='Run just this test path, e.g. test/app_test.dart')
parser.add_argument('--config', help='Local dart-define JSON for an optional connected web build')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
flutter = shutil.which(args.flutter)
if not flutter:
    parser.error('Flutter is not installed or the executable was not found.')
with tempfile.TemporaryDirectory(prefix='aira-flutter-check-') as tmp:
    app = Path(tmp) / 'app'
    shutil.copytree(root / 'app', app, ignore=shutil.ignore_patterns('build', '.dart_tool', '.env', '*.local.json'))
    def run(*cmd):
        subprocess.run([flutter, *cmd], cwd=app, check=True)
    run('pub', 'get')
    if not args.test:
        run('analyze', '--no-pub')
    run('test', '--no-pub', *([args.test] if args.test else []))
    if args.build:
        config = ['--dart-define-from-file=' + str(Path(args.config).resolve())] if args.config else []
        run('build', 'web', '--no-pub', *config)
        shutil.copytree(app / 'build' / 'web', root / 'app' / 'build' / 'web', dirs_exist_ok=True)
        print('Web build exported to app/build/web', flush=True)
