"""Structural safeguards only. This is NOT an iOS compile or AirPlay test."""
from pathlib import Path
import plistlib
root = Path(__file__).resolve().parents[1]
read = lambda p: (root / p).read_text()
tv = read('App/Views/DuelTelevision.swift')
world = read('App/Views/DuelWorld.swift')
plist = plistlib.loads((root/'App/Info.plist').read_bytes())
assert 'UIWindowSceneSessionRoleExternalDisplayNonInteractive' in plist['UIApplicationSceneManifest']['UISceneConfigurations']
assert 'DuelWorldView(' not in tv and 'CADisplayLink(' not in tv and 'DuelGame(' not in tv
assert 'makeKeyAndVisible' not in tv
assert 'world.shutdown()' in tv and 'router.unmount(self)' in tv
assert 'private var relocatingDisplay = false' in world
assert 'guard !ended, !relocatingDisplay else { return }' in world
assert 'guard scene.session.role == .windowApplication' in read('App/Views/ArenaView.swift')
assert '.onAppear' not in tv and 'DuelMusicLease' not in tv
print('8 structural television checks passed (native execution still required)')
