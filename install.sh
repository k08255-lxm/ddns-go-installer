#!/bin/bash
# Script Version: 1.2.1
# Purpose: Installer and manager for ddns-go
# Author: k08255-lxm (Original), Refactored by AI
# Ensure this script is saved with Unix line endings (LF) and UTF-8 encoding without BOM.

# --- Strict Mode ---
# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
# set -u # Can be too strict for some optional inputs, use with caution
# Pipestatus: rightmost command with a non-zero status in a pipeline determines exit status.
set -o pipefail

# --- Environment ---
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Script Metadata & Configuration ---
SCRIPT_VERSION="1.2.1"
readonly SCRIPT_FILENAME=$(basename "$0")
readonly DDNS_GO_GH_REPO="jeessy2/ddns-go"
readonly INSTALLER_GH_REPO="k08255-lxm/ddns-go-installer" # For self-update

readonly DDNS_GO_API_URL="https://api.github.com/repos/${DDNS_GO_GH_REPO}/releases"
readonly INSTALLER_API_URL="https://api.github.com/repos/${INSTALLER_GH_REPO}/releases/latest"
readonly INSTALLER_RAW_URL="https://raw.githubusercontent.com/${INSTALLER_GH_REPO}/main/install.sh" # Assuming 'main' branch

# --- Paths & Default values ---
DDNS_GO_INSTALL_DIR_DEFAULT="/usr/local/bin" # Directory to install ddns-go binary
DDNS_GO_BIN_NAME="ddns-go"
BIN_PATH_DEFAULT="${DDNS_GO_INSTALL_DIR_DEFAULT}/${DDNS_GO_BIN_NAME}"

# Attempt to find existing ddns-go or use default
BIN_PATH=$(which "${DDNS_GO_BIN_NAME}" 2>/dev/null || echo "${BIN_PATH_DEFAULT}")

CONFIG_DIR_DEFAULT="/etc/ddns-go" # Changed to a subdirectory for clarity
CONFIG_FILE_DEFAULT="${CONFIG_DIR_DEFAULT}/ddns-go.conf"
SERVICE_FILE="/etc/systemd/system/ddns-go.service"
MANAGER_INSTALL_PATH="/usr/local/bin/ddnsmgr" # Management script symlink/copy
DDNS_GO_USER="ddns-go" # Dedicated user for running ddns-go service

# Global state variables (will be populated by functions)
declare DDNS_GO_CONFIG_FILE="${CONFIG_FILE_DEFAULT}" # Actual config file path used
declare DDNS_GO_BIN_PATH="${BIN_PATH}"             # Actual binary path used
declare PORT="9876"
declare INTERVAL="300"
declare NOWEB="false" # 'true' or 'false'

# --- Utility Functions ---
_log() {
    local type="$1"
    local msg="$2"
    local color="${NC}"
    local timestamp
    timestamp=$(date +'%Y-%m-%d %H:%M:%S')

    case "$type" in
        INFO) color="${BLUE}" ;;
        SUCCESS) color="${GREEN}" ;;
        WARN) color="${YELLOW}" ;;
        ERROR) color="${RED}" ;;
        DEBUG) color="${NC}" ;; # Simple output for debug
        *) msg="LOG_TYPE_ERROR: $type $msg" ;;
    esac
    echo -e "${color}[${timestamp}] [${type}] ${msg}${NC}" >&2
}

info() { _log "INFO" "$1"; }
success() { _log "SUCCESS" "$1"; }
warn() { _log "WARN" "$1"; }
error() { _log "ERROR" "$1"; }
debug() { if [[ "${DEBUG_MODE:-0}" -eq 1 ]]; then _log "DEBUG" "$1"; fi }
error_exit() { _log "ERROR" "$1"; exit 1; }

# Check if running as root
check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        error_exit "此脚本需要 root 或 sudo 权限才能运行。"
    fi
    debug "Root check passed."
}

# Check for essential command existence
check_command() {
    local cmd_name="$1"
    if ! command -v "$cmd_name" &>/dev/null; then
        error_exit "必需命令 '$cmd_name' 未找到。请先安装它。"
    fi
    debug "Command '$cmd_name' found."
}

# Install dependencies if missing
install_dependencies() {
    info "正在检查并安装必要的依赖 (curl, tar, jq, bc)..."
    local missing_pkgs=()
    local pkgs_to_check=("curl" "tar" "jq" "bc") # bc for floating point in speed calc

    for pkg in "${pkgs_to_check[@]}"; do
        command -v "$pkg" &>/dev/null || missing_pkgs+=("$pkg")
    done

    if [[ ${#missing_pkgs[@]} -eq 0 ]]; then
        success "所有必要依赖已安装。"
        return
    fi

    warn "需要安装的依赖: ${missing_pkgs[*]}"
    local package_manager=""
    if command -v apt-get &>/dev/null; then package_manager="apt-get";
    elif command -v yum &>/dev/null; then package_manager="yum";
    elif command -v dnf &>/dev/null; then package_manager="dnf";
    elif command -v pacman &>/dev/null; then package_manager="pacman";
    elif command -v zypper &>/dev/null; then package_manager="zypper";
    else error_exit "未检测到支持的包管理器 (apt, yum, dnf, pacman, zypper)。请手动安装: ${missing_pkgs[*]}"; fi

    debug "Using package manager: $package_manager"
    case "$package_manager" in
        apt-get) sudo apt-get update -y && sudo apt-get install -y "${missing_pkgs[@]}" ;;
        yum) sudo yum install -y "${missing_pkgs[@]}" ;;
        dnf) sudo dnf install -y "${missing_pkgs[@]}" ;;
        pacman) sudo pacman -Sy --noconfirm "${missing_pkgs[@]}" ;;
        zypper) sudo zypper install -y "${missing_pkgs[@]}" ;;
    esac

    for pkg in "${missing_pkgs[@]}"; do
        check_command "$pkg" # Verify installation
    done
    success "依赖安装完成。"
}

