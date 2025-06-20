#!/bin/bash
#
# Node Exporter 安装脚本
# 适配主流操作系统，提供美观输出和错误处理
# 支持国内和海外网络环境
# 作者: jiangchuanhui <jiangchuanhui@kingsoft.com>

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# 默认配置
NODE_EXPORTER_VERSION="1.6.1"
NODE_EXPORTER_USER="node_exporter"
NODE_EXPORTER_GROUP="node_exporter"
NODE_EXPORTER_PORT="9100"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/node_exporter"
SERVICE_DIR=""
SYSTEMD_DIR="/etc/systemd/system"
OPENRC_DIR="/etc/init.d"
LAUNCHD_DIR="/Library/LaunchDaemons"

# 镜像站点配置
GITHUB_URL="https://github.com/prometheus/node_exporter/releases/download"
# 国内镜像站点列表
CHINA_MIRRORS=(
    "https://ghfast.top/https://github.com/prometheus/node_exporter/releases/download"
    "https://download.fastgit.org/prometheus/node_exporter/releases/download"
    "https://hub.fastgit.xyz/prometheus/node_exporter/releases/download"
)

# 日志函数
log() {
    local level=$1
    local message=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} ${timestamp} - ${message}"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} ${timestamp} - ${message}"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${timestamp} - ${message}"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} ${timestamp} - ${message}"
            ;;
        "STEP")
            echo -e "\n${BLUE}${BOLD}==> ${message}${NC}"
            ;;
    esac
}

# 显示横幅
show_banner() {
    echo -e "${CYAN}${BOLD}"
    echo "  _   _           _        _____                       _            "
    echo " | \ | | ___   __| | ___  | ____|_  ___ __   ___  _ __| |_ ___ _ __ "
    echo " |  \| |/ _ \ / _\` |/ _ \ |  _| \ \/ / '_ \ / _ \| '__| __/ _ \ '__|"
    echo " | |\  | (_) | (_| |  __/ | |___ >  <| |_) | (_) | |  | ||  __/ |   "
    echo " |_| \_|\___/ \__,_|\___| |_____/_/\_\ .__/ \___/|_|   \__\___|_|   "
    echo "                                     |_|                            "
    echo -e "${NC}"
    echo -e "${PURPLE}${BOLD}自动安装脚本 - 版本 1.0${NC}\n"
}

# 检查是否为 root 用户
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log "ERROR" "此脚本需要 root 权限运行"
        log "INFO" "请使用 sudo 或以 root 用户身份运行此脚本"
        exit 1
    fi
}

# 检测操作系统
detect_os() {
    log "STEP" "检测操作系统"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        OS_VERSION=$VERSION_ID
        OS_ID=$ID
        OS_ID_LIKE=$ID_LIKE
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si)
        OS_VERSION=$(lsb_release -sr)
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        OS=$DISTRIB_ID
        OS_VERSION=$DISTRIB_RELEASE
    elif [ -f /etc/debian_version ]; then
        OS="Debian"
        OS_VERSION=$(cat /etc/debian_version)
    elif [ -f /etc/redhat-release ]; then
        OS=$(cat /etc/redhat-release | cut -d ' ' -f 1)
        OS_VERSION=$(cat /etc/redhat-release | sed 's/.*release \([0-9]\+\).*/\1/')
    elif [ "$(uname)" == "Darwin" ]; then
        OS="macOS"
        OS_VERSION=$(sw_vers -productVersion)
    else
        OS=$(uname -s)
        OS_VERSION=$(uname -r)
    fi

    log "INFO" "检测到操作系统: ${OS} ${OS_VERSION}"

    # 确定服务管理器类型
    if command -v systemctl >/dev/null 2>&1; then
        SERVICE_MANAGER="systemd"
        SERVICE_DIR=$SYSTEMD_DIR
    elif [ -d /etc/init.d ] && command -v rc-service >/dev/null 2>&1; then
        SERVICE_MANAGER="openrc"
        SERVICE_DIR=$OPENRC_DIR
    elif [ "$OS" == "macOS" ]; then
        SERVICE_MANAGER="launchd"
        SERVICE_DIR=$LAUNCHD_DIR
    else
        SERVICE_MANAGER="unknown"
    fi

    log "INFO" "服务管理器: ${SERVICE_MANAGER}"
}

