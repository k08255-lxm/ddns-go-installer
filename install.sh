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
BIN_PATH=$(which ddns-go 2>/dev/null || echo "/usr/local/bin/ddns-go")
MANAGER_PATH="/usr/local/bin/ddnsmgr"
SCRIPT_VERSION="1.1.0"

# ---------------------- 函数定义开始 ----------------------
# 注意：所有函数必须在使用前定义

# 增强安装状态检测
check_installed() {
    # 检查二进制文件是否存在
    [ -x "$BIN_PATH" ] && return 0
    
    # 检查服务是否注册
    systemctl list-unit-files | grep -q ddns-go.service && return 0
    
    # 检查进程是否正在运行
    pgrep -x "ddns-go" >/dev/null && return 0
    
    # 检查常见安装路径
    [ -x "/usr/bin/ddns-go" ] && BIN_PATH="/usr/bin/ddns-go" && return 0
    [ -x "/usr/local/bin/ddns-go" ] && BIN_PATH="/usr/local/bin/ddns-go" && return 0
    [ -x "/opt/ddns-go" ] && BIN_PATH="/opt/ddns-go" && return 0
    
    return 1
}

# 显示安装结果
show_result() {
    IP=$(curl -4s ip.sb || curl -6s ip.sb)
    echo -e "\n${GREEN}✔ 安装成功！${NC}"
    echo -e "${BLUE}访问地址：${YELLOW}http://${IP}:${PORT}${NC}"
    echo -e "${RED}重要提示："
    echo -e "1. 动态IP用户请尽快配置域名解析"
    echo -e "2. 请确保以下防火墙已放行："
    echo -e "   - 系统防火墙："
    echo -e "     ${YELLOW}sudo ufw allow ${PORT}/tcp"
    echo -e "     sudo firewall-cmd --add-port=${PORT}/tcp --permanent"
    echo -e "   - 云服务商安全组/防火墙规则${NC}"
    sleep 3
}

# 查看状态
show_status() {
    clear
    echo -e "\n${BLUE}▌服务状态信息${NC}"
    
    if [[ -x "$BIN_PATH" ]]; then
        VERSION_INFO=$("$BIN_PATH" -version 2>&1)
        VERSION=$(echo "$VERSION_INFO" | grep -oE 'version [0-9]+\.[0-9]+\.[0-9]+' | awk '{print $2}')
        if [ -z "$VERSION" ]; then
            VERSION=$(echo "$VERSION_INFO" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')
        fi
        echo -e "程序版本：${GREEN}${VERSION:-未知}${NC}"
        echo -e "安装路径：${YELLOW}$BIN_PATH${NC}"
    else
        echo -e "程序版本：${RED}未安装${NC}"
    fi
    
    if systemctl is-active ddns-go &>/dev/null || pgrep -x "ddns-go" >/dev/null; then
        echo -e "运行状态：${GREEN}已运行${NC}"
        systemctl show ddns-go --property=ActiveEnterTimestamp 2>/dev/null | cut -d= -f2 | xargs -I{} echo "启动时间：{}"
    else
        echo -e "运行状态：${RED}未运行${NC}"
    fi
    
    echo -e "\n${BLUE}▌最近日志（最新5条）${NC}"
    journalctl -u ddns-go -n 5 --no-pager 2>/dev/null | tail -n 5
    
    read -n 1 -s -r -p "按任意键返回菜单..."
}

# 检查脚本更新
check_self_update() {
    echo -e "\n${BLUE}▌检查脚本更新...${NC}"
    API_RESPONSE=$(curl -sfL --connect-timeout 10 https://api.github.com/repos/k08255-lxm/ddns-go-installer/releases/latest)
    
    if [ -z "$API_RESPONSE" ]; then
        echo -e "${YELLOW}检查更新失败（网络连接超时）${NC}"
        return
    fi

    LATEST_TAG=$(echo "$API_RESPONSE" | jq -r '.tag_name' | sed 's/[^0-9.]//g')
    [ -z "$LATEST_TAG" ] && return

    # 版本号对比逻辑
    version_compare() {
        awk -v v1="$SCRIPT_VERSION" -v v2="$LATEST_TAG" '
        BEGIN {
            split(v1, a, ".")
            split(v2, b, ".")
            for (i=1; i<=3; i++) {
                if (a[i]+0 < b[i]+0) {print "newer"; exit}
                else if (a[i]+0 > b[i]+0) {print "older"; exit}
            }
            print "same"
        }'
    }

    COMPARE_RESULT=$(version_compare)
    case $COMPARE_RESULT in
        "newer")
            echo -e "${YELLOW}发现新版本脚本 (v$LATEST_TAG)，当前版本 (v$SCRIPT_VERSION)${NC}"
            read -p "是否更新脚本？[Y/n] " -n 1 -r
            echo
            [[ $REPLY =~ ^[Nn]$ ]] && return

            echo -e "${YELLOW}正在更新脚本...${NC}"
            TEMP_FILE=$(mktemp)
            if curl -sfL --connect-timeout 15 "https://raw.githubusercontent.com/k08255-lxm/ddns-go-installer/main/install.sh" -o "$TEMP_FILE"; then
                NEW_VERSION=$(grep -m1 '^SCRIPT_VERSION=' "$TEMP_FILE" | cut -d'"' -f2)
                if [ "$NEW_VERSION" != "$SCRIPT_VERSION" ]; then
                    mv "$TEMP_FILE" "$MANAGER_PATH"
                    chmod +x "$MANAGER_PATH"
                    echo -e "${GREEN}脚本已更新到 v$NEW_VERSION，请重新运行命令！${NC}"
                    exit 0
                fi
            fi
            rm -f "$TEMP_FILE"
            echo -e "${RED}更新失败，请手动更新${NC}"
            ;;
        "older")
            echo -e "${YELLOW}本地版本较新（v$SCRIPT_VERSION），GitHub版本：v$LATEST_TAG${NC}"
            ;;
        *)
            echo -e "${GREEN}当前已是最新版本${NC}"
            ;;
    esac
}

