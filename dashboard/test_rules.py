"""Проверка правил обнаружения атак из app.py.

Запуск:  python3 test_rules.py   (или pytest, если он установлен)
"""
from datetime import datetime, timedelta

from app import find_attacks

START = datetime(2026, 10, 23, 12, 0, 0)


def event(ip, logtype, second, port=22):
    """Событие в том виде, в каком его возвращает read_events()."""
    return {"src_host": ip, "logtype": logtype, "dst_port": port,
            "time": START + timedelta(seconds=second), "logdata": {}}


def test_brute_force():
    # 5 попыток входа по SSH за 20 секунд
    events = [event("10.0.0.5", 4002, s) for s in range(0, 20, 4)]
    assert find_attacks(events) == {"10.0.0.5": ["подбор пароля"]}


def test_slow_logins_are_not_brute_force():
    # 5 попыток, но раз в 30 секунд: в любые 60 секунд попадает не больше трёх
    events = [event("10.0.0.5", 4002, s) for s in range(0, 150, 30)]
    assert find_attacks(events) == {}


def test_port_scan():
    # SYN-пакеты на 10 разных портов за секунду
    events = [event("10.0.0.7", 5001, 0, port) for port in range(1000, 1010)]
    assert find_attacks(events) == {"10.0.0.7": ["сканирование портов"]}


def test_few_ports_are_not_scan():
    events = [event("10.0.0.7", 5001, 0, port) for port in range(1000, 1009)]
    assert find_attacks(events) == {}


def test_nmap_probe_is_scan():
    # один пакет определения ОС от nmap - уже сканирование
    assert find_attacks([event("10.0.0.8", 5002, 0, 1)]) == {"10.0.0.8": ["сканирование портов"]}


def test_different_ips_are_counted_separately():
    # 5 попыток входа, но с пяти разных адресов
    events = [event(f"10.0.0.{i}", 4002, i) for i in range(5)]
    assert find_attacks(events) == {}


if __name__ == "__main__":
    tests = [f for name, f in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
        print("OK  ", test.__name__)
    print(f"Все проверки пройдены: {len(tests)}")
