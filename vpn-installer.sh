#!/bin/bash

# VPN Installer Script
# Универсальный скрипт для установки VPN
# Поддерживает: wg-easy (WireGuard через Docker), 3x-ui (Xray через официальный скрипт), Outline VPN, Remnawave, Hysteria2
# Поддерживает: RedHat, Ubuntu, Debian и их производные

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Константы
SCRIPT_NAME="VPN Installer"
SCRIPT_VERSION="1.2.0"
LOG_FILE="/tmp/vpn-installer.log"
DOCKER_COMPOSE_VERSION="2.20.0"

# Переменные по умолчанию
DEFAULT_VPN="wg-easy"
DEFAULT_PORT="51820"
DEFAULT_PASSWORD=""
DEFAULT_DATA_PATH="/opt/wg-easy"

# Глобальные переменные
CURRENT_VPN=""
CURRENT_PORT=""
CURRENT_WEB_PORT=""
CURRENT_PASSWORD=""
CURRENT_PASSWORD_HASH=""
CURRENT_PASSWORD_HASH_ESCAPED=""
CURRENT_DATA_PATH=""
CURRENT_IP=""
CURRENT_INTERFACE=""
CURRENT_LANG=""
OS_TYPE=""
PACKAGE_MANAGER=""

# Функция логирования
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Функция вывода заголовка
print_header() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║              Универсальный установщик VPN                    ║"
    echo "║   wg-easy | 3x-ui | Outline | Remnawave | Hysteria2          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Функция вывода разделителя
print_separator() {
    echo -e "${BLUE}────────────────────────────────────────────────────────────${NC}"
}

# Функция вывода успешного сообщения
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
    log "SUCCESS" "$1"
}

# Функция вывода предупреждения
print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
    log "WARNING" "$1"
}

# Функция вывода ошибки
print_error() {
    echo -e "${RED}✗ $1${NC}"
    log "ERROR" "$1"
}

# Функция вывода информации
print_info() {
    echo -e "${BLUE} $1${NC}"
    log "INFO" "$1"
}

# Функция определения ОС и пакетного менеджера
detect_os() {
    print_info "Определение операционной системы..."
    
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_TYPE="$ID"
        
        case $ID in
            "rhel"|"centos"|"fedora"|"rocky"|"alma")
                PACKAGE_MANAGER="dnf"
                if ! command -v dnf &> /dev/null; then
                    PACKAGE_MANAGER="yum"
                fi
                ;;
            "ubuntu"|"debian"|"linuxmint"|"pop")
                PACKAGE_MANAGER="apt"
                ;;
            "arch"|"manjaro")
                PACKAGE_MANAGER="pacman"
                ;;
            *)
                print_error "Неподдерживаемая операционная система: $ID"
                exit 1
                ;;
        esac
        
        print_success "Обнаружена ОС: $PRETTY_NAME ($ID)"
        print_success "Пакетный менеджер: $PACKAGE_MANAGER"
    else
        print_error "Не удалось определить операционную систему"
        exit 1
    fi
}

# Функция проверки прав root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Этот скрипт должен быть запущен с правами root"
        print_info "Используйте: sudo $0"
        exit 1
    fi
}

# Функция проверки подключения к интернету
check_internet() {
    print_info "Проверка подключения к интернету..."
    if ping -c 1 8.8.8.8 &> /dev/null; then
        print_success "Подключение к интернету доступно"
    else
        print_error "Нет подключения к интернету"
        exit 1
    fi
}

# Функция обновления пакетов
update_packages() {
    print_info "Обновление пакетов..."
    
    case $PACKAGE_MANAGER in
        "apt")
            apt update -y
            ;;
        "dnf"|"yum")
            $PACKAGE_MANAGER update -y
            ;;
        "pacman")
            pacman -Syu --noconfirm
            ;;
    esac
    
    print_success "Пакеты обновлены"
}

# Функция установки зависимостей
install_dependencies() {
    print_info "Установка зависимостей..."
    
    case $PACKAGE_MANAGER in
        "apt")
            apt install -y curl wget git ca-certificates gnupg lsb-release
            ;;
        "dnf"|"yum")
            $PACKAGE_MANAGER install -y curl wget git ca-certificates gnupg
            ;;
        "pacman")
            pacman -S --noconfirm curl wget git ca-certificates gnupg
            ;;
    esac
    
    print_success "Зависимости установлены"
}

# Функция установки Docker
install_docker() {
    print_info "Проверка установки Docker..."
    
    if command -v docker &> /dev/null; then
        print_success "Docker уже установлен"
        return 0
    fi
    
    print_info "Установка Docker..."
    
    case $PACKAGE_MANAGER in
        "apt")
            # Установка Docker для Ubuntu/Debian
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            apt update -y
            apt install -y docker-ce docker-ce-cli containerd.io
            ;;
        "dnf"|"yum")
            # Установка Docker для RHEL/CentOS
            $PACKAGE_MANAGER install -y dnf-utils
            $PACKAGE_MANAGER config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            $PACKAGE_MANAGER install -y docker-ce docker-ce-cli containerd.io
            ;;
        "pacman")
            # Установка Docker для Arch
            pacman -S --noconfirm docker
            ;;
    esac
    
    # Запуск и включение Docker
    systemctl start docker
    systemctl enable docker
    
    print_success "Docker установлен и запущен"
}

# Функция установки Docker Compose
install_docker_compose() {
    print_info "Проверка установки Docker Compose..."
    
    if command -v docker-compose &> /dev/null; then
        print_success "Docker Compose уже установлен"
        return 0
    fi
    
    print_info "Установка Docker Compose..."
    
    # Установка Docker Compose v2
    curl -L "https://github.com/docker/compose/releases/download/v$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    print_success "Docker Compose установлен"
}

# Функция проверки статуса Docker
check_docker_status() {
    print_info "Проверка статуса Docker..."
    
    if ! systemctl is-active --quiet docker; then
        print_warning "Docker не запущен. Запускаю..."
        systemctl start docker
    fi
    
    if docker info &> /dev/null; then
        print_success "Docker работает корректно"
    else
        print_error "Docker не работает корректно"
        exit 1
    fi
}

# Функция проверки существующих контейнеров
check_existing_containers() {
    local vpn_name=$1
    print_info "Проверка существующих контейнеров для $vpn_name..."
    
    if docker ps -a --format "table {{.Names}}" | grep -q "$vpn_name"; then
        print_warning "Найдены существующие контейнеры для $vpn_name"
        return 1
    fi
    
    print_success "Существующие контейнеры не найдены"
    return 0
}

# Функция проверки установленного wg-easy
check_wg_easy_installed() {
    local found=false
    
    # Проверка контейнера
    if docker ps -a --format "{{.Names}}" | grep -q "^wg-easy$"; then
        print_warning "⚠ wg-easy уже установлен: найден Docker контейнер 'wg-easy'"
        found=true
    fi
    
    # Проверка директории с данными
    if [[ -d "$DEFAULT_DATA_PATH" && -f "$DEFAULT_DATA_PATH/docker-compose.yml" ]]; then
        print_warning "⚠ wg-easy уже установлен: найдена директория $DEFAULT_DATA_PATH с docker-compose.yml"
        found=true
    fi
    
    # Проверка запущенного контейнера
    if docker ps --format "{{.Names}}" | grep -q "^wg-easy$"; then
        print_warning "⚠ wg-easy уже запущен"
        found=true
    fi
    
    if [[ "$found" == "true" ]]; then
        echo
        print_warning "Продолжение установки может привести к конфликтам или перезаписи существующей установки!"
        return 1
    fi
    
    return 0
}

