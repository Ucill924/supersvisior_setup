#!/bin/bash
set -e

echo "=============================="
echo "   BOUNDLESS GPU INSTALLER"
echo "=============================="

### -----------------------------
### 1. INPUT MANUAL
### -----------------------------
read -p "Masukkan IP Server Redis/Postgres/MinIO (contoh: 10.207.29.183): " SERVER_IP
if [ -z "$SERVER_IP" ]; then
    echo "❌ IP tidak boleh kosong"
    exit 1
fi

read -p "Masukkan POVW_LOG_ID (0x....): " POW_ID
if [ -z "$POW_ID" ]; then
    echo "❌ POVW_LOG_ID tidak boleh kosong"
    exit 1
fi

echo ""
echo "----- GPU DETECTION -----"
nvidia-smi -L || { echo "❌ NVIDIA GPU tidak ditemukan"; exit 1; }

read -p "Masukkan GPU ID yang ingin dipakai (contoh 0,1 — default semua GPU): " GPU_IDS

if [ -z "$GPU_IDS" ]; then
    GPU_IDS=$(nvidia-smi --query-gpu=index --format=csv,noheader | tr '\n' ',' | sed 's/,$//')
    echo "Menggunakan semua GPU: $GPU_IDS"
else
    echo "GPU dipilih: $GPU_IDS"
fi

IFS=',' read -ra GPU_ARRAY <<< "$GPU_IDS"


### -----------------------------
### 2. INSTALL PACKAGE
### -----------------------------
echo "[1] Update & install dependencies..."
apt update && apt install -y build-essential pkg-config libssl-dev git curl nvtop

echo "[2] Install supervisor..."
apt install -y supervisor

# Pastikan folder supervisor ada
mkdir -p /var/log/supervisor
mkdir -p /etc/supervisor/conf.d

# Pastikan config supervisord utama ada
if [ ! -f /etc/supervisor/supervisord.conf ]; then
    echo "❗ Membuat supervisord.conf default..."
    cat > /etc/supervisor/supervisord.conf <<EOF
[supervisord]
nodaemon=false
logfile=/var/log/supervisor/supervisord.log
pidfile=/var/run/supervisord.pid

[supervisorctl]
serverurl=unix:///var/run/supervisor.sock

[unix_http_server]
file=/var/run/supervisor.sock

[include]
files = /etc/supervisor/conf.d/*.conf
EOF
fi


echo "[3] Install Rust..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source $HOME/.cargo/env

echo "[4] Install RISC Zero..."
curl -L https://risczero.com/install | bash
source "/root/.bashrc"
/root/.risc0/bin/rzup install

echo "[4.1] Install Groth16..."
export PATH=$PATH:/root/.risc0/bin
rzup install risc0-groth16


### -----------------------------
### 3. DOWNLOAD AGENT
### -----------------------------
echo "[5] Download agent binary..."
mkdir -p /app && cd /app
curl -L "https://cancanneed.de/boundless/v1.0.0/bento-agent-v1_0_1-cuda12_8" -o agent
chmod +x agent


### -----------------------------
### 4. GENERATE SUPERVISOR CONFIG
### -----------------------------
CONF_FILE=/etc/supervisor/conf.d/boundless.conf

echo "[6] Generate supervisor config..."
echo "" > $CONF_FILE

echo "[group:GPU]" >> $CONF_FILE
echo -n "programs=" >> $CONF_FILE

for i in "${!GPU_ARRAY[@]}"; do
    printf "gpu_prove_agent$((i+1))," >> $CONF_FILE
done

sed -i 's/,$//' $CONF_FILE

i=1
for GPU_ID in "${GPU_ARRAY[@]}"; do

cat >> $CONF_FILE <<EOF

####################################
# GPU $GPU_ID  (Agent $i)
####################################
[program:gpu_prove_agent$i]
command=/app/agent -t prove --redis-ttl 57600
directory=/app
autostart=true
autorestart=true
startsecs=5
stopwaitsecs=10
priority=$((50 + i))
stdout_logfile=/var/log/supervisor/gpu_prove_agent$i.log
redirect_stderr=true
environment=CUDA_VISIBLE_DEVICES="$GPU_ID",REDIS_URL="redis://$SERVER_IP:6379",DATABASE_URL="postgresql://worker:password@$SERVER_IP:5432/taskdb",S3_URL="http://$SERVER_IP:9000",S3_BUCKET="workflow",S3_ACCESS_KEY="admin",S3_SECRET_KEY="password",RUST_LOG="info",RUST_BACKTRACE="1",POVW_LOG_ID="$POW_ID"
EOF

i=$((i+1))
done


### -----------------------------
### 5. START SUPERVISOR (FIX)
### -----------------------------
echo "[7] Starting Supervisor daemon..."
supervisord -c /etc/supervisor/supervisord.conf >/dev/null 2>&1 || true

sleep 2

echo "[8] Reload supervisor..."
supervisorctl reread || true
supervisorctl update || true

echo "=============================="
echo " INSTALLASI SELESAI!"
echo "=============================="
echo "Supervisor config: $CONF_FILE"
echo "Untuk melihat log: supervisorctl tail -f gpu_prove_agent1"
echo "GPU Agents berjalan otomatis."