# 检查依赖项
check_dependencies() {
    log "STEP" "检查依赖项"

    local missing_deps=0
    local deps=("curl" "tar")

    for dep in "${deps[@]}"; do
        if ! command -v $dep >/dev/null 2>&1; then
            log "WARN" "未找到依赖项: $dep"
            missing_deps=1
        fi
    done

    if [ $missing_deps -eq 1 ]; then
        log "INFO" "正在安装缺失的依赖项..."

        case $OS_ID in
            "ubuntu"|"debian"|"linuxmint")
                apt-get update
                apt-get install -y curl tar
                ;;
            "centos"|"rhel"|"fedora"|"rocky"|"almalinux")
                if command -v dnf >/dev/null 2>&1; then
                    dnf install -y curl tar
                else
                    yum install -y curl tar
                fi
                ;;
            "opensuse"|"sles")
                zypper install -y curl tar
                ;;
            "alpine")
                apk add --no-cache curl tar
                ;;
            "arch"|"manjaro")
                pacman -Sy --noconfirm curl tar
                ;;
            *)
                if [ "$OS" == "macOS" ]; then
                    if command -v brew >/dev/null 2>&1; then
                        brew install curl
                    else
                        log "ERROR" "请安装 Homebrew 然后重试"
                        exit 1
                    fi
                else
                    log "ERROR" "无法自动安装依赖项，请手动安装 curl 和 tar"
                    exit 1
                fi
                ;;
        esac
    fi

    log "SUCCESS" "所有依赖项已满足"
}

# 检测网络环境
detect_network() {
    log "STEP" "检测网络环境"

    # 测试国内外网络连通性
    local china_sites=("www.baidu.com" "www.taobao.com" "www.qq.com")
    local overseas_sites=("www.google.com")

    local china_access=0
    local overseas_access=0

    # 检查国内网站访问
    for site in "${china_sites[@]}"; do
        if curl -s --connect-timeout 3 "https://${site}" >/dev/null; then
            china_access=1
            break
        fi
    done

    # 检查海外网站访问
    for site in "${overseas_sites[@]}"; do
        if curl -s --connect-timeout 3 "https://${site}" >/dev/null; then
            overseas_access=1
            break
        fi
    done

    # 确定网络环境
    if [ $overseas_access -eq 1 ]; then
        NETWORK_ENV="overseas"
        log "INFO" "检测到海外网络环境，将直接从 GitHub 下载"
        DOWNLOAD_BASE_URL=$GITHUB_URL
    else
        NETWORK_ENV="china"
        log "INFO" "检测到国内网络环境，将使用镜像站点下载"
        # 选择一个可用的镜像站点
        for mirror in "${CHINA_MIRRORS[@]}"; do
            if curl -s --connect-timeout 3 "${mirror}/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz" -o /dev/null; then
                DOWNLOAD_BASE_URL=$mirror
                log "INFO" "选择镜像站点: ${mirror}"
                break
            fi
        done

        # 如果所有镜像站点都不可用，则使用第一个镜像站点
        if [ -z "$DOWNLOAD_BASE_URL" ]; then
            DOWNLOAD_BASE_URL=${CHINA_MIRRORS[0]}
            log "WARN" "所有镜像站点测试失败，将使用默认镜像站点: ${DOWNLOAD_BASE_URL}"
        fi
    fi
}

# 创建用户和组
create_user() {
    log "STEP" "创建 Node Exporter 用户和组"

    # 在 macOS 上跳过此步骤
    if [ "$OS" == "macOS" ]; then
        log "INFO" "在 macOS 上跳过用户创建"
        return 0
    fi

    # 检查组是否存在
    if ! getent group $NODE_EXPORTER_GROUP >/dev/null 2>&1; then
        log "INFO" "创建组: $NODE_EXPORTER_GROUP"
        groupadd --system $NODE_EXPORTER_GROUP
    else
        log "INFO" "组已存在: $NODE_EXPORTER_GROUP"
    fi

    # 检查用户是否存在
    if ! id $NODE_EXPORTER_USER >/dev/null 2>&1; then
        log "INFO" "创建用户: $NODE_EXPORTER_USER"
        useradd --system -d /var/lib/node_exporter -s /sbin/nologin -g $NODE_EXPORTER_GROUP $NODE_EXPORTER_USER
    else
        log "INFO" "用户已存在: $NODE_EXPORTER_USER"
    fi
}