# Функция проверки установленного 3x-ui
check_3x_ui_installed() {
    local found=false
    
    # Проверка команды x-ui
    if command -v x-ui &> /dev/null; then
        print_warning "⚠ 3x-ui уже установлен: команда 'x-ui' доступна в системе"
        found=true
    fi
    
    # Проверка исполняемых файлов
    if [[ -f "/usr/local/bin/x-ui" || -f "/usr/bin/x-ui" ]]; then
        print_warning "⚠ 3x-ui уже установлен: найден исполняемый файл x-ui"
        found=true
    fi
    
    # Проверка systemd сервиса
    if systemctl list-unit-files | grep -q "x-ui.service"; then
        print_warning "⚠ 3x-ui уже установлен: найден systemd сервис x-ui"
        found=true
    fi
    
    # Проверка запущенного сервиса
    if systemctl is-active --quiet x-ui 2>/dev/null; then
        print_warning "⚠ 3x-ui уже запущен (systemd сервис активен)"
        found=true
    fi
    
    if [[ "$found" == "true" ]]; then
        echo
        print_warning "Продолжение установки может привести к конфликтам или перезаписи существующей установки!"
        return 1
    fi
    
    return 0
}

# Функция проверки установленного Outline VPN
check_outline_installed() {
    local found=false
    
    # Проверка контейнеров Outline
    if docker ps -a --format "{{.Names}}" | grep -q "shadowbox\|outline"; then
        print_warning "⚠ Outline VPN уже установлен: найдены Docker контейнеры"
        found=true
    fi
    
    # Проверка запущенных контейнеров
    if docker ps --format "{{.Names}}" | grep -q "shadowbox\|outline"; then
        print_warning "⚠ Outline VPN уже запущен"
        found=true
    fi
    
    # Проверка директорий
    if [[ -d "/opt/outline" || -d "/var/lib/outline" || -d "/opt/outline-server" ]]; then
        print_warning "⚠ Outline VPN уже установлен: найдены директории с данными"
        found=true
    fi
    
    # Проверка systemd сервиса
    if systemctl list-unit-files | grep -q "outline-server.service"; then
        print_warning "⚠ Outline VPN уже установлен: найден systemd сервис outline-server"
        found=true
    fi
    
    if [[ "$found" == "true" ]]; then
        echo
        print_warning "Продолжение установки может привести к конфликтам или перезаписи существующей установки!"
        return 1
    fi
    
    return 0
}

# Функция проверки установленного Remnawave
check_remnawave_installed() {
    local found=false
    
    # Проверка Docker контейнеров Remnawave
    if docker ps -a --format "{{.Names}}" | grep -q "remnawave-panel\|remnawave-postgres"; then
        print_warning "⚠ Remnawave уже установлен: найдены Docker контейнеры"
        found=true
    fi
    
    # Проверка директорий
    if [[ -d "/opt/remnawave/panel" && -f "/opt/remnawave/panel/docker-compose.yml" ]]; then
        print_warning "⚠ Remnawave Panel уже установлен: найдена директория с конфигурацией"
        found=true
    fi
    
    # Проверка запущенных контейнеров
    if docker ps --format "{{.Names}}" | grep -q "remnawave-panel"; then
        print_warning "⚠ Remnawave Panel уже запущен"
        found=true
    fi
    
    if [[ "$found" == "true" ]]; then
        echo
        print_warning "Продолжение установки может привести к конфликтам или перезаписи существующей установки!"
        return 1
    fi
    
    return 0
}

# Функция проверки установленного Hysteria2
check_hysteria2_installed() {
    local found=false
    
    # Проверка команды hysteria
    if command -v hysteria &> /dev/null; then
        print_warning "⚠ Hysteria2 уже установлен: команда 'hysteria' доступна в системе"
        found=true
    fi
    
    # Проверка исполняемых файлов
    if [[ -f "/usr/local/bin/hysteria" || -f "/usr/bin/hysteria" ]]; then
        print_warning "⚠ Hysteria2 уже установлен: найден исполняемый файл"
        found=true
    fi
    
    # Проверка директорий
    if [[ -d "/opt/hysteria" || -d "/etc/hysteria" ]]; then
        print_warning "⚠ Hysteria2 уже установлен: найдены директории с данными"
        found=true
    fi
    
    # Проверка systemd сервиса
    if systemctl list-unit-files | grep -q "hysteria.service\|hysteria-server.service"; then
        print_warning "⚠ Hysteria2 уже установлен: найден systemd сервис"
        found=true
    fi
    
    # Проверка запущенного сервиса
    if systemctl is-active --quiet hysteria 2>/dev/null || systemctl is-active --quiet hysteria-server 2>/dev/null; then
        print_warning "⚠ Hysteria2 уже запущен (systemd сервис активен)"
        found=true
    fi
    
    if [[ "$found" == "true" ]]; then
        echo
        print_warning "Продолжение установки может привести к конфликтам или перезаписи существующей установки!"
        return 1
    fi
    
    return 0
}

# Функция создания директории для данных
create_data_directory() {
    local path=$1
    print_info "Создание директории для данных: $path"
    
    mkdir -p "$path"
    chmod 755 "$path"
    
    print_success "Директория создана"
}

# Функция генерации пароля
generate_password() {
    if [[ -z "$CURRENT_PASSWORD" ]]; then
        CURRENT_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    fi
}

# Проверка и загрузка образа wg-easy
ensure_wg_easy_image() {
    print_info "Проверка образа wg-easy..."
    
    if ! docker images | grep -q "ghcr.io/wg-easy/wg-easy"; then
        print_info "Образ wg-easy не найден, загружаем..."
        if docker pull ghcr.io/wg-easy/wg-easy:latest; then
            print_success "Образ wg-easy загружен"
        else
            print_error "Не удалось загрузить образ wg-easy"
            exit 1
        fi
    else
        print_success "Образ wg-easy уже доступен"
    fi
}

# Генерация bcrypt-хеша пароля для wg-easy
generate_bcrypt_hash() {
    print_info "Генерирую bcrypt-хэш..."
    
    # Убеждаемся что образ доступен
    ensure_wg_easy_image
    
    # Генерируем хеш используя команду wgpw
    echo "Генерирую bcrypt-хэш..."
    CURRENT_PASSWORD_HASH=$(docker run --rm ghcr.io/wg-easy/wg-easy wgpw "$CURRENT_PASSWORD" | grep PASSWORD_HASH | cut -d= -f2- | tr -d "'\" ")
    
    if [[ -n "$CURRENT_PASSWORD_HASH" ]]; then
        print_info "Исходный bcrypt-хеш: $CURRENT_PASSWORD_HASH"
        
        # Заменяем $ на $$ для docker-compose
        CURRENT_PASSWORD_HASH_ESCAPED=$(echo "$CURRENT_PASSWORD_HASH" | sed 's/\$/\$\$/g')
        print_info "Хеш для docker-compose: $CURRENT_PASSWORD_HASH_ESCAPED"
        print_success "bcrypt-хеш сгенерирован"
        return 0
    fi
    
    print_error "Не удалось сгенерировать bcrypt-хеш"
    return 1
}

