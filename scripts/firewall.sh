#!/usr/bin/env bash
#
# firewall.sh — Bloquea el acceso DIRECTO al origen. Solo los rangos de
# Cloudflare pueden alcanzar los puertos 80/443 publicados por Docker (NPM).
#
# ⚠️  Docker inserta sus reglas en iptables SALTÁNDOSE ufw: `ufw deny` NO
#     bloquea puertos publicados por contenedores. Por eso el filtrado real
#     de 80/443 se hace en la cadena DOCKER-USER. Este script hace ambas capas.
#
# El panel de NPM (:81) NO se filtra aquí: en docker-compose.yml está atado a
# 127.0.0.1, así que nunca sale a internet. Se accede por túnel SSH:
#     ssh -L 81:localhost:81 usuario@vps   →   http://localhost:81
#
# Uso (como root, DESPUÉS de `docker compose up -d`):
#     WAN_IF=eth0 SSH_PORT=22 sudo ./scripts/firewall.sh
#
# La interfaz pública se averigua con:  ip -o -4 route show to default
#
set -euo pipefail

WAN_IF="${WAN_IF:-eth0}"
SSH_PORT="${SSH_PORT:-22}"
CHAIN="CF-ORIGIN"

if [[ $EUID -ne 0 ]]; then
  echo "Ejecutá como root (sudo)." >&2
  exit 1
fi

echo "==> [1/3] Firewall del host (ufw): permitir SSH, denegar el resto entrante"
ufw allow "${SSH_PORT}/tcp"
ufw default deny incoming
ufw default allow outgoing
ufw --force enable

apply_family() {
  local ipt="$1" url="$2"
  # (re)crear la cadena de allowlist, idempotente
  "$ipt" -N "$CHAIN" 2>/dev/null || "$ipt" -F "$CHAIN"
  while read -r cidr; do
    [[ -z "$cidr" ]] && continue
    "$ipt" -A "$CHAIN" -s "$cidr" -j RETURN   # es Cloudflare → seguir (se permite)
  done < <(curl -fsSL "$url")
  "$ipt" -A "$CHAIN" -j DROP                  # cualquier otro origen → descartar

  # Enganchar en DOCKER-USER solo para el tráfico público entrante a 80/443.
  # El scoping por interfaz (-i $WAN_IF) evita filtrar el tráfico entre
  # contenedores (que entra por las bridges de docker, no por la WAN).
  while "$ipt" -C DOCKER-USER -i "$WAN_IF" -p tcp -m multiport --dports 80,443 -j "$CHAIN" 2>/dev/null; do
    "$ipt" -D DOCKER-USER -i "$WAN_IF" -p tcp -m multiport --dports 80,443 -j "$CHAIN"
  done
  "$ipt" -I DOCKER-USER -i "$WAN_IF" -p tcp -m multiport --dports 80,443 -j "$CHAIN"
}

echo "==> [2/3] Allowlist Cloudflare en DOCKER-USER (IPv4)"
apply_family iptables  https://www.cloudflare.com/ips-v4

echo "==> [3/3] Allowlist Cloudflare en DOCKER-USER (IPv6)"
apply_family ip6tables https://www.cloudflare.com/ips-v6

echo
echo "✅ Solo Cloudflare alcanza 80/443. Panel NPM (81) solo por túnel SSH."
echo
echo "⚠️  Persistencia: las reglas DOCKER-USER se pierden si Docker se reinicia."
echo "    Recomendado: re-ejecutar este script al arrancar (systemd/@reboot),"
echo "    ya que Docker recrea DOCKER-USER vacía en cada arranque del daemon."