# 下载并安装 Node Exporter
download_and_install() {
    log "STEP" "下载并安装 Node Exporter v${NODE_EXPORTER_VERSION}"

    local arch
    case $(uname -m) in
        x86_64)
            arch="amd64"
            ;;
        i386|i686)
            arch="386"
            ;;
        armv7l|armv6l)
            arch="armv7"
            ;;
        aarch64|arm64)
            arch="arm64"
            ;;
        ppc64le)
            arch="ppc64le"
            ;;
        s390x)
            arch="s390x"
            ;;
        *)
            log "ERROR" "不支持的架构: $(uname -m)"
            exit 1
            ;;
    esac

    local os_name
    if [ "$OS" == "macOS" ]; then
        os_name="darwin"
    else
        os_name="linux"
    fi

    local download_url="${DOWNLOAD_BASE_URL}/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.${os_name}-${arch}.tar.gz"
    local temp_dir=$(mktemp -d)

    log "INFO" "下载 Node Exporter 从 ${download_url}"

    # 尝试下载，如果失败则尝试其他镜像
    if ! curl -L --silent --fail -o "${temp_dir}/node_exporter.tar.gz" "${download_url}"; then
        log "WARN" "从 ${DOWNLOAD_BASE_URL} 下载失败，尝试其他镜像"

        local download_success=0

        # 如果是国内网络，尝试其他镜像
        if [ "$NETWORK_ENV" == "china" ]; then
            for mirror in "${CHINA_MIRRORS[@]}"; do
                if [ "$mirror" != "$DOWNLOAD_BASE_URL" ]; then
                    local alt_url="${mirror}/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.${os_name}-${arch}.tar.gz"
                    log "INFO" "尝试从 ${mirror} 下载"

                    if curl -L --silent --fail -o "${temp_dir}/node_exporter.tar.gz" "${alt_url}"; then
                        download_success=1
                        log "SUCCESS" "从 ${mirror} 下载成功"
                        break
                    fi
                fi
            done
        fi

        # 如果所有镜像都失败，尝试直接从 GitHub 下载
        if [ $download_success -eq 0 ]; then
            local github_url="${GITHUB_URL}/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.${os_name}-${arch}.tar.gz"
            log "WARN" "所有镜像下载失败，尝试直接从 GitHub 下载"

            if curl -L --silent --fail -o "${temp_dir}/node_exporter.tar.gz" "${github_url}"; then
                download_success=1
                log "SUCCESS" "从 GitHub 下载成功"
            else
                log "ERROR" "所有下载尝试均失败"
                rm -rf "${temp_dir}"
                exit 1
            fi
        fi
    else
        log "SUCCESS" "下载成功"
    fi

    log "INFO" "解压 Node Exporter"
    tar -xzf "${temp_dir}/node_exporter.tar.gz" -C "${temp_dir}" --strip-components=1

    log "INFO" "安装 Node Exporter 到 ${INSTALL_DIR}"
    cp "${temp_dir}/node_exporter" "${INSTALL_DIR}/"
    chmod +x "${INSTALL_DIR}/node_exporter"

    # 创建配置目录
    if [ ! -d "${CONFIG_DIR}" ]; then
        mkdir -p "${CONFIG_DIR}"
    fi

    # 设置权限
    if [ "$OS" != "macOS" ]; then
        chown -R ${NODE_EXPORTER_USER}:${NODE_EXPORTER_GROUP} "${CONFIG_DIR}"
    fi

    # 清理临时文件
    rm -rf "${temp_dir}"

    log "SUCCESS" "Node Exporter v${NODE_EXPORTER_VERSION} 安装完成"
}