# Determine actual ddns-go binary path and config file path
determine_paths_and_load_config() {
    debug "Determining paths and loading config..."
    DDNS_GO_BIN_PATH=$(which "${DDNS_GO_BIN_NAME}" 2>/dev/null || echo "${BIN_PATH_DEFAULT}")

    # If config file exists, try to load settings from it
    # Prefer config file in /etc/ddns-go/ddns-go.conf, then /etc/ddns-go.conf
    if [[ -f "${CONFIG_DIR_DEFAULT}/${DDNS_GO_BIN_NAME}.conf" ]]; then
        DDNS_GO_CONFIG_FILE="${CONFIG_DIR_DEFAULT}/${DDNS_GO_BIN_NAME}.conf"
    elif [[ -f "/etc/${DDNS_GO_BIN_NAME}.conf" ]]; then # Legacy config path
        DDNS_GO_CONFIG_FILE="/etc/${DDNS_GO_BIN_NAME}.conf"
    else
        DDNS_GO_CONFIG_FILE="${CONFIG_FILE_DEFAULT}" # Default if nothing else found
    fi
    debug "Using config file: ${DDNS_GO_CONFIG_FILE}"

    if [[ -f "${DDNS_GO_CONFIG_FILE}" ]]; then
        info "从 ${DDNS_GO_CONFIG_FILE} 加载配置..."
        # Source config file in a subshell to avoid polluting global scope too much
        # and to control which variables are actually read.
        local cfg_bin_path cfg_port cfg_interval cfg_noweb
        cfg_bin_path=$(grep -E '^BIN_PATH=' "${DDNS_GO_CONFIG_FILE}" | cut -d'=' -f2-)
        cfg_port=$(grep -E '^PORT=' "${DDNS_GO_CONFIG_FILE}" | cut -d'=' -f2-)
        cfg_interval=$(grep -E '^INTERVAL=' "${DDNS_GO_CONFIG_FILE}" | cut -d'=' -f2-)
        cfg_noweb=$(grep -E '^NOWEB=' "${DDNS_GO_CONFIG_FILE}" | cut -d'=' -f2-)

        [[ -n "$cfg_bin_path" && -x "$cfg_bin_path" ]] && DDNS_GO_BIN_PATH="$cfg_bin_path"
        [[ -n "$cfg_port" ]] && PORT="$cfg_port"
        [[ -n "$cfg_interval" ]] && INTERVAL="$cfg_interval"
        [[ "$cfg_noweb" == "true" ]] && NOWEB="true" || NOWEB="false" # Normalize
        debug "Loaded from config: BIN_PATH=${DDNS_GO_BIN_PATH}, PORT=${PORT}, INTERVAL=${INTERVAL}, NOWEB=${NOWEB}"
    else
        debug "配置文件 ${DDNS_GO_CONFIG_FILE} 未找到，将使用默认值或提示输入。"
    fi
    # Ensure BIN_PATH is updated globally
    BIN_PATH="${DDNS_GO_BIN_PATH}"
}


# Check ddns-go installation status
# Returns 0 if installed (and updates DDNS_GO_BIN_PATH), 1 otherwise.
check_ddns_go_installed() {
    debug "Checking ddns-go installation status..."
    determine_paths_and_load_config # Ensure paths are fresh

    if [[ -x "${DDNS_GO_BIN_PATH}" ]]; then
        debug "Found ddns-go executable at ${DDNS_GO_BIN_PATH}"
        return 0
    fi

    # Check common system paths if default wasn't found by 'which'
    local common_paths=("${BIN_PATH_DEFAULT}" "/usr/bin/${DDNS_GO_BIN_NAME}" "/opt/${DDNS_GO_BIN_NAME}/${DDNS_GO_BIN_NAME}")
    for path_to_check in "${common_paths[@]}"; do
        if [[ -x "$path_to_check" ]]; then
            DDNS_GO_BIN_PATH="$path_to_check"
            BIN_PATH="$path_to_check" # Update global
            debug "Found ddns-go executable at ${DDNS_GO_BIN_PATH} (common path search)"
            return 0
        fi
    done

    # Check if service is running (might indicate an install not in PATH)
    if systemctl is-active --quiet "${DDNS_GO_BIN_NAME}.service"; then
        local service_exec_path
        service_exec_path=$(systemctl show "${DDNS_GO_BIN_NAME}.service" --property=ExecStart --value | awk '{print $1}')
        if [[ -n "$service_exec_path" && -x "$service_exec_path" ]]; then
            DDNS_GO_BIN_PATH="$service_exec_path"
            BIN_PATH="$service_exec_path" # Update global
            debug "Found ddns-go via active systemd service: ${DDNS_GO_BIN_PATH}"
            return 0
        fi
        warn "ddns-go service is active, but binary path could not be determined from service file."
        # Still, consider it "installed" in a broad sense if service is running
        return 0
    fi
    debug "ddns-go not found at expected locations or as an active service."
    return 1
}

