#!/usr/bin/env bash
set -euo pipefail

# =========================
# Debian 13 - SSH na 443 + tunel SOCKS
# - Mantém 22 e 443 (evita lockout)
# - Tuning para carga
# - NOFILE alto
# - IP automático (local) via "ip route get"
#
# Variáveis opcionais:
#   USE_UFW=1 ./setup_ssh443_socks.sh              -> ativa UFW e libera 22/443
#   ALLOW_ROOT_PASSWORD=1 ./setup_ssh443_socks.sh  -> permite root login por senha (NÃO recomendado)
# =========================

USE_UFW="${USE_UFW:-0}"
ALLOW_ROOT_PASSWORD="${ALLOW_ROOT_PASSWORD:-0}"

echo "[1/8] Atualizando e instalando pacotes..."
apt update
apt -y install openssh-server curl iproute2 net-tools >/dev/null

echo "[2/8] Definindo política de login do root..."
if [[ "${ALLOW_ROOT_PASSWORD}" == "1" ]]; then
  ROOT_LOGIN="yes"
  echo " -> Root por senha: ATIVADO (apenas se você realmente precisar)."
else
  ROOT_LOGIN="prohibit-password"
  echo " -> Root por senha: BLOQUEADO (recomendado). Use usuário normal."
fi

echo "[3/8] Criando config do sshd (22 + 443) + tuning pesado..."
mkdir -p /etc/ssh/sshd_config.d

cat > /etc/ssh/sshd_config.d/99-ssh22-ssh443-socks.conf <<EOF
Port 22
Port 443
Protocol 2

# Necessário para SOCKS (-D)
AllowTcpForwarding yes
GatewayPorts no

# Mantém sessão viva (ajuda em rede instável/NAT)
TCPKeepAlive yes
ClientAliveInterval 30
ClientAliveCountMax 10

# PESADO (50-200 usuários)
MaxSessions 500
MaxStartups 200:30:600

# Segurança e autenticação
PermitRootLogin ${ROOT_LOGIN}
PasswordAuthentication yes
KbdInteractiveAuthentication yes
UsePAM yes
EOF

echo "[4/8] Aumentando NOFILE do serviço SSH (muito importante para carga)..."
mkdir -p /etc/systemd/system/ssh.service.d
cat > /etc/systemd/system/ssh.service.d/override.conf <<'EOF'
[Service]
LimitNOFILE=1048576
EOF

echo "[5/8] Reiniciando SSH..."
systemctl daemon-reload
systemctl enable --now ssh
systemctl restart ssh

echo "[6/8] Checando portas 22/443..."
ss -lntp | egrep ':(22|443)\b' || true

if [[ "${USE_UFW}" == "1" ]]; then
  echo "[7/8] Instalando e configurando UFW..."
  apt -y install ufw >/dev/null
  ufw allow 22/tcp
  ufw allow 443/tcp
  ufw --force enable
  ufw status
else
  echo "[7/8] UFW não habilitado (USE_UFW=1 para habilitar)."
fi

echo "[8/8] Detectando IP (estilo 'ifconfig', porém correto)..."
# IP local principal (o que o servidor usa para sair)
VPS_LOCAL_IP="$(ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || true)"

# IP público (opcional). Se a VPS não tiver acesso externo por algum motivo, cai pro local.
VPS_PUBLIC_IP="$(curl -4fsS https://api.ipify.org 2>/dev/null || true)"

if [[ -z "${VPS_PUBLIC_IP}" ]]; then
  VPS_PUBLIC_IP="${VPS_LOCAL_IP:-SEU_IP_AQUI}"
fi

cat <<TXT

============================================================
PRONTO ✅

IP local detectado (saída principal): ${VPS_LOCAL_IP:-indisponível}
IP público detectado:               ${VPS_PUBLIC_IP}

Criar usuário SSH normal (RECOMENDADO):
  adduser usuario1

TESTE SSH (porta 443):
  ssh -p 443 usuario1@${VPS_PUBLIC_IP}

SOCKS local (no PC do usuário) na porta 1081:
  ssh -p 443 -N -D 127.0.0.1:1081 usuario1@${VPS_PUBLIC_IP} \\
    -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o TCPKeepAlive=yes -o ExitOnForwardFailure=yes

Firefox:
  SOCKS5 127.0.0.1  Porta 1081

ROOT:
  - Root por senha está: ${ROOT_LOGIN}
  - Para permitir root por senha (não recomendado):
      ALLOW_ROOT_PASSWORD=1 ./setup_ssh443_socks.sh
============================================================

TXT
