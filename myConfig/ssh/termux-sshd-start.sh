#!/data/data/com.termux/files/usr/bin/bash
set -eu

if ! command -v sshd >/dev/null 2>&1 || ! command -v rsync >/dev/null 2>&1; then
  pkg install -y openssh rsync >/dev/null
fi

if [ ! -d "$HOME/storage/shared" ]; then
  termux-setup-storage
fi

if ! pgrep -x sshd >/dev/null 2>&1; then
  sshd
fi

user_name="$(whoami)"
wifi_ip="$(ip -4 addr show wlan0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1)"

if [ -z "${wifi_ip:-}" ]; then
  wifi_ip="$(ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for (i = 1; i <= NF; i++) if ($i == "src") print $(i+1)}' | head -n1)"
fi

printf '\nTermux SSH ready\n'
printf 'user: %s\n' "$user_name"
printf 'port: 8022\n'
printf 'ip:   %s\n' "${wifi_ip:-unknown}"
printf 'drop: %s\n' "$HOME/storage/shared/Download"
printf 'test: ssh -p 8022 %s@%s\n' "$user_name" "${wifi_ip:-PHONE_IP}"
