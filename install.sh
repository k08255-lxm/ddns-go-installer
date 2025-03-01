#!/bin/bash

# 设置终端编码
export LC_ALL=C.UTF-8 2>/dev/null
export LANG=C.UTF-8 2>/dev/null

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置文件路径
CONFIG_FILE="/etc/ddns-go.conf"
SERVICE_FILE="/etc/systemd/system/ddns-go.service"

# 检查root权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}请使用sudo或root权限运行此脚本！${NC}" >&2
        exit 1
    fi
}

# 安装依赖
install_dependencies() {
    echo -e "\n${YELLOW}正在安装必要依赖...${NC}"
    
    if command -v apt &>/dev/null; then
        apt update -y
        apt install -y curl tar jq
    elif command -v yum &>/dev/null; then
        yum install -y curl tar jq
    elif command -v dnf &>/dev/null; then
        dnf install -y curl tar jq
    elif command -v pacman &>/dev/null; then
        pacman -Sy --noconfirm curl tar jq
    elif command -v zypper &>/dev/null; then
        zypper install -y curl tar jq
    else
        echo -e "${RED}不支持的包管理器！${NC}" >&2
        exit 1
    fi
}

# 获取最新版本（修复版本获取逻辑）
get_latest_version() {
    echo -e "\n${YELLOW}正在获取最新版本...${NC}" >&2
    API_URL="https://api.github.com/repos/jeessy2/ddns-go/releases/latest"
    
    if ! response=$(curl -fsSL "$API_URL"); then
        echo -e "${RED}获取版本失败，请检查网络连接！${NC}" >&2
        exit 1
    fi
    
    LATEST_VERSION=$(echo "$response" | jq -r '.tag_name | select(. != null)')
    
    if [[ -z "$LATEST_VERSION" || ! "$LATEST_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}版本号解析失败！原始数据：${response:0:200}...${NC}" >&2
        exit 1
    fi
    echo "$LATEST_VERSION"
}

# 安装DDNS-GO（修复URL拼接问题）
install_ddns_go() {
    local VERSION=$1
    local ARCH=$(uname -m)
    
    # 架构映射
    case $ARCH in
        x86_64) ARCH="x86_64" ;;
        armv7l) ARCH="armv7" ;;
        aarch64) ARCH="arm64" ;;
        *) 
            echo -e "${RED}不支持的CPU架构：$ARCH${NC}" >&2
            exit 1
            ;;
    esac

    local FILENAME_VERSION="${VERSION#v}"
    local URL="https://github.com/jeessy2/ddns-go/releases/download/${VERSION}/ddns-go_${FILENAME_VERSION}_linux_${ARCH}.tar.gz"

    echo -e "\n${YELLOW}正在下载版本：${VERSION} ...${NC}" >&2
    echo -e "下载地址：$URL" >&2
    
    if ! curl -fL "$URL" -o /tmp/ddns-go.tar.gz; then
        echo -e "${RED}下载失败！可能原因：" >&2
        echo -e "1. 检查网络连接是否正常" >&2
        echo -e "2. 确认系统架构支持（当前：$ARCH）" >&2
        echo -e "3. 验证下载地址有效性：$URL${NC}" >&2
        exit 1
    fi

    echo -e "\n${YELLOW}正在安装...${NC}" >&2
    tar xzf /tmp/ddns-go.tar.gz -C /tmp
    mv /tmp/ddns-go /usr/local/bin/ddns-go
    chmod +x /usr/local/bin/ddns-go
    rm -f /tmp/ddns-go.tar.gz
}

# 服务配置
configure_service() {
    echo -e "\n${YELLOW}正在配置后台服务...${NC}"
    cat > $SERVICE_FILE <<EOF
[Unit]
Description=DDNS-GO Service
After=network.target

[Service]
ExecStart=/usr/local/bin/ddns-go -l :$PORT -f $INTERVAL
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ddns-go --now
}