# Функция получения списка IP-адресов
get_available_ips() {
    print_info "Получение списка доступных IP-адресов..."
    
    local ips=()
    local interfaces=()
    local descriptions=()
    local index=1
    
    # Получаем все сетевые интерфейсы
    while IFS= read -r line; do
        if [[ $line =~ ^[0-9]+:[[:space:]]+([^:]+): ]]; then
            local interface="${BASH_REMATCH[1]}"
            
            # Пропускаем loopback и docker интерфейсы
            if [[ "$interface" == "lo" || "$interface" == "docker"* || "$interface" == "veth"* ]]; then
                continue
            fi
            
            # Получаем IP-адрес для интерфейса (убираем маску подсети)
            local ip=$(ip -4 addr show "$interface" 2>/dev/null | grep -oP 'inet \K[0-9.]+' | head -1)
            
            if [[ -n "$ip" ]]; then
                # Получаем описание интерфейса
                local description=""
                if [[ -f "/sys/class/net/$interface/device/uevent" ]]; then
                    description=$(grep -oP 'DRIVER=\K.*' "/sys/class/net/$interface/device/uevent" 2>/dev/null || echo "Unknown")
                else
                    description="Virtual"
                fi
                
                ips+=("$ip")
                interfaces+=("$interface")
                descriptions+=("$description")
                echo -e "  ${CYAN}$index)${NC} $ip (интерфейс: $interface, тип: $description)"
                ((index++))
            fi
        fi
    done < <(ip link show)
    
    # Добавляем внешний IP как опцию
    local external_ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "")
    if [[ -n "$external_ip" ]]; then
        ips+=("$external_ip")
        interfaces+=("external")
        descriptions+=("External")
        echo -e "  ${CYAN}$index)${NC} $external_ip (внешний IP)"
        ((index++))
    fi
    
    # Если нет IP-адресов, используем localhost
    if [[ ${#ips[@]} -eq 0 ]]; then
        ips+=("127.0.0.1")
        interfaces+=("lo")
        descriptions+=("Localhost")
        echo -e "  ${CYAN}1)${NC} 127.0.0.1 (localhost)"
    fi
    
    echo
    
    # Выбор IP-адреса
    local selected_index=0
    while [[ $selected_index -lt 1 || $selected_index -gt ${#ips[@]} ]]; do
        read -p "Выберите IP-адрес (1-${#ips[@]}): " -r selected_index
        if [[ ! "$selected_index" =~ ^[0-9]+$ ]]; then
            print_error "Пожалуйста, введите число от 1 до ${#ips[@]}"
            selected_index=0
        fi
    done
    
    # Возвращаем выбранный IP
    local selected_ip="${ips[$((selected_index-1))]}"
    local selected_interface="${interfaces[$((selected_index-1))]}"
    local selected_description="${descriptions[$((selected_index-1))]}"
    
    print_success "Выбран IP: $selected_ip (интерфейс: $selected_interface, тип: $selected_description)"
    
    # Сохраняем выбранный IP в глобальную переменную
    CURRENT_IP="$selected_ip"
    CURRENT_INTERFACE="$selected_interface"
}




# Функция запуска wg-easy
start_wg_easy() {
    print_info "Запуск wg-easy..."
    
    # Останавливаем и удаляем ранее запущенный контейнер, если есть
    docker rm -f wg-easy 2>/dev/null || true
    
    # Переходим в директорию с docker-compose.yml
    cd "$DEFAULT_DATA_PATH"
    
    # Запуск wg-easy через docker-compose
    if docker compose up -d; then
        print_success "wg-easy успешно запущен"
    else
        print_error "Ошибка при запуске wg-easy"
        exit 1
    fi
}



# Функция остановки VPN
stop_vpn() {
    local vpn_name=$1
    print_info "Остановка $vpn_name..."
    
    if [[ "$vpn_name" == "wg-easy" ]]; then
        # Для wg-easy используем docker-compose
        if [[ -d "$DEFAULT_DATA_PATH" ]]; then
            cd "$DEFAULT_DATA_PATH"
            if docker compose down; then
                print_success "$vpn_name остановлен"
            else
                print_error "Ошибка при остановке $vpn_name"
            fi
        else
            print_warning "Директория $DEFAULT_DATA_PATH не найдена"
        fi
    elif [[ -d "$CURRENT_DATA_PATH" ]]; then
        cd "$CURRENT_DATA_PATH"
        if docker compose down; then
            print_success "$vpn_name остановлен"
        else
            print_error "Ошибка при остановке $vpn_name"
        fi
    else
        print_warning "Директория $CURRENT_DATA_PATH не найдена"
    fi
}

# Функция очистки
cleanup() {
    print_warning "Выполняется полная очистка..."
    
    # Очистка wg-easy
    cleanup_wg_easy
    
    # Очистка 3x-ui
    cleanup_3x_ui
    
    # Очистка Outline VPN
    cleanup_outline
    
    # Очистка Remnawave
    cleanup_remnawave
    
    # Очистка Hysteria2
    cleanup_hysteria2
    
    print_success "Полная очистка завершена"
}

# Функция очистки 3x-ui
cleanup_3x_ui() {
    print_warning "Выполняется очистка 3x-ui..."
    
    # Использование официальной команды x-ui uninstall
    if command -v x-ui &> /dev/null; then
        print_info "Использование команды x-ui uninstall для удаления..."
        if x-ui uninstall; then
            print_success "3x-ui успешно удален через x-ui uninstall"
        else
            print_error "3x-ui успешно удален через x-ui uninstall"
        fi
    else
        print_warning "x-ui не найден. Возможно, он уже удален или не был установлен."
    fi
}

# Функция очистки wg-easy
cleanup_wg_easy() {
    print_warning "Выполняется очистка wg-easy..."
    
    # Остановка и удаление Docker контейнеров wg-easy через docker-compose
    print_info "Остановка и удаление Docker контейнеров wg-easy..."
    if [[ -d "$DEFAULT_DATA_PATH" ]]; then
        cd "$DEFAULT_DATA_PATH"
        docker compose down 2>/dev/null || true
    fi
    
    # Остановка и удаление контейнера wg-easy напрямую (если docker-compose не сработал)
    docker stop wg-easy 2>/dev/null || true
    docker rm wg-easy 2>/dev/null || true
    
    # Удаление образа wg-easy
    print_info "Удаление образа wg-easy..."
    docker rmi ghcr.io/wg-easy/wg-easy:latest 2>/dev/null || true
    
    # Удаление директорий с данными wg-easy
    print_info "Удаление директорий с данными wg-easy..."
    rm -rf "$DEFAULT_DATA_PATH" 2>/dev/null || true
    rm -rf "/opt/wg-easy" 2>/dev/null || true
    
    # Удаление сетей wg-easy
    print_info "Удаление сетей wg-easy..."
    docker network rm wg-network 2>/dev/null || true
    
    print_success "Очистка wg-easy завершена"
}

# Функция очистки Outline VPN
cleanup_outline() {
    print_warning "Выполняется очистка Outline VPN..."
    
    # Остановка и удаление всех контейнеров, связанных с Outline
    print_info "Остановка и удаление всех контейнеров Outline..."
    
    # Остановка и удаление контейнеров Outline
    docker stop $(docker ps -q --filter "ancestor=quay.io/outline/shadowbox:stable") 2>/dev/null || true
    docker rm $(docker ps -aq --filter "ancestor=quay.io/outline/shadowbox:stable") 2>/dev/null || true
    
    # Остановка и удаление watchtower (часто устанавливается вместе с Outline)
    print_info "Остановка и удаление watchtower..."
    docker stop watchtower 2>/dev/null || true
    docker rm watchtower 2>/dev/null || true
    
    # Остановка и удаление контейнера shadowbox (основной контейнер Outline)
    print_info "Остановка и удаление shadowbox..."
    docker stop shadowbox 2>/dev/null || true
    docker rm shadowbox 2>/dev/null || true
    
    # Остановка и удаление контейнера prometheus (мониторинг Outline)
    print_info "Остановка и удаление prometheus..."
    docker stop prometheus 2>/dev/null || true
    docker rm prometheus 2>/dev/null || true
    
    # Остановка и удаление других возможных контейнеров Outline по имени
    print_info "Остановка и удаление других контейнеров Outline..."
    docker stop $(docker ps -q --filter "name=outline*") 2>/dev/null || true
    docker rm $(docker ps -aq --filter "name=outline*") 2>/dev/null || true
    
    # Остановка и удаление контейнеров по образам Outline
    print_info "Остановка и удаление контейнеров по образам Outline..."
    docker stop $(docker ps -q --filter "ancestor=quay.io/outline/prometheus:stable") 2>/dev/null || true
    docker rm $(docker ps -aq --filter "ancestor=quay.io/outline/prometheus:stable") 2>/dev/null || true
    
    # Удаление образов Outline
    print_info "Удаление образов Outline..."
    docker rmi quay.io/outline/shadowbox:stable 2>/dev/null || true
    docker rmi quay.io/outline/prometheus:stable 2>/dev/null || true
    docker rmi containrrr/watchtower:latest 2>/dev/null || true
    
    # Удаление директорий с данными Outline
    print_info "Удаление директорий с данными Outline..."
    rm -rf /opt/outline 2>/dev/null || true
    rm -rf /var/lib/outline 2>/dev/null || true
    
    # Удаление конфигурационных файлов
    print_info "Удаление конфигурационных файлов Outline..."
    rm -rf /opt/outline-server 2>/dev/null || true
    rm -rf /etc/outline 2>/dev/null || true
    
    # Удаление systemd сервисов (если есть)
    print_info "Удаление systemd сервисов Outline..."
    systemctl stop outline-server 2>/dev/null || true
    systemctl disable outline-server 2>/dev/null || true
    rm -f /etc/systemd/system/outline-server.service 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    
    # Очистка Docker томов, связанных с Outline
    print_info "Очистка Docker томов Outline..."
    docker volume rm $(docker volume ls -q --filter "name=outline*") 2>/dev/null || true
    
    # Очистка Docker сетей, связанных с Outline
    print_info "Очистка Docker сетей Outline..."
    docker network rm $(docker network ls -q --filter "name=outline*") 2>/dev/null || true
    
    print_success "Очистка Outline VPN завершена"
}

# Функция очистки Remnawave
cleanup_remnawave() {
    print_warning "Выполняется очистка Remnawave..."
    
    # Остановка и удаление Docker контейнеров
    print_info "Остановка и удаление Docker контейнеров Remnawave..."
    if [[ -d "/opt/remnawave/panel" ]]; then
        cd /opt/remnawave/panel
        docker compose down -v 2>/dev/null || true
    fi
    
    # Остановка контейнеров напрямую (если docker-compose не сработал)
    docker stop remnawave-panel 2>/dev/null || true
    docker stop remnawave-postgres 2>/dev/null || true
    docker rm remnawave-panel 2>/dev/null || true
    docker rm remnawave-postgres 2>/dev/null || true
    
    # Удаление образов
    print_info "Удаление Docker образов Remnawave..."
    docker rmi ghcr.io/remnawave/backend:latest 2>/dev/null || true
    
    # Удаление Docker томов
    print_info "Удаление Docker томов Remnawave..."
    docker volume rm panel_postgres_data 2>/dev/null || true
    docker volume rm panel_panel_data 2>/dev/null || true
    docker volume ls -q | grep remnawave | xargs -r docker volume rm 2>/dev/null || true
    
    # Удаление Docker сетей
    print_info "Удаление Docker сетей Remnawave..."
    docker network rm panel_remnawave 2>/dev/null || true
    docker network ls -q | grep remnawave | xargs -r docker network rm 2>/dev/null || true
    
    # Удаление директорий с данными
    print_info "Удаление директорий с данными Remnawave..."
    rm -rf /opt/remnawave 2>/dev/null || true
    rm -rf /etc/remnawave 2>/dev/null || true
    
    print_success "Очистка Remnawave завершена"
}

# Функция очистки Hysteria2
cleanup_hysteria2() {
    print_warning "Выполняется очистка Hysteria2..."
    
    # Остановка и отключение systemd сервисов
    print_info "Остановка systemd сервиса Hysteria2..."
    systemctl stop hysteria 2>/dev/null || true
    systemctl stop hysteria-server 2>/dev/null || true
    systemctl disable hysteria 2>/dev/null || true
    systemctl disable hysteria-server 2>/dev/null || true
    
    # Удаление systemd сервисов
    print_info "Удаление systemd сервисов Hysteria2..."
    rm -f /etc/systemd/system/hysteria.service 2>/dev/null || true
    rm -f /etc/systemd/system/hysteria-server.service 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    
    # Удаление исполняемых файлов
    print_info "Удаление исполняемых файлов Hysteria2..."
    rm -f /usr/local/bin/hysteria 2>/dev/null || true
    rm -f /usr/bin/hysteria 2>/dev/null || true
    
    # Удаление директорий с данными
    print_info "Удаление директорий с данными Hysteria2..."
    rm -rf /opt/hysteria 2>/dev/null || true
    rm -rf /etc/hysteria 2>/dev/null || true
    rm -rf /var/log/hysteria 2>/dev/null || true
    
    # Удаление сертификатов
    print_info "Удаление сертификатов Hysteria2..."
    rm -rf /root/.hysteria 2>/dev/null || true
    
    print_success "Очистка Hysteria2 завершена"
}



# Функция получения пользовательского ввода
get_user_input() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    
    if [[ -n "$default" ]]; then
        echo -e -n "${CYAN}$prompt [${WHITE}$default${CYAN}]: ${NC}"
    else
        echo -e -n "${CYAN}$prompt: ${NC}"
    fi
    
    read -r input
    
    if [[ -z "$input" && -n "$default" ]]; then
        input="$default"
    fi
    
    eval "$var_name=\"$input\""
}

# Функция настройки wg-easy
setup_wg_easy() {
    print_header
    print_info "Настройка wg-easy"
    print_separator
    
    # Проверка на уже установленный wg-easy
    if ! check_wg_easy_installed; then
        echo
        read -p "Продолжить установку несмотря на предупреждение? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Установка отменена"
            return 1
        fi
        echo
    fi
    
    CURRENT_VPN="wg-easy"
    
    # === 1. Сбор данных у пользователя ===
    get_user_input "Введите порт для Web UI" "51821" "CURRENT_WEB_PORT"
    get_user_input "Введите порт WireGuard (UDP)" "51820" "CURRENT_PORT"
    
    # Выбор IP-адреса
    print_info "Выбор IP-адреса для wg-easy..."
    get_available_ips
    
    # Выбор языка интерфейса
    echo -e "${CYAN}Выберите язык интерфейса:${NC}"
    echo -e "  ${CYAN}1)${NC} Русский (по умолчанию)"
    echo -e "  ${CYAN}2)${NC} Английский"
    echo
    read -p "Выберите язык (1-2) [1]: " -r lang_choice
    lang_choice=${lang_choice:-1}
    
    case $lang_choice in
        1|"")
            CURRENT_LANG="ru"
            ;;
        2)
            CURRENT_LANG="en"
            ;;
        *)
            print_error "Неверный выбор языка. Используется русский по умолчанию."
            CURRENT_LANG="ru"
            ;;
    esac
    
    # Запрос пароля (без отображения) с повторными попытками
    while true; do
        read -rsp "Введите пароль для Web UI: " CURRENT_PASSWORD
        echo
        read -rsp "Повторите пароль: " CURRENT_PASSWORD2
        echo
        
        if [ "$CURRENT_PASSWORD" != "$CURRENT_PASSWORD2" ]; then
            print_error "Пароли не совпадают! Попробуйте еще раз."
            echo
        else
            break
        fi
    done
    

    
    print_separator
    print_info "Параметры установки:"
    echo -e "  VPN: ${WHITE}$CURRENT_VPN${NC}"
    echo -e "  WG_HOST: ${WHITE}$CURRENT_IP${NC}"
    echo -e "  Порт Web UI: ${WHITE}$CURRENT_WEB_PORT${NC}"
    echo -e "  Порт WireGuard: ${WHITE}$CURRENT_PORT${NC}"
    echo -e "  Язык интерфейса: ${WHITE}$CURRENT_LANG${NC}"
    echo -e "  Путь данных: ${WHITE}$DEFAULT_DATA_PATH${NC}"

    
    read -p "Продолжить установку? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_wg_easy
    else
        print_info "Установка отменена"
        return 1
    fi
}

# Функция настройки 3x-ui
setup_3x_ui() {
    print_header
    print_info "Настройка 3x-ui"
    print_separator
    
    # Проверка на уже установленный 3x-ui
    if ! check_3x_ui_installed; then
        echo
        read -p "Продолжить установку несмотря на предупреждение? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Установка отменена"
            return 1
        fi
        echo
    fi
    
    CURRENT_VPN="3x-ui"
    
    # Выбор IP-адреса
    get_available_ips
    
    print_separator
    print_info "Параметры установки:"
    echo -e "  VPN: ${WHITE}$CURRENT_VPN${NC}"
    echo -e "  IP-адрес: ${WHITE}$CURRENT_IP${NC} (интерфейс: $CURRENT_INTERFACE)"
    print_separator
    
    read -p "Продолжить установку? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_3x_ui_official
    else
        print_info "Установка отменена"
        return 1
    fi
}

# Функция установки wg-easy
install_wg_easy() {
    print_header
    print_info "Установка wg-easy"
    print_separator
    
    # Проверка существующих контейнеров
    if ! check_existing_containers "wg-easy"; then
        print_warning "Найдены существующие контейнеры wg-easy"
        read -p "Удалить существующие контейнеры? (y/N): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            stop_vpn "wg-easy"
            docker rm -f wg-easy 2>/dev/null || true
        else
            print_info "Установка отменена"
            return 1
        fi
    fi
    
    # Проверка и загрузка образа wg-easy (если необходимо)
    ensure_wg_easy_image
    
    # Генерация bcrypt-хеша пароля для PASSWORD_HASH
    if ! generate_bcrypt_hash; then
        print_error "Ошибка генерации хеша. Установка прервана."
        return 1
    fi
    
    # === 3. Подготовка папки и compose-файла ===
    print_info "Подготовка папки и compose-файла..."
    INSTALL_DIR="$DEFAULT_DATA_PATH"
    mkdir -p "$INSTALL_DIR/etc_wireguard"
    cd "$INSTALL_DIR"

    cat > docker-compose.yml <<EOF
version: "3.8"
services:
  wg-easy:
    image: ghcr.io/wg-easy/wg-easy:latest
    container_name: wg-easy
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      net.ipv4.conf.all.src_valid_mark: 1
      net.ipv4.ip_forward: 1
    ports:
      - "${CURRENT_PORT}:${CURRENT_PORT}/udp"
      - "${CURRENT_WEB_PORT}:${CURRENT_WEB_PORT}/tcp"
    volumes:
      - ./etc_wireguard:/etc/wireguard
    environment:
      - WG_HOST=${CURRENT_IP}
      - PASSWORD_HASH=${CURRENT_PASSWORD_HASH_ESCAPED}
      - PORT=${CURRENT_WEB_PORT}
      - WG_PORT=${CURRENT_PORT}
      - LANG=${CURRENT_LANG}
EOF

    # === 4. Запуск ===
    print_info "Запускаю wg-easy..."
    docker compose up -d
    
    print_separator
    print_success "Установка завершена!"
    print_info "Web UI: http://$CURRENT_IP:$CURRENT_WEB_PORT"
    print_info "Логин: admin"
    print_info "Пароль: $CURRENT_PASSWORD"
    print_info "Файлы WireGuard будут храниться в: $DEFAULT_DATA_PATH/etc_wireguard"
    print_separator
    
    read -p "Нажмите Enter для возврата в главное меню..."
}



# Функция установки 3x-ui
install_3x_ui_official() {
    print_header
    print_info "Установка 3x-ui"
    print_separator
    
    print_info "Установка 3x-ui через официальный скрипт"
    print_info "Официальный скрипт установки: https://github.com/MHSanaei/3x-ui"
    
    print_info "Загрузка и запуск официального скрипта установки..."
    
    # Загрузка и запуск официального скрипта
    if bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh); then
        print_success "3x-ui успешно установлен!"
        print_info "Веб-интерфейс обычно доступен по адресу: http://$CURRENT_IP:54321"
    else
        print_error "Ошибка при установке 3x-ui"
    fi
    
    print_separator
    read -p "Нажмите Enter для возврата в главное меню..."
}

