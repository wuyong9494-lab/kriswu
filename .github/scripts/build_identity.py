"""Embed CI identity without exposing credentials or depending on generated Info.plist."""
import os
import plistlib
from pathlib import Path
path = Path('App/Info.plist')
info = plistlib.loads(path.read_bytes())
info['ArenaCommitSHA'] = os.environ.get('GITHUB_SHA', 'unknown')
path.write_bytes(plistlib.dumps(info))
