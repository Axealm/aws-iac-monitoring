#!/usr/bin/env python3
"""おみくじ API。

監視の対象にするための小さな Web API。標準ライブラリだけで動く。

  GET /omikuji  おみくじを1つ引いて JSON で返す
  GET /healthz  生存確認。{"status": "ok"} を返す

nginx の後ろで 127.0.0.1:8000 で待ち受ける想定。
"""

import json
import os
import random
import socket
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# 結果と重み（出やすさ）。重みの合計は 100。
FORTUNES = [
    ("大吉", 15),
    ("中吉", 20),
    ("小吉", 20),
    ("吉", 20),
    ("末吉", 15),
    ("凶", 8),
    ("大凶", 2),
]

MESSAGES = {
    "大吉": "デプロイは一発で通るでしょう。",
    "中吉": "plan の差分は想定どおりでしょう。",
    "小吉": "小さな警告は早めに直すと吉。",
    "吉": "ログを読めば道は開けます。",
    "末吉": "タイムアウトの値を見直すと良いでしょう。",
    "凶": "本番で試す前に、検証環境で確かめましょう。",
    "大凶": "今日の apply は明日に回すのが無難です。",
}


def draw(rng=random):
    """おみくじを1つ引いて、結果の文字列を返す。"""
    names = [name for name, _ in FORTUNES]
    weights = [weight for _, weight in FORTUNES]
    return rng.choices(names, weights=weights, k=1)[0]


def build_omikuji(rng=random, now=None):
    """/omikuji が返す内容を辞書で作る。"""
    result = draw(rng)
    now = now or datetime.now(timezone.utc)
    return {
        "result": result,
        "message": MESSAGES[result],
        "host": socket.gethostname(),
        "time": now.isoformat(timespec="seconds"),
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "omikuji/1.0"

    def _send_json(self, status, body):
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):  # noqa: N802  （http.server の決まった名前）
        path = self.path.split("?", 1)[0]
        if path == "/omikuji":
            self._send_json(200, build_omikuji())
        elif path == "/healthz":
            self._send_json(200, {"status": "ok"})
        else:
            self._send_json(404, {"error": "not found"})

    def log_message(self, fmt, *args):
        # 標準エラーに出す（systemd の journal に入る）
        print("%s - %s" % (self.address_string(), fmt % args), flush=True)


def main():
    host = os.environ.get("OMIKUJI_HOST", "127.0.0.1")
    port = int(os.environ.get("OMIKUJI_PORT", "8000"))
    server = ThreadingHTTPServer((host, port), Handler)
    print("omikuji API listening on %s:%d" % (host, port), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