# Get installed ddns-go version
get_local_ddns_go_version() {
    if ! check_ddns_go_installed; then echo "未安装"; return; fi
    if [[ ! -x "${DDNS_GO_BIN_PATH}" ]]; then echo "路径无效"; return; fi

    local version_output
    version_output=$("${DDNS_GO_BIN_PATH}" -version 2>&1) || { warn "执行 '${DDNS_GO_BIN_PATH} -version' 失败"; echo "获取失败"; return; }
    
    # Regex to capture vX.Y.Z or X.Y.Z (and add 'v' if missing)
    local version
    version=$(echo "$version_output" | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    if [[ -n "$version" ]]; then
        [[ "$version" != v* ]] && version="v$version" # Prepend 'v' if not present
        echo "$version"
    else
        echo "版本未知"
    fi
}

# Fetch available ddns-go versions from GitHub API
fetch_available_versions() {
    info "正在从 GitHub 获取可用的 ddns-go 版本列表..."
    local versions_json versions_list retry_count=0 max_retries=2
    while [[ $retry_count -le $max_retries ]]; do
        versions_json=$(curl -sfL --connect-timeout 10 "${DDNS_GO_API_URL}")
        if [[ -n "$versions_json" ]]; then
            versions_list=$(echo "$versions_json" | jq -r '.[].tag_name | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))') # Filter for vX.Y.Z format
            if [[ -n "$versions_list" ]]; then
                echo "$versions_list"
                return 0
            fi
            warn "无法从API响应中用jq解析版本列表 (尝试 $((retry_count + 1))/${max_retries}). JSON: ${versions_json:0:100}..."
        else
            warn "获取版本信息 API 请求失败 (尝试 $((retry_count + 1))/${max_retries})."
        fi
        retry_count=$((retry_count + 1))
        [[ $retry_count -le $max_retries ]] && sleep $((retry_count * 2))
    done
    error "多次尝试后仍无法获取 DDNS-Go 版本列表。"
    return 1
}

# Validate a given version string against available versions
validate_version_exists() {
    local version_to_validate="$1"
    local available_versions
    info "正在验证版本号 ${version_to_validate}..."
    available_versions=$(fetch_available_versions) || return 1 # Exit if fetch fails

    if echo "$available_versions" | grep -Fxq "$version_to_validate"; then
        success "版本号 ${version_to_validate} 有效。"
        return 0
    else
        warn "版本号 ${version_to_validate} 无效或不存在于可用版本列表。"
        echo -e "${YELLOW}可用版本 (部分列表):${NC}" >&2
        echo "$available_versions" | head -n 10 >&2
        return 1
    fi
}

# Install or update ddns-go core binary
install_ddns_go_core() {
    local version_to_install="$1"
    info "准备安装/更新 ddns-go 至版本 ${version_to_install}"

    local arch os_type temp_dir download_url filename_version
    local cpu_arch=$(uname -m)
    os_type=$(uname -s | tr '[:upper:]' '[:lower:]')

    case "$cpu_arch" in
        x86_64|amd64) arch="x86_64" ;;
        i386|i686) arch="i386" ;; # Note: 32-bit might be deprecated by ddns-go
        armv6l) arch="armv6" ;;
        armv7l) arch="armv7" ;;
        aarch64|arm64) arch="arm64" ;;
        *) error_exit "不支持的CPU架构：$cpu_arch" ;;
    esac

    case "$os_type" in
        linux*) os_type="linux" ;;
        freebsd*) os_type="freebsd" ;;
        darwin*) os_type="darwin" ;; # macOS
        *) error_exit "不支持的操作系统：$os_type" ;;
    esac

    # Ensure version_to_install has 'v' prefix
    [[ "$version_to_install" != v* ]] && version_to_install="v$version_to_install"
    filename_version="${version_to_install#v}" # Remove 'v' for filename construction
    download_url="https://github.com/${DDNS_GO_GH_REPO}/releases/download/${version_to_install}/ddns-go_${filename_version}_${os_type}_${arch}.tar.gz"

    temp_dir=$(mktemp -d) || error_exit "无法创建临时目录。"
    debug "临时目录创建于: ${temp_dir}"
    # Setup trap to clean up temp_dir on exit, error, or interrupt
    trap 'debug "捕获到退出信号，正在清理临时目录 ${temp_dir}..."; rm -rf "${temp_dir}"; trap - EXIT HUP INT QUIT TERM PIPE; exit' EXIT HUP INT QUIT TERM PIPE

    info "正在从 ${download_url} 下载..."
    local tarball_path="${temp_dir}/${DDNS_GO_BIN_NAME}.tar.gz"
    local start_time end_time time_cost file_size_human file_bytes avg_speed speed_unit

    start_time=$(date +%s)
    if ! curl --progress-bar -fL --connect-timeout 30 "$download_url" -o "$tarball_path"; then
        error_exit "下载失败！请检查网络或确认版本 ${version_to_install} 是否支持您的系统 (${os_type}/${arch})。"
    fi
    end_time=$(date +%s)

    time_cost=$((end_time - start_time))
    ((time_cost == 0)) && time_cost=1 # Avoid division by zero

    file_size_human=$(du -sh "$tarball_path" | cut -f1)
    file_bytes=$(stat -c %s "$tarball_path" 2>/dev/null || stat -f %z "$tarball_path" 2>/dev/null || echo 0)

    if (( file_bytes > 0 && time_cost > 0 )); then
        avg_speed_bps=$((file_bytes / time_cost)) # Bytes per second
        if (( avg_speed_bps > 1024*1024 )); then # MB/s
            avg_speed=$(bc <<< "scale=2; ${avg_speed_bps} / (1024*1024)")
            speed_unit="MB/s"
        elif (( avg_speed_bps > 1024 )); then # KB/s
            avg_speed=$(bc <<< "scale=2; ${avg_speed_bps} / 1024")
            speed_unit="KB/s"
        else # B/s
            avg_speed="$avg_speed_bps"
            speed_unit="B/s"
        fi
        info "文件大小: ${file_size_human}, 下载耗时: ${time_cost}s, 平均速度: ${avg_speed} ${speed_unit}"
    else
        info "文件大小: ${file_size_human}, 下载耗时: ${time_cost}s (速度计算跳过)"
    fi
    success "下载完成。"

    info "正在解压到 ${temp_dir}..."
    if ! tar xzf "$tarball_path" -C "$temp_dir"; then
        error_exit "解压 ${tarball_path} 失败。"
    fi

    local new_binary_path_temp="${temp_dir}/${DDNS_GO_BIN_NAME}"
    if [[ ! -f "$new_binary_path_temp" ]]; then
        error_exit "解压后未找到 ${DDNS_GO_BIN_NAME} 执行文件于 ${temp_dir}。"
    fi

    # Ensure installation directory exists
    local install_dir
    install_dir=$(dirname "${DDNS_GO_BIN_PATH}")
    info "确保安装目录 ${install_dir} 存在..."
    sudo mkdir -p "$install_dir" || error_exit "创建安装目录 ${install_dir} 失败。"

    # Stop service if running, before replacing binary
    if systemctl is-active --quiet "${DDNS_GO_BIN_NAME}.service"; then
        info "正在停止现有的 ddns-go 服务..."
        sudo systemctl stop "${DDNS_GO_BIN_NAME}.service" || warn "停止服务失败，可能影响更新。"
        sleep 1 # Give service time to stop
    fi

    info "正在将 ${new_binary_path_temp} 安装到 ${DDNS_GO_BIN_PATH}..."
    if ! sudo mv "$new_binary_path_temp" "${DDNS_GO_BIN_PATH}"; then
        error_exit "移动 ${DDNS_GO_BIN_NAME} 到 ${DDNS_GO_BIN_PATH} 失败。请检查权限或是否有同名目录。"
    fi
    sudo chmod +x "${DDNS_GO_BIN_PATH}" || error_exit "设置 ${DDNS_GO_BIN_PATH} 执行权限失败。"

    success "ddns-go 已成功安装/更新到版本 ${version_to_install} (${DDNS_GO_BIN_PATH})。"
    # Cleanup is handled by trap
    rm -rf "${temp_dir}" # Explicitly remove temp_dir
    trap - EXIT HUP INT QUIT TERM PIPE # Clear trap on successful completion
}