# Функция настройки Outline VPN
setup_outline() {
    print_header
    print_info "Настройка Outline VPN"
    print_separator
    
    # Проверка на уже установленный Outline VPN
    if ! check_outline_installed; then
        echo
        read -p "Продолжить установку несмотря на предупреждение? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Установка отменена"
            return 1
        fi
        echo
    fi
    
    CURRENT_VPN="outline"
    
    # Выбор IP-адреса
    get_available_ips
    
    print_separator
    print_info "Параметры установки:"
    echo -e "  VPN: ${WHITE}$CURRENT_VPN${NC}"
    echo -e "  IP-адрес: ${WHITE}$CURRENT_IP${NC} (интерфейс: $CURRENT_INTERFACE)"
    print_separator
    
    read -p "Продолжить установку? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_outline
    else
        print_info "Установка отменена"
        return 1
    fi
}

# Функция установки Outline VPN
install_outline() {
    print_header
    print_info "Установка Outline VPN"
    print_separator
    
    print_info "Outline VPN - это бесплатный инструмент с открытым исходным кодом от Google"
    print_info "для развертывания собственной VPN на вашем сервере"
    
    # Установка Outline Server
    print_info "Установка Outline Server..."
    
    # Загрузка и запуск официального скрипта установки
    if sudo wget -qO- https://raw.githubusercontent.com/Jigsaw-Code/outline-server/master/src/server_manager/install_scripts/install_server.sh | bash; then
        print_success "Outline Server успешно установлен!"
        
        # Получение информации о сервере
        print_info "Информация о сервере (сохраните для Outline Manager):"
        print_info "Скопируйте и сохраните вывод выше для настройки Outline Manager"
        
        print_separator
        print_info "Следующие шаги:"
        print_info "1. Скачайте Outline Manager для вашей ОС:"
        print_info "   - Windows/Mac/Linux: https://getoutline.org/get-started/#step-3"
        print_info "2. Запустите Outline Manager и выберите 'Настроить Outline где угодно'"
        print_info "3. Вставьте полученный ключ и адрес сервера"
        print_info "4. Создайте ключи для клиентов в Outline Manager"
        print_info "5. Скачайте клиенты Outline для устройств:"
        print_info "   - Android: Google Play Store"
        print_info "   - iOS: App Store"
        print_info "   - Windows/Mac/Linux: https://getoutline.org/get-started/#step-3"
        
    else
        print_error "Ошибка при установке Outline Server"
        print_info "Возможные решения:"
        print_info "- Проверьте подключение к интернету"
        print_info "- Попробуйте запустить скрипт позже (репозиторий может быть временно недоступен)"
        print_info "- Убедитесь, что порты 443 и 1024-65535 открыты"
    fi
    
    print_separator
    read -p "Нажмите Enter для возврата в главное меню..."
}

