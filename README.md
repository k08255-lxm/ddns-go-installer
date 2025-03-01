# DDNS-Go 一键安装脚本

[![GitHub Release](https://img.shields.io/github/v/release/k08255-lxm/ddns-go-installer)](https://github.com/k08255-lxm/ddns-go-installer/releases)
[![Last Commit](https://img.shields.io/github/last-commit/k08255-lxm/ddns-go-installer)](https://github.com/k08255-lxm/ddns-go-installer/commits/main)
[![Code Style](https://img.shields.io/badge/code%20style-shellscript-yellowgreen)](https://www.shellcheck.net)
[![License](https://img.shields.io/github/license/k08255-lxm/ddns-go-installer)](https://github.com/k08255-lxm/ddns-go-installer/blob/main/LICENSE)


本脚本用于快速部署 [jeessy2/ddns-go](https://github.com/jeessy2/ddns-go) 动态域名解析服务，适配主流Linux发行版。

## 功能说明

- 自动安装 [DDNS-Go](https://github.com/jeessy2/ddns-go)
- 交互式配置端口、同步间隔
- 提供系统服务管理菜单
- 自动处理依赖安装

## 准备工作

### 安装curl下载工具
```bash
# Debian/Ubuntu
sudo apt update && sudo apt install -y curl

# CentOS/RHEL
sudo yum install -y curl

# Fedora
sudo dnf install -y curl
```

## 安装步骤

### 下载安装脚本
```bash
curl -O https://raw.githubusercontent.com/k08255-lxm/ddns-go-installer/main/install.sh
```

### 运行安装程序
```bash
sudo bash install.sh
```

## 使用说明

1. 首次运行完成安装后，访问：
   `http://你的服务器IP:9876`

2. 后续管理命令：
```bash
sudo ./install.sh  # 启动管理菜单
```

## 管理功能

1. 启动服务
2. 停止服务
3. 重启服务
4. 查看状态
5. 查看配置
6. 卸载程序


## 项目特点

✅ 全自动版本检测  
✅ 中文兼容  
✅ 系统服务集成  
✅ 配置持久化存储

## 许可证

[MIT License](LICENSE) © 2025 k08255-lxm

## 相关项目

[jeessy2/ddns-go](https://github.com/jeessy2/ddns-go) 