# 卸载程序
uninstall() {
    clear
    echo -e "\n${YELLOW}正在卸载...${NC}"
    systemctl stop ddns-go 2>/dev/null
    systemctl disable ddns-go 2>/dev/null
    rm -f "$BIN_PATH"
    rm -f "$MANAGER_PATH"
    rm -f "$SERVICE_FILE"
    rm -f "$CONFIG_FILE"
    systemctl daemon-reload
    echo -e "${GREEN}卸载完成！${NC}"
    sleep 2
}

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

# 获取所有版本
get_versions() {
    for i in {1..3}; do
        if versions=$(curl -sfL --connect-timeout 10 https://api.github.com/repos/jeessy2/ddns-go/releases | jq -r '.[].tag_name'); then
            echo "$versions"
            return
        fi
        sleep 1
    done
    echo -e "${RED}获取版本信息失败，请检查网络连接！${NC}" >&2
    exit 1
}

# 安装DDNS-GO
install_ddns_go() {
    local VERSION=$1
    local ARCH=$(uname -m)
    local OS=$(uname -s | tr '[:upper:]' '[:lower:]')

    # 架构映射
    case $ARCH in
        x86_64|amd64) ARCH="x86_64" ;;
        i386|i686)    ARCH="i386" ;;
        armv6l)       ARCH="armv6" ;;
        armv7l)       ARCH="armv7" ;;
        aarch64)      ARCH="arm64" ;;
        *) 
            echo -e "${RED}不支持的CPU架构：$ARCH${NC}" >&2
            exit 1
            ;;
    esac

    # 操作系统类型
    case $OS in
        linux*)   OS="linux" ;;
        freebsd*) OS="freebsd" ;;
        darwin*)  OS="darwin" ;;
        *)
            echo -e "${RED}不支持的操作系统：$OS${NC}" >&2
            exit 1
            ;;
    esac

    local FILENAME_VERSION="${VERSION#v}"
    local URL="https://github.com/jeessy2/ddns-go/releases/download/${VERSION}/ddns-go_${FILENAME_VERSION}_${OS}_${ARCH}.tar.gz"

    echo -e "\n${YELLOW}正在下载版本：${VERSION} ...${NC}" >&2
    echo -e "下载地址：$URL" >&2
    
    # 下载并统计信息
    local start_time=$(date +%s)
    if ! curl -fL --connect-timeout 15 "$URL" -o /tmp/ddns-go.tar.gz; then
        echo -e "${RED}下载失败！请检查："
        echo -e "1. 网络连接是否正常"
        echo -e "2. 该版本是否支持当前系统架构${NC}" >&2
        exit 1
    fi
    local end_time=$(date +%s)
    
    # 处理0秒情况
    local time_cost=$((end_time - start_time))
    ((time_cost == 0)) && time_cost=1

    # 显示下载统计
    local file_size=$(du -h /tmp/ddns-go.tar.gz | cut -f1)
    local file_bytes=$(stat -c %s /tmp/ddns-go.tar.gz)
    local avg_speed=$((file_bytes / time_cost / 1024))
    
    # 自动转换速度单位
    local speed_unit="KB/s"
    if ((avg_speed >= 1024)); then
        avg_speed=$(echo "scale=1; $avg_speed/1024" | bc)
        speed_unit="MB/s"
    fi

    echo -e "\n${GREEN}✓ 下载完成！"
    echo -e "  文件大小：${file_size}"
    echo -e "  下载耗时：${time_cost}秒"
    echo -e "  平均速度：${avg_speed} ${speed_unit}${NC}"

    echo -e "\n${YELLOW}正在安装到：$BIN_PATH ...${NC}" >&2
    tar xzf /tmp/ddns-go.tar.gz -C /tmp
    systemctl stop ddns-go 2>/dev/null
    mkdir -p $(dirname "$BIN_PATH")
    mv /tmp/ddns-go "$BIN_PATH"
    chmod +x "$BIN_PATH"
    rm -f /tmp/ddns-go.tar.gz
}

