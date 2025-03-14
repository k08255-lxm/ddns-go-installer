# DDNS-Go 一键安装脚本

[![GitHub Release](https://img.shields.io/github/v/release/k08255-lxm/ddns-go-installer)](https://github.com/k08255-lxm/ddns-go-installer/releases)
[![Last Commit](https://img.shields.io/github/last-commit/k08255-lxm/ddns-go-installer?style=flat-square)](https://github.com/k08255-lxm/ddns-go-installer/commits/main)
[![License](https://img.shields.io/github/license/k08255-lxm/ddns-go-installer)](LICENSE)
[![Shell Check](https://img.shields.io/badge/shellcheck-passed-brightgreen)](https://www.shellcheck.net)

> 本项目用于快速部署和管理 [jeessy2/ddns-go](https://github.com/jeessy2/ddns-go) 动态域名解析服务，支持主流Linux发行版和FreeBSD系统。

---

## 📦 功能特性

- **全自动部署** - 自动检测系统架构，下载最新版本
- **智能检测** - 支持识别通过其他方式安装的DDNS-Go
- **服务管理** - 提供启动/停止/重启等系统服务控制
- **关闭web面板** - 可禁用Web界面降低资源使用
- **自动更新** - 支持脚本自更新和程序更新
- **多架构支持** - 兼容x86_64/ARMv6/ARMv7/ARM64架构
- **防火墙提示** - 自动生成防火墙配置建议

---

## 🚀 快速安装

### 环境要求
- Linux / FreeBSD 系统
- Bash 4.0+ 环境
- root权限

### 安装命令
```bash
# 下载安装脚本
curl -O https://raw.githubusercontent.com/k08255-lxm/ddns-go-installer/main/install.sh

# 执行安装
sudo bash install.sh
```

---

## 🛠 管理菜单

安装完成后，通过以下命令启动管理界面：
```bash
ddnsmgr
```

### 菜单功能
```
▌DDNS-GO 管理菜单 v1.1.0
1. 启动服务      2. 停止服务
3. 重启服务      4. 切换Web界面状态
5. 查看状态      6. 更新程序
7. 卸载程序      8. 退出
```

---

## ⚠️ 注意事项

1. 建议在防火墙中开放对应端口
3. Web界面默认启用，可通过菜单选项4关闭
4. 动态IP用户请尽快完成域名解析配置

---

## 📜 许可证

[MIT License](LICENSE) © 2024 k08255-lxm

---