# Функция настройки Remnawave
setup_remnawave() {
    print_header
    print_info "Настройка Remnawave"
    print_separator
    
    # Проверка на уже установленный Remnawave
    if ! check_remnawave_installed; then
        echo
        read -p "Продолжить установку несмотря на предупреждение? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Установка отменена"
            return 1
        fi
        echo
    fi
    
    CURRENT_VPN="remnawave"
    
    # Вывод информации о требованиях
    print_info "Remnawave - это система Panel + Node для управления VPN"
    print_info "Документация: https://docs.rw/"
    echo
    print_warning "Требования для установки:"
    echo -e "  ${CYAN}•${NC} Docker и Docker Compose (будут установлены автоматически)"
    echo -e "  ${CYAN}•${NC} PostgreSQL (будет установлен в контейнере)"
    echo -e "  ${CYAN}•${NC} Reverse proxy с SSL (нужно настроить вручную после установки)"
    echo -e "  ${CYAN}•${NC} Доменное имя (рекомендуется)"
    echo
    
    # Выбор IP-адреса
    print_info "Выбор IP-адреса для панели управления..."
    get_available_ips
    
    # Запрос порта для панели
    get_user_input "Введите порт для Remnawave Panel" "3000" "CURRENT_PORT"
    
    print_separator
    print_info "Параметры установки:"
    echo -e "  VPN: ${WHITE}$CURRENT_VPN${NC}"
    echo -e "  IP-адрес Panel: ${WHITE}$CURRENT_IP${NC}"
    echo -e "  Порт Panel: ${WHITE}$CURRENT_PORT${NC}"
    echo -e "  База данных: ${WHITE}PostgreSQL (в Docker)${NC}"
    print_separator
    
    read -p "Продолжить установку Remnawave Panel? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_remnawave
    else
        print_info "Установка отменена"
        return 1
    fi
}

