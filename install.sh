#!/bin/bash

# 设置终端编码
export LC_ALL=C.UTF-8 2>/dev/null
export LANG=C.UTF-8 2>/dev/null

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 脚本信息
SCRIPT_VERSION="1.2.0" # 更新此处的版本号
SCRIPT_NAME=$(basename "<span class="math-inline">0"\)
SCRIPT\_REPO\="k08255\-lxm/ddns\-go\-installer"
\# 全局变量和配置文件路径
CONFIG\_FILE\="/etc/ddns\-go\.conf"
SERVICE\_FILE\="/etc/systemd/system/ddns\-go\.service"
\# 优先使用 which 查找路径, 否则使用默认路径
BIN\_PATH\_DEFAULT\="/usr/local/bin/ddns\-go"
BIN\_PATH\=</span>(which ddns-go 2>/dev/null)
[ -z "$BIN_PATH" ] && BIN_PATH="<span class="math-inline">BIN\_PATH\_DEFAULT" \# 如果which未找到，使用默认
MANAGER\_PATH\="/usr/local/bin/ddnsmgr"
\# \-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\- 函数定义开始 \-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-
\# 打印错误信息并退出
error\_exit\(\) \{
echo \-e "</span>{RED}错误：<span class="math-inline">1</span>{NC}" >&2
    exit 1
}

# 打印警告信息
warn_msg() {
    echo -e "${YELLOW}警告：<span class="math-inline">1</span>{NC}" >&2
}

# 打印成功信息
success_msg() {
    echo -e "${GREEN}<span class="math-inline">1</span>{NC}"
}

# 打印信息
info_msg() {
    echo -e "${BLUE}<span class="math-inline">1</span>{NC}"
}

# 检查root权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error_exit "请使用sudo或root权限运行此脚本！"
    fi
}