# Configure and save ddns-go.conf
save_ddns_go_config() {
    info "正在保存配置到 ${DDNS_GO_CONFIG_FILE}..."
    # Ensure config directory exists
    sudo mkdir -p "$(dirname "${DDNS_GO_CONFIG_FILE}")" || error_exit "创建配置目录 $(dirname "${DDNS_GO_CONFIG_FILE}") 失败。"

    # Create a temporary config file, then sudo mv to prevent permission issues with echo redirect
    local temp_conf_file
    temp_conf_file=$(mktemp) || error_exit "无法创建临时配置文件。"

    # Write base config
    {
        echo "# DDNS-Go Configuration File managed by installer script v${SCRIPT_VERSION}"
        echo "PORT=${PORT}"
        echo "INTERVAL=${INTERVAL}"
        echo "NOWEB=${NOWEB}" # 'true' or 'false'
        echo "BIN_PATH=${DDNS_GO_BIN_PATH}" # Save the binary path used
    } > "$temp_conf_file"

    # Change ownership and permissions before moving
    if id -u "${DDNS_GO_USER}" &>/dev/null; then
      sudo chown "${DDNS_GO_USER}:${DDNS_GO_USER}" "$temp_conf_file" || warn "设置临时配置文件所有权失败。"
    fi
    sudo chmod 600 "$temp_conf_file" || warn "设置临时配置文件权限失败。" # Restrictive permissions

    if sudo mv "$temp_conf_file" "${DDNS_GO_CONFIG_FILE}"; then
        success "配置已保存到 ${DDNS_GO_CONFIG_FILE}。"
    else
        rm -f "$temp_conf_file" # Clean up if mv failed
        error_exit "保存配置文件 ${DDNS_GO_CONFIG_FILE} 失败。"
    fi
}


# Create or update systemd service file
configure_systemd_service() {
    info "正在配置 systemd 服务 (${DDNS_GO_BIN_NAME}.service)..."

    # Create ddns-go system user if it doesn't exist
    if ! id -u "${DDNS_GO_USER}" &>/dev/null; then
        info "正在创建系统用户 ${DDNS_GO_USER}..."
        # Create a system user without a home dir by default, or a minimal one if needed by ddns-go
        sudo useradd -r -s /bin/false -M "${DDNS_GO_USER}" || {
            warn "创建用户 ${DDNS_GO_USER} 失败。将尝试以 root 运行服务 (不推荐)。"
            DDNS_GO_USER="root" # Fallback to root if user creation fails
        }
    else
        info "系统用户 ${DDNS_GO_USER} 已存在。"
    fi
    
    # Ensure config directory and file ownership is correct for the DDNS_GO_USER
    if [[ "${DDNS_GO_USER}" != "root" ]]; then
        sudo mkdir -p "$(dirname "${DDNS_GO_CONFIG_FILE}")" # Ensure directory exists
        sudo chown -R "${DDNS_GO_USER}:${DDNS_GO_USER}" "$(dirname "${DDNS_GO_CONFIG_FILE}")" || warn "设置配置目录所有权失败。"
        # If config file exists, set its ownership too
        if [[ -f "${DDNS_GO_CONFIG_FILE}" ]]; then
             sudo chown "${DDNS_GO_USER}:${DDNS_GO_USER}" "${DDNS_GO_CONFIG_FILE}" || warn "设置配置文件所有权失败。"
        fi
    fi

    local noweb_param=""
    [[ "${NOWEB}" == "true" ]] && noweb_param="-noweb"

    # Using DDNS_GO_CONFIG_FILE for -c parameter
    local exec_start_cmd="${DDNS_GO_BIN_PATH} ${noweb_param} -l :${PORT} -f ${INTERVAL} -c ${DDNS_GO_CONFIG_FILE}"
    debug "Service ExecStart command: ${exec_start_cmd}"

    # Create service file content
    # Use a temporary file for cat > HEREDOC then sudo mv
    local temp_service_file
    temp_service_file=$(mktemp) || error_exit "无法创建临时服务文件。"

    cat > "$temp_service_file" <<EOF
[Unit]
Description=DDNS-Go Dynamic DNS Client Service
Documentation=https://github.com/${DDNS_GO_GH_REPO}
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${DDNS_GO_USER}
Group=${DDNS_GO_USER} # Or primary group of DDNS_GO_USER
ExecStart=${exec_start_cmd}
Restart=on-failure
RestartSec=30s
TimeoutStopSec=60s
StandardOutput=journal # Log to systemd journal
StandardError=journal  # Log to systemd journal
# Consider a WorkingDirectory if ddns-go needs one, e.g., for relative paths in its own config
# WorkingDirectory=/var/lib/ddns-go # Example, ensure this dir exists and user has access
# AmbientCapabilities=CAP_NET_BIND_SERVICE # If non-root user needs to bind to privileged ports (<1024) - not typical for ddns-go default port

[Install]
WantedBy=multi-user.target
EOF

    if ! sudo mv "$temp_service_file" "${SERVICE_FILE}"; then
        rm -f "$temp_service_file"
        error_exit "写入服务文件 ${SERVICE_FILE} 失败。"
    fi
    sudo chmod 644 "${SERVICE_FILE}" # Standard permission for service files

    info "正在重载 systemd 配置并启用/重启服务..."
    sudo systemctl daemon-reload || error_exit "systemctl daemon-reload 失败。"
    sudo systemctl enable "${DDNS_GO_BIN_NAME}.service" || error_exit "启用服务 ${DDNS_GO_BIN_NAME}.service 失败。"
    
    if sudo systemctl restart "${DDNS_GO_BIN_NAME}.service"; then
        success "ddns-go 服务已成功配置并启动/重启。"
    else
        warn "ddns-go 服务启动/重启失败。请检查日志: sudo journalctl -u ${DDNS_GO_BIN_NAME}.service -xe"
    fi
}

