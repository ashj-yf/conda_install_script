# conda_install_script

从清华开源镜像站自动下载安装 Miniconda 的脚本，支持 Linux、macOS 和 Windows。另附 Windows 开发环境一键安装脚本（Chrome + Java 21 + Git + Miniconda）。

## 功能特性

- **自动检测**操作系统与 CPU 架构，自动选择对应安装包
- **清华镜像源**下载，国内速度极快
- **静默安装**（非交互式），一键完成
- 安装后自动执行 `conda init` 并写入清华镜像源配置（`~/.condarc`）
- Windows 开发环境脚本一次性安装 Chrome、Java 21、Git、Miniconda 并自动配置环境变量

## 权限说明

默认安装路径需要相应写入权限：

| 平台 | 默认路径 | 权限要求 |
|------|----------|----------|
| Linux / macOS | `/opt/miniconda3` | `sudo` 权限，或 `/opt` 目录可写 |
| Windows | `C:\ProgramData\miniconda3` | 管理员身份运行 PowerShell |

> 没有管理员权限时，可使用 `--path`（Linux/macOS）或 `-Path`（Windows）指定用户目录下的路径，例如 `~/miniconda3` 或 `$env:USERPROFILE\miniconda3`。

## 快速开始

无需克隆仓库，直接远程下载并执行。

### 安装 Miniconda

#### GitHub 源

<details>
<summary><b>Linux / macOS</b></summary>

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ashj-yf/conda_install_script/master/install_miniconda.sh)
```

<p><button onclick="navigator.clipboard.writeText('bash <(curl -fsSL https://raw.githubusercontent.com/ashj-yf/conda_install_script/master/install_miniconda.sh)').then(()=>this.textContent='已复制 ✓').catch(()=>this.textContent='复制失败')">复制命令</button></p>
</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
irm https://raw.githubusercontent.com/ashj-yf/conda_install_script/master/install_miniconda.ps1 | iex
```

<p><button onclick="navigator.clipboard.writeText('irm https://raw.githubusercontent.com/ashj-yf/conda_install_script/master/install_miniconda.ps1 | iex').then(()=>this.textContent='已复制 ✓').catch(()=>this.textContent='复制失败')">复制命令</button></p>
</details>

#### Gitee 源（国内推荐）

<details>
<summary><b>Linux / macOS</b></summary>

```bash
bash <(curl -fsSL https://gitee.com/ashj-yf/conda_install_script/raw/master/install_miniconda.sh)
```

<p><button onclick="navigator.clipboard.writeText('bash <(curl -fsSL https://gitee.com/ashj-yf/conda_install_script/raw/master/install_miniconda.sh)').then(()=>this.textContent='已复制 ✓').catch(()=>this.textContent='复制失败')">复制命令</button></p>
</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
irm https://gitee.com/ashj-yf/conda_install_script/raw/master/install_miniconda.ps1 | iex
```

<p><button onclick="navigator.clipboard.writeText('irm https://gitee.com/ashj-yf/conda_install_script/raw/master/install_miniconda.ps1 | iex').then(()=>this.textContent='已复制 ✓').catch(()=>this.textContent='复制失败')">复制命令</button></p>
</details>

> [!TIP]
> 可在命令后追加参数，例如 `--force`（跳过检查）、`--path ~/miniconda3`（自定义路径）等。详见下方[参数说明](#参数说明)。

### Windows 开发环境一键安装

一次性安装 **Chrome + Java 21 + Git + Miniconda**，并自动配置环境变量。

#### GitHub 源

<details>
<summary><b>点击查看命令</b></summary>

```powershell
irm https://raw.githubusercontent.com/ashj-yf/conda_install_script/master/install_dev_env.ps1 -OutFile $env:TEMP\install_dev_env.ps1; & $env:TEMP\install_dev_env.ps1 -Mirror github
```

<p><button onclick="navigator.clipboard.writeText('irm https://raw.githubusercontent.com/ashj-yf/conda_install_script/master/install_dev_env.ps1 -OutFile $env:TEMP\\install_dev_env.ps1; & $env:TEMP\\install_dev_env.ps1 -Mirror github').then(()=>this.textContent='已复制 ✓').catch(()=>this.textContent='复制失败')">复制命令</button></p>
</details>

#### Gitee 源（国内推荐）

<details>
<summary><b>点击查看命令</b></summary>

```powershell
irm https://gitee.com/ashj-yf/conda_install_script/raw/master/install_dev_env.ps1 | iex
```

<p><button onclick="navigator.clipboard.writeText('irm https://gitee.com/ashj-yf/conda_install_script/raw/master/install_dev_env.ps1 | iex').then(()=>this.textContent='已复制 ✓').catch(()=>this.textContent='复制失败')">复制命令</button></p>
</details>

> [!NOTE]
> 脚本会**自动提权**到管理员权限（运行时弹出 UAC 确认窗口，点击「是」即可），无需手动以管理员身份运行。
>
> 如遇到 `禁止运行脚本` 错误，请先执行：
> ```powershell
> Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
> ```

**安装内容**

| 软件 | 版本 | 安装路径 |
|------|------|----------|
| Chrome | 最新稳定版 | 默认安装位置 |
| Java (OpenJDK) | 21.0.2 | `C:\ProgramData\Java\jdk-21` |
| Git | 2.47.1 | `C:\Program Files\Git` |
| Miniconda | latest | `C:\ProgramData\miniconda3` |

**参数说明**

| 参数 | 说明 |
|------|------|
| `-Mirror github` | 使用 GitHub 源下载 Miniconda 安装脚本 |
| `-Mirror gitee` | 使用 Gitee 源下载 Miniconda 安装脚本（默认） |
| `-DryRun` | 仅打印配置信息，不实际安装 |

## 本地使用

### Linux / macOS

```bash
# 本地安装（默认路径 /opt/miniconda3，需要 sudo 或 /opt 目录有写入权限）
bash install_miniconda.sh

# 自定义安装路径
bash install_miniconda.sh --path ~/miniconda3

# 预览检测信息和下载地址（不实际执行）
bash install_miniconda.sh --dry-run

# 清除已下载的安装包
bash install_miniconda.sh --clean

# 强制安装（跳过已有 conda 检查）
bash install_miniconda.sh --force
```

### Windows (PowerShell)

```powershell
# 本地安装（默认路径 C:\ProgramData\miniconda3，需要管理员权限）
.\install_miniconda.ps1

# 自定义安装路径
.\install_miniconda.ps1 -Path "$env:USERPROFILE\miniconda3"

# 预览（不实际执行）
.\install_miniconda.ps1 -DryRun

# 清除已下载的安装包
.\install_miniconda.ps1 -Clean

# 强制安装
.\install_miniconda.ps1 -Force
```

## 参数说明

### install_miniconda.sh（Linux / macOS）

| 参数 | 说明 |
|------|------|
| `--force` | 跳过已有 conda 和安装路径已存在的检查 |
| `--path PATH` | 自定义安装路径（默认 `/opt/miniconda3`） |
| `--dry-run` | 仅打印检测信息和下载 URL，不实际执行 |
| `--clean` | 清除已下载的安装包并退出 |
| `--help` | 显示帮助信息 |
| `--version` | 显示脚本版本 |

支持环境变量 `CONDA_INSTALL_PATH` 覆盖默认安装路径。

### install_miniconda.ps1（Windows）

| 参数 | 说明 |
|------|------|
| `-Force` | 跳过已有 conda 和安装路径已存在的检查 |
| `-Path PATH` | 自定义安装路径（默认 `C:\ProgramData\miniconda3`） |
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