# 安装依赖
install_dependencies() {
    info_msg "\n▌正在检查并安装必要依赖 (curl, tar, jq)..."
    local packages_to_install=()
    command -v curl &>/dev/null || packages_to_install+=("curl")
    command -v tar &>/dev/null || packages_to_install+=("tar")
    command -v jq &>/dev/null || packages_to_install+=("jq")

    if [ ${#packages_to_install[@]} -eq 0 ]; then
        success_msg "所有必要依赖已安装。"
        return
    fi

    echo "需要安装的依赖: <span class="math-inline">\{packages\_to\_install\[\*\]\}"
if command \-v apt\-get &\>/dev/null; then
apt\-get update \-y \|\| warn\_msg "apt\-get update 失败。"
apt\-get install \-y "</span>{packages_to_install[@]}"
    elif command -v yum &>/dev/null; then
        yum install -y "<span class="math-inline">\{packages\_to\_install\[@\]\}"
elif command \-v dnf &\>/dev/null; then
dnf install \-y "</span>{packages_to_install[@]}"
    elif command -v pacman &>/dev/null; then
        pacman -Sy --noconfirm "<span class="math-inline">\{packages\_to\_install\[@\]\}"
elif command \-v zypper &\>/dev/null; then
zypper install \-y "</span>{packages_to_install[@]}"
    else
        error_exit "不支持的包管理器！请手动安装 curl, tar, jq."
    fi

    # 再次检查
    for pkg in "${packages_to_install[@]}"; do
        command -v "$pkg" &>/dev/null || error_exit "依赖 '$pkg' 安装失败。请手动安装。"
    done
    success_msg "依赖安装完成。"
}

# 增强安装状态检测
# 返回值: 0 = 已安装, 1 = 未安装
# 如果已安装, 会尝试更新全局 BIN_PATH
check_installed_status() {
    # 1. 优先检查 manager 管理的 BIN_PATH (如果存在且有效)
    if [[ -f "<span class="math-inline">CONFIG\_FILE" \]\]; then \# 假设配置文件存在，说明可能由本脚本管理
local saved\_bin\_path
saved\_bin\_path\=</span>(grep -oP '^BIN_PATH=\K.*' "$CONFIG_FILE" 2>/dev/null) # 尝试从配置文件读取
        if [[ -n "$saved_bin_path" && -x "$saved_bin_path" ]]; then
            BIN_PATH="$saved_bin_path"
            return 0
        fi
    fi

    # 2. 检查当前 BIN_PATH 变量指向的文件
    if [[ -x "<span class="math-inline">BIN\_PATH" \]\]; then
return 0
fi
\# 3\. 检查 systemd 服务
if systemctl list\-unit\-files \| grep \-q "^ddns\-go\.service"; then
\# 尝试从服务文件获取 ExecStart 路径
local service\_exec\_path
service\_exec\_path\=</span>(systemctl show ddns-go.service --property=ExecStart | grep -oP 'Path=\K[^ ;]*' | head -n 1)
        if [[ -n "$service_exec_path" && -x "$service_exec_path" ]]; then
            BIN_PATH="<span class="math-inline">service\_exec\_path"
return 0
fi
\# 即使无法获取路径，服务存在也认为已安装（可能需要修复）
return 0 
fi
\# 4\. 检查正在运行的进程 \(作为后备，可能不准确指向二进制文件位置\)
if pgrep \-x "ddns\-go" \>/dev/null; then
\# 尝试找到进程对应的可执行文件路径 \(这在Linux上比较可靠\)
local p\_path
p\_path\=</span>(readlink -f /proc/$(pgrep -x "ddns-go" | head -n 1)/exe 2>/dev/null)
        if [[ -n "$p_path" && -x "$p_path" ]]; then
             BIN_PATH="<span class="math-inline">p\_path"
return 0
fi
\# 即使找不到精确路径，进程在运行也认为已安装
return 0 
fi
\# 5\. 检查其他常见安装路径 \(按优先级\)
local common\_paths\=\("/usr/local/bin/ddns\-go" "/usr/bin/ddns\-go" "/opt/ddns\-go/ddns\-go" "/opt/bin/ddns\-go"\)
for path\_to\_check in "</span>{common_paths[@]}"; do
        if [[ -x "$path_to_check" ]]; then
            BIN_PATH="$path_to_check"
            return 0
        fi
    done
    
    return 1 # 未检测到安装
}


# 获取 ddns-go 版本信息
# $1: 二进制文件路径
# 输出: 版本号字符串 (例如 v6.9.1) 或空字符串
get_ddns_go_version() {
    local ddns_bin="$1"
    if [[ ! -x "<span class="math-inline">ddns\_bin" \]\]; then
echo ""
return
fi
\# 尝试不同方式获取版本，以兼容不同输出格式
local version\_output
version\_output\=</span>("<span class="math-inline">ddns\_bin" \-version 2\>&1\)
local version
\# 优先匹配 "ddns\-go version vX\.Y\.Z" 或 "version vX\.Y\.Z"
version\=</span>(echo "$version_output" | grep -oE '(ddns-go version|version) v[0-9]+\.[0-9]+\.[0-9]+' | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    if [[ -n "$version" ]]; then
        echo "<span class="math-inline">version"
return
fi
\# 其次匹配 "vX\.Y\.Z"
version\=</span>(echo "$version_output" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    if [[ -n "$version" ]]; then
        echo "<span class="math-inline">version"
return
fi
\# 再次匹配 "X\.Y\.Z" \(无v\)
version\=</span>(echo "$version_output" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    if [[ -n "$version" ]]; then
        echo "v$version" # 规范化为带v
        return
    fi
    echo "" # 未找到版本
}

# 显示安装结果
show_install_result() {
    local port_to_show="<span class="math-inline">\{1\:\-9876\}" \# 从参数获取端口，默认为9876
local public\_ip
public\_ip\=</span>(curl -4s --connect-timeout 5 ip.sb || curl -6s --connect-timeout 5 ip.sb || echo "YOUR_SERVER_IP")
    
    success_msg "\n✔ DDNS-Go 安装成功！"
    info_msg "访问地址：<span class="math-inline">\{YELLOW\}http\://</span>{public_ip}:<span class="math-inline">\{port\_to\_show\}</span>{NC}"
    echo -e "<span class="math-inline">\{RED\}重要提示：</span>{NC}"
    echo "1. 如果您的服务器IP是动态的，请尽快登录Web界面配置域名解析任务。"
    echo "2. 请确保防火墙已放行端口 <span class="math-inline">\{YELLOW\}</span>{port_to_show}/tcp${NC}。"
    echo "   示例命令："
    echo "   - 对于 UFW: ${YELLOW}sudo ufw allow <span class="math-inline">\{port\_to\_show\}/tcp</span>{NC}"
    echo "   - 对于 firewalld: <span class="math-inline">\{YELLOW\}sudo firewall\-cmd \-\-permanent \-\-add\-port\=</span>{port_to_show}/tcp && sudo firewall-cmd --reload${NC}"
    echo "3. 如果您使用的是云服务器，请检查其安全组/防火墙规则是否也放行了此端口。"
    sleep 3
}

# 查看状态
show_status() {
    clear
    info_msg "\n▌服务状态信息"
    
    local current_version
    current_version=$(get_ddns_go_version "$BIN_PATH")

    if [[ -n "<span class="math-inline">current\_version" \]\]; then
echo \-e "程序版本：</span>{GREEN}<span class="math-inline">\{current\_version\}</span>{NC}"
        echo -e "安装路径：<span class="math-inline">\{YELLOW\}</span>{BIN_PATH}<span class="math-inline">\{NC\}"
else
echo \-e "程序版本：</span>{RED}未知 (无法获取或未安装)${NC}"
        if [[ -x "<span class="math-inline">BIN\_PATH" \]\]; then
echo \-e "安装路径：</span>{YELLOW}<span class="math-inline">\{BIN\_PATH\}</span>{NC} (但无法获取版本)"
        else
             echo -e "安装路径：<span class="math-inline">\{RED\}未找到 ddns\-go 程序</span>{NC}"
        fi
    fi
    
    if systemctl is-active --quiet ddns-go; then
        echo -e "运行状态：<span class="math-inline">\{GREEN\}已运行 \(通过 systemd\)</span>{NC}"
        local start_time
        start_time=$(systemctl show ddns-go --property=ActiveEnterTimestamp --value 2>/dev/null)
        [[ -n "$start_time" && "$start_time" != "n/a" ]] && echo "启动时间：<span class="math-inline">start\_time"
elif pgrep \-x "ddns\-go" \>/dev/null; then
echo \-e "运行状态：</span>{YELLOW}已运行 (但可能不由 systemd 管理)<span class="math-inline">\{NC\}"
else
echo \-e "运行状态：</span>{RED}未运行${NC}"
    fi
    
    if [[ -f "<span class="math-inline">CONFIG\_FILE" \]\]; then
echo \-e "配置文件：</span>{YELLOW}<span class="math-inline">CONFIG\_FILE</span>{NC}"
        local web_status="启用"
        grep -q "NOWEB=true" "<span class="math-inline">CONFIG\_FILE" && web\_status\="禁用 \(NOWEB\=true\)"
local port\_cfg interval\_cfg
port\_cfg\=</span>(grep -oP '^PORT=\K[0-9]+' "<span class="math-inline">CONFIG\_FILE" 2\>/dev/null \|\| echo "默认9876"\)
interval\_cfg\=</span>(grep -oP '^INTERVAL=\K[0-9]+' "<span class="math-inline">CONFIG\_FILE" 2\>/dev/null \|\| echo "默认300s"\)
echo \-e "监听端口：</span>{GREEN}<span class="math-inline">port\_cfg</span>{NC}"
        echo -e "同步间隔：${GREEN}<span class="math-inline">interval\_cfg秒</span>{NC}"
        echo -e "Web界面：${GREEN}<span class="math-inline">web\_status</span>{NC}"
    else
        echo -e "配置文件：${RED}未找到 (<span class="math-inline">CONFIG\_FILE\)</span>{NC}"
    fi

    info_msg "\n▌最近日志（尝试从 journalctl 获取最新5条）"
    if command -v journalctl &>/dev/null && systemctl list-unit-files | grep -q "^ddns-go.service"; then
        journalctl -u ddns-go -n 5 --no-pager --quiet 2>/dev/null || echo "无法获取 systemd 日志。"
    else
        echo "未通过 systemd 管理或 journalctl 不可用。"
        echo "您可以尝试查看 ddns-go 自身的日志（如果已配置）。"
    fi
    
    read -n 1 -s -r -p <span class="math-inline">'\\n按任意键返回菜单\.\.\.'
\}
\# 检查脚本自身更新
check\_self\_update\(\) \{
info\_msg "\\n▌检查管理脚本更新 \(当前版本 v</span>{SCRIPT_VERSION})..."
    local api_url="[https://api.github.com/repos/<span class="math-inline">\]\(https\://api\.github\.com/repos/</span>){SCRIPT_REPO}/releases/latest"
    local api_response
    
    api_response=$(curl -sfL --connect-timeout 8 "$api_url")
    if [[ -z "<span class="math-inline">api\_response" \]\]; then
warn\_msg "检查脚本更新失败（网络连接超时或API请求失败）"
return 1
fi
local latest\_tag
latest\_tag\=</span>(echo "<span class="math-inline">api\_response" \| jq \-r '\.tag\_name' 2\>/dev/null \| sed 's/^v//'\) \# 移除v前缀
local current\_script\_ver\_no\_v
current\_script\_ver\_no\_v\=</span>(echo "$SCRIPT_VERSION" | sed 's/^v//')

    if [[ -z "$latest_tag" ]]; then
        warn_msg "无法从API响应中解析最新版本标签。"
        return 1
    fi

    # 版本号对比逻辑 (主.次.修订)
    local IFS='.'
    local latest_parts=($latest_tag)
    local current_parts=(<span class="math-inline">current\_script\_ver\_no\_v\)
local is\_newer\=0
for i in 0 1 2; do
local latest\_p\=</span>{latest_parts[i]:-0} # 如果某部分不存在，则视为0
        local current_p=<span class="math-inline">\{current\_parts\[i\]\:\-0\}
if \(\( latest\_p \> current\_p \)\); then
is\_newer\=1
break
elif \(\( latest\_p < current\_p \)\); then
is\_newer\=0 \# 本地版本更新或相同
break 
fi
done
if \(\( is\_newer \)\); then
echo \-e "</span>{YELLOW}发现新版管理脚本 (v${latest_tag})，当前版本 (v${SCRIPT_VERSION})${NC}"
        read -p "是否更新管理脚本？[Y/n] " -n 1 -r -t 15 REPLY
        echo
        if [[ "<span class="math-inline">REPLY" \=\~ ^\[Nn\]</span> ]]; then
            info_msg "取消脚本更新。"
            return
        fi

        info_msg "正在更新管理脚本..."
        local temp_script_file
        temp_script_file=<span class="math-inline">\(mktemp\)
local download\_url\="\[https\://raw\.githubusercontent\.com/</span>](https://raw.githubusercontent.com/$){SCRIPT_REPO}/main/install.sh" # 假设主分支是main

        if curl -sfL --connect-timeout 15 "$download_url" -o "$temp_script_file"; then
            # 简单验证下载的文件是否是bash脚本
            if head -n 1 "<span class="math-inline">temp\_script\_file" \| grep \-q "bash"; then
\# 获取新脚本中的版本号
local new\_version\_in\_file
new\_version\_in\_file\=</span>(grep -m1 '^SCRIPT_VERSION=' "$temp_script_file" | cut -d'"' -f2)
                
                mv "$temp_script_file" "$MANAGER_PATH" || error_exit "移动脚本失败，权限问题？"
                chmod +x "<span class="math-inline">MANAGER\_PATH" \|\| error\_exit "设置脚本执行权限失败。"
success\_msg "管理脚本已更新到 v</span>{new_version_in_file:-$latest_tag}。请重新运行 '$MANAGER_PATH'！"
                exit 0
            else
                warn_msg "下载的文件似乎不是有效的脚本。"
                rm -f "$temp_script_file"
            fi
        else
            rm -f "$temp_script_file"
            error_exit "下载新版脚本失败。请检查网络或手动从 GitHub 更新。"
        fi
    elif [[ "$latest_tag" == "<span class="math-inline">current\_script\_ver\_no\_v" \]\]; then
success\_msg "当前管理脚本已是最新版本 \(v</span>{SCRIPT_VERSION})。"
    else
        info_msg "本地管理脚本版本 (v${SCRIPT_VERSION}) 高于 GitHub 最新发布版本 (v${latest_tag})。可能是开发版。"
    fi
}

# 卸载程序
uninstall_ddns_go() {
    check_root
    clear
    read -p "$(echo -e <span class="math-inline">\{RED\}"警告：此操作将停止并移除DDNS\-Go服务及其配置文件！\\n确定要卸载吗？\[y/N\] "</span>{NC})" -n 1 -r REPLY
    echo
    if [[ ! "<span class="math-inline">REPLY" \=\~ ^\[Yy\]</span> ]]; then
        info_msg "卸载操作已取消。"
        return
    fi

    info_msg "\n正在卸载 DDNS-Go..."
    if systemctl list-unit-files | grep -q "^ddns-go.service"; then
        systemctl stop ddns-go 2>/dev/null
        systemctl disable ddns-go 2>/dev/null
        rm -f "$SERVICE_FILE" || warn_msg "删除服务文件 $SERVICE_FILE 失败。"
        systemctl daemon-reload
        systemctl reset-failed
        success_msg "DDNS-Go systemd 服务已卸载。"
    else
        info_msg "未找到 DDNS-Go systemd 服务。"
    fi
    
    # 尝试杀掉残余进程
    pgrep -x "ddns-go" | xargs -r kill -9 2>/dev/null
    
    if [[ -f "$BIN_PATH" ]]; then
        rm -f "$BIN_PATH" || warn_msg "删除二进制文件 $BIN_PATH 失败。"
        success_msg "DDNS-Go 二进制文件已删除。"
    else
        info_msg "未找到 DDNS-Go 二进制文件 ($BIN_PATH)。"
    fi
    
    if [[ -f "$CONFIG_FILE" ]]; then
        rm -f "$CONFIG_FILE" || warn_msg "删除配置文件 $CONFIG_FILE 失败。"
        success_msg "DDNS-Go 配置文件已删除。"
    else
        info_msg "未找到 DDNS-Go 配置文件 ($CONFIG_FILE)。"
    fi

    # 删除管理脚本自身 (如果当前是通过 ddnsmgr 运行的)
    if [[ "$SCRIPT_NAME" == "ddnsmgr" && -f "$MANAGER_PATH" ]]; then
        rm -f "$MANAGER_PATH" || warn_msg "删除管理脚本 $MANAGER_PATH 失败。"
        success_msg "管理脚本 ddnsmgr 已删除。"
    fi
    
    success_msg "\nDDNS-Go 卸载完成！"
    sleep 2
}


# 获取所有 ddns-go 版本列表
# 输出: 版本号列表，每行一个 (例如 v6.9.1)
# 失败则输出空并打印错误到stderr
get_ddns_go_available_versions() {
    local versions_json
    local retry_count=0
    local max_retries=2 # 总共尝试3次

    while [[ $retry_count -le <span class="math-inline">max\_retries \]\]; do
versions\_json\=</span>(curl -sfL --connect-timeout 10 "[https://api.github.com/repos/jeessy2/ddns-go/releases](https://api.github.com/repos/jeessy2/ddns-go/releases)")
        if [[ -n "<span class="math-inline">versions\_json" \]\]; then
local versions\_list
versions\_list\=</span>(echo "$versions_json" | jq -r '.[].tag_name' 2>/dev/null)
            if [[ -n "$versions_list" ]]; then
                echo "$versions_list" # 成功获取并解析
                return 0
            fi
            # JQ 解析失败或返回空
            warn_msg "无法从API响应中用jq解析版本列表 (尝试 $((retry_count+1)))。"
        else
            warn_msg "获取版本信息API请求失败 (尝试 <span class="math-inline">\(\(retry\_count\+1\)\)\)。"
fi
retry\_count\=</span>((retry_count + 1))
        if [[ $retry_count -le $max_retries ]]; then
            sleep $((retry_count * 2)) # 增加等待时间
        fi
    done
    
    error_exit "多次尝试后仍无法获取DDNS-Go版本列表。请检查网络连接和GitHub API状态！"
    return 1 # 理论上不会执行到这里，因为error_exit会退出
}


# 验证版本号是否存在于可用版本列表
# $1: 用户输入的版本号
# 返回: 0 (有效), 1 (无效)
validate_ddns_go_version() {
    local version_to_validate="$1"
    local available_versions
    
    info_msg "正在验证版本号 <span class="math-inline">\{version\_to\_validate\}\.\.\."
available\_versions\=</span>(get_ddns_go_available_versions)
    if [[ $? -ne 0 ]]; then # get_ddns_go_available_versions 内部会处理错误退出
        return 1 # 如果由于某种原因没有退出，这里也返回错误
    fi

    if echo "$available_versions" | grep -Fxq "$version_to_validate"; then
        success_msg "版本号 ${version_to_validate} 有效。"
        return 0
    else
        warn_msg "错误：版本号 <span class="math-inline">\{version\_to\_validate\} 无效或不存在于可用版本列表。"
echo \-e "</span>{YELLOW}可用版本 (部分列表):${NC}"
        echo "$available_versions" | head -n 10 # 显示前10个作为提示
        return 1
    fi
}


# 安装DDNS-GO
# $1: 要安装的版本号 (例如 v6.9.1)
install_ddns_go_core() {
    local version_to_install="<span class="math-inline">1"
local arch cpu\_arch
cpu\_arch\=</span>(uname -m)
    local os_type
    os_type=<span class="math-inline">\(uname \-s \| tr '\[\:upper\:\]' '\[\:lower\:\]'\)
local temp\_dir
\# 创建临时目录，并设置trap确保退出时清理
temp\_dir\=</span>(mktemp -d)
    if [[ -z "$temp_dir" || ! -d "$temp_dir" ]]; then
        error_exit "无法创建临时目录。"
    fi
    trap 'echo "捕获到退出信号，正在清理临时目录 $temp_dir..."; rm -rf "$temp_dir"' EXIT HUP INT QUIT TERM PIPE

    # 架构映射
    case "$cpu_arch" in
        x86_64|amd64) arch="x86_64" ;;
        i386|i686)    arch="i386" ;; # ddns-go 可能不再支持32位x86，需确认
        armv6l)       arch="armv6" ;;
        armv7l)       arch="armv7" ;;
        aarch64|arm64) arch="arm64" ;;
        *) error_exit "不支持的CPU架构：$cpu_arch" ;;
    esac

    # 操作系统类型映射
    case "$os_type" in
        linux*)   os_type="linux" ;;
        freebsd*) os_type="freebsd" ;;
        darwin*)  os_type="darwin" ;; # macOS, ddns-go 是否提供 darwin 包?
        *) error_exit "不支持的操作系统：$os_type" ;;
    esac

    # 确保版本号以 'v' 开头，如果不是则添加
    [[ "$version_to_install" != v* ]] && version_to_install="v$version_to_install"
    
    local filename_version="<span class="math-inline">\{version\_to\_install\#v\}" \# 移除 'v' 以用于文件名