# --- Main Installation Workflow ---
prompt_for_install_settings() {
    info "开始配置 DDNS-Go 安装参数..."
    local input_port input_interval input_noweb_choice
    
    # Port
    while true; do
        read -r -p "请输入 DDNS-Go Web 界面监听端口 [默认 ${PORT}]: " input_port
        input_port=${input_port:-$PORT}
        if [[ "$input_port" =~ ^[0-9]+$ && "$input_port" -ge 1 && "$input_port" -le 65535 ]]; then
            if ss -tuln | grep -q ":${input_port}\s" && [[ "$(uname -s)" == "Linux" ]]; then
                 warn "端口 ${input_port} 当前似乎已被占用。确定要继续使用吗？(y/N)"
                 read -r -n 1 -t 10 reply_port_confirm || reply_port_confirm="n" # Timeout to 'n'
                 echo
                 [[ "$reply_port_confirm" =~ ^[Yy]$ ]] && PORT="$input_port" && break
                 continue # Ask again
            fi
            PORT="$input_port"
            break
        else
            warn "端口必须为 1-65535 之间的数字！"
        fi
    done
    debug "监听端口设置为: ${PORT}"

    # Interval
    while true; do
        read -r -p "请输入 DNS 同步间隔（秒）[默认 ${INTERVAL}, 最小 60]: " input_interval
        input_interval=${input_interval:-$INTERVAL}
        if [[ "$input_interval" =~ ^[0-9]+$ && "$input_interval" -ge 60 ]]; then
            INTERVAL="$input_interval"
            break
        else
            warn "间隔时间必须为数字且不能小于 60 秒！"
        fi
    done
    debug "同步间隔设置为: ${INTERVAL}s"

    # NoWeb
    read -r -p "是否在启动时禁用 Web 管理界面 (更安全)? [y/N, 默认 N (启用Web)]: " -n 1 input_noweb_choice
    echo
    if [[ "$input_noweb_choice" =~ ^[Yy]$ ]]; then
        NOWEB="true"
        info "Web 界面将在启动时被禁用。"
    else
        NOWEB="false"
        info "Web 界面将在启动时启用 (端口: ${PORT})。"
    fi
    debug "NOWEB 设置为: ${NOWEB}"
}

select_ddns_go_version() {
    local available_versions selected_version latest_version
    available_versions=$(fetch_available_versions) || return 1
    latest_version=$(echo "$available_versions" | head -n 1)

    info "最新可用 DDNS-Go 版本: ${latest_version}"
    echo -e "${YELLOW}其他可用版本 (部分列表):${NC}" >&2
    echo "$available_versions" | head -n 5 >&2
    
    while true; do
        read -r -p "请输入要安装的 DDNS-Go 版本号 (例如 ${latest_version}，留空则安装最新版): " selected_version
        if [[ -z "$selected_version" ]]; then
            selected_version="$latest_version"
            info "将安装最新版本: ${selected_version}"
            break
        fi
        # Ensure 'v' prefix if user omits it but it's in the list like that
        if [[ "$selected_version" != v* ]] && echo "$available_versions" | grep -q "v${selected_version}"; then
            selected_version="v$selected_version"
        fi

        if validate_version_exists "$selected_version"; then
            break
        fi
        # validate_version_exists already prints error, no need to repeat
    done
    echo "$selected_version" # Return selected version
}

main_install_sequence() {
    info "开始 DDNS-Go 安装流程..."
    check_root
    install_dependencies # curl, tar, jq, bc

    prompt_for_install_settings

    local version_to_install
    version_to_install=$(select_ddns_go_version) || error_exit "未能选择有效的 DDNS-Go 版本。"
    
    # Set global BIN_PATH to the default before core installation, if user wants custom, they can edit config later
    DDNS_GO_BIN_PATH="${BIN_PATH_DEFAULT}" 
    BIN_PATH="${BIN_PATH_DEFAULT}" # Update global
    info "DDNS-Go 将被安装到: ${DDNS_GO_BIN_PATH}"

    install_ddns_go_core "$version_to_install" # Installs binary
    save_ddns_go_config # Saves config based on globals (PORT, INTERVAL, NOWEB, BIN_PATH)
    configure_systemd_service # Configures and starts service based on globals and config file

    success "DDNS-Go 安装流程完成！"
    info "访问Web界面 (如果启用): http://<你的服务器IP>:${PORT}"
    info "管理脚本 (如果由此脚本安装): sudo ${MANAGER_INSTALL_PATH}"

    # Create/Update manager symlink/copy
    if [[ "${SCRIPT_FILENAME}" != "$(basename "${MANAGER_INSTALL_PATH}")" ]]; then # Avoid self-copy if already named ddnsmgr
        info "正在创建/更新管理命令 ${MANAGER_INSTALL_PATH}..."
        if sudo cp "$0" "${MANAGER_INSTALL_PATH}" && sudo chmod +x "${MANAGER_INSTALL_PATH}"; then
            success "管理命令已链接到 ${MANAGER_INSTALL_PATH}"
        else
            warn "创建管理命令 ${MANAGER_INSTALL_PATH} 失败。"
        fi
    fi
}

