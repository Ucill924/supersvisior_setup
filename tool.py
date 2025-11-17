from web3 import Web3
from dotenv import load_dotenv
import os
import time
from colorama import init, Fore, Style

init(autoreset=True)
load_dotenv()
PRIVATE_KEY = os.getenv("PRIVATE_KEY")
BASE_RPC = os.getenv("BASE_RPC", "https://mainnet.base.org")

if not PRIVATE_KEY:
    print(Fore.RED + "PRIVATE_KEY tidak ada di .env!")
    exit()

MARKETPLACE_CONTRACT = "0xFd152dADc5183870710FE54f939Eae3aB9F0fE82"
ZKC_TOKEN = "0xAA61bB7777bD01B684347961918f1E07fBbCe7CF" 

w3 = Web3(Web3.HTTPProvider(BASE_RPC))
if not w3.is_connected():
    print(Fore.RED + "Gagal koneksi ke Base! Cek RPC di .env")
    exit()

account = w3.eth.account.from_key(PRIVATE_KEY)
my_address = account.address
ZKC_ABI = [
    {"constant":True,"inputs":[{"name":"_owner","type":"address"}],"name":"balanceOf","outputs":[{"name":"","type":"uint256"}],"type":"function"},
    {"constant":True,"inputs":[],"name":"decimals","outputs":[{"name":"","type":"uint8"}],"type":"function"},
    {"constant":True,"inputs":[],"name":"symbol","outputs":[{"name":"","type":"string"}],"type":"function"},
    {"constant":False,"inputs":[{"name":"_spender","type":"address"},{"name":"_value","type":"uint256"}],"name":"approve","outputs":[],"type":"function"}
]

