#!/bin/bash

# VPN Installer Script
# Универсальный скрипт для установки VPN
# Поддерживает: wg-easy (WireGuard через Docker), 3x-ui (Xray через официальный скрипт)
# Поддерживает: RedHat, Ubuntu, Debian и их производные

set -e

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
SCRIPT_VERSION="1.1.0"
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
CURRENT_DATA_PATH=""
CURRENT_IP=""
CURRENT_INTERFACE=""
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
    echo "║        wg-easy (Docker) + 3x-ui (официальный скрипт)         ║"
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
    echo -e "${BLUE}ℹ $1${NC}"
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

# Функция создания docker-compose.yml для wg-easy
create_wg_easy_compose() {
    local compose_file="$CURRENT_DATA_PATH/docker-compose.yml"
    
    print_info "Создание docker-compose.yml для wg-easy..."
    
    cat > "$compose_file" << EOF
version: '3.8'

services:
  wg-easy:
    image: weejewel/wg-easy:latest
    container_name: wg-easy
    restart: unless-stopped
    ports:
      - "$CURRENT_PORT:51820/udp"
      - "$CURRENT_WEB_PORT:51821/tcp"
    environment:
      - WG_HOST=$CURRENT_IP
      - PASSWORD=$CURRENT_PASSWORD
      - WG_PORT=$CURRENT_PORT
      - WG_DEFAULT_ADDRESS=10.0.0.x
      - WG_DEFAULT_DNS=1.1.1.1
      - WG_MTU=1420
      - WG_PERSISTENT_KEEPALIVE=25
      - WG_LOG_LEVEL=info
      - WG_STORAGE=sqlite3
      - WG_DB_PATH=/etc/wireguard/db
      - WG_CONFIG_PATH=/etc/wireguard
      - WG_DEVICE=wg0
      - WG_ALLOWED_IPS=0.0.0.0/0
      - WG_DISABLED=false
    volumes:
      - ./data:/etc/wireguard
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
      - net.ipv4.conf.default.src_valid_mark=1
    networks:
      - wg-network

networks:
  wg-network:
    driver: bridge
EOF
    
    print_success "docker-compose.yml создан"
}

# Функция запуска wg-easy
start_wg_easy() {
    print_info "Запуск wg-easy..."
    
    cd "$CURRENT_DATA_PATH"
    
    if docker-compose up -d; then
        print_success "wg-easy успешно запущен"
        print_info "Веб-интерфейс доступен по адресу: http://$CURRENT_IP:$CURRENT_WEB_PORT"
        print_info "Логин: admin"
        print_info "Пароль: $CURRENT_PASSWORD"
    else
        print_error "Ошибка при запуске wg-easy"
        exit 1
    fi
}



# Функция остановки VPN
stop_vpn() {
    local vpn_name=$1
    print_info "Остановка $vpn_name..."
    
    if [[ -d "$CURRENT_DATA_PATH" ]]; then
        cd "$CURRENT_DATA_PATH"
        if docker-compose down; then
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
    
    # Остановка и удаление всех остальных контейнеров
    print_info "Остановка и удаление всех контейнеров..."
    docker stop $(docker ps -aq) 2>/dev/null || true
    docker rm $(docker ps -aq) 2>/dev/null || true
    
    # Удаление всех образов
    print_info "Удаление всех образов..."
    docker rmi $(docker images -q) 2>/dev/null || true
    
    # Удаление всех томов
    print_info "Удаление всех томов..."
    docker volume rm $(docker volume ls -q) 2>/dev/null || true
    
    # Удаление всех сетей
    print_info "Удаление всех сетей..."
    docker network rm $(docker network ls -q) 2>/dev/null || true
    
    # Очистка логов скрипта
    print_info "Очистка логов скрипта..."
    rm -f "$LOG_FILE" 2>/dev/null || true
    
    print_success "Полная очистка завершена"
}

# Функция очистки 3x-ui
cleanup_3x_ui() {
    print_warning "Выполняется очистка 3x-ui..."
    
    # Удаление директорий с данными 3x-ui
    print_info "Удаление директорий с данными 3x-ui..."
    rm -rf "/opt/3x-ui" 2>/dev/null || true
    rm -rf "/usr/local/x-ui" 2>/dev/null || true
    rm -rf "/etc/x-ui" 2>/dev/null || true
    
    # Удаление systemd сервиса 3x-ui
    print_info "Удаление systemd сервиса 3x-ui..."
    systemctl stop x-ui 2>/dev/null || true
    systemctl disable x-ui 2>/dev/null || true
    rm -f /etc/systemd/system/x-ui.service 2>/dev/null || true
    rm -f /etc/systemd/system/x-ui 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    
    # Удаление исполняемых файлов 3x-ui
    print_info "Удаление исполняемых файлов 3x-ui..."
    rm -f /usr/local/bin/x-ui 2>/dev/null || true
    rm -f /usr/bin/x-ui 2>/dev/null || true
    
    # Удаление конфигурационных файлов
    print_info "Удаление конфигурационных файлов 3x-ui..."
    rm -rf /usr/local/x-ui/config.json 2>/dev/null || true
    rm -rf /etc/x-ui/config.json 2>/dev/null || true
    
    # Удаление логов 3x-ui
    print_info "Удаление логов 3x-ui..."
    rm -rf /var/log/x-ui 2>/dev/null || true
    rm -rf /usr/local/x-ui/logs 2>/dev/null || true
    
    # Удаление пользователя x-ui (если создан)
    print_info "Удаление пользователя x-ui..."
    userdel -r x-ui 2>/dev/null || true
    
    # Очистка cron задач (если есть)
    print_info "Очистка cron задач 3x-ui..."
    crontab -l 2>/dev/null | grep -v "x-ui" | crontab - 2>/dev/null || true
    
    print_success "Очистка 3x-ui завершена"
}

