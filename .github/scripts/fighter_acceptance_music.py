#!/usr/bin/env python3
"""Pinned encrypted transport staging; no network and no credential printing."""
import hashlib
from pathlib import Path
import sys
import music_envelope, music_package
PARTS = [('sf3-music-v1.musicpack.enc.part01',20971520,'0422f78880cf4848d1c71b24e5745246b5347ad94df23a3bb721a37f8bfb27e7'),('sf3-music-v1.musicpack.enc.part02',13361700,'7361c7f7116e2219ddec0a4c7dae89f2d6b56d06ac3305443d5e0eb61a603b33')]
CIPHER_SHA='b45109955a9b8e789ddd9c1c6240d037428b05fb086a4623f59fe52f5560438a'
def stage(parts, source, temporary):
    parts, source, temporary=map(Path,(parts,source,temporary))
    blocks=[music_envelope.read_file(parts/name,size) for name,size,_ in PARTS]
    for data,(_,_,sha) in zip(blocks,PARTS):
        if hashlib.sha256(data).hexdigest()!=sha: raise ValueError('Part digest mismatch')
    cipher=b''.join(blocks); music_envelope.verify_cipher(cipher,CIPHER_SHA)
    helper=music_envelope.load_envelope(source/'.github/scripts/fighter_private_model.py')
    clear=helper.unseal(cipher,music_package.PURPOSE); music_package.verify_bytes(clear)
    archive=temporary/'music-clear.musicpack'; music_envelope.publish_new(archive,clear)
    music_package.stage(archive,source/'App/Resources/FighterPrivate')
    archive.unlink()
if __name__=='__main__':
    try: stage(*sys.argv[1:])
    except Exception: raise SystemExit('Pinned music staging failed; no plaintext was published') from None
