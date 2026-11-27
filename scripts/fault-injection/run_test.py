#!/usr/bin/env python3
"""障害注入テストを1つ実行し、検知と解消の時刻を記録する。

  bash scripts/fault-injection/run.sh nginx-stop
  bash scripts/fault-injection/run.sh chronyd-stop
  bash scripts/fault-injection/run.sh omikuji-stop
  bash scripts/fault-injection/run.sh cpu-load

流れ:
  1. 発生中の障害が 0 件であることを確かめる
  2. web サーバーに障害を注入する（SSM 経由）
  3. 期待するアラートが Zabbix（と、CPU の場合は CloudWatch）に出るまで待つ
  4. 復旧させる
  5. アラートが解消するまで待つ
  6. 時刻の記録を docs/evidence/<シナリオ名>.json に保存する

注入と復旧のコマンドは、下の SCENARIOS に書いてあるものだけを実行する。
"""

import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "scripts", "dev"))

from zabbix_api import Zabbix  # noqa: E402

TARGET = "web"
CPU_ALARM = "aws-iac-monitoring-dev-web-cpu-high"

SCENARIOS = {
    "nginx-stop": {
        "title": "nginx を止める",
        "inject": "systemctl stop nginx",
        "recover": "systemctl start nginx",
        "expect": ["nginx is not running", "HTTP check of /omikuji failed"],
        "not_expect": ["omikuji API is not running"],
        "detect_timeout": 300,
        "cloudwatch": False,
    },
    "chronyd-stop": {
        "title": "chronyd を止める",
        "inject": "systemctl stop chronyd",
        "recover": "systemctl start chronyd",
        "expect": ["chronyd is not running"],
        "not_expect": [],
        "detect_timeout": 300,
        "cloudwatch": False,
    },
    "omikuji-stop": {
        "title": "おみくじ API を止める（nginx は動かしたまま）",
        "inject": "systemctl stop omikuji",
        "recover": "systemctl start omikuji",
        "expect": ["omikuji API is not running", "/omikuji returns 502", "HTTP check of /omikuji failed"],
        "not_expect": ["nginx is not running"],
        "detect_timeout": 300,
        "cloudwatch": False,
    },
    "cpu-load": {
        "title": "CPU に負荷をかける",
        # CPU の数だけ空回りのループを動かす。止め忘れても 20 分で自動的に終わる。
        "inject": ("systemd-run --unit=fault-cpu-load --collect --property=RuntimeMaxSec=1200 "
                   "bash -c 'for i in $(seq $(nproc)); do (while :; do :; done) & done; wait'"),
        "recover": "systemctl stop fault-cpu-load",
        "expect": ["CPU utilization is above 80%"],
        "not_expect": [],
        "detect_timeout": 600,
        "cloudwatch": True,
        "cloudwatch_timeout": 1080,
    },
}


def now():
    return time.time()


def iso(epoch):
    return datetime.fromtimestamp(epoch, timezone.utc).astimezone().isoformat(timespec="seconds")


def log(message):
    print("%s  %s" % (time.strftime("%H:%M:%S"), message), flush=True)


def ssm(command):
    """web サーバーでコマンドを実行する。成功したら True。"""
    result = subprocess.run(
        ["bash", os.path.join(ROOT, "scripts", "dev", "ssm-run.sh"), TARGET],
        input=command, text=True, capture_output=True,
    )
    return result.returncode == 0, (result.stdout + result.stderr).strip()


def alarm_state(name):
    result = subprocess.run(
        ["aws", "cloudwatch", "describe-alarms", "--alarm-names", name,
         "--query", "MetricAlarms[0].StateValue", "--output", "text"],
        capture_output=True, text=True,
    )
    return result.stdout.strip()


def matching(problems, needle):
    return [p for p in problems if needle in p["name"]]