# Функция очистки wg-easy
cleanup_wg_easy() {
    print_warning "Выполняется очистка wg-easy..."
    
    # Остановка и удаление Docker контейнеров wg-easy
    print_info "Остановка и удаление Docker контейнеров wg-easy..."
    docker stop wg-easy 2>/dev/null || true
    docker rm wg-easy 2>/dev/null || true
    
    # Удаление образа wg-easy
    print_info "Удаление образа wg-easy..."
    docker rmi weejewel/wg-easy:latest 2>/dev/null || true
    
    # Удаление директорий с данными wg-easy
    print_info "Удаление директорий с данными wg-easy..."
    rm -rf "$DEFAULT_DATA_PATH" 2>/dev/null || true
    rm -rf "/opt/wg-easy" 2>/dev/null || true
    
    # Удаление сетей wg-easy
    print_info "Удаление сетей wg-easy..."
    docker network rm wg-network 2>/dev/null || true
    
    print_success "Очистка wg-easy завершена"
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
    
    CURRENT_VPN="wg-easy"
    
    get_user_input "Введите порт для WireGuard" "$DEFAULT_PORT" "CURRENT_PORT"
    get_user_input "Введите порт для веб-интерфейса" "8080" "CURRENT_WEB_PORT"
    get_user_input "Введите пароль для веб-интерфейса" "" "CURRENT_PASSWORD"
    get_user_input "Введите путь для данных" "$DEFAULT_DATA_PATH" "CURRENT_DATA_PATH"
    
    # Генерация пароля если не указан
    generate_password
    
    # Выбор IP-адреса
    get_available_ips
    
    print_separator
    print_info "Параметры установки:"
    echo -e "  VPN: ${WHITE}$CURRENT_VPN${NC}"
    echo -e "  Порт WireGuard: ${WHITE}$CURRENT_PORT${NC}"
    echo -e "  Порт веб-интерфейса: ${WHITE}$CURRENT_WEB_PORT${NC}"
    echo -e "  Пароль: ${WHITE}$CURRENT_PASSWORD${NC}"
    echo -e "  Путь данных: ${WHITE}$CURRENT_DATA_PATH${NC}"
    echo -e "  IP-адрес: ${WHITE}$CURRENT_IP${NC} (интерфейс: $CURRENT_INTERFACE)"
    print_separator
    
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
    
    # Создание директории
    create_data_directory "$CURRENT_DATA_PATH"
    
    # Загрузка последней версии wg-easy
    print_info "Загрузка последней версии wg-easy (Node.js v18)..."
    docker pull weejewel/wg-easy:latest
    
    # Создание docker-compose.yml
    create_wg_easy_compose
    
    # Запуск wg-easy
    start_wg_easy
    
    print_separator
    print_success "wg-easy успешно установлен!"
    print_info "Веб-интерфейс: http://$CURRENT_IP:$CURRENT_WEB_PORT"
    print_info "Логин: admin"
    print_info "Пароль: $CURRENT_PASSWORD"
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
        print_info "Логин: admin"
        print_info "Пароль: admin"
        print_warning "ВАЖНО: Измените пароль по умолчанию после первого входа!"
    else
        print_error "Ошибка при установке 3x-ui"
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
    
    # Если нет установленных VPN
    if [[ ! -d "$DEFAULT_DATA_PATH" && ! -f "/usr/local/bin/x-ui" && ! -f "/usr/bin/x-ui" ]]; then
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
        echo -e "  ${CYAN}1)${NC} Установить wg-easy"
        echo -e "  ${CYAN}2)${NC} Установить 3x-ui"
        echo -e "  ${CYAN}3)${NC} Показать статус"
        echo -e "  ${CYAN}4)${NC} Остановить VPN"
        echo -e "  ${CYAN}5)${NC} Очистка wg-easy"
        echo -e "  ${CYAN}6)${NC} Очистка 3x-ui"
        echo -e "  ${CYAN}7)${NC} Полная очистка (удалить всё)"
        echo -e "  ${CYAN}8)${NC} Выход"
        echo
        print_separator
        
        read -p "Выберите действие (1-8): " -n 1 -r
        echo
        
        case $REPLY in
            1)
                setup_wg_easy
                ;;
            2)
                setup_3x_ui
                ;;
            3)
                show_status
                ;;
            4)
                print_info "Остановка VPN..."
                stop_vpn "wg-easy"
                stop_vpn "3x-ui"
                read -p "Нажмите Enter для возврата в главное меню..."
                ;;
            5)
                print_warning "ВНИМАНИЕ: Это действие удалит wg-easy и все его данные!"
                read -p "Вы уверены? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    cleanup_wg_easy
                    read -p "Нажмите Enter для возврата в главное меню..."
                fi
                ;;
            6)
                print_warning "ВНИМАНИЕ: Это действие удалит 3x-ui и все его данные!"
                read -p "Вы уверены? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    cleanup_3x_ui
                    read -p "Нажмите Enter для возврата в главное меню..."
                fi
                ;;
            7)
                print_warning "ВНИМАНИЕ: Это действие удалит ВСЕ контейнеры, образы и данные!"
                read -p "Вы уверены? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    cleanup
                    read -p "Нажмите Enter для возврата в главное меню..."
                fi
                ;;
            8)
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
