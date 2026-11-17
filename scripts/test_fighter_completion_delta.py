#!/usr/bin/env python3
"""Reproduce 37 bounded delta checks without a production private key.

Requires existing pinned base metadata, the reviewed public delta and the exact
D13 manifest as a private source input. Missing inputs fail; nothing is skipped.
Only an isolated temporary test certificate/key is used for round-trip tests.
No private resource bytes are embedded in this script, and the production cipher
is reused unchanged. Synthetic small files exercise base-closure helpers only.
"""
from pathlib import Path
from types import SimpleNamespace
import argparse
import ast
import io
import json
import os
import shutil
import sys
import tempfile
import warnings
import zipfile

sys.dont_write_bytecode=True
SCRIPTS=Path(__file__).resolve().parent
sys.path.insert(0,str(SCRIPTS))
import prepare_fighter_completion_delta as prepare
import stage_fighter_completion_delta as stage


def run(args):
    BASE=args.base_manifest
    DELTA=args.delta_directory
    MORPH=args.morph
    REPORT=args.report
    cases=[]
    def passed(name,detail=''):
        cases.append({'case':name,'passed':True,'detail':detail})
    def rejects(name,callback):
        try:callback()
        except (ValueError,zipfile.BadZipFile,RuntimeError) as e:
            passed(name,type(e).__name__+': '+str(e)[:180])
        else:raise AssertionError('Unsafe input accepted: '+name)

    for name in ('prepare_fighter_completion_delta.py','stage_fighter_completion_delta.py'):
        ast.parse((SCRIPTS/name).read_text())
    passed('python_ast_two_scripts')
    base,compiled=stage.authenticated_metadata(BASE,DELTA)
    assert len(compiled['compiledFiles'])==541 and compiled['release']==prepare.RELEASE
    old={r['name']:r for r in base['compiledFiles']}
    assert all(next(r for r in compiled['compiledFiles'] if r['name']==name)==row for name,row in old.items())
    assert set(r['name'] for r in compiled['compiledFiles'])-set(old)=={prepare.ADDITION['name']}
    passed('production_external_pins_and_exact_540_plus_one_union')
    clear=prepare.clear_zip(prepare.checked(MORPH,prepare.ADDITION,prepare.ADDITION['bytes']))
    payload=prepare.validate_clear(clear)
    assert clear==prepare.clear_zip(payload)==prepare.clear_zip(payload)
    assert prepare.digest(clear)==stage.CLEAR_ZIP['sha256']
    passed('deterministic_clear_zip_and_fixed_plaintext_pin')
    prepare.inspect_seal(DELTA/prepare.SEALED_NAME)
    passed('real_cipher_public_envelope_structure_only','No protected recipient private key was read or used.')

    def zip_bytes(names,*,mode=0o100600,compression=zipfile.ZIP_STORED,body=payload):
        b=io.BytesIO()
        with warnings.catch_warnings():
            warnings.simplefilter('ignore',UserWarning)
            with zipfile.ZipFile(b,'w') as z:
                for name in names:
                    info=zipfile.ZipInfo(name,date_time=(1980,1,1,0,0,0))
                    info.create_system=3;info.external_attr=mode<<16;info.compress_type=compression
                    z.writestr(info,body)
        return b.getvalue()
    for name,raw in [
        ('duplicate_zip_entry',zip_bytes([prepare.ADDITION['name']]*2)),
        ('extra_zip_entry',zip_bytes([prepare.ADDITION['name'],'unreviewed.json'])),
        ('zip_parent_traversal',zip_bytes(['../'+prepare.ADDITION['name']])),
        ('zip_absolute_path',zip_bytes(['/tmp/'+prepare.ADDITION['name']])),
        ('zip_nested_path',zip_bytes(['nested/'+prepare.ADDITION['name']])),
        ('zip_backslash_path',zip_bytes(['..\\'+prepare.ADDITION['name']])),
        ('zip_symbolic_link',zip_bytes([prepare.ADDITION['name']],mode=0o120777)),
        ('zip_noncanonical_compression',zip_bytes([prepare.ADDITION['name']],compression=zipfile.ZIP_DEFLATED)),
        ('zip_oversized_file',zip_bytes([prepare.ADDITION['name']],body=payload+b'x')),
        ('zip_changed_content',zip_bytes([prepare.ADDITION['name']],body=b'X'+payload[1:])),
        ('zip_trailing_bytes',clear+b'\0'),
        ('zip_total_bound',b'X'*(prepare.MAX_CLEAR+1)),
    ]: rejects(name,lambda raw=raw:prepare.validate_clear(raw))
    rejects('duplicate_json_keys',lambda:prepare.decode(b'{"id":1,"id":2}'))

    with tempfile.TemporaryDirectory(prefix='completion-delta-negative-',dir=REPORT.parent) as temp:
        temp=Path(temp)
        public=temp/'public';public.mkdir(mode=0o700)
        for name in (prepare.SEALED_NAME,prepare.COMPILED_NAME,prepare.DELTA_MANIFEST_NAME):
            shutil.copyfile(DELTA/name,public/name)
        original=(public/prepare.DELTA_MANIFEST_NAME).read_bytes()
        forged=json.loads(original);forged['files'][0]['sha256']='0'*64
        (public/prepare.DELTA_MANIFEST_NAME).write_bytes(prepare.encoded(forged))
        rejects('input_manifest_cannot_authorize_own_plaintext_hash',lambda:stage.authenticated_metadata(BASE,public))
        (public/prepare.DELTA_MANIFEST_NAME).write_bytes(original)
        forged=json.loads(original);forged['cms']['sha256']='0'*64
        (public/prepare.DELTA_MANIFEST_NAME).write_bytes(prepare.encoded(forged))
        rejects('input_manifest_cannot_authorize_own_cipher_hash',lambda:stage.authenticated_metadata(BASE,public))
        (public/prepare.DELTA_MANIFEST_NAME).write_bytes(original)
        merged_original=(public/prepare.COMPILED_NAME).read_bytes()
        merged=json.loads(merged_original);merged['compiledFiles'].pop()
        (public/prepare.COMPILED_NAME).write_bytes(prepare.encoded(merged))
        rejects('changed_merged_inventory_rejected',lambda:stage.authenticated_metadata(BASE,public))
        (public/prepare.COMPILED_NAME).write_bytes(merged_original)
        cipher_original=(public/prepare.SEALED_NAME).read_bytes()
        changed=bytearray(cipher_original);changed[len(changed)//2]^=1
        (public/prepare.SEALED_NAME).write_bytes(changed)
        rejects('changed_production_cipher_rejected_before_key',lambda:stage.authenticated_metadata(BASE,public))
        (public/prepare.SEALED_NAME).write_bytes(cipher_original)
        # The full CLI entry validates hostile metadata before even looking for a
        # private key. A nonexistent sentinel makes accidental key access visible.
        (public/prepare.DELTA_MANIFEST_NAME).write_bytes(b'{}')
        negative_args=SimpleNamespace(output=temp/'stage-must-not-exist',delta_directory=public,base_manifest=BASE,
            recipient_certificate=temp/'unused-cert',recipient_key=temp/'unused-key',base_directory=temp/'unused-base')
        rejects('stage_metadata_failure_does_not_consult_key',lambda:stage.stage(negative_args))
        assert not negative_args.output.exists()
        # A real already-created result is never overwritten or re-encrypted.
        existing=temp/'existing-output';existing.mkdir(mode=0o700)
        negative_args=SimpleNamespace(output=existing)
        rejects('prepare_existing_output_rejected_before_inputs',lambda:prepare.prepare(negative_args))
        rejects('stage_existing_output_rejected_before_inputs',lambda:stage.stage(negative_args))

        # Only this isolated temporary key is ever used for decryption tests.
        key=temp/'test-recipient.pem';cert=temp/'test-recipient.crt'
        prepare.command([prepare.openssl(),'req','-x509','-newkey','rsa:2048','-nodes','-days','1',
            '-subj','/CN=CompletionDeltaIsolatedTest','-keyout',str(key),'-out',str(cert)])
        key.chmod(0o600)
        spki=prepare.command([prepare.openssl(),'pkey','-in',str(key),'-passin','pass:','-pubout','-outform','DER'])
        test_spki=prepare.digest(spki)
        prepare.certificate_spki(cert,prepare.record(cert),test_spki)
        stage.protected_key_spki(key,test_spki)
        passed('isolated_test_recipient_certificate_and_protected_key_spki')
        rejects('test_key_cannot_impersonate_real_recipient',lambda:stage.protected_key_spki(key))
        key.chmod(0o644)
        rejects('recipient_key_group_readability_rejected',lambda:stage.protected_key_spki(key,test_spki))
        key.chmod(0o600)
        link=temp/'linked-key.pem';link.symlink_to(key)
        rejects('recipient_key_symlink_rejected',lambda:stage.protected_key_spki(link,test_spki))
        test_clear=temp/prepare.CLEAR_NAME;test_clear.write_bytes(clear)
        test_seal=temp/'isolated-test.cms'
        prepare.command([prepare.openssl(),'cms','-encrypt','-binary','-aes-256-gcm','-in',str(test_clear),
            '-out',str(test_seal),'-outform','DER','-recip',str(cert),'-keyopt','rsa_padding_mode:oaep',
            '-keyopt','rsa_oaep_md:sha256','-keyopt','rsa_mgf1_md:sha256'])
        test_seal_record=prepare.record(test_seal)
        decoded=stage.unseal(test_seal,key,test_seal_record,stage.CLEAR_ZIP,test_spki)
        assert decoded==payload
        passed('isolated_test_key_gcm_oaep_round_trip_only','Not a protected production-recipient decryption.')
        wrong_clear={**stage.CLEAR_ZIP,'sha256':'0'*64}
        rejects('externally_wrong_clear_pin_rejected_after_decryption',lambda:stage.unseal(test_seal,key,test_seal_record,wrong_clear,test_spki))
        changed=bytearray(test_seal.read_bytes());changed[-10]^=1;test_seal.write_bytes(changed)
        # Explicit test-authority hash reaches GCM validation despite altered bytes;
        # production cannot change its sealed pin this way.
        changed_seal=prepare.record(test_seal)
        rejects('gcm_authentication_failure_rejected_without_output',lambda:stage.unseal(test_seal,key,changed_seal,stage.CLEAR_ZIP,test_spki))

        # Small synthetic base files validate closure and mutation handling without
        # rehashing/rebuilding the real 540-resource pack or changing its authority.
        fake_base=temp/'synthetic-base';fake_base.mkdir(mode=0o700)
        fake_rows=[]
        for index in range(540):
            p=fake_base/f'fixture_{index:03d}.json';p.write_bytes(('fixed synthetic base '+str(index)).encode())
            fake_rows.append(prepare.record(p))
        snapshot=stage.verified_base(fake_base,fake_rows);stage.base_unchanged(fake_base,snapshot)
        passed('synthetic_540_base_closure_helper_only','Production base remains authorized only by fixed 5341… manifest.')
        target=fake_base/fake_rows[0]['name'];old=target.read_bytes()
        target.write_bytes(b'X'+old[1:])
        rejects('base_changed_hash_rejected',lambda:stage.verified_base(fake_base,fake_rows))
        rejects('base_changed_after_snapshot_rejected',lambda:stage.base_unchanged(fake_base,snapshot))
        target.write_bytes(old)
        target.unlink();target.symlink_to(fake_base/fake_rows[1]['name'])
        rejects('base_resource_symlink_rejected',lambda:stage.verified_base(fake_base,fake_rows))
        target.unlink();target.write_bytes(old)
        extra=fake_base/'not-authorized.json';extra.write_bytes(b'x')
        rejects('base_extra_file_rejected',lambda:stage.verified_base(fake_base,fake_rows))
        extra.unlink();target.unlink()
        rejects('base_missing_file_rejected',lambda:stage.verified_base(fake_base,fake_rows))

    assert not temp.exists()
    report={'schema':'fighter-completion-delta-local-regressions-v1','passed':len(cases),'failed':0,'cases':cases,
        'realRecipientPrivateKeyRead':False,'realRecipientDecryptionVerified':False,
        'temporaryTestKeyUsed':True,'temporaryTestKeyDestroyed':True,'realCipherPublicMetadataVerified':True,
        'realBase540BytesRehashed':False,'realBaseAuthorityAnd541UnionVerified':True,
        'oldCMSPartsChanged':False,'nativeAcceptanceExecuted':False,'workflowTriggered':False,'uploaded':False}
    path=REPORT
    path.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');path.chmod(0o600)
    print(json.dumps({'report':str(path),'passed':len(cases),'failed':0,
        'realRecipientPrivateKeyRead':False,'realRecipientDecryptionVerified':False,'temporaryTestKeyDestroyed':True}))


def main():
    os.umask(0o077)
    parser=argparse.ArgumentParser(description=__doc__)
    for flag,variable in (
        ('base-manifest','FIGHTER_COMPLETION_BASE_MANIFEST'),
        ('delta-directory','FIGHTER_COMPLETION_DELTA_DIRECTORY'),
        ('morph','FIGHTER_COMPLETION_MORPH'),
        ('report','FIGHTER_COMPLETION_REPORT'),
    ):
        default=os.environ.get(variable)
        parser.add_argument('--'+flag,default=default,required=not bool(default),
            type=lambda value:Path(value).absolute(),help='Explicit path, or '+variable)
    args=parser.parse_args()
    prepare.require(not args.report.exists() and not args.report.is_symlink(),
                    'Refuse to overwrite an existing regression receipt')
    prepare.require(args.report.parent.is_dir() and args.report.parent.resolve(strict=True)==args.report.parent,
                    'Report parent must be an existing unlinked private directory')
    prepare.require(not args.report.resolve().is_relative_to(SCRIPTS.parent),
                    'Regression receipts and temporary test keys must remain outside the checkout')
    try:
        run(args)
    except Exception as error:
        failure={'schema':'fighter-completion-delta-local-regressions-v1','passed':False,'failed':1,
            'errorType':type(error).__name__,'error':str(error)[:300],
            'realRecipientPrivateKeyRead':False,'realRecipientDecryptionVerified':False,
            'nativeAcceptanceExecuted':False,'workflowTriggered':False,'uploaded':False}
        prepare.new_file(args.report,prepare.encoded(failure))
        print(json.dumps(failure,sort_keys=True))
        return 1
    return 0


if __name__=='__main__':
    raise SystemExit(main())
