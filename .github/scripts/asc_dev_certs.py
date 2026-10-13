#!/usr/bin/env python3
"""云端打包时 xcodebuild 每次都会新建一张「Apple Development」证书，攒到苹果的上限后就打不了包。
这个脚本在打包前后吊销 CI 自己建的开发证书（名字里带 "Created via API"，或序列号和这台云端电脑钥匙串里的一致）。
SideStore 等别的工具建的证书不动。

用法：asc_dev_certs.py cleanup [钥匙串里证书的序列号 ...]
环境变量：ASC_KEY_PATH、ASC_KEY_ID、ASC_ISSUER_ID
"""
import json
import os
import sys
import time
import urllib.request

import jwt  # pyjwt

API = "https://api.appstoreconnect.apple.com/v1"


def token():
    with open(os.environ["ASC_KEY_PATH"]) as f:
        key = f.read()
    now = int(time.time())
    payload = {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method, path):
    req = urllib.request.Request(API + path, method=method, headers={"Authorization": "Bearer " + token()})
    with urllib.request.urlopen(req, timeout=30) as r:
        body = r.read()
        return json.loads(body) if body else {}


def main():
    serials = {s.upper().lstrip("0") for s in sys.argv[2:]}
    certs = call("GET", "/certificates?filter[certificateType]=DEVELOPMENT,IOS_DEVELOPMENT&limit=200").get("data", [])
    print(f"开发证书 {len(certs)} 张：")
    for c in certs:
        a = c["attributes"]
        name = a.get("name") or ""
        display = a.get("displayName") or ""
        serial = (a.get("serialNumber") or "").upper().lstrip("0")
        mine = "Created via API" in name or "Created via API" in display or serial in serials
        print(f"  {'吊销' if mine else '保留'}  {display or name}  到期 {a.get('expirationDate', '')[:10]}")
        if mine:
            try:
                call("DELETE", f"/certificates/{c['id']}")
            except Exception as e:  # 吊销失败不影响打包
                print(f"    吊销失败：{e}")


if __name__ == "__main__":
    main()