local download\_url\="\[https\://github\.com/jeessy2/ddns\-go/releases/download/</span>](https://github.com/jeessy2/ddns-go/releases/download/<span class="math-inline">\)\{version\_to\_install\}/ddns\-go\_</span>{filename_version}_${os_type}_${arch}.tar.gz"

    info_msg "\n▌正在下载 DDNS-Go 版本：${version_to_install} (架构 ${arch}, 系统 ${os_type})"
    echo "下载地址：<span class="math-inline">download\_url"
local start\_time file\_size time\_cost avg\_speed speed\_unit file\_bytes
start\_time\=</span>(date +%s)
    
    # 使用 curl 下载，增加进度条
    echo "正在下载到 $temp_dir/ddns-go.tar.gz ..."
    if ! curl --progress-bar -fL --connect-timeout 20 "$download_url" -o "$temp_dir/ddns-go.tar.gz"; then
        rm -rf "$temp_dir" # 清理
        trap - EXIT HUP INT QUIT TERM PIPE # 移除 trap
        error_exit "下载失败！请检查：\n1. 网络连接是否正常。\n2. 版本 <span class="math-inline">\{version\_to\_install\} 是否支持您的系统架构 \(</span>{os_type}/<span class="math-inline">\{arch\}\)。"
fi
end\_time\=</span>(date +%s)
    time_cost=<span class="math-inline">\(\(end\_time \- start\_time\)\)