# 服务配置
configure_service() {
    local NOWEB_PARAM=""
    [ "$NOWEB" = "true" ] && NOWEB_PARAM="-noweb"

    echo -e "\n${YELLOW}正在配置后台服务...${NC}"
    cat > $SERVICE_FILE <<EOF
[Unit]
Description=DDNS-GO Service
After=network.target

[Service]
ExecStart=$BIN_PATH $NOWEB_PARAM -l :$PORT -f $INTERVAL
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ddns-go --now
}

# 切换Web界面状态
toggle_webui() {
    source $CONFIG_FILE
    if grep -q "NOWEB=true" $CONFIG_FILE; then
        sed -i '/NOWEB/d' $CONFIG_FILE
        NOWEB="false"
        echo -e "${GREEN}已启用Web界面${NC}"
    else
        echo "NOWEB=true" >> $CONFIG_FILE
        NOWEB="true"
        echo -e "${YELLOW}已禁用Web界面${NC}"
    fi
    configure_service
    systemctl restart ddns-go
    read -n 1 -s -r -p "操作完成，按任意键继续..."
}

# 保存配置
save_config() {
    echo "PORT=$PORT" > $CONFIG_FILE
    echo "INTERVAL=$INTERVAL" >> $CONFIG_FILE
    [ "$NOWEB" = "true" ] && echo "NOWEB=true" >> $CONFIG_FILE
    chmod 600 $CONFIG_FILE
}

