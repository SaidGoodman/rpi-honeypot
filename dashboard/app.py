"""Страница мониторинга сетевой ловушки OpenCanary.

OpenCanary пишет каждое событие отдельной строкой JSON в лог-файл.
Этот скрипт читает лог, находит атаки по простым правилам и показывает
всё на веб-странице. Базы данных нет: при каждом открытии страницы лог
читается заново.

Запуск:  python3 app.py           (лог /var/log/opencanary.log)
Проверка без Pi:  CANARY_LOG=sample.log python3 app.py
"""
import json
import os
from collections import Counter, defaultdict
from datetime import datetime, timedelta

from flask import Flask, render_template

LOG_FILE = os.environ.get("CANARY_LOG", "/var/log/opencanary.log")
PORT = 5000
LAST_EVENTS = 100  # сколько последних событий показывать в таблице

# Правила обнаружения атак
WINDOW = timedelta(seconds=60)  # окно времени, в котором считаются события
BRUTE_LOGINS = 5                # попыток входа с одного IP за окно -> подбор пароля
SCAN_PORTS = 10                 # разных портов с одного IP за окно -> сканирование

# Коды logtype из исходников OpenCanary (файл opencanary/logger.py)
EVENT_NAMES = {
    2000: "FTP: попытка входа",
    2001: "FTP: начало входа",
    3000: "HTTP: открыта страница",
    3001: "HTTP: попытка входа",
    4000: "SSH: подключение",
    4001: "SSH: версия клиента",
    4002: "SSH: попытка входа",
    5001: "Порт: SYN-пакет",
    5002: "Порт: nmap OS",
    5003: "Порт: nmap NULL",
    5004: "Порт: nmap XMAS",
    5005: "Порт: nmap FIN",
    6001: "Telnet: попытка входа",
    6002: "Telnet: подключение",
}
LOGIN_TYPES = {2000, 3001, 4002, 6001}       # попытки входа с логином и паролем
SCAN_TYPES = {5001, 5002, 5003, 5004, 5005}  # пакеты, пойманные правилами iptables
NMAP_PROBES = {5002, 5003, 5004, 5005}       # такие пакеты шлёт только сканер

app = Flask(__name__)


def read_events():
    """Читает лог и возвращает список событий в порядке их записи."""
    events = []
    if not os.path.exists(LOG_FILE):
        return events
    with open(LOG_FILE, encoding="utf-8") as f:
        for line in f:
            try:
                event = json.loads(line)
                event["time"] = datetime.strptime(event["local_time_adjusted"],
                                                  "%Y-%m-%d %H:%M:%S.%f")
            except (ValueError, KeyError):
                continue  # битая или недописанная строка
            if event.get("logtype", 0) >= 2000:  # 1000-1006 - служебные сообщения
                events.append(event)
    return events


def find_attacks(events):
    """Возвращает словарь {IP: [виды атак]} по правилам из начала файла."""
    by_ip = defaultdict(list)
    for event in events:
        by_ip[event["src_host"]].append(event)

    attacks = {}
    for ip, items in by_ip.items():
        found = set()
        start = 0
        for end, event in enumerate(items):
            # сдвигаем начало окна, чтобы в нём остались только последние 60 секунд
            while items[start]["time"] < event["time"] - WINDOW:
                start += 1
            window = items[start:end + 1]
            logins = [e for e in window if e["logtype"] in LOGIN_TYPES]
            ports = {e["dst_port"] for e in window if e["logtype"] in SCAN_TYPES}
            if len(logins) >= BRUTE_LOGINS:
                found.add("подбор пароля")
            if len(ports) >= SCAN_PORTS or event["logtype"] in NMAP_PROBES:
                found.add("сканирование портов")
        if found:
            attacks[ip] = sorted(found)
    return attacks


@app.route("/")
def index():
    events = read_events()
    attacks = find_attacks(events)
    logins = [e for e in events if e["logtype"] in LOGIN_TYPES]

    attackers = []
    for ip, kinds in attacks.items():
        mine = [e for e in events if e["src_host"] == ip]
        attackers.append({"ip": ip, "kinds": kinds, "count": len(mine),
                          "first": mine[0]["time"], "last": mine[-1]["time"]})

    return render_template(
        "index.html",
        events=events[-LAST_EVENTS:][::-1],  # новые события сверху
        names=EVENT_NAMES,
        attacks=attacks,
        attackers=attackers,
        total=len(events),
        unique_ips=len({e["src_host"] for e in events}),
        login_count=len(logins),
        top_users=Counter(e["logdata"].get("USERNAME") for e in logins).most_common(5),
        top_passwords=Counter(e["logdata"].get("PASSWORD") for e in logins).most_common(5),
        log_file=LOG_FILE,
        now=datetime.now(),
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=PORT)