# --- Management Menu Functions ---
show_ddns_go_status() {
    clear
    info "DDNS-Go 服务状态信息"
    determine_paths_and_load_config # Load current config

    local local_version="未知"
    if [[ -x "${DDNS_GO_BIN_PATH}" ]]; then
        local_version=$(get_local_ddns_go_version)
        echo -e "  程序版本: ${GREEN}${local_version}${NC}"
        echo -e "  安装路径: ${YELLOW}${DDNS_GO_BIN_PATH}${NC}"
    else
        echo -e "  程序版本: ${RED}未找到或路径无效 (${DDNS_GO_BIN_PATH})${NC}"
    fi
    echo -e "  配置文件: ${YELLOW}${DDNS_GO_CONFIG_FILE}${NC}"
    echo -e "  监听端口: ${GREEN}${PORT}${NC}"
    echo -e "  同步间隔: ${GREEN}${INTERVAL}s${NC}"
    echo -e "  Web界面 : ${GREEN}$( [[ "$NOWEB" == "true" ]] && echo "禁用" || echo "启用" )${NC}"

    if systemctl is-active --quiet "${DDNS_GO_BIN_NAME}.service"; then
        echo -e "  运行状态: ${GREEN}服务正在运行 (systemd)${NC}"
        local start_time
        start_time=$(systemctl show "${DDNS_GO_BIN_NAME}.service" --property=ActiveEnterTimestamp --value 2>/dev/null)
        [[ -n "$start_time" && "$start_time" != "n/a" ]] && echo -e "  启动时间: ${start_time}"
    elif pgrep -x "${DDNS_GO_BIN_NAME}" >/dev/null; then
        echo -e "  运行状态: ${YELLOW}进程正在运行 (但可能不由 systemd 管理)${NC}"
    else
        echo -e "  运行状态: ${RED}服务未运行${NC}"
    fi

    info "\n  最近的5条服务日志 (来自 journalctl):"
    if command -v journalctl &>/dev/null; then
        sudo journalctl -u "${DDNS_GO_BIN_NAME}.service" -n 5 --no-pager --quiet || echo "  无法获取 systemd 日志，或服务未通过 systemd 运行。"
    else
        echo "  journalctl 命令未找到。"
    fi
    read -r -n 1 -s -p $'\n  按任意键返回菜单...'
    echo
}

update_ddns_go_program() {
    info "开始更新 DDNS-Go 程序..."
    check_root
    determine_paths_and_load_config # Ensure paths and current config are loaded

    local current_version="未安装"
    if [[ -x "${DDNS_GO_BIN_PATH}" ]]; then current_version=$(get_local_ddns_go_version); fi
    info "当前 DDNS-Go 版本: ${current_version}"

    local latest_version
    latest_version=$(fetch_available_versions | head -n 1) || { error "无法获取最新版本信息，更新中止。"; return 1; }
    info "最新可用 DDNS-Go 版本: ${latest_version}"

    if [[ "$current_version" == "$latest_version" ]] && [[ "$current_version" != "未安装" ]] && [[ "$current_version" != "版本未知" ]]; then
        success "DDNS-Go 已是最新版本 (${current_version})。"
        return
    fi
    
    local prompt_msg="发现新版本 ${latest_version} (当前: ${current_version}). 是否更新? [Y/n]: "
    if [[ "$current_version" != "未安装" ]] && [[ "$current_version" != "版本未知" ]]; then
      # Basic version comparison (does not handle complex pre-releases well)
      # If latest_version is numerically greater than current_version
      if [[ "$(printf '%s\n' "$latest_version" "$current_version" | sed 's/v//g' | sort -V | head -n 1)" == "$(echo "$current_version" | sed 's/v//g')" && "$latest_version" != "$current_version" ]]; then
        # Latest version is greater
        : # Standard update prompt
      else 
        # Current version is greater or equal (or non-standard format)
        prompt_msg="最新版本 ${latest_version} 不高于当前版本 ${current_version}。确定要 '更新' (可能降级或重装)? [y/N]: "
      fi
    fi
    
    read -r -p "$(echo -e "${YELLOW}${prompt_msg}${NC}")" -n 1 -r -t 15 reply_update || reply_update="n" # Default to No on timeout for downgrades
    echo
    if [[ ! "$reply_update" =~ ^[Yy]$ ]]; then
        info "取消 DDNS-Go 程序更新。"
        return
    fi

    # Global BIN_PATH might be changed by user, stick to the default install dir for updates unless advanced
    # For simplicity, this script updates to BIN_PATH_DEFAULT. Advanced users can manage custom paths.
    DDNS_GO_BIN_PATH="${BIN_PATH_DEFAULT}"
    BIN_PATH="${BIN_PATH_DEFAULT}" # Update global
    info "DDNS-Go 将被更新/安装到: ${DDNS_GO_BIN_PATH}"

    install_ddns_go_core "$latest_version" # Installs/updates binary
    # Config (PORT, INTERVAL, NOWEB) should persist from loaded values or defaults
    save_ddns_go_config # Re-save config to ensure BIN_PATH is correct if it changed
    configure_systemd_service # Re-configure and restart service with new binary

    success "DDNS-Go 程序已更新到 ${latest_version}。"
    read -r -n 1 -s -p "按任意键继续..."
    echo
}

toggle_webui() {
    info "切换 Web UI 状态..."
    check_root
    determine_paths_and_load_config # Load current config

    if [[ "$NOWEB" == "true" ]]; then
        NOWEB="false"
        success "Web UI 已设置为: 启用 (将在服务重启后生效)。"
    else
        NOWEB="true"
        success "Web UI 已设置为: 禁用 (将在服务重启后生效)。"
    fi
    save_ddns_go_config # Save new NOWEB state
    configure_systemd_service # Restart service to apply
    read -r -n 1 -s -p "操作完成。按任意键继续..."
    echo
}

