#!/bin/bash
# ============================================================================
# setup_v2.sh - Boundless Prover v2.0 (Redis-only) via Supervisor, NO Docker
#
# Binary v2 resmi dikemas sebagai Docker image di ghcr.io. Script ini narik
# image itu pakai `crane` (binary tunggal, bukan Docker, tanpa daemon) lalu
# extract /app/agent, /app/rest_api, /app/broker, bento_cli, RISC0 runtime,
# dan artifact BLAKE3 langsung dari layer image. Tanpa build, tanpa compile.
#
# Stack v2 (Redis-only): redis + rest_api + exec_agent + aux_agent +
# gpu_prove_agent (1 per GPU) + broker. TANPA Postgres, TANPA MinIO.
#
# Pakai: bash setup_v2.sh
# Lalu jawab prompt RPC + private key, atau pakai -s buat silent mode.
# ============================================================================
set -e

SILENT_MODE=false
while getopts "s" opt; do
    case $opt in
        s) SILENT_MODE=true; echo "Running in silent mode with default values..." ;;
        \?) echo "Usage: $0 [-s]"; exit 1 ;;
    esac
done

REDIS_TTL=57600
AGENT_IMG="ghcr.io/boundless-xyz/boundless/prover-agent:prover-v2.0"
REST_IMG="ghcr.io/boundless-xyz/boundless/prover-rest-api:prover-v2.0"
CLI_IMG="ghcr.io/boundless-xyz/boundless/prover-cli:prover-v2.0"
BROKER_IMG="ghcr.io/boundless-xyz/boundless/broker:broker-v2.0"

echo "-----Installing dependencies-----"
apt update
apt install -y curl wget nano git supervisor screen redis-server nvtop ca-certificates
echo

echo "-----Installing crane (image extractor, bukan Docker)-----"
CRANE_VER="v0.20.2"
curl -L "https://github.com/google/go-containerregistry/releases/download/${CRANE_VER}/go-containerregistry_Linux_x86_64.tar.gz" -o /tmp/crane.tgz
tar -xzf /tmp/crane.tgz -C /usr/local/bin crane
rm /tmp/crane.tgz
crane version
echo

echo "-----Extracting prover binaries from images-----"
mkdir -p /app /opt/img
extract_img () {
    local img="$1"; local dest="$2"
    echo "--- export $img ---"
    mkdir -p "$dest"
    crane export "$img" - | tar -x -C "$dest"
}

extract_img "$AGENT_IMG"  /opt/img/agent
extract_img "$REST_IMG"   /opt/img/rest
extract_img "$CLI_IMG"    /opt/img/cli
extract_img "$BROKER_IMG" /opt/img/broker

cp /opt/img/agent/app/agent      /app/agent
cp /opt/img/rest/app/rest_api    /app/rest_api
cp /opt/img/broker/app/broker    /app/broker
CLI_BIN=$(find /opt/img/cli -maxdepth 3 -name "bento_cli" -type f | head -1)
cp "$CLI_BIN" /usr/local/bin/bento_cli
chmod +x /app/agent /app/rest_api /app/broker /usr/local/bin/bento_cli

# RISC0 runtime (dipakai agent buat groth16)
if [ -d /opt/img/agent/usr/local/risc0 ]; then
    rm -rf /usr/local/risc0
    cp -r /opt/img/agent/usr/local/risc0 /usr/local/risc0
fi

# Artifact BLAKE3 Groth16 (baked-in di image agent, baru di v2)
if [ -d /opt/img/agent/.blake3_groth16_artifacts ]; then
    rm -rf /root/.blake3_groth16_artifacts
    cp -r /opt/img/agent/.blake3_groth16_artifacts /root/.blake3_groth16_artifacts
fi

rm -rf /opt/img
echo "Binary terpasang: /app/agent /app/rest_api /app/broker /usr/local/bin/bento_cli"
echo

