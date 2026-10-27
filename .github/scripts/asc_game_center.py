#!/usr/bin/env python3
"""在 App Store Connect 里给这个 App 打开 Game Center（小游戏的远程对战、轮流下要用）。已经开了就什么都不做。

以后不想要了，在 App Store Connect 网页上这个 App 的 Game Center 那里关掉就行。

用法：asc_game_center.py
环境变量：ASC_KEY_PATH、ASC_KEY_ID、ASC_ISSUER_ID、BUNDLE_ID
"""
import os
import sys
import urllib.error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asc_whats_new import call  # noqa: E402


def main():
    apps = call("GET", f"/apps?filter[bundleId]={os.environ['BUNDLE_ID']}").get("data", [])
    if not apps:
        print("::warning::App Store Connect 里找不到这个 App，没打开 Game Center")
        return
    app_id = apps[0]["id"]
    try:
        detail = call("GET", f"/apps/{app_id}/gameCenterDetail").get("data")
    except urllib.error.HTTPError as e:
        detail = None
        if e.code != 404:
            print(f"::warning::查 Game Center 设置失败（{e.code}）：{e.read().decode(errors='replace')[:300]}")
            return
    if detail:
        print("Game Center 已经打开了")
        return
    try:
        call("POST", "/gameCenterDetails",
             {"data": {"type": "gameCenterDetails",
                       "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
        print("已在 App Store Connect 里打开 Game Center")
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")[:500]
        if e.code == 409:
            print("Game Center 已经打开了")
        else:
            print(f"::warning::打开 Game Center 失败（{e.code}）：{body}。可以在 App Store Connect 网页上这个 App 的「Game Center」里手动打开")


if __name__ == "__main__":
    main()
