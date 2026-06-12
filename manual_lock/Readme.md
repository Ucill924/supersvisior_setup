# Boundless Prover v2.0 - Manual Lock Mode (Supervisor, No Docker)

Panduan dari NOL: VPS GPU fresh sampai bisa lock order manual pakai
`/root/lock.sh <request_id>`. Mode ini: bento + broker jalan, tapi broker
GAK ngelock apa-apa sampai LO tentuin order mana yang mau di-lock.

Stack: Redis-only (tanpa Postgres/MinIO), binary di-extract dari image resmi,
broker di-build dari source dengan 2 patch (whitelist gate + fetch-by-id).

---

## 0. Prasyarat

- VPS GPU fresh (Ubuntu 24.04), driver NVIDIA udah kepasang (`nvidia-smi` jalan)
- Wallet prover yang udah punya deposit collateral ZKC di Boundless market (Base)
- RPC URL Base mainnet
- Disk lega (image agent ~beberapa GB)

---

## 1. Update sistem + dependency dasar

```bash
apt update
```

```bash
apt install -y curl wget nano git supervisor screen redis-server nvtop ca-certificates sqlite3
```

---

## 2. Jalanin supervisor daemon

```bash
supervisord -c /etc/supervisor/supervisord.conf
```

---

## 3. Deploy stack (download binary dari image resmi)

Download setup script:

```bash
curl -L "https://raw.githubusercontent.com/Ucill924/supersvisior_setup/main/v2_migration/setup.sh" -o setup.sh
```

Jalanin:

```bash
bash setup.sh
```

Script bakal:
- Install `crane` (extractor image, bukan Docker)
- Extract binary `/app/agent`, `/app/rest_api`, `/app/broker`, `bento_cli`, RISC0 runtime, artifact BLAKE3 dari image ghcr resmi
- Ambil `broker.toml` template + chain-overrides
- Auto-detect GPU + SEGMENT_SIZE
- Generate supervisor config Redis-only
- Start `dependencies` (redis) + `bento` (rest_api, exec, aux, gpu agents)

Saat diminta, isi: Base RPC URL, prover private key, POVW Log ID
(KOSONGIN, kita gak mining).

Verifikasi bento jalan:

```bash
redis-cli ping
```

```bash
curl -f http://localhost:8081/health
```

```bash
RUST_LOG=info bento_cli --iter-count 32
```

---

## 4. Pasang toolchain build (buat compile broker patch)

Binary broker bawaan gak punya fitur manual lock, jadi broker HARUS di-build
ulang dari source dengan patch. Toolchain ini cuma buat compile.

```bash
apt install -y build-essential pkg-config libssl-dev clang mold binutils unzip
```

```bash
curl https://sh.rustup.rs -sSf | sh -s -- -y && source ~/.cargo/env
```

```bash
curl -o /tmp/protoc.zip -L https://github.com/protocolbuffers/protobuf/releases/download/v31.1/protoc-31.1-linux-x86_64.zip && unzip -o /tmp/protoc.zip -d /usr/local && rm /tmp/protoc.zip
```

Toolchain RISC Zero (buat compile guest assessor/set-builder):

```bash
curl -L https://risczero.com/install | bash && export PATH="$HOME/.risc0/bin:$PATH"
```

```bash
rzup install
```

```bash
rzup install risc0-groth16
```

Cek:

```bash
cargo --version && protoc --version && rzup show
```

---

## 5. Clone repo + apply patch

Repo boundless biasanya udah ke-clone di `/root/boundless` dari step 3. Kalau
belum:

```bash
cd /root && git clone --depth 1 --branch v2.0.0 https://github.com/boundless-xyz/boundless.git
```

```bash
cd /root/boundless
```

Download + apply patch whitelist gate (broker cuma proses id di whitelist):

```bash
curl -L "https://raw.githubusercontent.com/Ucill924/supersvisior_setup/main/v2_migration/patch_whitelist_v2.sh" -o patch_wl.sh && bash patch_wl.sh
```

Download + apply patch fetch-by-id (broker fetch order by id dari order-stream):

```bash
curl -L "https://raw.githubusercontent.com/Ucill924/supersvisior_setup/main/v2_migration/patch_fetch_by_id_v2.sh" -o patch_fetch.sh && bash patch_fetch.sh
```

