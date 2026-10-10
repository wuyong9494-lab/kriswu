#!/usr/bin/env python3
"""仿值班网站的测试服务器（只用于 CI 测试，数据都是虚构的）。

GET  /                       单页应用（index.html），手机版 / 电脑版按屏幕宽度、触摸、浏览器标识区分
POST /api/login              {"username","password"} → {"token"}
GET  /api/mine?start=&end=   我的分工（需要登录）
GET  /api/duty?start=&end=   全员排班（需要登录）
GET  /api/expected?date=     测试用：某天我的分工和全员排班（不需要登录）
"""
import json
import sys
from datetime import date, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

PEOPLE = ["张三", "李四", "王五", "赵六", "钱七", "孙八", "周九", "吴十", "郑一"]
POSTS = ["遥测", "调度", "组A", "组B", "组C", "组D", "组E", "值班交班前", "休息"]
ME = "张三"
USER, PASSWORD, TOKEN = "zhangsan", "pw123", "tok-123"
ROOT = Path(__file__).parent


def roster(day):
    """某天每个人的岗位：按日期轮转。"""
    n = (day - date(2026, 1, 1)).days
    return {PEOPLE[(i + n) % len(PEOPLE)]: post for i, post in enumerate(POSTS)}


def days(q):
    start = date.fromisoformat(q["start"][0])
    end = date.fromisoformat(q["end"][0])
    d = start
    while d <= end:
        yield d
        d += timedelta(days=1)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stderr.write("mock: " + fmt % args + "\n")

    def send(self, code, body, ctype="application/json; charset=utf-8"):
        data = body.encode() if isinstance(body, str) else json.dumps(body, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def authed(self):
        return self.headers.get("Authorization") == "Bearer " + TOKEN

    def do_POST(self):
        if urlparse(self.path).path == "/api/login":
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
            if body.get("username") == USER and body.get("password") == PASSWORD:
                return self.send(200, {"code": 0, "token": TOKEN})
            return self.send(200, {"code": 1, "msg": "用户名或密码错误"})
        self.send(404, {"code": 404})

    def do_GET(self):
        url = urlparse(self.path)
        q = parse_qs(url.query)
        if url.path in ("/", "/index.html"):
            return self.send(200, (ROOT / "index.html").read_text(encoding="utf-8"), "text/html; charset=utf-8")
        if url.path == "/api/expected":
            day = date.fromisoformat(q["date"][0])
            r = roster(day)
            return self.send(200, {"mine": r[ME], "roster": r})
        if url.path in ("/api/mine", "/api/duty"):
            if not self.authed():
                return self.send(401, {"code": 401, "msg": "未登录"})
            rows = []
            for d in days(q):
                r = roster(d)
                if url.path == "/api/mine":
                    post = r[ME]
                    rows.append({"dutyDate": d.isoformat(), "groupName": "" if post == "休息" else post})
                else:
                    rows += [{"dutyDate": d.isoformat(), "userName": name, "postName": post, "times": 3}
                             for name, post in r.items()]
            return self.send(200, {"code": 0, "data": rows})
        self.send(404, {"code": 404})


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