# 更新程序
update_ddns() {
    check_root
    echo -e "\n${BLUE}▌正在检查DDNS-GO更新...${NC}"
    
    # 获取当前版本
    if ! CURRENT_VERSION=$("$BIN_PATH" -version 2>&1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1); then
        echo -e "${RED}无法获取当前版本，请检查安装状态${NC}"
        read -n 1 -s -r -p "按任意键继续..."
        return 1
    fi

    # 获取最新版本
    if ! LATEST_VERSION=$(get_versions | head -1); then
        read -n 1 -s -r -p "按任意键继续..."
        return 1
    fi

    # 版本号对比逻辑
    local IFS=.
    local current=(${CURRENT_VERSION#v}) latest=(${LATEST_VERSION#v})
    for ((i=0; i<3; i++)); do
        if [[ -z ${latest[i]} ]] || ((10#${latest[i]} < 10#${current[i]})); then
            echo -e "${GREEN}当前已是最新版本：$CURRENT_VERSION${NC}"
            read -n 1 -s -r -p "按任意键继续..."
            return
        elif ((10#${latest[i]} > 10#${current[i]})); then
            break
        fi
    done

    echo -e "${YELLOW}发现新版本：$LATEST_VERSION，当前版本：$CURRENT_VERSION${NC}"
    read -p "是否更新？[Y/n] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Nn]$ ]] && return

    install_ddns_go "$LATEST_VERSION"
    systemctl restart ddns-go
    echo -e "${GREEN}更新完成！${NC}"
    read -n 1 -s -r -p "按任意键继续..."
}

# 管理菜单
show_menu() {
    check_self_update
    
    while true; do
        clear
        echo -e "\n${BLUE}▌DDNS-GO 管理菜单 v$SCRIPT_VERSION${NC}"
        echo -e "1. 启动服务      2. 停止服务"
        echo -e "3. 重启服务      4. 切换Web界面状态"
        echo -e "5. 查看状态      6. 更新程序"
        echo -e "7. 卸载程序      8. 退出"
        
        read -p "请输入选项 [1-8]: " CHOICE
        case $CHOICE in
            1) 
                systemctl start ddns-go
                if systemctl is-active ddns-go &>/dev/null; then
                    echo -e "\n${GREEN}✔ 服务启动成功${NC}"
                else
                    echo -e "\n${RED}✖ 服务启动失败，请查看日志${NC}"
                fi
                read -n 1 -s -r -p "按任意键继续..."
                ;;
            2) 
                systemctl stop ddns-go
                if ! systemctl is-active ddns-go &>/dev/null; then
                    echo -e "\n${GREEN}✔ 服务停止成功${NC}"
                else
                    echo -e "\n${RED}✖ 服务停止失败，请查看日志${NC}"
                fi
                read -n 1 -s -r -p "按任意键继续..."
                ;;
            3) 
                systemctl restart ddns-go
                if systemctl is-active ddns-go &>/dev/null; then
                    echo -e "\n${GREEN}✔ 服务重启成功${NC}"
                else
                    echo -e "\n${RED}✖ 服务重启失败，请查看日志${NC}"
                fi
                read -n 1 -s -r -p "按任意键继续..."
                ;;
            4) toggle_webui;;
            5) show_status;;
            6) update_ddns;;
            7) uninstall; break;;
            8) exit 0;;
            *) 
                echo -e "${RED}无效输入，请重新选择${NC}"
                sleep 1
                ;;
        esac
    done
}

# 主安装流程
main_install() {
    check_root
    install_dependencies
    
    echo -e "\n${BLUE}▌配置参数设置${NC}"
    
    # 端口验证
    while true; do
        read -p "请输入监听端口 [默认9876]: " PORT
        PORT=${PORT:-9876}
        [[ $PORT =~ ^[0-9]+$ ]] && ((PORT >= 1 && PORT <= 65535)) && break
        echo -e "${RED}端口必须为1-65535之间的数字！${NC}"
    done

    # 间隔验证
    while true; do
        read -p "请输入同步间隔（秒）[默认300]: " INTERVAL
        INTERVAL=${INTERVAL:-300}
        [[ $INTERVAL =~ ^[0-9]+$ ]] && ((INTERVAL >= 60)) && break
        echo -e "${RED}间隔时间不能小于60秒！${NC}"
    done

    # 版本选择
    echo -e "\n可用版本："
    get_versions | head -5
    while true; do
        read -p "输入版本号（留空使用最新版）：" VERSION
        if [ -z "$VERSION" ]; then
            VERSION=$(get_versions | head -1)
            break
        elif validate_version "$VERSION"; then
            break
        fi
        echo -e "${RED}无效版本号，请重新输入！${NC}"
    done

    install_ddns_go "$VERSION"
    configure_service
    save_config
    show_result
    
    # 创建管理命令
    cp "$0" "$MANAGER_PATH"
    chmod +x "$MANAGER_PATH"
    echo -e "\n${GREEN}管理命令已安装到：$MANAGER_PATH${NC}"
    echo -e "可通过 ${YELLOW}ddnsmgr ${NC}命令管理服务"
}

# ---------------------- 主执行流程 ----------------------
if check_installed; then
    if [[ "$(basename "$0")" == "ddnsmgr" ]]; then
        show_menu
    else
        if [ -x "$MANAGER_PATH" ]; then
            "$MANAGER_PATH"
        else
            # 已安装但未使用本脚本的情况
            echo -e "${GREEN}检测到已安装的DDNS-GO服务${NC}"
            echo -e "当前安装路径：$BIN_PATH"
            read -p "是否使用本脚本进行管理？[Y/n] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                # 创建管理命令
                cp "$0" "$MANAGER_PATH"
                chmod +x "$MANAGER_PATH"
                echo -e "\n${GREEN}管理命令已安装到：$MANAGER_PATH${NC}"
                echo -e "可通过 ${YELLOW}ddnsmgr ${NC}命令管理服务"
                "$MANAGER_PATH"
            else
                exit 0
            fi
        fi
    fi
else
    main_install
fi