# Функция установки Remnawave
install_remnawave() {
    print_header
    print_info "Установка Remnawave"
    print_separator
    
    print_info "Remnawave - это современная панель управления VPN с архитектурой Panel + Node"
    print_info "Официальная документация: https://docs.rw/"
    echo
    
    print_info "Remnawave состоит из двух компонентов:"
    print_info "1. Remnawave Panel - веб-панель управления (требует PostgreSQL)"
    print_info "2. Remnawave Node - VPN сервер"
    echo
    
    print_warning "ВНИМАНИЕ: Для полноценной работы Remnawave требуется:"
    print_info "✓ Docker и Docker Compose"
    print_info "✓ PostgreSQL база данных"
    print_info "✓ Reverse proxy (Nginx/Caddy) с SSL"
    print_info "✓ Доменное имя"
    echo
    
    read -p "Установить Remnawave Panel с PostgreSQL? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Установка отменена"
        read -p "Нажмите Enter для возврата в главное меню..."
        return 1
    fi
    
    # Проверка Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker не установлен!"
        read -p "Нажмите Enter для возврата в главное меню..."
        return 1
    fi
    
    # Создание директорий
    print_info "Создание директорий..."
    mkdir -p /opt/remnawave/panel
    mkdir -p /opt/remnawave/node
    mkdir -p /etc/remnawave
    
    # Проверка переменных
    if [[ -z "$CURRENT_PORT" ]]; then
        CURRENT_PORT="3000"
        print_warning "Порт не установлен, используется значение по умолчанию: $CURRENT_PORT"
    fi
    
    if [[ -z "$CURRENT_IP" ]]; then
        print_error "IP-адрес не установлен!"
        read -p "Нажмите Enter для возврата в главное меню..."
        return 1
    fi
    
    # Генерация паролей
    print_info "Генерация паролей..."
    DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    JWT_SECRET=$(openssl rand -base64 64 | tr -d "=+/" | cut -c1-64)
    
    # Проверка сгенерированных паролей
    if [[ -z "$DB_PASSWORD" || -z "$JWT_SECRET" ]]; then
        print_error "Ошибка при генерации паролей"
        read -p "Нажмите Enter для возврата в главное меню..."
        return 1
    fi
    
    cd /opt/remnawave/panel
    
    # Создание docker-compose для Panel + PostgreSQL
    print_info "Создание конфигурации Docker Compose..."
    
    # Экранирование паролей для URL (URL encoding специальных символов)
    if command -v python3 &> /dev/null; then
        DB_PASSWORD_URL=$(python3 -c "import urllib.parse; import sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$DB_PASSWORD" 2>/dev/null)
    fi
    
    # Если Python не доступен, используем sed для базового экранирования
    if [[ -z "$DB_PASSWORD_URL" ]]; then
        DB_PASSWORD_URL=$(echo "$DB_PASSWORD" | sed 's/:/%3A/g' | sed 's/@/%40/g' | sed 's/#/%23/g' | sed 's/\$/%24/g' | sed 's/&/%26/g' | sed 's/+/%2B/g' | sed 's/=/%3D/g' | sed 's/\?/%3F/g' | sed 's/\//%2F/g' | sed 's/ /%20/g')
    fi
    
    # Создание docker-compose.yml с использованием printf для безопасной вставки переменных
    {
        echo "version: '3.8'"
        echo ""
        echo "services:"
        echo "  postgres:"
        echo "    image: postgres:16-alpine"
        echo "    container_name: remnawave-postgres"
        echo "    restart: unless-stopped"
        echo "    environment:"
        echo "      POSTGRES_DB: remnawave"
        echo "      POSTGRES_USER: remnawave"
        printf "      POSTGRES_PASSWORD: '%s'\n" "${DB_PASSWORD}"
        echo "    volumes:"
        echo "      - postgres_data:/var/lib/postgresql/data"
        echo "    networks:"
        echo "      - remnawave"
        echo "    healthcheck:"
        echo "      test:"
        echo "        - CMD-SHELL"
        echo "        - pg_isready -U remnawave"
        echo "      interval: 10s"
        echo "      timeout: 5s"
        echo "      retries: 5"
        echo ""
        echo "  panel:"
        echo "    image: ghcr.io/remnawave/backend:latest"
        echo "    container_name: remnawave-panel"
        echo "    restart: unless-stopped"
        echo "    ports:"
        printf "      - '%s:3000'\n" "${CURRENT_PORT}"
        echo "    environment:"
        printf "      DATABASE_URL: 'postgresql://remnawave:%s@postgres:5432/remnawave'\n" "${DB_PASSWORD_URL}"
        printf "      JWT_SECRET: '%s'\n" "${JWT_SECRET}"
        echo "      NODE_ENV: production"
        echo "      PORT: '3000'"
        echo "    depends_on:"
        echo "      postgres:"
        echo "        condition: service_healthy"
        echo "    networks:"
        echo "      - remnawave"
        echo "    volumes:"
        echo "      - panel_data:/app/data"
        echo ""
        echo "networks:"
        echo "  remnawave:"
        echo "    driver: bridge"
        echo ""
        echo "volumes:"
        echo "  postgres_data:"
        echo "  panel_data:"
    } > docker-compose.yml
    
    # Проверка созданного файла
    if [[ ! -f docker-compose.yml ]]; then
        print_error "Ошибка: файл docker-compose.yml не создан"
        read -p "Нажмите Enter для возврата в главное меню..."
        return 1
    fi
    
    # Проверка синтаксиса YAML (если доступен yamllint или docker compose config)
    print_info "Проверка синтаксиса конфигурации..."
    if docker compose config > /dev/null 2>&1; then
        print_success "Синтаксис конфигурации корректен"
    else
        print_warning "Предупреждение: возможна ошибка в синтаксисе конфигурации"
        print_info "Проверяю файл docker-compose.yml..."
        if docker compose config 2>&1 | head -20; then
            :
        else
            print_error "Ошибка в конфигурации docker-compose.yml"
            print_info "Содержимое файла:"
            cat docker-compose.yml
            read -p "Нажмите Enter для возврата в главное меню..."
            return 1
        fi
    fi
    
    # Запуск контейнеров
    print_info "Запуск Remnawave Panel и PostgreSQL..."
    if docker compose up -d; then
        # Ожидание запуска
        print_info "Ожидание запуска сервисов (30 секунд)..."
        sleep 30
        
        if docker ps | grep -q "remnawave-panel"; then
            print_success "Remnawave Panel успешно запущен!"
        else
            print_error "Ошибка при запуске Panel"
            print_info "Проверьте логи: docker compose logs"
            read -p "Нажмите Enter для возврата в главное меню..."
            return 1
        fi
    else
        print_error "Ошибка при запуске Docker Compose"
        read -p "Нажмите Enter для возврата в главное меню..."
        return 1
    fi
    
    print_separator
    print_success "Установка Remnawave Panel завершена!"
    echo
    print_info "📋 Информация для доступа:"
    echo -e "  Панель управления: ${WHITE}http://${CURRENT_IP}:${CURRENT_PORT}${NC}"
    echo -e "  База данных: ${WHITE}PostgreSQL${NC}"
    echo -e "  DB Password: ${WHITE}${DB_PASSWORD}${NC}"
    echo -e "  JWT Secret: ${WHITE}${JWT_SECRET}${NC}"
    echo
    print_warning "⚠ ВАЖНО: Сохраните эти данные в безопасном месте!"
    echo
    print_info "📚 Следующие шаги:"
    print_info "1. Настройте reverse proxy (Nginx/Caddy) для доступа к панели через домен"
    print_info "2. Получите SSL сертификат (Let's Encrypt/Certbot)"
    print_info "3. Откройте панель в браузере и завершите первоначальную настройку"
    print_info "4. Установите Remnawave Node (на этом или другом сервере)"
    echo
    print_info "📖 Официальная документация:"
    print_info "   Quick Start: https://docs.rw/docs/overview/quick-start/"
    print_info "   Panel Setup: https://docs.rw/docs/install/remnawave-panel/"
    print_info "   Node Setup: https://docs.rw/docs/install/remnawave-node/"
    print_info "   Reverse Proxy: https://docs.rw/docs/install/reverse-proxy/"
    echo
    print_info "🔧 Управление:"
    print_info "   Директория: cd /opt/remnawave/panel"
    print_info "   Логи Panel: docker compose logs -f panel"
    print_info "   Логи DB: docker compose logs -f postgres"
    print_info "   Перезапуск: docker compose restart"
    print_info "   Остановка: docker compose down"
    print_info "   Запуск: docker compose up -d"
    
    print_separator
    read -p "Нажмите Enter для возврата в главное меню..."
}

