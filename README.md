Supersvisior Setup
> This script helps you to run Bento and Boundless prover stack using **Supervisor**, without Docker.  

 🧰 Install Dependencies
1. Run the following commands to install system dependencies and Supervisor:

    ```bash
    apt update
    apt install -y curl wget nano supervisor screen
    ```

2. Start the Supervisor daemon:

    ```bash
    supervisord -c /etc/supervisor/supervisord.conf
    ```

---

 ⚙️ Setup Script
Download and run the setup script:

```bash
curl -L "https://raw.githubusercontent.com/Ucill924/supersvisior_setup/main/setup.sh" -o setup.sh
bash setup.sh
```

🔁 Reload Environment
After setup completes, restart your console or run the following commands:

```bash
source /root/.cargo/env
source /root/.bashrc
```

🌐 RPC Configuration
Set up your RPC URL and wallet private key
```bash
export RPC_URL=<BASE_MAINNET_RPC_URL>
export PRIVATE_KEY=<PRIVATE_KEY>
source /app/.env.rpc
```

🧪 Test Bento
To verify Bento is working properly
```bash
RUST_LOG=info bento_cli -c 32
```

⚡ Benchmarking Bento
Get a reference value for the peak_prove_khz parameter
```bash
export RPC_URL=<TARGET_CHAIN_RPC_URL>
boundless proving benchmark --request-ids <IDS>
```


🧩  Service management  
All of them are independent commands to start , stop or restart a service. Your prover is running through `supervisord` so use `supervisorctl` commands to manage it
- Dependencies:
    ```bash
    supervisorctl start dependencies:*
    supervisorctl stop dependencies:*
    supervisorctl restart dependencies:*
    ```
- Bento:
    ```bash
    supervisorctl start bento:*
    supervisorctl stop bento:*
    supervisorctl restart bento:*
    ```
- Broker:
    ```bash
    supervisorctl start broker:*
    supervisorctl stop broker:*
    supervisorctl restart broker:*
    ```
- Logs:
    ```bash
    supervisorctl tail -f broker:broker3
    ```

⚡Edit Broker file
```bash
Nano /app/broker3.toml
```