echo "-----Fetching broker.toml template (v2)-----"
cd /root
[ -d boundless ] || git clone --depth 1 --branch v2.0.0 https://github.com/boundless-xyz/boundless.git
cp boundless/broker-template.toml /app/broker.toml
mkdir -p /app/chain-overrides
cp -r boundless/chain-overrides/* /app/chain-overrides/ 2>/dev/null || true
echo

echo "-----Configuration-----"
if [ "$SILENT_MODE" = true ]; then
    BASE_RPC="https://base-mainnet.g.alchemy.com/v2/YOUR_API_KEY"
    PROVER_KEY="0x0000000000000000000000000000000000000000000000000000000000000000"
    echo "WARNING: Silent mode. Update RPC URL dan private key di"
    echo "/etc/supervisor/conf.d/prover.conf sebelum start broker!"
else
    read -p "Base Mainnet RPC URL: " BASE_RPC
    read -p "Prover private key: " PROVER_KEY
fi
POVW_LOG_ID=""
read -p "POVW Log ID (kosongin kalau gak mining): " POVW_LOG_ID

echo
echo "-----Detecting GPUs and segment size-----"
nvidia-smi -L
GPU_IDS=$(nvidia-smi --query-gpu=index --format=csv,noheader,nounits | tr '\n' ' ')

gpu_info=$(nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader)
SEGMENT_SIZE=22
while IFS=',' read -r index name memory; do
    memory_gb=$(echo "$memory" | tr -d ' MiB' | awk '{printf "%.2f", $1/1024}')
    if (( $(awk -v m="$memory_gb" 'BEGIN{print (m<16)?1:0}') )); then s=19
    elif (( $(awk -v m="$memory_gb" 'BEGIN{print (m<20)?1:0}') )); then s=20
    elif (( $(awk -v m="$memory_gb" 'BEGIN{print (m<40)?1:0}') )); then s=21
    else s=22; fi
    [ "$s" -lt "$SEGMENT_SIZE" ] && SEGMENT_SIZE=$s
done <<< "$gpu_info"
echo "SEGMENT_SIZE: $SEGMENT_SIZE"
echo

echo "-----Generating supervisord configuration-----"
GPU_BLOCKS=""
for g in $GPU_IDS; do
GPU_BLOCKS+="
[program:gpu_prove_agent${g}]
command=/app/agent -t prove --redis-ttl ${REDIS_TTL}
autostart=false
autorestart=true
startsecs=5
priority=50
stdout_logfile=/var/log/gpu_prove_agent${g}.log
redirect_stderr=true
environment=BENTO_API_URL=\"http://localhost:8081\",REDIS_URL=\"redis://localhost:6379\",RISC0_HOME=\"/usr/local/risc0\",BLAKE3_GROTH16_SETUP_DIR=\"/root/.blake3_groth16_artifacts\",RUST_LOG=\"info\",RUST_BACKTRACE=\"1\",CUDA_VISIBLE_DEVICES=\"${g}\",POVW_LOG_ID=\"${POVW_LOG_ID}\"
"
done

cat > /etc/supervisor/conf.d/prover.conf <<EOF
[group:dependencies]
programs=redis

[group:bento]
programs=rest_api,exec_agent0,exec_agent1,aux_agent$(for g in $GPU_IDS; do printf ',gpu_prove_agent%s' "$g"; done)

[group:broker]
programs=broker

[program:redis]
command=/usr/bin/redis-server --port 6379 --maxmemory-policy noeviction --save 900 1 --appendonly yes --dir /data/redis
directory=/data/redis
autostart=false
autorestart=true
startsecs=5
priority=10
stdout_logfile=/var/log/redis.log
redirect_stderr=true

[program:rest_api]
command=/app/rest_api --bind-addr 0.0.0.0:8081 --snark-timeout 180
directory=/app
autostart=false
autorestart=true
startsecs=5
priority=20
stdout_logfile=/var/log/rest_api.log
redirect_stderr=true
environment=BENTO_API_URL="http://localhost:8081",REDIS_URL="redis://localhost:6379",RISC0_HOME="/usr/local/risc0",RUST_LOG="info",RUST_BACKTRACE="1"

[program:exec_agent0]
command=/app/agent -t exec --segment-po2 ${SEGMENT_SIZE} --redis-ttl ${REDIS_TTL}
directory=/app
autostart=false
autorestart=true
startsecs=5
priority=30
stdout_logfile=/var/log/exec_agent0.log
redirect_stderr=true
environment=BENTO_API_URL="http://localhost:8081",REDIS_URL="redis://localhost:6379",RISC0_HOME="/usr/local/risc0",RISC0_KECCAK_PO2="17",RUST_LOG="info",RUST_BACKTRACE="1"

[program:exec_agent1]
command=/app/agent -t exec --segment-po2 ${SEGMENT_SIZE} --redis-ttl ${REDIS_TTL}
directory=/app
autostart=false
autorestart=true
startsecs=5
priority=30
stdout_logfile=/var/log/exec_agent1.log
redirect_stderr=true
environment=BENTO_API_URL="http://localhost:8081",REDIS_URL="redis://localhost:6379",RISC0_HOME="/usr/local/risc0",RISC0_KECCAK_PO2="17",RUST_LOG="info",RUST_BACKTRACE="1"

[program:aux_agent]
command=/app/agent -t aux --monitor-requeue --redis-ttl ${REDIS_TTL}
directory=/app
autostart=false
autorestart=true
startsecs=5
priority=30
stdout_logfile=/var/log/aux_agent.log
redirect_stderr=true
environment=BENTO_API_URL="http://localhost:8081",REDIS_URL="redis://localhost:6379",RISC0_HOME="/usr/local/risc0",RUST_LOG="info",RUST_BACKTRACE="1"

[program:broker]
command=/app/broker --db-url sqlite:///db/broker.db --config-file /app/broker.toml --bento-api-url http://localhost:8081
directory=/app
autostart=false
autorestart=true
startsecs=5
stopwaitsecs=10800
priority=60
stdout_logfile=/var/log/broker.log
redirect_stderr=true
environment=PROVER_PRIVATE_KEY="${PROVER_KEY}",PROVER_RPC_URL_8453="${BASE_RPC}",RUST_LOG="info,broker=debug,boundless_market=debug",RUST_BACKTRACE="1"
EOF

cat >> /etc/supervisor/conf.d/prover.conf <<EOF
$GPU_BLOCKS
EOF

mkdir -p /db /data/redis
echo

echo "-----Starting dependencies + bento-----"
supervisorctl update
supervisorctl start dependencies:*
sleep 3
supervisorctl start bento:*
supervisorctl status
echo

echo "Prover v2 setup complete (Redis-only stack, no Postgres/MinIO)"
echo
echo "Selanjutnya:"
echo "1. Edit /app/broker.toml (pakai nama field v2: min_mcycle_price,"
echo "   max_collateral, max_concurrent_proofs, min_batch_size, peak_prove_khz)"
echo "2. Tes bento: RUST_LOG=info bento_cli --iter-count 32"
echo "3. Start broker otomatis: supervisorctl start broker:*"
echo "4. Pantau: tail -f /var/log/broker.log"
echo "   Cari: 'Starting pipeline for chain chain_id=8453' dan"
echo "   'Configured to run with Bento backend'"
echo
echo "Service management:"
echo "  supervisorctl start|stop|restart dependencies:*"
echo "  supervisorctl start|stop|restart bento:*"
echo "  supervisorctl start|stop|restart broker:*"
