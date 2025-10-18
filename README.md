# Supersvisior Setup
> This script helps you to run Bento and Boundless prover stack using **Supervisor**, without Docker.  

## 🧰 Install Dependencies
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

## ⚙️ Setup Script
Download and run the setup script:

```bash
curl -L "https://raw.githubusercontent.com/Ucill924/supersvisior_setup/main/setup.sh" -o setup.sh
bash setup.sh
```
