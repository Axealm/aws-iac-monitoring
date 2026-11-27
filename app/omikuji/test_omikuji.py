"""おみくじ API のテスト。標準の unittest だけで動く。

  python3 -m unittest discover -s app/omikuji -v
"""

import json
import random
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer

import omikuji


class DrawTest(unittest.TestCase):
    def test_weights_sum_to_100(self):
        self.assertEqual(sum(weight for _, weight in omikuji.FORTUNES), 100)

    def test_every_fortune_has_a_message(self):
        for name, _ in omikuji.FORTUNES:
            self.assertIn(name, omikuji.MESSAGES)

    def test_draw_returns_a_known_fortune(self):
        names = {name for name, _ in omikuji.FORTUNES}
        rng = random.Random(0)
        for _ in range(200):
            self.assertIn(omikuji.draw(rng), names)

    def test_draw_is_reproducible_with_a_seed(self):
        first = [omikuji.draw(random.Random(42)) for _ in range(3)]
        second = [omikuji.draw(random.Random(42)) for _ in range(3)]
        self.assertEqual(first, second)

    def test_build_omikuji_has_the_expected_keys(self):
        body = omikuji.build_omikuji(random.Random(1))
        self.assertEqual(set(body), {"result", "message", "host", "time"})
        self.assertEqual(body["message"], omikuji.MESSAGES[body["result"]])


class HttpTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # 空いているポートで実際にサーバーを立てて、HTTP で確かめる
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), omikuji.Handler)
        cls.base = "http://127.0.0.1:%d" % cls.server.server_address[1]
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def get(self, path):
        with urllib.request.urlopen(self.base + path, timeout=5) as res:
            return res.status, res.headers, json.loads(res.read().decode("utf-8"))

    def test_omikuji_returns_json(self):
        status, headers, body = self.get("/omikuji")
        self.assertEqual(status, 200)
        self.assertTrue(headers["Content-Type"].startswith("application/json"))
        self.assertIn(body["result"], omikuji.MESSAGES)

    def test_healthz_returns_ok(self):
        status, _, body = self.get("/healthz")
        self.assertEqual(status, 200)
        self.assertEqual(body, {"status": "ok"})

    def test_unknown_path_returns_404(self):
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            self.get("/nope")
        self.assertEqual(ctx.exception.code, 404)


if __name__ == "__main__":
    unittest.main()
