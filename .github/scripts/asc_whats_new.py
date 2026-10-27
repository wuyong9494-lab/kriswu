#!/usr/bin/env python3
"""把「这版改了什么」写进 TestFlight 的「测试内容」：装之前在 TestFlight App 里就能看到。

等这次上传的 build（版本号 = build 号）在 App Store Connect 里出现，再给它写测试说明。
说明来自上次写过说明以后的提交里以「更新说明：」开头的行（没有就用提交标题）。

用法：asc_whats_new.py <build 号> <说明文件>
环境变量：ASC_KEY_PATH、ASC_KEY_ID、ASC_ISSUER_ID、BUNDLE_ID
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt  # pyjwt

API = "https://api.appstoreconnect.apple.com/v1"


def token():
    with open(os.environ["ASC_KEY_PATH"]) as f:
        key = f.read()
    now = int(time.time())
    payload = {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method,
                                 headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        raw = r.read()
        return json.loads(raw) if raw else {}


def main():
    build_number, notes_path = sys.argv[1], sys.argv[2]
    with open(notes_path, encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]
    if not lines:
        print("没有要写的说明")
        return
    text = f"build {build_number} 改了什么：\n" + "\n".join("• " + line for line in lines)
    text = text[:3900]

    apps = call("GET", f"/apps?filter[bundleId]={os.environ['BUNDLE_ID']}").get("data", [])
    if not apps:
        print("::warning::App Store Connect 里找不到这个 App，跳过测试说明")
        return
    app_id = apps[0]["id"]

    # 上传后要等苹果处理一会儿才查得到这个 build
    build = None
    for _ in range(60):
        found = call("GET", f"/builds?filter[app]={app_id}&filter[version]={build_number}&limit=1").get("data", [])
        if found:
            build = found[0]
            break
        time.sleep(30)
    if not build:
        print("::warning::30 分钟内没查到这个 build，测试说明没写上")
        return

    localizations = call("GET", f"/builds/{build['id']}/betaBuildLocalizations").get("data", [])
    if localizations:
        for loc in localizations:
            call("PATCH", f"/betaBuildLocalizations/{loc['id']}",
                 {"data": {"type": "betaBuildLocalizations", "id": loc["id"], "attributes": {"whatsNew": text}}})
            print(f"已写入测试说明（{loc['attributes'].get('locale')}）")
        return
    for locale in ("zh-Hans", "en-US"):
        try:
            call("POST", "/betaBuildLocalizations",
                 {"data": {"type": "betaBuildLocalizations", "attributes": {"locale": locale, "whatsNew": text},
                           "relationships": {"build": {"data": {"type": "builds", "id": build["id"]}}}}})
            print(f"已写入测试说明（{locale}）")
        except urllib.error.HTTPError as e:
            print(f"{locale} 没写上：{e.code} {e.read()[:300]!r}")
    print(text)


if __name__ == "__main__":
    main()