uninstall_ddns_go() {
    info "开始卸载 DDNS-Go..."
    check_root
    read -r -p "$(echo -e "${RED}警告：此操作将停止并移除DDNS-Go服务、二进制文件、配置文件和管理脚本！\n确定要卸载吗？[y/N]${NC}")" -n 1 -r reply_uninstall
    echo
    if [[ ! "$reply_uninstall" =~ ^[Yy]$ ]]; then
        info "卸载操作已取消。"
        return 1 # Indicate cancellation
    fi

    info "正在停止并禁用 ddns-go 服务..."
    sudo systemctl stop "${DDNS_GO_BIN_NAME}.service" 2>/dev/null || warn "停止服务失败 (可能未运行)。"
    sudo systemctl disable "${DDNS_GO_BIN_NAME}.service" 2>/dev/null || warn "禁用服务失败 (可能未启用)。"
    
    if [[ -f "${SERVICE_FILE}" ]]; then
        info "正在删除 systemd 服务文件: ${SERVICE_FILE}"
        sudo rm -f "${SERVICE_FILE}" || warn "删除服务文件失败。"
    fi
    sudo systemctl daemon-reload
    sudo systemctl reset-failed # Clear failed state if any

    if [[ -x "${DDNS_GO_BIN_PATH}" ]]; then # Use the determined/configured path
        info "正在删除 ddns-go 二进制文件: ${DDNS_GO_BIN_PATH}"
        sudo rm -f "${DDNS_GO_BIN_PATH}" || warn "删除二进制文件失败。"
    else
        info "未找到 ddns-go 二进制文件于 ${DDNS_GO_BIN_PATH} (或路径未知)。"
    fi

    if [[ -f "${DDNS_GO_CONFIG_FILE}" ]]; then # Use the determined/configured path
        info "正在删除配置文件: ${DDNS_GO_CONFIG_FILE}"
        sudo rm -f "${DDNS_GO_CONFIG_FILE}" || warn "删除配置文件失败。"
        # Also remove the config directory if it's the default one and now empty
        if [[ "$(dirname "${DDNS_GO_CONFIG_FILE}")" == "${CONFIG_DIR_DEFAULT}" ]]; then
             # Check if directory is empty (ignoring . and ..)
            if [[ -z "$(ls -A "${CONFIG_DIR_DEFAULT}" 2>/dev/null)" ]]; then
                info "正在删除空的配置目录: ${CONFIG_DIR_DEFAULT}"
                sudo rmdir "${CONFIG_DIR_DEFAULT}" 2>/dev/null || warn "删除配置目录失败 (可能非空或无权限)。"
            else
                debug "配置目录 ${CONFIG_DIR_DEFAULT} 非空，未删除。"
            fi
        fi
    else
        info "未找到配置文件于 ${DDNS_GO_CONFIG_FILE}。"
    fi
    
    # Attempt to remove the ddns-go user if it exists and was created by this script logic
    if id -u "${DDNS_GO_USER}" &>/dev/null && [[ "${DDNS_GO_USER}" != "root" ]]; then
        info "正在尝试删除系统用户 ${DDNS_GO_USER}..."
        sudo userdel "${DDNS_GO_USER}" 2>/dev/null || warn "删除用户 ${DDNS_GO_USER} 失败 (可能仍有进程或文件归属该用户)。"
    fi

    if [[ -f "${MANAGER_INSTALL_PATH}" ]]; then
        info "正在删除管理脚本: ${MANAGER_INSTALL_PATH}"
        sudo rm -f "${MANAGER_INSTALL_PATH}" || warn "删除管理脚本失败。"
    fi

    success "DDNS-Go 卸载完成。"
    # No 'exit' here if called from menu, let menu loop
}

