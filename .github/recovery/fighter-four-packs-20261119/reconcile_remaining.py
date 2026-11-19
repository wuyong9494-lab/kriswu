"""Verify pinned ciphertext and resource manifests without an asset key."""
import base64
import hashlib
import json
from pathlib import Path
import re
import stat
import subprocess

CANDIDATE = "73a0cf1ef86e35f40ed99ed9cc0ec467f10f4826"
RECEIPT_RUN = 44460243590
RECEIPT_JOB = 135344980371
RECEIPT_HEAD = "87fe4bf5bd4724dd0c888671f3bb91caefed8379"
PRIVATE = Path(".github/private")
INVENTORY = PRIVATE / "fighter-completion-20261117/completion-compiled-inventory.json"
INVENTORY_SHA = "4c8984617203134c7bf3328f3a6e41520bb823063f94d37013cae11839bc97a1"


def must(ok, reason):
    if not ok:
        raise ValueError(reason)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def read(path, limit, size=None, digest=None):
    p = Path(path).absolute()
    st = p.lstat()
    must(p.resolve(strict=True) == p and stat.S_ISREG(st.st_mode) and 0 < st.st_size <= limit,
         f"Expected a bounded regular file: {p.name}")
    raw = p.read_bytes()
    must(len(raw) == st.st_size and (size is None or size == len(raw))
         and (digest is None or digest == sha(raw)), f"Bytes differ: {p.name}")
    return raw


def pinned(repo, rel, limit=200_000):
    raw = read(repo / rel, limit)
    p = subprocess.run(["git","-C",str(repo),"show",f"{CANDIDATE}:{rel}"],
                       capture_output=True, check=True)
    must(raw == p.stdout, f"Tracked checkpoint differs: {rel}")
    return raw


def identity(r):
    return r["bytes"], r["sha256"]


def rows_by_name(rows, field):
    result = {}
    for row in rows:
        n = row[field]
        sz, digest = identity(row)
        must(re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]*", n) and n not in result
             and isinstance(sz, int) and 0 < sz < 80_000_000 and re.fullmatch(r"[a-f0-9]{64}", digest),
             "Bad resource identity")
        result[n] = row
    return result


def packaged_parts(folder, row, prefix):
    pieces = row["parts"]
    must(0 < len(pieces) <= 128, "Wrong shard count")
    h = hashlib.sha256()
    byte_count = 0
    for i, piece in enumerate(pieces):
        name = prefix + f"{i:03}"
        must(piece["file"] == name, "Unexpected shard path")
        raw = read(folder / name, 512 * 1024, *identity(piece))
        h.update(raw)
        byte_count += len(raw)
    must(h.hexdigest() == row["cipher_sha256"], "Ciphertext collection differs")
    return len(pieces), byte_count


def checked_packages(repo):
    result, sources = {}, {}
    for key, filename in [("fighter-presentation","presentation-v1.enc.b64"),
                          ("fighter-source-trails","source-trails-v1.enc.b64")]:
        rel = PRIVATE / key / "manifest.json"
        raw = pinned(repo, rel)
        m = json.loads(raw)
        cipher = base64.b64decode(read(repo / rel.parent / filename, 6_000_000), validate=True)
        must(len(cipher) == m["cipherBytes"] and sha(cipher) == m["cipherSHA256"], "Ciphertext differs")
        result[key] = rows_by_name(m["files"], "file")
        sources[key] = {"cipherObjects": 1, "cipherBytes": len(cipher), "manifestSHA256":sha(raw)}
    for key in ("sf3-distinct", "sf3"):
        rel = PRIVATE / key / "manifest.json"
        raw = pinned(repo, rel)
        m = json.loads(raw)
        if key == "sf3-distinct":
            parts, size = packaged_parts(repo / rel.parent, m, "distinct.pack.enc.")
            entries = m["files"]
        else:
            entries = m["assets"]
            counts = [packaged_parts(repo / rel.parent, row, row["file"] + ".enc.") for row in entries]
            parts, size = (sum(x) for x in zip(*counts))
        result[key] = rows_by_name(entries,"file")
        sources[key] = {"cipherObjects":parts, "cipherBytes":size, "manifestSHA256":sha(raw)}
    return result,sources
