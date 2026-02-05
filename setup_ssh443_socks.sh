
#!/usr/bin/env bash
set -euo pipefail

# =========================
# Debian 13 - SSH em 443 (sem sslh)
# Mantém 22 junto por segurança (evita lockout) e habilita SOCKS via -D
# =========================

USE_UFW="${USE_UFW:-0}"  # para habilitar UFW: USE_UFW=1 ./setup_ssh443_socks.sh

echo "[1/7] Atualizando e instalando OpenSSH Server..."
apt update
apt -y install openssh-server

echo "[2/7] Criando config do sshd (22 + 443) + tuning pesado..."
mkdir -p /etc/ssh/sshd_config.d

cat > /etc/ssh/sshd_config.d/99-ssh22-ssh443-socks.conf <<'EOF'
# Ouve em 22 E 443 (não trava você fora). Depois você pode remover a 22 se quiser.
Port 22
Port 443
Protocol 2

# Necessário para SOCKS (-D)
AllowTcpForwarding yes
GatewayPorts no

# Mantém sessão viva (ajuda em rede instável)
TCPKeepAlive yes
ClientAliveInterval 30
ClientAliveCountMax 10

# PESADO (50-200 simultâneos)
MaxSessions 500
MaxStartups 200:30:600

# Segurança básica (mantém senha por enquanto)
PermitRootLogin prohibit-password
PasswordAuthentication yes
KbdInteractiveAuthentication yes
UsePAM yes
EOF

echo "[3/7] Aumentando NOFILE do serviço SSH (muito importante para carga)..."
mkdir -p /etc/systemd/system/ssh.service.d
cat > /etc/systemd/system/ssh.service.d/override.conf <<'EOF'
[Service]
LimitNOFILE=1048576
EOF

echo "[4/7] Reiniciando SSH..."
systemctl daemon-reload
systemctl enable --now ssh
systemctl restart ssh

echo "[5/7] Checando se o sshd está ouvindo em 22 e 443..."
echo "---- ss -lntp (22/443) ----"
ss -lntp | egrep ':(22|443)\b' || true

if [[ "${USE_UFW}" == "1" ]]; then
  echo "[6/7] Instalando e configurando UFW (opcional)..."
  apt -y install ufw
  ufw allow 22/tcp
  ufw allow 443/tcp
  ufw --force enable
  ufw status
else
  echo "[6/7] UFW não habilitado (USE_UFW=1 para habilitar)."
fi

echo "[7/7] FINAL ✅"
cat <<'TXT'

============================================================
PRONTO ✅

TESTE AGORA do seu PC/qualquer lugar:
  ssh -p 443 root@IP_DA_VPS

Criar usuário SSH normal:
  adduser usuario1
  adduser usuario2

Cada usuário abre SOCKS local na porta 1081 (no PC dele):
  ssh -p 443 -N -D 127.0.0.1:1081 usuario@IP_DA_VPS ^
    -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o TCPKeepAlive=yes

No Firefox:
  SOCKS5: 127.0.0.1  Porta: 1081
============================================================

TXT