# Self-update installer script
self_update_script() {
    info "检查管理脚本更新 (当前版本 v${SCRIPT_VERSION})..."
    local api_response latest_tag_name latest_version current_version_no_v
    
    api_response=$(curl -sfL --connect-timeout 8 "${INSTALLER_API_URL}")
    if [[ -z "$api_response" ]]; then
        warn "检查脚本更新失败 (网络连接超时或API请求失败)。"
        return 1
    fi

    latest_tag_name=$(echo "$api_response" | jq -r '.tag_name' 2>/dev/null) # Expects format like vX.Y.Z
    if [[ -z "$latest_tag_name" || "$latest_tag_name" == "null" ]]; then
        warn "无法从API响应中解析最新版本标签。"
        return 1
    fi
    latest_version="${latest_tag_name#v}" # Remove 'v' prefix: X.Y.Z
    current_version_no_v="${SCRIPT_VERSION#v}"

    # Simple version comparison: assumes X.Y.Z format, compares lexicographically after splitting
    local IFS='.'
    local latest_parts=($latest_version) current_parts=($current_version_no_v)
    local is_newer=0

    for i in 0 1 2; do
        local lp=${latest_parts[i]:-0} cp=${current_parts[i]:-0} # Default to 0 if part missing
        if (( 10#$lp > 10#$cp )); then is_newer=1; break; fi # Base 10 comparison
        if (( 10#$lp < 10#$cp )); then is_newer=0; break; fi
    done
    
    if (( is_newer )); then
        info "发现新版管理脚本 (${latest_tag_name})，当前版本 (v${SCRIPT_VERSION})。"
        read -r -p "是否更新管理脚本？[Y/n] " -n 1 -r -t 15 reply_self_update || reply_self_update="n"
        echo
        if [[ ! "$reply_self_update" =~ ^[Yy]$ ]]; then
            info "取消脚本更新。"
            return
        fi

        info "正在更新管理脚本从 ${INSTALLER_RAW_URL}..."
        local temp_script_file
        temp_script_file=$(mktemp) || error_exit "无法创建临时脚本文件。"
        
        if curl -sfL --connect-timeout 15 "${INSTALLER_RAW_URL}" -o "$temp_script_file"; then
            # Basic validation: check if it's a bash script
            if head -n 1 "$temp_script_file" | grep -q -E "^#!/(usr/)?bin/(bash|sh)"; then
                # Get version from the downloaded script to confirm
                local new_script_ver_in_file
                new_script_ver_in_file=$(grep -m1 '^SCRIPT_VERSION=' "$temp_script_file" | cut -d'"' -f2)

                # Replace current script with the new one
                # This needs to be done carefully, often with exec or by a wrapper
                info "准备执行脚本更新..."
                # The script should replace itself and then exit.
                # For system-wide manager script, we need sudo.
                if sudo cp "$temp_script_file" "${MANAGER_INSTALL_PATH}" && sudo chmod +x "${MANAGER_INSTALL_PATH}"; then
                     rm -f "$temp_script_file"
                     success "管理脚本已更新到 ${new_script_ver_in_file:-$latest_tag_name}。"
                     info "请使用 'sudo ${MANAGER_INSTALL_PATH}' 重新运行。"
                     exit 0 # Exit after successful update.
                else
                     rm -f "$temp_script_file"
                     error_exit "更新管理脚本失败 (无法复制到 ${MANAGER_INSTALL_PATH})。"
                fi
            else
                warn "下载的文件似乎不是有效的shell脚本。"
                rm -f "$temp_script_file"
            fi
        else
            rm -f "$temp_script_file"
            error "下载新版脚本失败。"
        fi
    elif [[ "$latest_version" == "$current_version_no_v" ]]; then
        success "当前管理脚本已是最新版本 (v${SCRIPT_VERSION})。"
    else
        info "本地管理脚本版本 (v${SCRIPT_VERSION}) 高于或不同于 GitHub 最新发布 (${latest_tag_name})。可能是开发版或自定义版。"
    fi
}


# --- Main Menu Logic ---
main_menu() {
    check_root # Menu operations require root
    # Load config and determine paths every time menu is shown, in case they changed
    determine_paths_and_load_config

    # Optionally check for self-update at menu start
    # self_update_script # Uncomment if desired, can be noisy

    while true; do
        clear
        local local_ddns_version
        local_ddns_version=$(get_local_ddns_go_version) # Get current installed version for display

        echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║           DDNS-Go 管理菜单 (脚本 v${SCRIPT_VERSION})             ║${NC}"
        echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${BLUE}║ DDNS-Go 版本: ${GREEN}${local_ddns_version}${NC}                                      ║" # Adjust spacing
        echo -e "${BLUE}╠──────────────────────────────────────────────────────────────╣${NC}"
        echo -e "${BLUE}║ 1. 启动服务                      6. 更新 DDNS-Go 程序        ║${NC}"
        echo -e "${BLUE}║ 2. 停止服务                      7. 卸载 DDNS-Go             ║${NC}"
        echo -e "${BLUE}║ 3. 重启服务                      8. 检查脚本更新             ║${NC}"
        echo -e "${BLUE}║ 4. 切换 Web UI (现在: ${GREEN}$( [[ "$NOWEB" == "true" ]] && echo "禁用" || echo "启用" )${NC})   9. 退出菜单                 ║${NC}" # Adjust spacing
        echo -e "${BLUE}║ 5. 查看状态/日志                                             ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
        
        local choice
        read -r -p "请输入选项 [1-9]: " choice
        case "$choice" in
            1) info "正在启动服务..."; sudo systemctl start "${DDNS_GO_BIN_NAME}.service" && success "服务已启动" || error "启动服务失败"; sleep 1 ;;
            2) info "正在停止服务..."; sudo systemctl stop "${DDNS_GO_BIN_NAME}.service" && success "服务已停止" || error "停止服务失败"; sleep 1 ;;
            3) info "正在重启服务..."; sudo systemctl restart "${DDNS_GO_BIN_NAME}.service" && success "服务已重启" || error "重启服务失败"; sleep 1 ;;
            4) toggle_webui ;;
            5) show_ddns_go_status ;;
            6) update_ddns_go_program ;;
            7) uninstall_ddns_go && info "卸载完成, 请手动退出或重新安装。" ;; # After uninstall, menu might not be fully functional
            8) self_update_script; read -r -n 1 -s -p "按任意键继续..."; echo ;;
            9) success "退出管理菜单。"; exit 0 ;;
            *) warn "无效输入 '$choice'，请输入1-9之间的数字。"; sleep 1 ;;
        esac
    done
}


# --- Script Execution Entry Point ---
main() {
    # Ensure essential commands for the script itself are present at the very start
    check_command "curl"
    check_command "tar"
    check_command "jq"
    check_command "basename"
    check_command "dirname"
    check_command "mktemp"
    check_command "date"
    check_command "grep"
    check_command "awk"
    check_command "sed"
    check_command "bc" # For speed calculation
    check_command "systemctl" # If systemd is expected

    # DEBUG_MODE=1 # Uncomment for verbose debug logging

    # Determine if script is run as installer or manager
    if [[ "${SCRIPT_FILENAME}" == "$(basename "${MANAGER_INSTALL_PATH}")" ]]; then
        debug "以管理模式 (${MANAGER_INSTALL_PATH}) 运行。"
        main_menu
    else # Run as installer (e.g. install.sh)
        debug "以安装模式 (${SCRIPT_FILENAME}) 运行。"
        if check_ddns_go_installed; then
            warn "检测到已安装的 DDNS-Go (版本: $(get_local_ddns_go_version))."
            echo -e "  路径: ${YELLOW}${DDNS_GO_BIN_PATH}${NC}"
            echo -e "  配置: ${YELLOW}${DDNS_GO_CONFIG_FILE}${NC}"
            read -r -p "是否重新安装 (会覆盖), 进入管理菜单, 或退出? [R(重装)/M(菜单)/Q(退出), 默认 Q]: " -n 1 action
            echo
            case "$action" in
                [Rr]) info "选择重新安装..."; main_install_sequence ;;
                [Mm]) 
                    info "尝试进入管理菜单..."
                    if [[ -x "${MANAGER_INSTALL_PATH}" ]]; then
                        sudo "${MANAGER_INSTALL_PATH}" # Execute the proper manager script
                    else
                        warn "管理脚本 ${MANAGER_INSTALL_PATH} 未找到或不可执行。尝试使用当前脚本作为管理器。"
                        # This implies current script should be copied to MANAGER_INSTALL_PATH first
                        # For simplicity, just run main_menu if user insists.
                        main_menu 
                    fi
                    ;;
                *) info "退出安装程序。"; exit 0 ;;
            esac
        else
            info "DDNS-Go 未检测到安装。开始全新安装..."
            main_install_sequence
        fi
    fi
    exit 0
}

# --- Call main function ---
main "$@"
