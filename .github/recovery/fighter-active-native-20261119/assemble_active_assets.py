"""Stage only authenticated active resources; never place an incomplete set in the app."""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import stat
import tempfile
import zipfile
from collections import defaultdict

from completion_native_preflight import snapshot,nonsymlink,flat_resources,checked_rows,CheckError
from completion_active_pack import active_inventory

HELPER_LIMIT=80_000_000
LOCAL_ONLY_COUNT=157
LOCAL_ONLY_BYTES=103_174_495

def require(ok,detail):
    if not ok: raise ValueError(detail)

def read(row,path):
    return snapshot(path, maximum=HELPER_LIMIT, size=row["bytes"], sha256=row["sha256"], keep=True)["data"]

def key(row):
    return row["bytes"],row["sha256"]

def index(rows):
    return {r["name"]:r for r in checked_rows(rows)}

def write_new(path,raw):
    with os.fdopen(os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600),"wb") as file:
        file.write(raw)

def resolve_available(rows,direct,allowed_package_rows):
    """Plan names by authenticated identity; any alias must share size and SHA."""
    expected=index(rows)
    target_keys=defaultdict(list)
    for r in rows:
        target_keys[key(r)].append(r["name"])
    found={}
    for path,manifest in [*allowed_package_rows,*[(p,rows) for p in direct]]:
        root=nonsymlink(Path(path).absolute())
        require(root.is_dir(),"Resource source is not a directory")
        for r in checked_rows(manifest):
            wanted=target_keys.get(key(r),())
            if not wanted or all(n in found for n in wanted):continue
            f=root/r["name"]
            if not f.exists():continue
            try:
                read(r,f)
            except CheckError:
                continue
            for n in wanted:
                if n not in found:found[n]=(f,expected[n])
    return found

def stage_new(root,destination,direct,allowed_package_rows):
    """Re-read all selected files, then rename a fully verified sibling onto the App input path."""
    rows,digest=active_inventory(root)
    dst=Path(destination).absolute()
    nonsymlink(dst.parent)
    require(not dst.exists() and not dst.is_symlink() and dst.name=="FighterPrivate","Unsafe or existing staging destination")
    hits=resolve_available(rows,direct,allowed_package_rows)
    require(len(hits)==len(rows),f"Active resource closure incomplete: {len(hits)}/{len(rows)}")
    with tempfile.TemporaryDirectory(dir=dst.parent,prefix=".fighter-stage-") as t:
        d=Path(t)/dst.name;d.mkdir(mode=0o700)
        for n,(f,r) in hits.items():
            write_new(d/n,read(r,f))
        audited=flat_resources(d,rows)
        require(not dst.exists() and not dst.is_symlink(),"Stage occupied")
        d.rename(dst)
    return dict(stagedFiles=len(rows),compiledContentSHA256=digest,verifiedBytes=sum(r["bytes"] for r in rows),
                installed=False,published=False)

def make_local_archive(destination,rows,sources):
    """Write deterministic local ZIP after rehashing; output mode 0600."""
    by=index(rows)
    require(set(sources)==set(by),"Local proof source closure differs")
    path=Path(destination).absolute()
    nonsymlink(path.parent)
    with os.fdopen(os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600),"wb") as file:
        with zipfile.ZipFile(file,"w",compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
            for n in sorted(by):
                info=zipfile.ZipInfo(n,date_time=(1980,1,1,0,0,0));info.external_attr=(stat.S_IFREG|0o600)<<16
                z.writestr(info,read(by[n],Path(sources[n])),compress_type=zipfile.ZIP_DEFLATED,compresslevel=6)
    with path.open("rb") as file:
        return hashlib.file_digest(file,"sha256").hexdigest()

def extract_local_archive(path,output,rows):
    """Application-scope ZIP member checks and exact content pins, no extractall."""
    expected=index(rows)
    target=Path(output)
    require(not target.exists() and not target.is_symlink(),"Local extraction target exists")
    with zipfile.ZipFile(nonsymlink(Path(path).absolute()),"r") as z:
        members=z.infolist()
        require(len(members)==len(expected) and {i.filename for i in members}==set(expected),"Local ZIP closure differs")
        with tempfile.TemporaryDirectory(dir=target.parent,prefix=".local-verified-") as temp:
            d=Path(temp)/"validated";d.mkdir(mode=0o700)
            for i in members:
                r=expected[i.filename]
                require(not i.is_dir() and stat.S_IFMT(i.external_attr>>16)==stat.S_IFREG and
                        not (i.flag_bits&1) and i.compress_type==zipfile.ZIP_DEFLATED and i.file_size==r["bytes"],"Invalid local ZIP member")
                with z.open(i) as f:raw=f.read(r["bytes"]+1)
                require(len(raw)==r["bytes"] and hashlib.sha256(raw).hexdigest()==r["sha256"],"Local ZIP resource identity differs")
                write_new(d/i.filename,raw)
            flat_resources(d,rows)
            d.rename(target)
    return len(rows)
