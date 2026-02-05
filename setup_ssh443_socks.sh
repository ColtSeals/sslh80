#!/usr/bin/env bash
set -euo pipefail

USE_UFW="${USE_UFW:-0}"  # USE_UFW=1 ./setup_ssh443_socks.sh

echo "[1/7] Atualizando e instalando OpenSSH Server..."
apt update
apt -y install openssh-server curl

echo "[2/7] Criando config do sshd (22 + 443) + tuning pesado..."
mkdir -p /etc/ssh/sshd_config.d

cat > /etc/ssh/sshd_config.d/99-ssh22-ssh443-socks.conf <<'EOF'
Port 22
Port 443
Protocol 2

AllowTcpForwarding yes
GatewayPorts no

TCPKeepAlive yes
ClientAliveInterval 30
ClientAliveCountMax 10

MaxSessions 500
MaxStartups 200:30:600

PermitRootLogin prohibit-password
PasswordAuthentication yes
KbdInteractiveAuthentication yes
UsePAM yes
EOF

echo "[3/7] Aumentando NOFILE do serviço SSH..."
mkdir -p /etc/systemd/system/ssh.service.d
cat > /etc/systemd/system/ssh.service.d/override.conf <<'EOF'
[Service]
LimitNOFILE=1048576
EOF

echo "[4/7] Reiniciando SSH..."
systemctl daemon-reload
systemctl enable --now ssh
systemctl restart ssh

echo "[5/7] Checando portas 22/443..."
ss -lntp | egrep ':(22|443)\b' || true

if [[ "${USE_UFW}" == "1" ]]; then
  echo "[6/7] Instalando e configurando UFW..."
  apt -y install ufw
  ufw allow 22/tcp
  ufw allow 443/tcp
  ufw --force enable
  ufw status
else
  echo "[6/7] UFW não habilitado (USE_UFW=1 para habilitar)."
fi

echo "[7/7] Detectando IP público da VPS..."
VPS_IP="$(curl -4fsS https://api.ipify.org || true)"
if [[ -z "${VPS_IP}" ]]; then
  VPS_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
fi
if [[ -z "${VPS_IP}" ]]; then
  VPS_IP="SEU_IP_AQUI"
fi

cat <<TXT

============================================================
PRONTO ✅

IP detectado da VPS: ${VPS_IP}

Criar usuário SSH normal:
  adduser usuario1

TESTE SSH (porta 443):
  ssh -p 443 usuario1@${VPS_IP}

SOCKS local (no PC do usuário) na porta 1081:
  ssh -p 443 -N -D 127.0.0.1:1081 usuario1@${VPS_IP} \\
    -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o TCPKeepAlive=yes

Firefox:
  SOCKS5 127.0.0.1  Porta 1081
============================================================

TXT
