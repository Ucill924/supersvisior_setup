
# Boundless Prover Setup (Supervisor, No Docker)

Script ini buat jalanin stack **Bento + Boundless prover** pakai **Supervisor**, tanpa Docker. Versi ini (`setup2.sh`) udah dipatch biar PostgreSQL dan Redis bisa diakses dari luar (cocok buat VPS dengan port mapping seperti Novita).

## Perbedaan dengan setup asli

1. **Redis `--protected-mode no`**, jadi redis terima koneksi dari luar localhost.
2. **`postgresql.conf` dan `pg_hba.conf` ditulis otomatis** sebelum postgres direstart, jadi gak perlu edit manual.
3. **`data_directory` di-set ke `/var/lib/postgresql/16/main`**. Ini wajib. Cluster yang punya user `worker` / db `taskdb` dibuat oleh `initdb.sh` saat postgres jalan dengan config Debian default, yaitu di `/var/lib/postgresql/16/main`. GUC `data_directory` menang atas flag `-D /data/postgresql` di supervisord, jadi harus diarahkan ke `/var/lib`, bukan `/data/postgresql` (yang kosong, gak pernah di-initdb). Salah set di sini bikin postgres FATAL exited too quickly.
4. **`pg_hba.conf` allow `0.0.0.0/0` (md5)** buat remote access.

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
curl -L "https://raw.githubusercontent.com/Ucill924/supersvisior_setup/main/setup2.sh" -o setup2.sh
bash setup2.sh
```

Opsi:

- `-s` : silent mode (pakai nilai default tanpa prompt)
- `-c` : skip install CLI tools (`boundless-cli`)

## Reload Environment

Setelah selesai, restart console atau jalanin:

```bash
source /root/.cargo/env
source /root/.bashrc
```

## RPC Configuration

```bash
export RPC_URL=<BASE_MAINNET_RPC_URL>
export PRIVATE_KEY=<PRIVATE_KEY>
source /app/.env.rpc
```

## Test Bento

```bash
RUST_LOG=info bento_cli -c 32
```

## Benchmark

Buat dapet referensi nilai `peak_prove_khz`:

```bash
export RPC_URL=<TARGET_CHAIN_RPC_URL>
boundless proving benchmark --request-ids <IDS>
```

## Service Management

Prover jalan lewat `supervisord`, jadi pakai `supervisorctl`.

**Dependencies (redis, postgres, minio, grafana):**

```bash
supervisorctl start dependencies:*
supervisorctl stop dependencies:*
supervisorctl restart dependencies:*
```

**Bento (exec agents, gpu prove agents, aux, rest_api):**

```bash
supervisorctl start bento:*
supervisorctl stop bento:*
supervisorctl restart bento:*
```

**Broker:**

```bash
supervisorctl start broker:*
supervisorctl stop broker:*
supervisorctl restart broker:*
```

**Logs:**

```bash
supervisorctl tail -f broker:broker3
```

## Edit Broker Config

```bash
nano /app/broker3.toml
```

## Lokasi Penting

| Item | Path |
|------|------|
| Prover main dir | `/app` |
| Log dir | `/var/log` |
| Broker config | `/app/broker3.toml` |
| Supervisord config | `/etc/supervisor/conf.d/boundless.conf` |
| Postgres config | `/etc/postgresql/16/main/postgresql.conf` |
| Postgres data | `/var/lib/postgresql/16/main` |