CATATAN: JANGAN pakai patch no-preflight. Preflight itu yang ngisi image_id;
kalau di-skip, assessor gagal ("Missing image_id") dan order gak bisa submit.

---

## 6. Build broker

```bash
cd /root/boundless && cargo build --release --bin broker
```

Build pertama ~8-20 menit. Tunggu sampai `Finished release profile`.

Pasang:

```bash
supervisorctl stop broker
```

```bash
cp /root/boundless/target/release/broker /app/broker && chmod +x /app/broker
```

---

## 7. Konfigurasi broker.toml

```bash
cat > /app/broker.toml <<'EOF'
[market]
min_mcycle_price = "0"
expected_probability_win_secondary_fulfillment = 1
peak_prove_khz = 7500
max_mcycle_limit = 1500
max_journal_bytes = 1000000
min_deadline = 1000
lookback_blocks = 5000
max_collateral = "30"
max_file_size = 10_000_000_000
max_concurrent_proofs = 1
order_pricing_priority = "shortest_expiry"
order_commitment_priority = "shortest_expiry"
max_critical_task_retries = 10
skip_gas_profitability_check = true
balance_warn_threshold = "0.1"
balance_error_threshold = "0.05"
collateral_balance_warn_threshold = "10"
collateral_balance_error_threshold = "5"
lockin_gas_estimate = 800000
fulfill_gas_estimate = 800000

[prover]
status_poll_retry_count = 3
status_poll_ms = 1000
req_retry_count = 3
req_retry_sleep_ms = 500
proof_retry_count = 1
proof_retry_sleep_ms = 500

[batcher]
batch_max_time = 400
min_batch_size = 1
block_deadline_buffer_secs = 180
txn_timeout = 90
single_txn_fulfill = true
withdraw = false
max_submission_attempts = 200
EOF
```

Catatan setting (mode manual):
- TIDAK pakai `allow_client_addresses`. Gate whitelist (per-id) udah jauh lebih
  ketat: order cuma diproses kalau id-nya ada di whitelist, dan id itu otomatis
  ngiket ke requestor tertentu. Jadi filter per-requestor redundant. Tanpa ini,
  lo bebas lock order dari requestor mana pun cukup lewat `lock.sh <id>`.
- `peak_prove_khz = 7500` DIPERTAHANKAN. Ini bukan filter requestor, tapi
  estimasi kapasitas: broker pakai buat ngira lama proving vs `min_deadline`.
  Kalau dihapus/salah, broker bisa ambil order yang gak kekejar -> telat
  fulfill -> SLASH. Idealnya isi sesuai benchmark GPU lo.
- `min_mcycle_price = "0"` + `skip_gas_profitability_check = true` = lock SEMUA
  order yang lo tentuin tanpa peduli untung/rugi (mode manual murni). Ganti ke
  harga wajar + `false` kalau mau jaga profit.
- `min_deadline = 1000` (16 menit) + `peak_prove_khz` = pengaman slash terakhir.
  Order gede + batch_max_time 400 bisa mepet. Naikkan `min_deadline` kalau
  ambil order besar.
- `max_mcycle_limit = 1500` = jaring pengaman biar gak iseng lock order raksasa
  yang gak kekejar. Naikkan kalau ngalangin order yang lo mau.

Siapin file antrian + db dir:

```bash
mkdir -p /db && touch /app/whitelist.txt
```

Start broker:

```bash
supervisorctl start broker
```

Broker sekarang STANDBY: gak ngelock apa-apa karena whitelist kosong.

---

## 8. Script lock manual

```bash
cat > /root/lock.sh <<'EOF'
#!/bin/bash
# Pakai: ./lock.sh <request_id>
WL="/app/whitelist.txt"
if [ -z "$1" ]; then
    echo "Pakai: $0 <request_id>"
    echo "Antrian sekarang:"; cat "$WL" 2>/dev/null
    exit 1
fi
id=$(echo "$1" | tr 'A-Z' 'a-z' | sed 's/^0x//')
if grep -qi "$id" "$WL" 2>/dev/null; then
    echo "Order $id udah ada di antrian."
else
    echo "$id" >> "$WL"
    echo "Order $id dimasukin. Broker fetch + lock dalam ~5 detik."
fi
EOF
chmod +x /root/lock.sh
```