\(\(time\_cost \=\= 0\)\) && time\_cost\=1 \# 避免除以零
file\_size\=</span>(du -sh "<span class="math-inline">temp\_dir/ddns\-go\.tar\.gz" \| cut \-f1\)
file\_bytes\=</span>(stat -c %s "$temp_dir/ddns-go.tar.gz" 2>/dev/null || stat -f %z "<span class="math-inline">temp\_dir/ddns\-go\.tar\.gz" 2\>/dev/null \|\| echo 0\) \#兼容macOS stat
avg\_speed\=</span>((file_bytes / time_cost / 1024)) # KB/s
    speed_unit="KB/s"
    if ((avg_speed >= 1024)); then
        avg_speed=$(awk -v speed="<span class="math-inline">avg\_speed" 'BEGIN \{ printf "%\.1f", speed / 1024 \}'\)
speed\_unit\="MB/s"
fi
success\_msg "✓ 下载完成！"
echo "  文件大小：</span>{file_size}"
    echo "  下载耗时：<span class="math-inline">\{time\_cost\} 秒"
echo "  平均速度：</span>{avg_speed} ${speed_unit}"

    info_msg "\n正在安装到：$BIN_PATH ..."
    if ! tar xzf "$temp_dir/ddns-go.tar.gz" -C "$temp_dir"; then
        rm -rf "<span class="math-inline">temp\_dir"
