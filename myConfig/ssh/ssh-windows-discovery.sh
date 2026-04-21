#!/data/data/com.termux/files/usr/bin/bash
set -eu

PORT="${PORT:-22}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-1}"
FULL_SCAN="${FULL_SCAN:-0}"
PREFERRED_HOST="${1:-}"

get_wifi_ip() {
  ip -4 addr show wlan0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1
}

get_prefix_len() {
  ip -4 addr show wlan0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f2 | head -n1
}

ipv4_to_int() {
  local IFS=.
  local a b c d
  read -r a b c d <<EOF
$1
EOF
  echo $(( (a << 24) + (b << 16) + (c << 8) + d ))
}

int_to_ipv4() {
  local value="$1"
  echo "$(( (value >> 24) & 255 )).$(( (value >> 16) & 255 )).$(( (value >> 8) & 255 )).$(( value & 255 ))"
}

get_network_bounds() {
  local ip="$1"
  local prefix_len="$2"
  local ip_int mask host_mask network broadcast

  ip_int="$(ipv4_to_int "$ip")"
  if [ "$prefix_len" -eq 0 ]; then
    mask=0
  else
    mask=$(( (0xFFFFFFFF << (32 - prefix_len)) & 0xFFFFFFFF ))
  fi

  host_mask=$(( (~mask) & 0xFFFFFFFF ))
  network=$(( ip_int & mask ))
  broadcast=$(( network | host_mask ))

  printf '%s\n%s\n' "$network" "$broadcast"
}

is_ip_in_network() {
  local candidate="$1"
  local network="$2"
  local broadcast="$3"
  local value

  value="$(ipv4_to_int "$candidate")"
  [ "$value" -ge "$network" ] && [ "$value" -le "$broadcast" ]
}

get_nearby_ips() {
  local ip="$1"
  local network="$2"
  local broadcast="$3"
  local window="${4:-16}"
  local center start end value

  [ -n "$ip" ] || return 0

  center="$(ipv4_to_int "$ip")"
  start=$(( center - window ))
  end=$(( center + window ))

  if [ "$start" -lt $((network + 1)) ]; then
    start=$((network + 1))
  fi

  if [ "$end" -gt $((broadcast - 1)) ]; then
    end=$((broadcast - 1))
  fi

  value="$start"
  while [ "$value" -le "$end" ]; do
    int_to_ipv4 "$value"
    value=$((value + 1))
  done
}

test_port() {
  local host="$1"
  timeout "$TIMEOUT_SECONDS" sh -c "exec 3<>/dev/tcp/$host/$PORT" >/dev/null 2>&1
}

discover_arp_candidates() {
  local network="$1"
  local broadcast="$2"
  ip neigh 2>/dev/null | awk '{print $1}' | while read -r candidate; do
    if [ -n "$candidate" ] && is_ip_in_network "$candidate" "$network" "$broadcast"; then
      printf '%s\n' "$candidate"
    fi
  done | sort -u
}

scan_list() {
  while read -r candidate; do
    [ -n "$candidate" ] || continue
    if test_port "$candidate"; then
      printf '%s\n' "$candidate"
    fi
  done
}

wifi_ip="$(get_wifi_ip)"
prefix_len="$(get_prefix_len)"

if [ -z "${wifi_ip:-}" ] || [ -z "${prefix_len:-}" ]; then
  echo "Could not determine Wi-Fi IPv4 network." >&2
  exit 1
fi

network_and_broadcast="$(get_network_bounds "$wifi_ip" "$prefix_len")"
network="$(printf '%s\n' "$network_and_broadcast" | sed -n '1p')"
broadcast="$(printf '%s\n' "$network_and_broadcast" | sed -n '2p')"
network_ip="$(int_to_ipv4 "$network")"

if [ "$FULL_SCAN" = "1" ]; then
  echo "Scanning $network_ip/$prefix_len on port $PORT with ${TIMEOUT_SECONDS}s timeout"
  value=$((network + 1))
  while [ "$value" -le $((broadcast - 1)) ]; do
    int_to_ipv4 "$value"
    value=$((value + 1))
  done | scan_list
  exit 0
fi

echo "Scanning likely Windows hosts on $network_ip/$prefix_len on port $PORT with ${TIMEOUT_SECONDS}s timeout"

{
  if [ -n "$PREFERRED_HOST" ] && is_ip_in_network "$PREFERRED_HOST" "$network" "$broadcast"; then
    printf '%s\n' "$PREFERRED_HOST"
  fi
  discover_arp_candidates "$network" "$broadcast"
  get_nearby_ips "$PREFERRED_HOST" "$network" "$broadcast" 16
} | sort -u | scan_list
