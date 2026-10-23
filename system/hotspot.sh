#!/bin/bash
# Точка доступа Wi-Fi на Raspberry Pi через NetworkManager.
# Pi раздаёт свою сеть, к которой подключается ноутбук атакующего,
# и сама выдаёт адреса (DHCP). Интернет в этой сети не нужен.
#
# Использование (из папки репозитория):
#   sudo ./system/hotspot.sh on    - включить точку доступа
#   sudo ./system/hotspot.sh off   - выключить и вернуться к обычному Wi-Fi
set -e

cd "$(dirname "$0")/.."
if [ ! -f config.env ]; then
    echo "Нет файла config.env. Создайте его: cp config.env.example config.env"
    exit 1
fi
source ./config.env   # WIFI_SSID, WIFI_PASSWORD, AP_ADDRESS

CON=honeypot-ap

case "$1" in
    on)
        if [ ${#WIFI_PASSWORD} -lt 8 ]; then
            echo "Пароль Wi-Fi должен быть не короче 8 символов"
            exit 1
        fi
        nmcli connection delete "$CON" >/dev/null 2>&1 || true
        nmcli connection add type wifi ifname wlan0 con-name "$CON" ssid "$WIFI_SSID" \
            connection.autoconnect yes connection.autoconnect-priority 100 \
            802-11-wireless.mode ap 802-11-wireless.band bg \
            ipv4.method shared ipv4.addresses "$AP_ADDRESS" ipv6.method disabled \
            wifi-sec.key-mgmt wpa-psk wifi-sec.proto rsn wifi-sec.psk "$WIFI_PASSWORD"
        nmcli connection up "$CON"
        echo "Точка доступа «$WIFI_SSID» включена, адрес Pi: ${AP_ADDRESS%/*}"
        ;;
    off)
        nmcli connection down "$CON" || true
        nmcli connection modify "$CON" connection.autoconnect no || true
        echo "Точка доступа выключена"
        ;;
    *)
        echo "Использование: sudo $0 on|off"
        exit 1
        ;;
esac