trap \- EXIT HUP INT QUIT TERM PIPE
error\_exit "解压 ddns\-go\.tar\.gz 失败。"
fi
\# 确保目标目录存在
mkdir \-p "</span>(dirname "$BIN_PATH")" || error_exit "创建安装目录 $(dirname "$BIN_PATH") 失败。"

    # 如果服务正在运行，先停止
    if systemctl is-active --quiet ddns-go; then
        info_msg "检测到 ddns-go 服务正在运行，将尝试停止..."
        systemctl stop ddns-go || warn_msg "停止 ddns-go 服务失败，可能影响更新。"
        sleep 1 # 等待服务停止
    fi
    
    if ! mv "$temp_dir/ddns-go" "$BIN_PATH"; then
        rm -rf "$temp_dir"
        trap - EXIT HUP INT QUIT TERM PIPE
        error_exit "移动 ddns-go 到 $BIN_PATH 失败。请检查权限或是否有同名目录。"
    fi
    
    if ! chmod +x "$BIN_PATH"; then
        rm -rf "$temp_dir"
        trap - EXIT HUP INT QUIT TERM PIPE
        error_exit "设置 $BIN_PATH 执行权限失败。"
    fi
  
    success_msg "DDNS-Go 已安装/更新到 $BIN_PATH"
    rm -rf "$temp_dir" # 清理临时目录
    trap - EXIT HUP INT QUIT TERM PIPE # 移除 trap
}