## 9. Script cek status

```bash
cat > /root/status.sh <<'EOF'
#!/bin/bash
# Pakai: ./status.sh <request_id atau potongan id>
id=$(echo "$1" | tr 'A-Z' 'a-z' | sed 's/^0x//')
[ -z "$id" ] && { echo "Pakai: $0 <request_id>"; exit 1; }
short="${id:0:12}"
L=/var/log/broker.log
echo "=== Status order $short ==="
if grep -qi "request fulfilled 0x.*$short\|\"outcome\":\"Fulfilled\".*$short\|$short.*\"outcome\":\"Fulfilled\"" "$L"; then
    echo "STATUS: FULFILLED (selesai, reward masuk)"
elif grep -qi "Running assessor.*$short" "$L"; then
    echo "STATUS: AGGREGATING / SUBMITTING"
elif grep -qi "Locked.*$short\|Locking request.*$short" "$L"; then
    echo "STATUS: PROVING / LOCKED"
elif grep -qi "WL match.*$short\|WL fetch.*$short" "$L"; then
    echo "STATUS: QUEUED (preflight)"
else
    echo "STATUS: belum keliatan"
fi
echo "--- jejak terakhir ---"
grep -iE "$short" "$L" | grep -iE "Locked|Customer Proof|assessor|Finalizing|Submitting|fulfilled" | tail -5
EOF
chmod +x /root/status.sh
```

---

## 10. Pakai: lock order manual

Lock sebuah order (cari id dari order-stream / explorer dulu):

```bash
/root/lock.sh 0x371479ca8a23b662f5b08d137bb21a4850861acae07642a7
```

Cek status:

```bash
/root/status.sh e07642a7
```

Pantau real-time (cuma milestone penting):

```bash
tail -f /var/log/broker.log | grep --line-buffered -iE "Locking request|Locked request|Customer Proof complete|Running assessor|Finalizing batch|Submitting|Fulfilled" | grep --line-buffered -ivE "Skipping|WL skip"
```

Alur normal (~6 menit): `WL fetch OK` -> `WL match` -> preflight -> `Locking request`
-> `Locked` -> proving GPU -> `Running assessor` (tanpa "Missing image_id")
-> `Finalizing batch` -> `Submitting` -> `Fulfilled`.

Hitung total order sukses:

```bash
grep -c '"outcome":"Fulfilled"' /var/log/broker.log
```

---

## 11. Bersihin antrian

Setelah order kelar, hapus id-nya biar gak dicoba fetch ulang tiap restart:

```bash
sed -i '/e07642a7/d' /app/whitelist.txt
```

Atau kosongin semua (broker balik standby):

```bash
> /app/whitelist.txt
```

Whitelist kosong = broker GAK ngelock apa-apa. Aman.

---

## Service Management

```bash
supervisorctl status
```

```bash
supervisorctl restart broker
```

```bash
supervisorctl restart bento:*
```

```bash
tail -f /var/log/broker.log
```

---

## Troubleshooting

**Agent "POVW join failed" / proving macet**: POVW kebawa nyala padahal gak
mining. Matiin:

```bash
sed -i 's/,POVW_LOG_ID="[^"]*"//g' /etc/supervisor/conf.d/prover.conf && supervisorctl reread && supervisorctl update && supervisorctl restart bento:*
```

**Assessor "Missing image_id"**: kepasang patch no-preflight. Revert:

```bash
cd /root/boundless && git checkout crates/boundless-market/src/prover_utils/mod.rs && cargo build --release --bin broker && supervisorctl stop broker && cp target/release/broker /app/broker && supervisorctl start broker
```

**Order nyangkut / mau reset bersih**:

```bash
supervisorctl stop broker && rm -f /db/*.db /db/*.db-* && redis-cli FLUSHALL && supervisorctl start broker
```

**Pre-lock "gas cost exceeds reward"**: order reward < gas, broker nunggu harga
naik. Buat paksa lock (test): set `skip_gas_profitability_check = true` di
broker.toml (live-reload).
