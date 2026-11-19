"""Check one sealed Serpent Morph delta without emitting keys or resource bytes."""
from pathlib import Path
import argparse
import hashlib
import hmac
import io
import json
import os
import re
import stat
import sys
import tempfile
import zipfile

import fighter_integration_recipient as recipient
import prepare_fighter_completion_delta as prep
import stage_fighter_completion_delta as stage

ARCHIVE_SHA = 'd92923cbdc2bbb5854b142321ea8e240a483ff6b15edc6a91a8b1b13cb06f7e8'
RECORDS = {
    'recipient-public.crt': (1529, '9d8d67155afdd3068e8593b62ea674c1592350f2de6bde89e64450a7613dd656'),
    'recipient-private.pkcs8.enc': (1914, '3fe043a275b2fa9d994a9b7d7db5ec6dfaab39bc839060e1b199a180683d6bdd'),
    'recipient-report.json': (None, 'dd864405de351951596cd6fd00c2da1e582b18e88b0edfb3730b9ee1b7ad3d63'),
}
ENV = {'GITHUB_ACTIONS':'true','GITHUB_REPOSITORY':'wuyong9494-lab/kriswu',
       'GITHUB_REF':'refs/heads/codex/fighter-visual-acceptance-20261113-1200',
       'GITHUB_EVENT_NAME':'push','GITHUB_RUN_ATTEMPT':'1'}
KEY = 'FIGHTER_H17_D19_KEY'


def exact_zip(raw, records, expected_digest):
    prep.require(prep.digest(raw)==expected_digest,'Artifact archive differs')
    with zipfile.ZipFile(io.BytesIO(raw)) as z:
        entries=z.infolist()
        prep.require(len(entries)==len(records) and {r.filename for r in entries}==set(records),
                     'Unexpected recipient members')
        result={}
        for item in entries:
            size,digest=records[item.filename]
            mode=item.external_attr>>16
            prep.require(not item.is_dir() and not stat.S_ISLNK(mode)
                         and not item.flag_bits & 1 and 0 < item.file_size < 8192
                         and (size is None or item.file_size==size),'Invalid recipient member')
            payload=z.read(item)
            prep.require(prep.digest(payload)==digest,'Recipient member differs')
            result[item.filename]=payload
    return result


def metadata(archive, delta, scratch, phase=lambda _:None):
    phase("recipient-archive")
    raw=prep.regular(archive,8192).read_bytes()
    prep.require(len(raw)==4184,'Recipient archive size differs')
    files=exact_zip(raw,RECORDS,ARCHIVE_SHA)
    receipt=prep.decode(files['recipient-report.json'])
    prep.require(receipt['runID']=='44029477961' and receipt['runAttempt']==1
                 and receipt['sourceCommit']=='fbe1f97b947df6936eb9a1721510e92a178fb543'
                 and receipt['recipientSPKISHA256']==prep.RECIPIENT_SPKI
                 and receipt['plaintextPrivateKeyPublished'] is False,'Recipient receipt differs')
    phase('recipient-certificate')
    cert=scratch/'recipient-public.crt'
    prep.new_file(cert,files[cert.name])
    prep.certificate_spki(cert)
    phase('delta-inventory')
    doc=prep.decode(prep.checked(delta/prep.DELTA_MANIFEST_NAME,stage.DELTA_MANIFEST))
    prep.require(doc==prep.delta_document(stage.CLEAR_ZIP,stage.SEALED_DELTA,stage.COMPILED_INVENTORY),
                 'Delta manifest differs')
    inv=prep.decode(prep.checked(delta/prep.COMPILED_NAME,stage.COMPILED_INVENTORY))
    rows=prep.inventory(inv['compiledFiles'],541)
    prep.require(rows.get(prep.ADDITION['name'])==prep.ADDITION,'Compiled inventory target differs')
    sealed=delta/prep.SEALED_NAME
    prep.checked(sealed,stage.SEALED_DELTA,prep.MAX_SEALED)
    phase('cms-profile')
    prep.inspect_seal(sealed)
    return receipt,files['recipient-private.pkcs8.enc'],sealed


def unwrap(scratch,wrapped,expected_mac,passphrase,expected_spki):
    derived=recipient.resource_key(passphrase)
    prep.require(hmac.compare_digest(recipient.wrapper_hmac(derived,wrapped),expected_mac),
                 'Wrapped key authentication failed')
    box=scratch/'recipient-key.enc'
    key=scratch/'recipient-key.pem'
    prep.new_file(box,wrapped)
    prep.command([prep.openssl(),'pkey','-inform','DER','-in',str(box),'-passin','stdin','-out',str(key)],
                 data=(passphrase+'\n').encode())
    return stage.protected_key_spki(key,expected_spki)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('archive',type=Path)
    p.add_argument('delta',type=Path)
    p.add_argument('--protected',action='store_true')
    a=p.parse_args()
    passphrase=None
    step='approved-runner'
    def mark(value):
        nonlocal step
        step=value
    try:
        if a.protected:
            prep.require(all(os.environ.get(k)==v for k,v in ENV.items()),'Approved runner required')
            passphrase=os.environ.pop(KEY,'')
            prep.require(bool(passphrase),'Private resource key unavailable')
        else:
            prep.require(KEY not in os.environ,'Preflight must not receive a key')
        # macOS TMPDIR may live under /var (a symlink to /private/var).
        # Resolve the parent before mkdtemp so regular() can reject all links.
        root = Path(os.environ['RUNNER_TEMP'] if a.protected else
                    os.environ.get('RUNNER_TEMP', tempfile.gettempdir())).resolve(strict=True)
        os.umask(0o077)
        with tempfile.TemporaryDirectory(prefix='serpent-receipt-',dir=root) as t:
            scratch=Path(t)
            step='pinned-metadata'
            receipt,wrapped,sealed=metadata(a.archive,a.delta,scratch,mark)
            if a.protected:
                step='wrapped-recipient'
                key=unwrap(scratch,wrapped,receipt['wrappedKeyHMACSHA256'],passphrase,prep.RECIPIENT_SPKI)
                passphrase=None
                step='delta-authentication'
                payload=stage.unseal(sealed,key,stage.SEALED_DELTA,stage.CLEAR_ZIP)
                prep.require(len(payload)==prep.ADDITION['bytes']
                             and hashlib.sha256(payload).hexdigest()==prep.ADDITION['sha256'],'Payload differs')
        print(json.dumps({'pinnedInputsVerified':True,'exactNewResources':int(a.protected),
                           'decryptionPerformed':a.protected,'built':False,'published':False}))
    except Exception:
        print('Serpent receipt failed during '+step+'; no secrets or resource bytes emitted.',file=sys.stderr)
        raise SystemExit(1) from None


if __name__=='__main__':
    main()