# 服务配置
# $1: Port, $2: Interval, $3: Noweb (true/false string)
configure_systemd_service() {
    local listen_port="$1"
    local sync_interval="$2"
    local noweb_mode="$3" # "true" or "false"
    local noweb_param=""

    [[ "<span class="math-inline">noweb\_mode" \=\= "true" \]\] && noweb\_param\="\-noweb"
info\_msg "\\n▌正在配置 systemd 后台服务 \(ddns\-go\.service\)\.\.\."
\# 创建 ddns\-go 系统用户 \(如果不存在\)
if \! id \-u ddns\-go &\>/dev/null; then
info\_msg "正在创建 ddns\-go 系统用户\.\.\."
useradd \-r \-s /bin/false \-m \-d /var/lib/ddns\-go ddns\-go \|\| \{
warn\_msg "创建 ddns\-go 用户失败。将尝试以 root 用户运行服务（不推荐）。"
SERVICE\_USER\="root"
\}
SERVICE\_USER\="ddns\-go"
\# 确保配置目录和文件的所有权
mkdir \-p "</span>(dirname "$CONFIG_FILE")"
        touch "<span class="math-inline">CONFIG\_FILE" \# 确保文件存在以便后续 chown
chown \-R ddns\-go\:ddns\-go "</span>(dirname "$CONFIG_FILE")"
        chown ddns-go:ddns-go "$CONFIG_FILE" || warn_msg "设置 $CONFIG_FILE 所有权失败。"

    else
        SERVICE_USER="ddns-go" # 用户已存在
        info_msg "系统用户 ddns-go 已存在。"
    fi


    cat > "<span class="math-inline">SERVICE\_FILE" <<EOF
\[Unit\]
Description\=DDNS\-Go Dynamic DNS Client Service
Documentation\=\[https\://github\.com/jeessy2/ddns\-go\]\(https\://github\.com/jeessy2/ddns\-go\)
After\=network\.target network\-online\.target
Wants\=network\-online\.target
\[Service\]
Type\=simple
User\=</span>{SERVICE_USER}
Group=${SERVICE_USER}
ExecStart=$BIN_PATH $noweb_param -l :$listen_port -f $sync_interval -c $CONFIG_FILE
Restart=on-failure
RestartSec=30s
TimeoutStopSec=60s
StandardOutput=journal
StandardError=journal
# PermissionsStartOnly=true # 如果需要在 ExecStartPre 中以root执行命令
# AmbientCapabilities=CAP_NET_BIND_SERVICE # 如果以非root用户运行且端口 < 1024 (通常不适用此场景)

[Install]
WantedBy=multi-user.target
EOF

    if [[ ! -f "$SERVICE_FILE" ]]; then
        error_exit "创建服务文件 $SERVICE_FILE 失败。"
    fi

    systemctl daemon-reload || error_exit "systemctl daemon-reload 失败。"
    systemctl enable ddns-go || error_exit "systemctl enable ddns-go 失败。"
    
    info_msg "正在尝试启动/重启 ddns-go 服务..."
    if ! systemctl restart ddns-go; then
        warn_msg "ddns-go 服务启动/重启失败。请检查日志：journalctl -u ddns-go -xe"
    else
        success_msg "ddns-go 服务配置完成并已启动/重启。"
    fi
}


# 切换Web界面状态
toggle_webui_status() {
    check_root
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error_exit "配置文件 $CONFIG_FILE 不存在。请先完成安装或检查路径。"
    fi
    
    source "<span class="math-inline">CONFIG\_FILE" \# 加载当前配置以获取 PORT 和 INTERVAL
local current\_port\="</span>{PORT:-9876}" # 使用加载的值或默认值
    local current_interval="${INTERVAL:-300}"
    local current_noweb_status="false" # 默认启用Web
    grep -q "NOWEB=true" "$CONFIG_FILE" && current_noweb_status="true"

    if [[ "$current_noweb_status" == "true" ]]; then
        # 当前是禁用状态，现在要启用
        # 从配置文件中删除 NOWEB=true 行或注释掉
        sed -i '/^NOWEB=true/d' "$CONFIG_FILE"
        success_msg "Web界面已设置为 <span class="math-inline">\{GREEN\}启用</span>{NC}。"
        current_noweb_status="false"
    else
        # 当前是启用状态，现在要禁用
        # 如果 NOWEB 行已存在但被注释或值为false，则修改；否则添加
        if grep -q "^#*NOWEB=" "$CONFIG_FILE"; then
            sed -i 's/^#*NOWEB=.*/NOWEB=true/' "$CONFIG_FILE"
        else
            echo "NOWEB=true" >> "$CONFIG_FILE"
        fi
        success_msg "Web界面已设置为 <span class="math-inline">\{YELLOW\}禁用</span>{NC}。"
        current_noweb_status="true"
    fi
    
    # 重新配置并重启服务以应用更改
    configure_systemd_service "$current_port" "$current_interval" "$current_noweb_status"
    read -n 1 -s -r -p "操作完成，按任意键继续..."
}


# 保存配置到 $CONFIG_FILE
# $1: Port, $2: Interval, $3: Noweb (true/false string), $4: BIN_PATH
save_configuration() {
    local conf_port="$1"
    local conf_interval="$2"
    local conf_noweb="$3"
    local conf_bin_path="$4"

    info_msg "正在保存配置到 <span class="math-inline">CONFIG\_FILE\.\.\."
\# 为确保原子性，先写入临时文件再移动
local temp\_conf\_file
temp\_conf\_file\=</span>(mktemp)

    echo "# DDNS-Go Installer Configuration" > "$temp_conf_file"
    echo "PORT=$conf_port" >> "$temp_conf_file"
    echo "INTERVAL=$conf_interval" >> "$temp_conf_file"
    [[ "$conf_noweb" == "true" ]] && echo "NOWEB=true" >> "$temp_conf_file"
    echo "BIN_PATH=$conf_bin_path" >> "$temp_conf_file" # 保存二进制路径
    echo "MANAGED_BY_SCRIPT_VERSION=$SCRIPT_VERSION" >> "$temp_conf_file"
    
    # 设置文件权限和所有权 (如果 ddns-go 用户存在)
    if id -u ddns-go &>/dev/null; then
        chown ddns-go:ddns-go "$temp_conf_file" || warn_msg "设置临时配置文件所有权失败。"
    fi
    chmod 600 "$temp_conf_file" || warn_msg "设置临时配置文件权限失败。"

    # 移动临时文件到最终位置
    if mv "$temp_conf_file" "$CONFIG_FILE"; then
        success_msg "配置已保存到 $CONFIG_FILE。"
    else
        rm -f "$temp_conf_file"
        error_exit "保存配置文件 <span class="math-inline">CONFIG\_FILE 失败。"
fi
\}
\# 更新 DDNS\-Go 程序
update\_ddns\_program\(\) \{
check\_root
info\_msg "\\n▌正在检查 DDNS\-Go 程序更新\.\.\."
if \! check\_installed\_status; then \# 会更新 BIN\_PATH
error\_exit "DDNS\-Go 未安装或无法确定安装状态。请先安装。"
fi
local current\_version
current\_version\=</span>(get_ddns_go_version "$BIN_PATH")
    if [[ -z "<span class="math-inline">current\_version" \]\]; then
warn\_msg "无法获取当前 DDNS\-Go 版本。将尝试获取最新版本进行比较。"
\# 强制用户选择是否更新
else
info\_msg "当前 DDNS\-Go 版本：</span>{GREEN}<span class="math-inline">current\_version</span>{NC}"
    fi

    local latest_version
    latest_version=$(get_ddns_go_available_versions | head -n 1)
    if [[ -z "<span class="math-inline">latest\_version" \]\]; then
\# get\_ddns\_go\_available\_versions 内部会处理错误退出，这里理论上不会执行
error\_exit "无法获取最新的 DDNS\-Go 版本。" 
fi
info\_msg "最新可用 DDNS\-Go 版本：</span>{GREEN}<span class="math-inline">latest\_version</span>{NC}"

    if [[ "$current_version" == "$latest_version" ]]; then
        success_msg "您的 DDNS-Go 程序已是最新版本！"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi
    
    # 版本比较 (简化：不完全等于则认为可更新，包括降级场景提示)
    local prompt_msg="发现新版本 ${latest_version} (当前 ${current_version:-未知})。是否更新？[Y/n] "
    if [[ -n "<span class="math-inline">current\_version" \]\]; then
\# 进行更精确的版本比较
local IFS\='\.'
local latest\_parts\=\(</span>{latest_version#v}) current_parts=(<span class="math-inline">\{current\_version\#v\}\)
local can\_update\=0
for i in 0 1 2; do
local lp\=</span>{latest_parts[i]:-0} cp=${current_parts[i]:-0}
            if (( 10#$lp > 10#$cp )); then can_update=1; break; fi
            if (( 10#$lp < 10#$cp )); then
                prompt_msg="最新版本 ${latest_version} 低于当前版本 ${current_version}。确定要 '更新' (降级) 吗？[y/N] "
                can_update=1 # 允许用户选择降级
                break
            fi
        done
        if (( ! can_update )) && [[ "$latest_version" != "<span class="math-inline">current\_version" \]\]; then \# 处理如 v1\.1\.0 vs v1\.1 这种情况
can\_update\=1 \# 如果不完全相同且不是明确的旧版本，则也提示更新
fi
if \(\( \! can\_update \)\); then \# 如果严格相同或者本地更新
success\_msg "您的 DDNS\-Go 程序已是最新版本或更新！"
read \-n 1 \-s \-r \-p "按任意键继续\.\.\."
return
fi
fi
read \-p "</span>(echo -e "<span class="math-inline">\{YELLOW\}</span>{prompt_msg}${NC}")" -n 1 -r -t 15 REPLY
    echo
    local default_reply='Y'
    [[ "$prompt_msg" == *"降级"* ]] && default_reply='N' # 降级时默认为N

    if [[ -z "$REPLY" ]]; then REPLY="$default_reply"; fi # 超时则使用默认

    if [[ "<span class="math-inline">REPLY" \=\~ ^\[Nn\]</span> ]]; then
        info_msg "取消 DDNS-Go 程序更新。"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi
    
    # 加载现有配置用于服务重启
    local conf_port=9876 conf_interval=300 conf_noweb="false"
    if [[ -f "$CONFIG_FILE" ]]; then
        source "<span class="math-inline">CONFIG\_FILE" \# 这会覆盖上面的默认值
conf\_port\="</span>{PORT:-9876}"
        conf_interval="${INTERVAL:-300}"
        grep -q "NOWEB=true" "$CONFIG_FILE" && conf_noweb="true"
    fi

    install_ddns_go_core "$latest_version" # 安装核心
    # 安装后，BIN_PATH 可能已被 install_ddns_go_core 内部更新 (如果它修改了全局变量)
    # 或者我们在这里重新获取，并更新配置文件中的 BIN_PATH
    local new_bin_path_after_install="$BIN_PATH" # 假设 install_ddns_go_core 更新了全局 BIN_PATH
                                             # 或在此处重新 check_installed_status 来确定新的 BIN_PATH
    
    # 重新配置服务 (使用新路径和旧配置)
    configure_systemd_service "$conf_port" "$conf_interval" "$conf_noweb"
    # 更新配置文件中的 BIN_PATH 和脚本版本
    save_configuration "$conf_port" "$conf_interval" "$conf_noweb" "$new_bin_path_after_install"
    
    success_msg "\nDDNS-Go 程序已成功更新到 ${latest_version}！"
    read -n 1 -s -r -p "按任意键继续..."
}


# 管理菜单
show_management_menu() {
    check_root # 菜单操作大都需要root
    # 每次进入菜单前，检查脚本自身更新
    check_self_update || warn_msg "脚本自更新检查失败，请稍后重试或手动更新。"
    
    while true; do
        clear
        # 确保 BIN_PATH 是最新的
        if ! check_installed_status && [[ "<span class="math-inline">SCRIPT\_NAME" \!\= "install\.sh" \]\]; then \# 如果是直接运行install\.sh且未安装，则不显示错误
warn\_msg "DDNS\-Go 可能未正确安装或状态未知。某些菜单选项可能无法正常工作。"
fi
local current\_ddns\_version
current\_ddns\_version\=</span>(get_ddns_go_version "<span class="math-inline">BIN\_PATH"\)
info\_msg "\\n▌DDNS\-Go 管理菜单 \(脚本 v</span>{SCRIPT_VERSION}) ${NC}"
        [[ -n "$current_ddns_version" ]] && echo -e "  DDNS-Go 版本: <span class="math-inline">\{GREEN\}</span>{current_ddns_version}${NC}"
        echo "  安装路径: <span class="math-inline">\{YELLOW\}</span>{BIN_PATH}${NC}"
        echo "--------------------------------------------------"
        echo "1. 启动 DDNS-Go 服务"
        echo "2. 停止 DDNS-Go 服务"
        echo "3. 重启 DDNS-Go 服务"
        echo "4. 切换 Web 界面状态 (启用/禁用)"
        echo "5. 查看 DDNS-Go 状态和日志"
        echo "6. 更新 DDNS-Go 程序到最新版"
        echo "7. 卸载 DDNS-Go"
        echo "8. 退出管理菜单"
        echo "--------------------------------------------------"
        
        local choice
        read -p "请输入选项 [1-8]: " choice
        case "$choice" in
            1) 
                info_msg "正在启动 DDNS-Go 服务..."
                if systemctl start ddns-go; then success_msg "✔ 服务启动成功"; else error_exit "✖ 服务启动失败，请查看日志: journalctl -u ddns-go -xe"; fi
                read -n 1 -s -r -p "按任意键继续..." ;;
            2) 
                info_msg "正在停止 DDNS-Go 服务..."
                if systemctl stop ddns-go; then success_msg "✔ 服务停止成功"; else error_exit "✖ 服务停止失败"; fi
                read -n 1 -s -r -p "按任意键继续..." ;;
            3) 
                info_msg "正在重启 DDNS-Go 服务..."
                if systemctl restart ddns-go; then success_msg "✔ 服务重启成功"; else error_exit "✖ 服务重启失败，请查看日志: journalctl -u ddns-go -xe"; fi
                read -n 1 -s -r -p "按任意键继续..." ;;
            4) toggle_webui_status ;;
            5) show_status ;;
            6) update_ddns_program ;;
            7) uninstall_ddns_go; exit 0 ;; # 卸载后通常应退出脚本
            8) success_msg "退出管理菜单。"; exit 0 ;;
            *) 
                warn_msg "无效输入 '<span class="math-inline">choice'，请输入1\-8之间的数字。"
