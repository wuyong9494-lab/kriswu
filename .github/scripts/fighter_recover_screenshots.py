"""Sample authenticated existing screenshots, encrypted to a one-time recipient."""
import hashlib,json,os,secrets,subprocess,sys,zipfile
from pathlib import Path
import fighter_private_model as envelope
from fighter_recover_diagnostics import decrypt
PUBLIC_KEY = '-----BEGIN PUBLIC KEY-----\nMIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEA1yIN9Heinj7crMSL13Td\n4EOpWuVNS/dv7/kFSnyivXVQ9atkcQQMHWcVJ/qVkHpXCU2XPU2SiYylvCEkafgE\nyzPOcWL1nbQmufT5iso0nuDb1uZ1D/SubsAU/1Fo0TjvG2ebpXQxA4XMU0I5JUl6\nLhTDUFDMIoN955Ti6USsqhvTBaZuVQwWDxaI3dRQDdvv3aGv928NNRl/NjfUc5Dp\ntdDpQzLkMNBTBrrx6WVWbZG7J5yHySCo4xoahDa9TEEDy0K570++Ym0f+kShVUvy\nGnaqK2eAxMDcNsh2qUauWSUprJeFVpm0voTb3ycwtOp+qoFKXyvsuOwuS/ppuyyr\nXIxbwS+eP8yRRsqHc8vrsBEV+seMVH2Z7Y4eteUQxDLT1IAcwJ/yWj9qcC9UL3/y\nSSndDPv2yHcNtOSNjGWQRPVyua1iMbgAGL4cA9USqWF35Hsb6lV39e8+NGCOlBZ4\nKuVo3C9AZDY/98Id8WWFvKpL89V9QskuMF8PMotFWJ+xAgMBAAE=\n-----END PUBLIC KEY-----\n'

def select(z):
    images=[i for i in z.infolist() if i.filename.lower().endswith(('.png','.jpg','.jpeg')) and 0<i.file_size<=12*1024**2]
    labels={i.filename:i.filename for i in images};manifests=[]
    for info in z.infolist():
        if info.filename.endswith('.json') and info.file_size<2*1024**2:
            try:data=json.loads(z.read(info))
            except (ValueError,UnicodeError):continue
            manifests.append((info.filename,data))
            def walk(x):
                if isinstance(x,dict):
                    text=' '.join(v for v in x.values() if isinstance(v,str))
                    for image in images:
                        if Path(image.filename).name in text:labels[image.filename]+=' '+text
                    for v in x.values():walk(v)
                elif isinstance(x,list):
                    for v in x:walk(v)
            walk(data)
    chosen=[]
    for term in ['original-weapons-final', 'failed', 'returned-landscape', 'lobby', 'selection', 'original-ember', 'original-liu', 'portrait']:
        matches=[i for i in images if term in labels[i.filename].lower() and i not in chosen]
        if matches:
            chosen.append(matches[0])
            if len(matches)>1:chosen.append(matches[-1])
    remaining=[i for i in images if i not in chosen];slots=24-len(chosen)
    if remaining and slots>0:
        chosen.extend(remaining[round(k*(len(remaining)-1)/max(1,min(slots,len(remaining))-1))] for k in range(min(slots,len(remaining))))
    return chosen[:24],labels,manifests,images

def main():
    os.umask(0o077)
    root=Path(sys.argv[1]);work=Path(sys.argv[2]);work.mkdir(exist_ok=False)
    source=root/'fighter-evidence.enc'
    expected=(root/'fighter-evidence.enc.sha256').read_text().split()[0]
    with source.open('rb') as f:actual=hashlib.file_digest(f,'sha256').hexdigest()
    if actual!=expected:raise ValueError('Checksum mismatch')
    clear=work/'prior.zip';decrypt(source,clear)
    sample=work/'sample.zip'
    with zipfile.ZipFile(clear) as old,zipfile.ZipFile(sample,'w',compression=zipfile.ZIP_STORED) as new:
        selected,labels,manifests,images=select(old)
        if not selected:raise ValueError('No captured images')
        entries=[]
        for n,info in enumerate(selected):
            name=f'{n:02d}'+Path(info.filename).suffix
            data=old.read(info);new.writestr(name,data)
            entries.append({'file':name,'source':info.filename,'label':labels[info.filename],'sha256':hashlib.sha256(data).hexdigest()})
        new.writestr('selection.json',json.dumps({'run':43170811422,'images':entries,'available':[{'source':i.filename,'label':labels[i.filename]} for i in images],'manifests':manifests},ensure_ascii=False))
    if sample.stat().st_size>350*1024**2:raise ValueError('Sample too large')
    # The existing environment key is used only to read old evidence. Never
    # publish or overwrite it. A fresh random output key is OAEP-wrapped.
    output_key=secrets.token_bytes(32)
    public=work/'recipient.public.pem';public.write_text(PUBLIC_KEY)
    wrapped=subprocess.run(['openssl','pkeyutl','-encrypt','-pubin','-inkey',str(public),'-pkeyopt','rsa_padding_mode:oaep','-pkeyopt','rsa_oaep_md:sha256'],input=output_key,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,check=True).stdout
    os.environ['FIGHTER_LIU_MODEL_KEY']=output_key.hex()
    output=work/'screenshots.enc';envelope.seal_evidence_file(sample,output)
    (work/'screenshots.key.enc').write_bytes(wrapped)
    (work/'screenshots.SHA256SUMS').write_text(''.join(hashlib.sha256((work/name).read_bytes()).hexdigest()+'  '+name+'\n' for name in ['screenshots.enc','screenshots.key.enc']))
    print('Existing screenshot sample authenticated and encrypted. No game tests executed.')
if __name__=='__main__':
    try:main()
    except Exception:
        print('Screenshot recovery failed; no plaintext published.',file=sys.stderr);sys.exit(1)
