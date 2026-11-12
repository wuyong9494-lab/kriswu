"""Read only a pinned prior evidence envelope; emit encrypted diagnostic text only."""
import hashlib,hmac,json,os,re,subprocess,sys,zipfile
from pathlib import Path
import fighter_private_model as envelope


def decrypt(source, target):
    prefix=b'FIGHTER1\0evidence\0'
    size=source.stat().st_size
    if source.is_symlink() or not 50 < size <= envelope.MAX_EVIDENCE_BYTES:
        raise ValueError('Invalid input size')
    with source.open('rb') as f:
        if f.read(len(prefix)) != prefix: raise ValueError('Invalid envelope')
        f.seek(0)
        mac=hmac.new(envelope.mac_key('evidence'),digestmod='sha256')
        remaining=size-32
        while remaining:
            b=f.read(min(1048576,remaining))
            if not b: raise ValueError('Truncated envelope')
            mac.update(b);remaining-=len(b)
        if not hmac.compare_digest(mac.digest(),f.read(32)): raise ValueError('Invalid authentication')
        f.seek(len(prefix))
        with target.open('xb') as out:
            p=subprocess.Popen(envelope.openssl_command(True),stdin=subprocess.PIPE,stdout=out,stderr=subprocess.DEVNULL)
            try:
                remaining=size-len(prefix)-32
                while remaining:
                    b=f.read(min(1048576,remaining))
                    if not b: raise ValueError('Truncated ciphertext')
                    p.stdin.write(b);remaining-=len(b)
                p.stdin.close()
                if p.wait(): raise ValueError('Decrypt failed')
            finally:
                if p.poll() is None: p.kill();p.wait()


def summarize(archive):
    result={'source_run':43170811422,'artifact':13923982443,'logs':[]}
    pattern=re.compile(r'fail|error|crash|assert|timed? ?out|TEST|Executed|passed|Unable',re.I)
    budget=1500000
    with zipfile.ZipFile(archive) as z:
        for info in z.infolist():
            if not info.filename.endswith('.log') or info.file_size>40000000: continue
            # Never extract archive paths or execute archived content.
            lines=z.read(info).decode('utf-8','replace').splitlines()
            indices=set()
            for i,line in enumerate(lines):
                if pattern.search(line): indices.update(range(max(0,i-2),min(len(lines),i+3)))
            selected=[]
            for i in sorted(indices):
                s=f'{i+1}: {lines[i][:2000]}'
                if len(s)>budget: break
                budget-=len(s);selected.append(s)
            result['logs'].append({'name':info.filename,'lines':len(lines),'selected':selected})
    return result


def main():
    os.umask(0o077)
    root=Path(sys.argv[1]); work=Path(sys.argv[2]);work.mkdir(exist_ok=False)
    source=root/'fighter-evidence.enc'
    expected=(root/'fighter-evidence.enc.sha256').read_text().split()[0]
    if not re.fullmatch('[a-f0-9]{64}',expected): raise ValueError('Invalid checksum')
    with source.open('rb') as f: actual=hashlib.file_digest(f,'sha256').hexdigest()
    if actual!=expected: raise ValueError('Checksum mismatch')
    clear=work/'prior.zip'
    decrypt(source,clear)
    report=work/'diagnostics.json';report.write_text(json.dumps(summarize(clear),ensure_ascii=False,indent=2))
    output=work/'diagnostics.enc'
    envelope.seal_evidence_file(report,output)
    (work/'diagnostics.enc.sha256').write_text(hashlib.sha256(output.read_bytes()).hexdigest()+'  diagnostics.enc\n')
    print('Existing evidence authenticated; diagnostic summary encrypted. No tests executed.')

if __name__=='__main__':
    try:main()
    except Exception:
        print('Diagnostic recovery failed; no plaintext output published.',file=sys.stderr);sys.exit(1)