# 保存配置
save_config() {
    echo "PORT=$PORT" > $CONFIG_FILE
    echo "INTERVAL=$INTERVAL" >> $CONFIG_FILE
    chmod 600 $CONFIG_FILE
}

# 显示安装结果
show_result() {
    IP=$(curl -4s ip.sb || curl -6s ip.sb)
    echo -e "\n${GREEN}✔ 安装成功！${NC}"
    echo -e "${BLUE}访问地址：${YELLOW}http://${IP}:${PORT}${NC}"
    echo -e "${RED}重要提示：动态IP用户请尽快配置域名解析！${NC}"
}

# 查看状态
show_status() {
    clear
    echo -e "\n${BLUE}▌服务状态信息${NC}"
    
    if systemctl is-active ddns-go &>/dev/null; then
        echo -e "运行状态：${GREEN}已运行${NC}"
        echo -e "启动时间：$(systemctl show ddns-go --property=ActiveEnterTimestamp | cut -d= -f2)"
    else
        echo -e "运行状态：${RED}未运行${NC}"
    fi
    
    echo -e "\n${BLUE}▌最近日志（最新5条）${NC}"
    journalctl -u ddns-go -n 5 --no-pager | tail -n 5
    
    read -n 1 -s -r -p "按任意键返回菜单..."
}

# 查看配置
show_config() {
    clear
    echo -e "\n${BLUE}▌当前配置信息${NC}"
    
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "监听端口：${YELLOW}$(grep PORT $CONFIG_FILE | cut -d= -f2)${NC}"
        echo -e "同步间隔：${YELLOW}$(grep INTERVAL $CONFIG_FILE | cut -d= -f2) 秒${NC}"
        echo -e "配置文件：${YELLOW}$CONFIG_FILE${NC}"
    else
        echo -e "${RED}配置文件不存在${NC}"
    fi
    
    read -n 1 -s -r -p "按任意键返回菜单..."
}

# 卸载程序
uninstall() {
    clear
    echo -e "\n${YELLOW}正在卸载...${NC}"
    systemctl stop ddns-go 2>/dev/null
    systemctl disable ddns-go 2>/dev/null
    rm -f /usr/local/bin/ddns-go
    rm -f $SERVICE_FILE
    rm -f $CONFIG_FILE
    systemctl daemon-reload
    echo -e "${GREEN}卸载完成！${NC}"
    sleep 2
}

# 功能菜单
show_menu() {
    while true; do
        clear
        echo -e "\n${BLUE}▌DDNS-GO 管理菜单${NC}"
        echo -e "1. 启动服务"
        echo -e "2. 停止服务"
        echo -e "3. 重启服务"
        echo -e "4. 查看状态"
        echo -e "5. 查看配置"
        echo -e "6. 卸载程序"
        echo -e "7. 退出"
        
        read -p "请输入选项 [1-7]: " CHOICE
        case $CHOICE in
            1) systemctl start ddns-go;;
            2) systemctl stop ddns-go;;
            3) systemctl restart ddns-go;;
            4) show_status;;
            5) show_config;;
            6) uninstall; break;;
            7) exit 0;;
            *) echo -e "${RED}无效输入，请重新选择${NC}"; sleep 1;;
        esac
    done
}

# 主安装流程
main_install() {
    check_root
    install_dependencies
    
    echo -e "\n${BLUE}▌配置参数设置${NC}"
    read -p "请输入监听端口 [默认9876]: " PORT
    PORT=${PORT:-9876}
    
    read -p "请输入同步间隔（秒）[默认300]: " INTERVAL
    INTERVAL=${INTERVAL:-300}

    VERSION=$(get_latest_version)
    install_ddns_go "$VERSION"
    configure_service
    save_config
    show_result
}

# 执行入口
if systemctl is-active ddns-go &>/dev/null || [ -f /usr/local/bin/ddns-go ]; then
    show_menu
else
    main_install
fi