# Функция настройки Hysteria2
setup_hysteria2() {
    print_header
    print_info "Настройка Hysteria2"
    print_separator
    
    # Проверка на уже установленный Hysteria2
    if ! check_hysteria2_installed; then
        echo
        read -p "Продолжить установку несмотря на предупреждение? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Установка отменена"
            return 1
        fi
        echo
    fi
    
    CURRENT_VPN="hysteria2"
    
    # Выбор IP-адреса
    get_available_ips
    
    # Запрос порта
    get_user_input "Введите порт для Hysteria2" "443" "CURRENT_PORT"
    
    # Запрос пароля
    while true; do
        read -rsp "Введите пароль для Hysteria2: " CURRENT_PASSWORD
        echo
        read -rsp "Повторите пароль: " CURRENT_PASSWORD2
        echo
        
        if [ "$CURRENT_PASSWORD" != "$CURRENT_PASSWORD2" ]; then
            print_error "Пароли не совпадают! Попробуйте еще раз."
            echo
        else
            break
        fi
    done
    
    print_separator
    print_info "Параметры установки:"
    echo -e "  VPN: ${WHITE}$CURRENT_VPN${NC}"
    echo -e "  IP-адрес: ${WHITE}$CURRENT_IP${NC} (интерфейс: $CURRENT_INTERFACE)"
    echo -e "  Порт: ${WHITE}$CURRENT_PORT${NC}"
    print_separator
    
    read -p "Продолжить установку? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_hysteria2
    else
        print_info "Установка отменена"
        return 1
    fi
}

