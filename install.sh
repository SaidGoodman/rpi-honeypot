#!/bin/bash
# Установка сетевой ловушки на Raspberry Pi OS.
#
# Запуск из папки репозитория (нужен интернет):
#   sudo ./install.sh
#
# Каждый шаг этого скрипта можно выполнить руками: см. README.md,
# раздел «Что делает install.sh». Скрипт можно запускать повторно.
set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите через sudo: sudo ./install.sh"
    exit 1
fi

REPO="$(cd "$(dirname "$0")" && pwd)"
USER_NAME="${SUDO_USER:-}"   # обычный пользователь, который вызвал sudo
USER_HOME=""
if [ -n "$USER_NAME" ]; then
    USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
fi

step() { echo; echo "=== $1 ==="; }


step "1/7 Пакеты"
# iptables (с бинарником iptables-legacy) и rsyslog нужны модулю portscan:
# он добавляет правила iptables и читает пойманные пакеты из /var/log/kern.log.
apt-get update
apt-get install -y python3-venv python3-dev build-essential libssl-dev libffi-dev \
    libpcap-dev iptables rsyslog python3-flask curl
systemctl enable --now rsyslog
touch /var/log/kern.log


step "2/7 OpenCanary в виртуальном окружении /opt/opencanary/venv"
python3 -m venv /opt/opencanary/venv
/opt/opencanary/venv/bin/pip install --upgrade pip
/opt/opencanary/venv/bin/pip install opencanary


step "3/7 Конфиг ловушки"
# Конфиг читает root, поэтому писать в него может только root.
install -D -m 600 -o root -g root "$REPO/opencanary/opencanary.conf" /etc/opencanaryd/opencanary.conf
touch /var/log/opencanary.log
chmod 644 /var/log/opencanary.log   # страница мониторинга должна его читать


step "4/7 Страница мониторинга в /opt/rpi-honeypot/dashboard"
mkdir -p /opt/rpi-honeypot
rm -rf /opt/rpi-honeypot/dashboard
cp -r "$REPO/dashboard" /opt/rpi-honeypot/
chmod -R a+rX /opt/rpi-honeypot


step "5/7 Настоящий SSH на порт 2222"
install -m 644 "$REPO/system/sshd-honeypot.conf" /etc/ssh/sshd_config.d/10-honeypot.conf
if [ -z "$USER_HOME" ] || [ ! -s "$USER_HOME/.ssh/authorized_keys" ]; then
    # Ключа нет: если запретить вход по паролю, доступ по SSH пропадёт совсем.
    echo "ВНИМАНИЕ: в ~/.ssh/authorized_keys нет ключа. Вход по паролю пока оставлен."
    echo "Добавьте ключ (ssh-copy-id -p 2222 ...) и запустите install.sh ещё раз."
    sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' \
        /etc/ssh/sshd_config.d/10-honeypot.conf
fi
sshd -t   # проверка конфига: при ошибке скрипт остановится и SSH не сломается
# Если SSH запускается через ssh.socket, порт берётся из сокета, а не из конфига.
systemctl disable --now ssh.socket >/dev/null 2>&1 || true
systemctl enable ssh.service
systemctl restart ssh.service


step "6/7 Службы systemd"
install -m 644 "$REPO/system/opencanary.service" /etc/systemd/system/opencanary.service
install -m 644 "$REPO/system/dashboard.service" /etc/systemd/system/dashboard.service
systemctl daemon-reload
systemctl enable opencanary.service dashboard.service
systemctl restart opencanary.service dashboard.service


step "7/7 Режим киоска"
if command -v labwc >/dev/null && [ -n "$USER_HOME" ]; then
    AUTOSTART="$USER_HOME/.config/labwc/autostart"
    sudo -u "$USER_NAME" mkdir -p "$USER_HOME/.config/labwc"
    # Свой autostart заменяет системный, поэтому сначала копируем системный:
    # иначе пропадут панель задач и рабочий стол.
    if [ ! -f "$AUTOSTART" ] && [ -f /etc/xdg/labwc/autostart ]; then
        cp /etc/xdg/labwc/autostart "$AUTOSTART"
    fi
    if ! grep -qs "localhost:5000" "$AUTOSTART"; then
        cat "$REPO/system/labwc-autostart" >> "$AUTOSTART"
    fi
    chown "$USER_NAME:" "$AUTOSTART"
    # Автоматический вход в рабочий стол после включения
    if command -v raspi-config >/dev/null; then
        raspi-config nonint do_boot_behaviour B4
    fi
    echo "Киоск включён: после перезагрузки страница откроется на весь экран."
else
    echo "Рабочий стол labwc не найден, шаг пропущен (для Raspberry Pi OS Lite это нормально)."
fi


step "Готово"
sleep 3
echo "opencanary: $(systemctl is-active opencanary.service)"
echo "dashboard:  $(systemctl is-active dashboard.service)"
for ip in $(hostname -I); do
    echo "Страница мониторинга: http://$ip:5000"
done
echo "Настоящий SSH теперь на порту 2222: ssh -p 2222 $USER_NAME@<ip>"
echo "Точка доступа Wi-Fi (по желанию): cp config.env.example config.env && sudo ./system/hotspot.sh on"