sleep 1 ;;
esac
done
\}
\# 主安装流程
main\_installation\_process\(\) \{
check\_root
install\_dependencies \# 安装curl, tar, jq
clear
info\_msg "欢迎使用 DDNS\-Go 一键安装脚本 \(v</span>{SCRIPT_VERSION})"
    info_msg "\n▌配置参数设置"
    
    local listen_port sync_interval selected_version noweb_choice noweb_value
    
    # 1. 端口验证
    while true; do
        read -p "请输入 DDNS-Go Web 界面监听端口 [默认 9876]: " listen_port
        listen_port=${listen_port:-9876}
        if [[ "<span class="math-inline">listen\_port" \=\~ ^\[0\-9\]\+</span> && "$listen_port" -ge 1 && "<span class="math-inline">listen\_port" \-le 65535 \]\]; then
\# 检查端口是否被占用 \(可选，但友好\)
if ss \-tuln \| grep \-q "\:</span>{listen_port}\s"; then # Linux
                 warn_msg "端口 ${listen_port} 当前似乎已被占用。确定要继续使用吗？(y/N)"
                 read -n 1 -r -t 10 REPLY
                 echo
                 [[ "<span class="math-inline">REPLY" \=\~ ^\[Yy\]</span> ]] && break
                 continue
            elif netstat -anL | grep -q "\.<span class="math-inline">\{listen\_port\}\.\*LISTEN" && \[\[ "</span>(uname -s)" == "FreeBSD" ]]; then # FreeBSD
                 warn_msg "端口 ${listen_port} 当前似乎已被占用。确定要继续使用吗？(y/N)"
                 read -n 1 -r -t 10 REPLY
                 echo
                 [[ "<span class="math-inline">REPLY" \=\~ ^\[Yy\]</span> ]] && break
                 continue
            fi
            break
        else
            warn_msg "端口必须为 1-65535 之间的数字！"
        fi
    done

    # 2. 同步间隔验证
    while true; do
        read -p "请输入 DNS 同步间隔（秒）[默认 300, 最小 60]: " sync_interval
        sync_interval=${sync_interval:-300}
        if [[ "<span class="math-inline">sync\_interval" \=\~ ^\[0\-9\]\+</span> && "$sync_interval" -ge 60 ]]; then
            break
        else
            warn_msg "间隔时间必须为数字且不能小于 60 秒！"
        fi
    done

    # 3. 是否启用Web界面
    read -p "是否在启动时禁用 Web 管理界面 (更安全，但需手动修改配置开启)? [y/N]: " -n 1 -r noweb_choice
    echo
    if [[ "<span class="math-inline">noweb\_choice" \=\~ ^\[Yy\]</span> ]]; then
        noweb_value="true" # 表示禁用Web
        info_msg "Web 界面将在启动时被禁用。"
    else
        noweb_value="false" # 表示启用Web
        info_msg "Web 界面将在启动时启用 (端口: <span class="math-inline">listen\_port\)。"
fi
\# 4\. 版本选择
info\_msg "\\n▌正在获取可用的 DDNS\-Go 版本列表\.\.\."
local available\_versions
available\_versions\=</span>(get_ddns_go_available_versions) # 此函数内部有错误处理和重试
    
    echo -e "<span class="math-inline">\{YELLOW\}最新可用版本：</span>(echo "<span class="math-inline">available\_versions" \| head \-n 1\)</span>{NC}"
    echo "其他最近版本 (最多显示5个):"
    echo "$available_versions" | head -n 5
    
    while true; do
        read -p "请输入要安装的 DDNS-Go 版本号 (例如 vX.Y.Z，留空则安装最新版): " selected_version
        if [ -z "<span class="math-inline">selected\_version" \]; then
selected\_version\=</span>(echo "$available_versions" | head -n 1)
            success_msg "将安装最新版本: $selected_version"
            break
        fi
        # 确保用户输入的版本号带'v'前缀 (如果他们忘记了)
        [[ "$selected_version" != v* ]] && selected_version="v$selected_version"

        if validate_ddns_go_version "$selected_version"; then # validate 函数内部有提示
            break # 版本有效
        else
            warn_msg "无效的版本号。请从上面列表选择或确保格式正确。"
            # validate_ddns_go_version 内部已显示提示，此处无需重复
        fi
    done

    # 执行核心安装
    install_ddns_go_core "$selected_version"
    
    # 配置服务和保存配置
    # BIN_PATH 在 install_ddns_go_core 后应该是正确的（指向新安装的二进制）
    configure_systemd_service "$listen_port" "$sync_interval" "$noweb_value"
    save_configuration "$listen_port" "$sync_interval" "$noweb_value" "$BIN_PATH"
    
    show_install_result "$listen_port"
    
    # 创建管理命令的软链接或复制脚本
    if [[ "<span class="math-inline">SCRIPT\_NAME" \=\= "install\.sh" \]\]; then \# 只有在运行原始安装脚本时才创建管理器
info\_msg "\\n正在创建管理命令 'ddnsmgr'\.\.\."
\# 确保 /usr/local/bin 存在于 PATH 或可写
mkdir \-p "</span>(dirname "$MANAGER_PATH")"
        if cp "$0" "$MANAGER_PATH"; then # 复制自身作为管理器
            chmod +x "<span class="math-inline">MANAGER\_PATH"
success\_msg "管理命令已成功创建到：</span>{YELLOW}<span class="math-inline">MANAGER\_PATH</span>{NC}"
            info_msg "您现在可以使用 <span class="math-inline">\{YELLOW\}sudo ddnsmgr</span>{NC} 命令来管理 DDNS-Go 服务。"
        else
            warn_msg "创建管理命令 $MANAGER_PATH 失败。您可能需要手动复制 $0 到一个 PATH 路径下并命名为 ddnsmgr。"
        fi
    fi
    
    info_msg "\n安装流程结束。如果服务未自动启动或遇到问题，请检查日志: journalctl -u ddns-go -xe"
}


