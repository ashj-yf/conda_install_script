# conda_install_script

从清华开源镜像站自动下载安装 Miniconda 的脚本，支持 Linux、macOS 和 Windows。

## 功能

- 自动检测操作系统和 CPU 架构，选择对应的安装包
- 从清华大学开源软件镜像站下载，国内速度极快
- 静默安装（非交互式），一键完成
- 安装后自动执行 `conda init` 并配置清华镜像源（`~/.condarc`）

## 使用方法

### Linux / macOS

```bash
# 基本安装（默认路径 ~/miniconda3）
bash install_miniconda.sh

# 自定义安装路径
bash install_miniconda.sh --path /opt/miniconda3

# 预览检测信息和下载地址（不实际执行）
bash install_miniconda.sh --dry-run

# 清除已下载的安装包
bash install_miniconda.sh --clean

# 强制安装（跳过已有 conda 检查）
bash install_miniconda.sh --force
```

### Windows (PowerShell)

```powershell
# 基本安装（默认路径 %USERPROFILE%\miniconda3）
.\install_miniconda.ps1

# 自定义安装路径
.\install_miniconda.ps1 -Path "C:\miniconda3"

# 预览（不实际执行）
.\install_miniconda.ps1 -DryRun

# 清除已下载的安装包
.\install_miniconda.ps1 -Clean

# 强制安装
.\install_miniconda.ps1 -Force
```

## 参数说明

### bash 脚本

| 参数 | 说明 |
|------|------|
| `--force` | 跳过已有 conda 和安装路径已存在的检查 |
| `--path PATH` | 自定义安装路径（默认 `$HOME/miniconda3`） |
| `--dry-run` | 仅打印检测信息和下载 URL，不实际执行 |
| `--clean` | 清除已下载的安装包并退出 |
| `--help` | 显示帮助信息 |
| `--version` | 显示脚本版本 |

支持环境变量 `CONDA_INSTALL_PATH` 覆盖默认安装路径。

### PowerShell 脚本

| 参数 | 说明 |
|------|------|
| `-Force` | 跳过已有 conda 和安装路径已存在的检查 |
| `-Path PATH` | 自定义安装路径（默认 `%USERPROFILE%\miniconda3`） |
| `-DryRun` | 仅打印检测信息和下载 URL，不实际执行 |
| `-Clean` | 清除已下载的安装包并退出 |
| `-Help` | 显示帮助信息 |
| `-Version` | 显示脚本版本 |

支持环境变量 `CONDA_INSTALL_PATH` 覆盖默认安装路径。

## 支持的平台

| 操作系统 | 架构 | 脚本 |
|----------|------|------|
| Linux | x86_64, aarch64, armv7l, ppc64le, s390x, x86 | `install_miniconda.sh` |
| macOS | x86_64 (Intel), arm64 (Apple Silicon) | `install_miniconda.sh` |
| Windows | x86_64, x86 | `install_miniconda.ps1` |

## 镜像源配置

安装完成后，`~/.condarc` 会自动配置为清华镜像源：

```yaml
channels:
  - defaults
show_channel_urls: true
default_channels:
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/r
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/msys2
custom_channels:
  conda-forge: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  pytorch: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
```

## License

[Apache License 2.0](LICENSE)