MARKETPLACE_ABI = [
    {"inputs":[{"internalType":"uint256","name":"value","type":"uint256"}],"name":"depositCollateral","outputs":[],"stateMutability":"nonpayable","type":"function"},
    {"inputs":[{"internalType":"uint256","name":"value","type":"uint256"}],"name":"withdrawCollateral","outputs":[],"stateMutability":"nonpayable","type":"function"},
    {"inputs":[{"internalType":"address","name":"addr","type":"address"}],"name":"balanceOfCollateral","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
    {"inputs":[{"internalType":"uint256","name":"value","type":"uint256"}],"name":"withdraw","outputs":[],"stateMutability":"nonpayable","type":"function"},
    {"inputs":[{"internalType":"address","name":"addr","type":"address"}],"name":"balanceOf","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"}
]

ZKC = w3.eth.contract(address=ZKC_TOKEN, abi=ZKC_ABI)
market = w3.eth.contract(address=MARKETPLACE_CONTRACT, abi=MARKETPLACE_ABI)
symbol = ZKC.functions.symbol().call()
decimals = 18 

zkc_balance_raw       = ZKC.functions.balanceOf(my_address).call()
collateral_balance_raw = market.functions.balanceOfCollateral(my_address).call()
eth_rewards_raw       = market.functions.balanceOf(my_address).call()

zkc_balance       = zkc_balance_raw / 10**decimals
collateral_balance = collateral_balance_raw / 10**decimals
eth_rewards       = eth_rewards_raw / 1e18

print(Fore.CYAN + Style.BRIGHT + "\nINFORMASI WALLET & BALANCE")
print(Fore.CYAN + "═" * 50)
print(Fore.WHITE + f"Wallet          : {my_address}")
print(Fore.WHITE + f"Token           : {symbol} ({ZKC_TOKEN})")
print(Fore.GREEN + f"├─ Di wallet    : {zkc_balance:,.6f} {symbol}")
print(Fore.YELLOW + f"├─ Locked (collateral) : {collateral_balance:,.6f} {symbol}")
print(Fore.MAGENTA + f"└─ ETH rewards  : {eth_rewards:.10f} ETH")
print(Fore.CYAN + "═" * 50 + "\n")

print(Fore.YELLOW + Style.BRIGHT + "PILIH ACTION")
print("1 → Deposit Collateral")
print("2 → Withdraw Collateral")
print("3 → Cek ETH rewards")
print("4 → Withdraw ETH rewards")
print("5 → Refresh balance (tampilkan lagi info di atas)")

while True:
    choice = input(Fore.CYAN + "\nMasukkan pilihan (1-5): ").strip()
    if choice in ["1","2","3","4","5"]:
        action = int(choice)
        break
    print(Fore.RED + "Input salah! Pilih 1, 2, 3, 4, atau 5")

if action == 5:
    print(Fore.CYAN + "\nMerefresh balance...")
    os.system('python ' + __file__)   # restart script biar balance ter-update
    exit()

# ================== DEPOSIT / WITHDRAW ZKC ==================
if action in [1, 2]:
    while True:
        try:
            amount_token = float(input(Fore.CYAN + f"Masukkan jumlah {symbol} untuk {'deposit' if action==1 else 'withdraw'}: ").strip())
            if amount_token <= 0:
                raise ValueError
            break
        except:
            print(Fore.RED + "Masukkan angka positif yang valid!")

    amount_raw = int(amount_token * 10**decimals)

    if action == 1 and zkc_balance < amount_token:
        print(Fore.RED + f"ZKC di wallet tidak cukup! Butuh {amount_token:,}, kamu punya {zkc_balance:,.6f}")
        exit()
    if action == 2 and collateral_balance < amount_token:
        print(Fore.RED + f"Collateral tidak cukup! Terkunci {collateral_balance:,.6f}, kamu mau tarik {amount_token:,}")
        exit()

    # APPROVE (hanya untuk deposit)
    if action == 1:
        print(Fore.YELLOW + f"\n1. Approving {amount_token:,} {symbol}...")
        tx = ZKC.functions.approve(MARKETPLACE_CONTRACT, amount_raw).build_transaction({
            'chainId': 8453, 'nonce': w3.eth.get_transaction_count(my_address),
            'gas': 100_000, 'maxFeePerGas': w3.to_wei('0.05', 'gwei'), 'maxPriorityFeePerGas': w3.to_wei('0.001', 'gwei')
        })
        signed = account.sign_transaction(tx)
        tx_hash = w3.eth.send_raw_transaction(signed.raw_transaction)
        print(Fore.CYAN + f"   Approve → https://basescan.org/tx/0x{tx_hash.hex()}")
        w3.eth.wait_for_transaction_receipt(tx_hash, timeout=300)
        print(Fore.GREEN + "   Approve berhasil!\n")
        time.sleep(3)

    # DEPOSIT / WITHDRAW
    func = market.functions.depositCollateral if action == 1 else market.functions.withdrawCollateral
    print(Fore.YELLOW + f"{'2.' if action==1 else ''} Melakukan {'deposit' if action==1 else 'withdraw'} {amount_token:,} {symbol}...")
    tx = func(amount_raw).build_transaction({
        'chainId': 8453, 'nonce': w3.eth.get_transaction_count(my_address),
        'gas': 300_000, 'maxFeePerGas': w3.to_wei('0.05', 'gwei'), 'maxPriorityFeePerGas': w3.to_wei('0.001', 'gwei')
    })
    signed = account.sign_transaction(tx)
    tx_hash = w3.eth.send_raw_transaction(signed.raw_transaction)
    print(Fore.CYAN + f"   Tx → https://basescan.org/tx/0x{tx_hash.hex()}")
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=300)
    status = "BERHASIL" if receipt.status == 1 else "GAGAL"
    color = Fore.GREEN if receipt.status == 1 else Fore.RED
    print(color + f"\n{'DEPOSIT' if action==1 else 'WITHDRAW'} {status}!")

# ================== CEK / WITHDRAW ETH REWARDS ==================
elif action == 3:
    print(Fore.MAGENTA + f"\nETH rewards yang bisa di-withdraw: {eth_rewards:.10f} ETH")

elif action == 4:
    if eth_rewards == 0:
        print(Fore.YELLOW + "Tidak ada ETH rewards untuk ditarik.")
    else:
        print(Fore.YELLOW + f"Withdraw {eth_rewards:.10f} ETH rewards...")
        tx = market.functions.withdraw(eth_rewards_raw).build_transaction({
            'chainId': 8453, 'nonce': w3.eth.get_transaction_count(my_address),
            'gas': 200_000, 'maxFeePerGas': w3.to_wei('0.05', 'gwei'), 'maxPriorityFeePerGas': w3.to_wei('0.001', 'gwei')
        })
        signed = account.sign_transaction(tx)
        tx_hash = w3.eth.send_raw_transaction(signed.raw_transaction)
        print(Fore.CYAN + f"   Tx → https://basescan.org/tx/0x{tx_hash.hex()}")
        receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=300)
        print(Fore.GREEN + "WITHDRAW ETH BERHASIL!" if receipt.status == 1 else Fore.RED + "WITHDRAW GAGAL!")

print(Fore.CYAN + f"\nSelesai! Marketplace → https://basescan.org/address/{MARKETPLACE_CONTRACT}\n")