# 创建 systemd 服务
create_systemd_service() {
    log "STEP" "创建 systemd 服务"

    cat > "${SYSTEMD_DIR}/node_exporter.service" << EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=${NODE_EXPORTER_USER}
Group=${NODE_EXPORTER_GROUP}
Type=simple
ExecStart=${INSTALL_DIR}/node_exporter --web.listen-address=:${NODE_EXPORTER_PORT}

[Install]
WantedBy=multi-user.target
EOF

    log "INFO" "重新加载 systemd 配置"
    systemctl daemon-reload

    log "INFO" "启用 Node Exporter 服务"
    systemctl enable node_exporter

    log "INFO" "启动 Node Exporter 服务"
    systemctl start node_exporter

    # 检查服务状态
    if systemctl is-active --quiet node_exporter; then
        log "SUCCESS" "Node Exporter 服务已成功启动"
    else
        log "ERROR" "Node Exporter 服务启动失败"
        log "INFO" "请检查日志: journalctl -u node_exporter"
    fi
}

# 创建 OpenRC 服务
create_openrc_service() {
    log "STEP" "创建 OpenRC 服务"

    cat > "${OPENRC_DIR}/node_exporter" << EOF
#!/sbin/openrc-run

name="Node Exporter"
description="Prometheus Node Exporter"
command="${INSTALL_DIR}/node_exporter"
command_args="--web.listen-address=:${NODE_EXPORTER_PORT}"
command_user="${NODE_EXPORTER_USER}:${NODE_EXPORTER_GROUP}"
supervisor="supervise-daemon"
pidfile="/run/node_exporter.pid"

depend() {
    need net
    after firewall
}
EOF

    chmod +x "${OPENRC_DIR}/node_exporter"

    log "INFO" "启用 Node Exporter 服务"
    rc-update add node_exporter default

    log "INFO" "启动 Node Exporter 服务"
    rc-service node_exporter start

    # 检查服务状态
    if rc-service node_exporter status | grep -q "started"; then
        log "SUCCESS" "Node Exporter 服务已成功启动"
    else
        log "ERROR" "Node Exporter 服务启动失败"
    fi
}

# 创建 macOS LaunchDaemon
create_launchd_service() {
    log "STEP" "创建 macOS LaunchDaemon"

    cat > "${LAUNCHD_DIR}/com.prometheus.node_exporter.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.prometheus.node_exporter</string>
    <key>ProgramArguments</key>
    <array>
        <string>${INSTALL_DIR}/node_exporter</string>
        <string>--web.listen-address=:${NODE_EXPORTER_PORT}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/node_exporter.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/node_exporter.log</string>
</dict>
</plist>
EOF

    # 设置正确的权限
    chmod 644 "${LAUNCHD_DIR}/com.prometheus.node_exporter.plist"

    log "INFO" "加载并启动 Node Exporter 服务"
    launchctl load -w "${LAUNCHD_DIR}/com.prometheus.node_exporter.plist"

    # 检查服务状态
    if launchctl list | grep -q "com.prometheus.node_exporter"; then
        log "SUCCESS" "Node Exporter 服务已成功启动"
    else
        log "ERROR" "Node Exporter 服务启动失败"
    fi
}

# 配置防火墙
configure_firewall() {
    log "STEP" "配置防火墙"

    # 在 macOS 上跳过此步骤
    if [ "$OS" == "macOS" ]; then
        log "INFO" "在 macOS 上跳过防火墙配置"
        return 0
    fi

    # UFW (Ubuntu, Debian)
    if command -v ufw >/dev/null 2>&1; then
        log "INFO" "配置 UFW 防火墙"
        ufw allow ${NODE_EXPORTER_PORT}/tcp
        log "SUCCESS" "UFW 规则已添加"
    # FirewallD (CentOS, RHEL, Fedora)
    elif command -v firewall-cmd >/dev/null 2>&1; then
        log "INFO" "配置 FirewallD 防火墙"
        firewall-cmd --permanent --add-port=${NODE_EXPORTER_PORT}/tcp
        firewall-cmd --reload
        log "SUCCESS" "FirewallD 规则已添加"
    # IPTables
    elif command -v iptables >/dev/null 2>&1; then
        log "INFO" "配置 IPTables 防火墙"
        iptables -A INPUT -p tcp --dport ${NODE_EXPORTER_PORT} -j ACCEPT
        log "WARN" "IPTables 规则已添加，但可能不会在重启后保持"
    else
        log "WARN" "未检测到支持的防火墙，请手动配置防火墙以允许端口 ${NODE_EXPORTER_PORT}"
    fi
}

