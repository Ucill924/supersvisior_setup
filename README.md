

    ```bash
    apt update 
    apt install -y curl wget nano supervisor screen 
    ```
    
    ```bash
    supervisord -c /etc/supervisor/supervisord.conf
    ```

    
    ```bash
    curl -L "https://raw.githubusercontent.com/Ucill924/supersvisior_setup/main/setup.sh" -O setup.sh
    bash setup.sh
    ```
# Restart the console or run the following command
    ```bash
    source /root/.cargo/env
    source /root/.bashrc
    ```
#  Rpc Set up
    ```bash
    export RPC_URL=<BASE_MAINNET_RPC_URL>
    export PRIVATE_KEY=<PRIVATE_KEY>
    source /app/.env.rpc
    ```

    
# Test that bento is working properly
    ```bash
    RUST_LOG=info bento_cli -c 32
    ```

#  Benchmarking bento, you can get a reference value for the `peak_prove_khz` parameter here
    ```bash
    export RPC_URL=<TARGET_CHAIN_RPC_URL>
    boundless proving benchmark --request-ids <IDS>
    ```

# ### Service management  

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


# check logs 
 ```bash
  supervisorctl tail -f broker:broker3
 ```
    
  