# ---------------------- 主执行流程 ----------------------

# 脚本是作为管理器 (ddnsmgr) 运行还是作为安装脚本 (install.sh) 运行
if [[ "$SCRIPT_NAME" == "ddnsmgr" ]]; then
    # 作为管理器运行
    if ! check_installed_status; then
         # 如果以 ddnsmgr 身份运行但 ddns-go 未安装 (或检测不到)
        warn_msg "DDNS-Go似乎未安装或无法检测。管理菜单可能无法正常工作。"
        read -p "是否尝试进入安装流程？[Y/n] " -n 1 -r REPLY
        echo
        if [[ "<span class="math-inline">REPLY" \=\~ ^\[Yy\]</span> ]] || [[ -z "<span class="math-inline">REPLY" \]\]; then
\# 切换到安装模式，需要原始脚本名 install\.sh 的行为
\# 这有点 tricky，因为脚本名已是 ddnsmgr
\# 最好的做法是提示用户用原始 install\.sh 运行
info\_msg "请通过原始的 install\.sh 脚本执行安装。"
info\_msg "如果 install\.sh 已被覆盖或删除，请从 GitHub 重新下载。"
exit 1
else
info\_msg "继续进入管理菜单，但功能可能受限。"
fi
fi
show\_management\_menu
else
\# 作为安装脚本 \(install\.sh 或其他名字\) 运行
if check\_installed\_status; then
\# DDNS\-Go 已安装
info\_msg "</span>{GREEN}检测到已安装的 DDNS-Go 服务 (版本: $(get_ddns_go_version "<span class="math-inline">BIN\_PATH"\)\)</span>{NC}"
        echo "安装路径: ${YELLOW}<span class="math-inline">BIN\_PATH</span>{NC}"
        
        if [[ -x "$MANAGER_PATH" && "$MANAGER_PATH" != "$0" ]]; then # 检查管理器是否已存在且不是当前脚本自身
            read -p "是否进入管理菜单 (ddnsmgr)？[Y/n] " -n 1 -r REPLY
            echo
            if [[ "<span class="math-inline">REPLY" \=\~ ^\[Yy\]</span> ]] || [[ -z "$REPLY" ]]; then
                # 使用 sudo 执行，因为菜单操作通常需要 root
                # 如果当前已经是 root，sudo 不会产生问题
                sudo "$MANAGER_PATH"
                exit $?
            else
                info_msg "已选择不进入管理菜单。如果需要重新安装，请先卸载现有版本。"
                exit 0
            fi
        else
            # 管理器不存在，或当前脚本就是管理器但以install.sh之名运行
            read -p "DDNS-Go 已安装。是否进入管理菜单？(将尝试使用当前脚本作为管理器) [Y/n/r(重新安装)] " -n 1 -r REPLY
            echo
            if [[ "<span class="math-inline">REPLY" \=\~ ^\[Yy\]</span> ]] || [[ -z "$REPLY" ]]; then
                # 复制当前脚本到MANAGER_PATH（如果它还不是）
                if [[ "$0" != "<span class="math-inline">MANAGER\_PATH" \]\]; then
info\_msg "正在设置当前脚本为管理脚本\.\.\."
check\_root \# 确保有权限复制
mkdir \-p "</span>(dirname "$MANAGER_PATH")"
                    cp "$0" "$MANAGER_PATH" && chmod +x "$MANAGER_PATH" || {
                        warn_msg "设置管理脚本失败，请检查权限。将尝试直接运行当前脚本的菜单。"
                        show_management_menu # 直接运行菜单
                        exit $?
                    }
                    sudo "$MANAGER_PATH" # 用新的管理器路径执行
                    exit $?
                else
                     show_management_menu # 当前脚本已经是管理器
                     exit $?
                fi

            elif [[ "<span class="math-inline">REPLY" \=\~ ^\[Rr\]</span> ]]; then
                read -p "$(echo -e <span class="math-inline">\{RED\}"确定要重新安装 DDNS\-Go 吗？现有配置和服务将被覆盖！\[y/N\] "</span>{NC})" -n 1 -r CONFIRM_REINSTALL
                echo
                if [[ "<span class="math-inline">CONFIRM\_REINSTALL" \=\~ ^\[Yy\]</span> ]]; then
                    main_installation_process
                else
                    info_msg "重新安装已取消。"
                fi
            else
                info_msg "已选择不进入管理菜单或重新安装。"
                exit 0
            fi
        fi
    else
        # DDNS-Go 未安装，执行主安装流程
        main_installation_process
    fi
fi

exit 0
