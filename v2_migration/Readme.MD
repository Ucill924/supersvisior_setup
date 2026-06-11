# Boundless Prover v2.0 Setup (Supervisor, No Docker)

Script ini jalanin **Boundless Prover v2.0** (prover stack Redis-only) pakai **Supervisor**, tanpa Docker. Binary v2 resmi cuma didistribusi sebagai Docker image, jadi script ini narik binary-nya langsung dari image ghcr.io pakai `crane` (binary tunggal, bukan Docker, tanpa daemon). Tanpa build, tanpa compile.

## Beda v2 vs v1

| | v1 | v2 |
|---|---|---|
| Storage | Redis + PostgreSQL + MinIO | Redis aja |
| Kecepatan proving | baseline | 1.5-2x lebih cepat (order kecil-menengah) |
| RPC usage | baseline | sampai 5x lebih hemat |
| Stabilitas | pernah slash | benchmark resmi: zero slashing |
| Chain | Base | Base + Taiko (multi-chain 1 node) |
| Binary | prebuilt bento-* | prover-* dari image ghcr |

Stack v2 yang jalan: `redis`, `rest_api` (:8081), `exec_agent` x2, `aux_agent`, `gpu_prove_agent` (1 per GPU, auto-detect), `broker`. Tidak ada Postgres dan MinIO.

## Install Dependencies

```bash
apt update
apt install -y curl wget nano supervisor screen
```

Start daemon supervisor:

```bash
supervisord -c /etc/supervisor/supervisord.conf
```

## Jalanin Setup

```bash
curl -L "https://raw.githubusercontent.com/Ucill924/supersvisior_setup/main/v2_migration/setup.sh" -o setup.sh
bash setup.sh
```

Script bakal minta: Base Mainnet RPC URL, prover private key, POVW Log ID (kosongin kalau gak mining). Opsi `-s` buat silent mode (isi placeholder, edit belakangan di `/etc/supervisor/conf.d/prover.conf`).

Yang dilakukan script:

1. Install dependencies + `crane`
2. Extract binary dari image resmi: `/app/agent`, `/app/rest_api`, `/app/broker`, `bento_cli`, RISC0 runtime, artifact BLAKE3
3. Ambil `broker.toml` template v2 + `chain-overrides`
4. Auto-detect GPU dan SEGMENT_SIZE dari VRAM
5. Generate supervisor config Redis-only
6. Start `dependencies` + `bento` (broker dibiarkan STOPPED, start manual setelah config beres)

## Konfigurasi Broker

```bash
nano /app/broker.toml
```

PENTING, v2 pakai nama field baru. Nama lama udah dihapus dan bikin broker gagal start:

| v1 (lama) | v2 (baru) |
|---|---|
| `mcycle_price` | `min_mcycle_price` |
| `max_stake` | `max_collateral` |
| `max_concurrent_locks` | `max_concurrent_proofs` |
| `batch_size` | `min_batch_size` |
| `stake_balance_warn_threshold` | `collateral_balance_warn_threshold` |
| `expired_order_fulfillment_priority` | `order_commitment_priority` |

Knob penting: `min_mcycle_price`, `peak_prove_khz` (set di bawah hasil benchmark), `max_concurrent_proofs`, `max_collateral`, `min_deadline`.

## Tes Bento

```bash
RUST_LOG=info bento_cli --iter-count 32
```

Cek juga:

```bash
redis-cli ping
curl -f http://localhost:8081/health
```

## Deposit Collateral

Lock order butuh collateral ZKC di market (sekali setup per wallet):

```bash
export RPC_URL=<BASE_MAINNET_RPC_URL>
export PRIVATE_KEY=<PROVER_PRIVATE_KEY>
boundless prover deposit-collateral <ZKC_AMOUNT>
boundless prover balance-collateral
```

## Start Broker (otomatis)

```bash
supervisorctl start broker:*
tail -f /var/log/broker.log
```

Tanda sehat di log:

```
Starting pipeline for chain chain_id=8453
Configured to run with Bento backend
```

Habis itu broker jalan sendiri: discover order, lock, prove di GPU, submit, dapet reward.

## Service Management

```bash
supervisorctl start|stop|restart dependencies:*
supervisorctl start|stop|restart bento:*
supervisorctl start|stop|restart broker:*
supervisorctl status
```

Logs:

```bash
tail -f /var/log/broker.log
tail -f /var/log/gpu_prove_agent0.log
tail -f /var/log/rest_api.log
```

## Lokasi Penting

| Item | Path |
|---|---|
| Binary | `/app/agent`, `/app/rest_api`, `/app/broker` |
| Broker config | `/app/broker.toml` |
| Chain overrides | `/app/chain-overrides/` |
| Broker DB | `/db/broker.db` (SQLite, per-chain otomatis) |
| Supervisor config | `/etc/supervisor/conf.d/prover.conf` |
| Logs | `/var/log/*.log` |
| Redis data | `/data/redis` |
| Artifact BLAKE3 | `/root/.blake3_groth16_artifacts` |

## Multi-chain (opsional)

Mau nambah Taiko? Tambahin env `PROVER_RPC_URL_167000` di blok `[program:broker]` pada `/etc/supervisor/conf.d/prover.conf`, bridge ZKC ke Taiko, deposit collateral di Taiko, lalu restart broker. Alamat kontrak auto-resolve dari chain id.

## Catatan

- Image agent gede (ada CUDA runtime di dalamnya), download pertama bisa beberapa GB. Pastikan disk cukup.
- Driver NVIDIA harus terpasang di host (runtime CUDA udah dibawa binary).
- POVW Log ID cuma perlu kalau ikut mining rewards. Kosongin kalau nggak.
- Semua service localhost, gak ada port database yang dibuka keluar.