def main():
    name = sys.argv[1] if len(sys.argv) > 1 else ""
    if name not in SCENARIOS:
        print("使い方: run_test.py [%s]" % " | ".join(SCENARIOS), file=sys.stderr)
        return 2
    sc = SCENARIOS[name]
    record = {"scenario": name, "title": sc["title"], "target": TARGET, "expect": sc["expect"],
              "detected": {}, "resolved": {}, "unexpected": [], "result": "FAIL"}

    z = Zabbix().login()
    try:
        # 1. 事前の状態
        before = z.problems()
        if before:
            log("発生中の障害が残っているので中止します: %s" % [p["name"] for p in before])
            return 1
        if sc["cloudwatch"]:
            record["cloudwatch_alarm"] = CPU_ALARM
            record["cloudwatch_before"] = alarm_state(CPU_ALARM)
            log("CloudWatch アラームの事前の状態: %s" % record["cloudwatch_before"])
        log("事前確認: 発生中の障害は 0 件")

        # 2. 注入
        log("注入: %s" % sc["inject"])
        ok, out = ssm(sc["inject"])
        t_inject = now()
        record["injected_at"] = iso(t_inject)
        if not ok:
            log("注入に失敗しました: %s" % out)
            return 1

        # 3. 検知を待つ
        pending = list(sc["expect"])
        deadline = t_inject + sc["detect_timeout"]
        while pending and now() < deadline:
            problems = z.problems()
            for needle in list(pending):
                hit = matching(problems, needle)
                if hit:
                    clock = hit[0]["clock"]
                    record["detected"][needle] = {
                        "event_name": hit[0]["name"], "severity": hit[0]["severity"],
                        "at": iso(clock), "seconds_after_injection": round(clock - t_inject),
                    }
                    log("Zabbix が検知: %s（注入から %d 秒）" % (hit[0]["name"], clock - t_inject))
                    pending.remove(needle)
            if pending:
                time.sleep(5)
        if pending:
            log("時間内に検知されなかったもの: %s" % pending)

        # 出てはいけないアラートが出ていないか
        problems = z.problems()
        for needle in sc["not_expect"]:
            if matching(problems, needle):
                record["unexpected"].append(needle)
                log("想定外のアラート: %s" % needle)
        record["problems_while_injected"] = [p["name"] for p in problems]

        if sc["cloudwatch"]:
            log("CloudWatch アラームが ALARM になるのを待ちます（5分間隔の値を使うので時間がかかります）")
            cw_deadline = t_inject + sc["cloudwatch_timeout"]
            state = alarm_state(CPU_ALARM)
            while state != "ALARM" and now() < cw_deadline:
                time.sleep(20)
                state = alarm_state(CPU_ALARM)
            if state == "ALARM":
                record["cloudwatch_alarm_at"] = iso(now())
                record["cloudwatch_seconds_after_injection"] = round(now() - t_inject)
                log("CloudWatch が検知: ALARM（注入から約 %d 秒）" % (now() - t_inject))
            else:
                log("CloudWatch アラームは時間内に ALARM になりませんでした（状態: %s）" % state)
            record["cloudwatch_state_while_injected"] = state

        # 4. 復旧
        log("復旧: %s" % sc["recover"])
        ok, out = ssm(sc["recover"])
        t_recover = now()
        record["recovered_at"] = iso(t_recover)
        if not ok:
            log("復旧に失敗しました。手で復旧してください: %s" % out)
            return 1

        # 5. 解消を待つ
        deadline = t_recover + 600
        remaining = list(record["detected"])
        while remaining and now() < deadline:
            problems = z.problems()
            for needle in list(remaining):
                if not matching(problems, needle):
                    record["resolved"][needle] = {
                        "at": iso(now()), "seconds_after_recovery": round(now() - t_recover)}
                    log("Zabbix で解消: %s（復旧から約 %d 秒）" % (needle, now() - t_recover))
                    remaining.remove(needle)
            if remaining:
                time.sleep(5)
        if remaining:
            log("時間内に解消しなかったもの: %s" % remaining)

        if sc["cloudwatch"] and record.get("cloudwatch_state_while_injected") == "ALARM":
            log("CloudWatch アラームが OK に戻るのを待ちます")
            cw_deadline = t_recover + 900
            state = alarm_state(CPU_ALARM)
            while state != "OK" and now() < cw_deadline:
                time.sleep(20)
                state = alarm_state(CPU_ALARM)
            record["cloudwatch_state_after_recovery"] = state
            if state == "OK":
                record["cloudwatch_ok_at"] = iso(now())
                record["cloudwatch_seconds_after_recovery"] = round(now() - t_recover)
                log("CloudWatch で解消: OK（復旧から約 %d 秒）" % (now() - t_recover))

        after = z.problems()
        record["problems_after"] = [p["name"] for p in after]
        all_detected = len(record["detected"]) == len(sc["expect"])
        all_resolved = len(record["resolved"]) == len(record["detected"]) and not after
        cw_ok = (not sc["cloudwatch"]) or (
            record.get("cloudwatch_state_while_injected") == "ALARM"
            and record.get("cloudwatch_state_after_recovery") == "OK")
        if all_detected and all_resolved and cw_ok and not record["unexpected"]:
            record["result"] = "PASS"
    finally:
        z.logout()

    out_dir = os.path.join(ROOT, "docs", "evidence")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, name + ".json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(record, f, ensure_ascii=False, indent=2)
        f.write("\n")
    log("結果: %s（記録: docs/evidence/%s.json）" % (record["result"], name))
    return 0 if record["result"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