# 验证安装
verify_installation() {
    log "STEP" "验证安装"

    # 等待服务启动
    sleep 2

    # 检查端口是否开放
    if command -v curl >/dev/null 2>&1; then
        if curl -s http://localhost:${NODE_EXPORTER_PORT}/metrics >/dev/null; then
            log "SUCCESS" "Node Exporter 正在监听端口 ${NODE_EXPORTER_PORT}"
        else
            log "ERROR" "无法连接到 Node Exporter"
            log "INFO" "请检查服务状态和日志"
        fi
    else
        log "WARN" "无法验证 Node Exporter 是否正在运行，curl 命令不可用"
    fi
}

# 显示安装信息
show_completion_info() {
    local ip_address

    if command -v ip >/dev/null 2>&1; then
        ip_address=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
    elif command -v ifconfig >/dev/null 2>&1; then
        ip_address=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -n 1)
    else
        ip_address="<your-ip>"
    fi

    echo -e "\n${GREEN}${BOLD}=== Node Exporter 安装完成 ===${NC}\n"
    echo -e "Node Exporter 版本: ${BOLD}v${NODE_EXPORTER_VERSION}${NC}"
    echo -e "监听端口: ${BOLD}${NODE_EXPORTER_PORT}${NC}"
    echo -e "指标 URL: ${BOLD}http://${ip_address}:${NODE_EXPORTER_PORT}/metrics${NC}"

    echo -e "\n${BLUE}${BOLD}在 Prometheus 中添加以下配置:${NC}"
    echo -e "${CYAN}  - job_name: 'node'
    static_configs:
      - targets: ['${ip_address}:${NODE_EXPORTER_PORT}']${NC}"

    echo -e "\n${YELLOW}${BOLD}如需卸载 Node Exporter:${NC}"

    case $SERVICE_MANAGER in
        "systemd")
            echo -e "${YELLOW}  sudo systemctl stop node_exporter"
            echo -e "  sudo systemctl disable node_exporter"
            echo -e "  sudo rm ${SYSTEMD_DIR}/node_exporter.service"
            echo -e "  sudo rm ${INSTALL_DIR}/node_exporter${NC}"
            ;;
        "openrc")
            echo -e "${YELLOW}  sudo rc-service node_exporter stop"
            echo -e "  sudo rc-update del node_exporter default"
            echo -e "  sudo rm ${OPENRC_DIR}/node_exporter"
            echo -e "  sudo rm ${INSTALL_DIR}/node_exporter${NC}"
            ;;
        "launchd")
            echo -e "${YELLOW}  sudo launchctl unload -w ${LAUNCHD_DIR}/com.prometheus.node_exporter.plist"
            echo -e "  sudo rm ${LAUNCHD_DIR}/com.prometheus.node_exporter.plist"
            echo -e "  sudo rm ${INSTALL_DIR}/node_exporter${NC}"
            ;;
    esac

    echo -e "\n${GREEN}${BOLD}感谢使用此安装脚本！${NC}\n"
}

# 主函数
main() {
    show_banner
    check_root
    detect_os
    check_dependencies
    detect_network
    create_user
    download_and_install

    # 根据服务管理器创建服务
    case $SERVICE_MANAGER in
        "systemd")
            create_systemd_service
            ;;
        "openrc")
            create_openrc_service
            ;;
        "launchd")
            create_launchd_service
            ;;
        *)
            log "ERROR" "不支持的服务管理器，无法自动创建服务"
            log "INFO" "请手动配置 Node Exporter 服务"
            ;;
    esac

    #configure_firewall
    verify_installation
    show_completion_info
}

# 捕获 Ctrl+C
trap 'echo -e "\n${RED}安装已取消${NC}"; exit 1' INT

# 执行主函数
main