# Функция установки Hysteria2
install_hysteria2() {
    print_header
    print_info "Установка Hysteria2"
    print_separator
    
    print_info "Hysteria2 - это мощный прокси-протокол нового поколения"
    print_info "с высокой производительностью и обфускацией"
    print_info "Официальный сайт: https://v2.hysteria.network/"
    echo
    
    # Установка Hysteria2 через официальный скрипт
    print_info "Запуск официального скрипта установки..."
    print_info "Команда: bash <(curl -fsSL https://get.hy2.sh/)"
    echo
    
    if bash <(curl -fsSL https://get.hy2.sh/); then
        print_success "Hysteria2 успешно установлен!"
        echo
        
        # Создание директории для конфигурации
        print_info "Создание конфигурации сервера..."
        mkdir -p /etc/hysteria
        
        # Генерация самоподписанного сертификата
        print_info "Генерация самоподписанного SSL сертификата..."
        openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 \
            -nodes -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt \
            -subj "/CN=${CURRENT_IP}" \
            -addext "subjectAltName=IP:${CURRENT_IP}"
        
        print_success "Сертификат создан"
        echo
        
        # Создание конфигурационного файла сервера
        print_info "Создание файла конфигурации сервера..."
        cat > /etc/hysteria/config.yaml <<EOF
# Hysteria2 Server Configuration
# Документация: https://v2.hysteria.network/docs/getting-started/Server/

listen: :${CURRENT_PORT}

# TLS сертификаты
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

# Аутентификация
auth:
  type: password
  password: ${CURRENT_PASSWORD}

# Маскировка под обычный веб-сервер
masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
    rewriteHost: true

# Параметры QUIC
quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 8388608
  initConnReceiveWindow: 20971520
  maxConnReceiveWindow: 20971520
  maxIdleTimeout: 30s
  maxIncomingStreams: 1024
  disablePathMTUDiscovery: false

# Ограничения скорости (можно изменить)
bandwidth:
  up: 1 gbps
  down: 1 gbps

# Игнорирование ошибок клиентов
ignoreClientBandwidth: false
disableUDP: false
udpIdleTimeout: 60s

# Логирование (опционально)
# acme:
#   domains:
#     - your-domain.com
#   email: your-email@example.com
EOF
        
        print_success "Конфигурация создана: /etc/hysteria/config.yaml"
        echo
        
        # Создание systemd сервиса
        print_info "Создание systemd сервиса..."
        cat > /etc/systemd/system/hysteria-server.service <<EOF
[Unit]
Description=Hysteria2 Server Service
Documentation=https://v2.hysteria.network/
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/hysteria
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml
Restart=on-failure
RestartSec=5s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
        
        # Запуск и активация сервиса
        print_info "Запуск Hysteria2 сервера..."
        systemctl daemon-reload
        systemctl enable hysteria-server
        systemctl start hysteria-server
        
        sleep 3
        
        if systemctl is-active --quiet hysteria-server; then
            print_success "Hysteria2 сервер успешно запущен!"
        else
            print_error "Ошибка при запуске сервера"
            print_info "Проверьте логи: journalctl -u hysteria-server -f"
            print_separator
            read -p "Нажмите Enter для возврата в главное меню..."
            return 1
        fi
        
        print_separator
        print_success "✓ Установка Hysteria2 завершена!"
        echo
        print_info "📋 Информация для подключения:"
        echo -e "  Сервер: ${WHITE}${CURRENT_IP}:${CURRENT_PORT}${NC}"
        echo -e "  Пароль: ${WHITE}${CURRENT_PASSWORD}${NC}"
        echo
        print_warning "⚠ ВАЖНО: Сохраните эти данные!"
        echo
        print_info "📱 Конфигурация клиента (client.yaml):"
        print_separator
        cat <<CLIENTCONFIG
server: ${CURRENT_IP}:${CURRENT_PORT}

auth: ${CURRENT_PASSWORD}

tls:
  insecure: true
  sni: ${CURRENT_IP}

bandwidth:
  up: 100 mbps
  down: 100 mbps

socks5:
  listen: 127.0.0.1:1080

http:
  listen: 127.0.0.1:8080

fastOpen: true
lazy: false
CLIENTCONFIG
        print_separator
        echo
        print_info "💾 Сохраните конфигурацию выше в файл client.yaml"
        print_info "   Запуск клиента: hysteria client -c client.yaml"
        echo
        print_info "📂 Файлы сервера:"
        print_info "   Конфигурация: /etc/hysteria/config.yaml"
        print_info "   Сертификаты: /etc/hysteria/server.{crt,key}"
        print_info "   Бинарник: /usr/local/bin/hysteria"
        echo
        print_info "🔧 Управление сервером:"
        print_info "   Статус: systemctl status hysteria-server"
        print_info "   Запуск: systemctl start hysteria-server"
        print_info "   Остановка: systemctl stop hysteria-server"
        print_info "   Перезапуск: systemctl restart hysteria-server"
        print_info "   Логи: journalctl -u hysteria-server -f"
        echo
        print_info "📥 Скачать клиенты Hysteria2:"
        print_info "   Официальный сайт: https://v2.hysteria.network/docs/getting-started/Installation/"
        print_info "   Windows/Mac/Linux: https://v2.hysteria.network/docs/getting-started/Client/"
        print_info "   Android: v2rayNG, NekoBox"
        print_info "   iOS: Shadowrocket, Stash"
        echo
        print_info "📖 Документация:"
        print_info "   https://v2.hysteria.network/docs/getting-started/Server/"
        
    else
        print_error "Ошибка при установке Hysteria2"
        print_info "Попробуйте установить вручную:"
        print_info "   bash <(curl -fsSL https://get.hy2.sh/)"
        print_info ""
        print_info "Репозиторий: https://github.com/apernet/hysteria"
    fi
    
    print_separator
    read -p "Нажмите Enter для возврата в главное меню..."
}

# Функция показа статуса
show_status() {
    print_header
    print_info "Статус системы"
    print_separator
    
    # Статус Docker
    if systemctl is-active --quiet docker; then
        print_success "Docker: запущен"
    else
        print_error "Docker: остановлен"
    fi
    
    # Статус контейнеров
    print_info "Контейнеры:"
    if docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -q .; then
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    else
        print_warning "Нет запущенных контейнеров"
    fi
    
    print_separator
    
    # Статус VPN
    print_info "Найденные VPN:"
    
    # Проверка wg-easy
    if [[ -d "$DEFAULT_DATA_PATH" && -f "$DEFAULT_DATA_PATH/docker-compose.yml" ]]; then
        print_success "wg-easy: установлен в $DEFAULT_DATA_PATH"
    fi
    
    # Проверка 3x-ui
    if systemctl is-active --quiet x-ui 2>/dev/null; then
        print_success "3x-ui: установлен и запущен (systemd сервис)"
    elif [[ -f "/usr/local/bin/x-ui" || -f "/usr/bin/x-ui" ]]; then
        print_success "3x-ui: установлен (исполняемые файлы найдены)"
    fi
    
    # Проверка Outline VPN
    if docker ps --format "{{.Names}}" | grep -q "shadowbox"; then
        print_success "Outline VPN: установлен и запущен (Docker контейнер)"
    elif [[ -d "/opt/outline" || -d "/var/lib/outline" ]]; then
        print_success "Outline VPN: установлен (директории найдены)"
    fi
    
    # Проверка Remnawave
    if docker ps --format "{{.Names}}" | grep -q "remnawave-panel"; then
        print_success "Remnawave: установлен и запущен (Docker контейнеры)"
        if docker ps --format "{{.Names}}" | grep -q "remnawave-postgres"; then
            print_info "  └─ PostgreSQL: активен"
        fi
    elif [[ -d "/opt/remnawave/panel" && -f "/opt/remnawave/panel/docker-compose.yml" ]]; then
        print_success "Remnawave: установлен (конфигурация найдена, контейнеры остановлены)"
    fi
    
    # Проверка Hysteria2
    if systemctl is-active --quiet hysteria-server 2>/dev/null || systemctl is-active --quiet hysteria 2>/dev/null; then
        print_success "Hysteria2: установлен и запущен (systemd сервис)"
    elif [[ -f "/usr/local/bin/hysteria" || -f "/usr/bin/hysteria" ]]; then
        print_success "Hysteria2: установлен (исполняемый файл найден)"
    fi
    
    # Если нет установленных VPN
    local vpn_found=false
    [[ -d "$DEFAULT_DATA_PATH" ]] && vpn_found=true
    [[ -f "/usr/local/bin/x-ui" || -f "/usr/bin/x-ui" ]] && vpn_found=true
    [[ -d "/opt/outline" || -d "/var/lib/outline" ]] && vpn_found=true
    [[ -d "/opt/remnawave/panel" ]] && vpn_found=true
    [[ -f "/usr/local/bin/hysteria" ]] && vpn_found=true
    
    if [[ "$vpn_found" == "false" ]]; then
        print_warning "VPN не установлены"
    fi
    
    print_separator
    read -p "Нажмите Enter для возврата в главное меню..."
}

# Функция главного меню
main_menu() {
    while true; do
        print_header
        echo -e "${WHITE}Главное меню:${NC}"
        echo
        echo -e "${YELLOW}Установка VPN:${NC}"
        echo -e "  ${CYAN}1)${NC} Установить wg-easy"
        echo -e "  ${CYAN}2)${NC} Установить 3x-ui"
        echo -e "  ${CYAN}3)${NC} Установить Outline VPN"
        echo -e "  ${CYAN}4)${NC} Установить Remnawave"
        echo -e "  ${CYAN}5)${NC} Установить Hysteria2"
        echo
        echo -e "${YELLOW}Управление:${NC}"
        echo -e "  ${CYAN}6)${NC} Показать статус"
        echo -e "  ${CYAN}7)${NC} Остановить VPN"
        echo
        echo -e "${YELLOW}Очистка:${NC}"
        echo -e "  ${CYAN}8)${NC} Очистка wg-easy"
        echo -e "  ${CYAN}9)${NC} Очистка 3x-ui"
        echo -e "  ${CYAN}10)${NC} Очистка Outline VPN"
        echo -e "  ${CYAN}11)${NC} Очистка Remnawave"
        echo -e "  ${CYAN}12)${NC} Очистка Hysteria2"
        echo -e "  ${CYAN}13)${NC} Полная очистка (удалить всё)"
        echo
        echo -e "  ${CYAN}0)${NC} Выход"
        echo
        print_separator
        
        read -p "Выберите действие (0-13): " -r
        
        case $REPLY in
            1)
                setup_wg_easy
                ;;
            2)
                setup_3x_ui
                ;;
            3)
                setup_outline
                ;;
            4)
                setup_remnawave
                ;;
            5)
                setup_hysteria2
                ;;
            6)
                show_status
                ;;
            7)
                print_info "Остановка VPN..."
                stop_vpn "wg-easy"
                stop_vpn "3x-ui"
                read -p "Нажмите Enter для возврата в главное меню..."
                ;;
            8)
                print_warning "ВНИМАНИЕ: Это действие удалит wg-easy и все его данные!"
                read -p "Вы уверены? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    cleanup_wg_easy
                    read -p "Нажмите Enter для возврата в главное меню..."
                fi
                ;;
            9)
                print_warning "ВНИМАНИЕ: Это действие удалит 3x-ui и все его данные!"
                read -p "Вы уверены? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    cleanup_3x_ui
                    read -p "Нажмите Enter для возврата в главное меню..."
                fi
                ;;
            10)
                print_warning "ВНИМАНИЕ: Это действие удалит Outline VPN и все его данные!"
                read -p "Вы уверены? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    cleanup_outline
                    read -p "Нажмите Enter для возврата в главное меню..."
                fi
                ;;
            11)
                print_warning "ВНИМАНИЕ: Это действие удалит Remnawave и все его данные!"
                read -p "Вы уверены? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    cleanup_remnawave
                    read -p "Нажмите Enter для возврата в главное меню..."
                fi
                ;;
            12)
                print_warning "ВНИМАНИЕ: Это действие удалит Hysteria2 и все его данные!"
                read -p "Вы уверены? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    cleanup_hysteria2
                    read -p "Нажмите Enter для возврата в главное меню..."
                fi
                ;;
            13)
                print_warning "ВНИМАНИЕ: Это действие удалит ВСЕ контейнеры, образы и данные!"
                read -p "Вы уверены? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    cleanup
                    read -p "Нажмите Enter для возврата в главное меню..."
                fi
                ;;
            0)
                print_info "До свидания!"
                exit 0
                ;;
            *)
                print_error "Неверный выбор. Попробуйте снова."
                sleep 2
                ;;
        esac
    done
}

# Функция инициализации
init() {
    # Создание лог-файла
    touch "$LOG_FILE"
    
    print_header
    print_info "Инициализация системы..."
    print_separator
    
    # Проверка прав root
    check_root
    
    # Определение ОС
    detect_os
    
    # Проверка интернета
    check_internet
    
    # Обновление пакетов
    update_packages
    
    # Установка зависимостей
    install_dependencies
    
    # Установка Docker
    install_docker
    
    # Установка Docker Compose
    install_docker_compose
    
    # Проверка статуса Docker
    check_docker_status
    
    print_separator
    print_success "Система готова к работе!"
    print_separator
    
    sleep 2
}

# Главная функция
main() {
    # Обработка сигналов
    trap 'print_error "Скрипт прерван пользователем"; exit 1' INT TERM
    
    # Инициализация
    init
    
    # Запуск главного меню
    main_menu
}

# Запуск скрипта
main "$@"
