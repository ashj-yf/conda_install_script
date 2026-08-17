# conda_install_script

从中科大开源镜像站（USTC）自动下载安装 Miniconda 的脚本，支持 Linux、macOS 和 Windows。另附 Windows 开发环境一键安装脚本（Chrome + Java 21 + Git + Miniconda + Node.js + Allure 3）。

## 功能特性

- **自动检测**操作系统与 CPU 架构，自动选择对应安装包
- **中科大镜像源**下载，国内速度极快
- **静默安装**（非交互式），一键完成
- 安装后自动执行 `conda init` 并写入中科大镜像源配置（`~/.condarc`）
- Windows 开发环境脚本一次性安装 Chrome、Java 21、Git、Miniconda、Node.js、Allure 3 并自动配置环境变量

## 脚本清单

### 编排脚本

| 脚本 | 平台 | 说明 |
|------|------|------|
| `install_dev_env.ps1` | Windows | 一键编排器，依次调用 6 个独立组件脚本完成全量安装 |

### 独立组件脚本

每个脚本均可**单独运行**，也可被编排脚本调用。

| 脚本 | 平台 | 安装内容 | 下载源 | 参与编排 |
|------|------|----------|--------|----------|
| `install_chrome.ps1` | Windows | Google Chrome（最新稳定版） | Google 官方 | ✅ |
| `install_java.ps1` | Windows | OpenJDK 21 + JAVA_HOME / PATH 配置 | 华为镜像 | ✅ |
| `install_git.ps1` | Windows | Git for Windows | 华为镜像 | ✅ |
| `install_miniconda.ps1` | Windows | Miniconda（最新版）+ conda init + 中科大镜像源 | 中科大镜像 | ✅ |
| `install_node.ps1` | Windows | Node.js 最新 LTS（含 npm）+ PATH 配置 | 华为镜像 | ✅ |
| `install_allure3.ps1` | Windows | Allure 3（npm 全局包 `allure`，需 Node.js） | npmmirror | ✅ |
| `install_allure.ps1` | Windows | Allure 2（2.45.0，需 Java）+ PATH 配置 | 华为 Maven 镜像 | ❌ 仅单独运行 |
| `install_miniconda.sh` | Linux / macOS | Miniconda（最新版）+ conda init + 中科大镜像源 | 中科大镜像 | — |

> **Allure 2 与 Allure 3**：编排器默认安装 **Allure 3**。Allure 2 的脚本 `install_allure.ps1` 仍然保留，可按需单独运行。两者的 CLI 命令名都是 `allure`，同时安装时由 PATH 顺序决定谁生效——`install_allure3.ps1` 会检测这种冲突并给出警告。
>
> | | Allure 2 | Allure 3 |
> |---|---|---|
> | 分发方式 | Java ZIP（Maven 仓库） | npm 包 `allure` |
> | 运行时依赖 | Java 8+ | Node.js |
> | 安装位置 | `C:\ProgramData\Allure\allure-<版本>` | npm 全局前缀 |

> **调用关系**：`install_dev_env.ps1` 通过 `Invoke-SubScript` 函数远程下载 `script/` 目录下的各组件脚本并执行，也支持 `-Offline` 模式从本地 `script/` 子目录加载。

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
bash <(curl -fsSL https://raw.githubusercontent.com/ashj-yf/conda_install_script/master/script/install_miniconda.sh)
```

<p><button onclick="navigator.clipboard.writeText('bash <(curl -fsSL https://raw.githubusercontent.com/ashj-yf/conda_install_script/master/script/install_miniconda.sh)').then(()=>this.textContent='已复制 ✓').catch(()=>this.textContent='复制失败')">复制命令</button></p>
</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
irm https://raw.githubusercontent.com/ashj-yf/conda_install_script/master/script/install_miniconda.ps1 -OutFile $env:TEMP\install_miniconda.ps1; & $env:TEMP\install_miniconda.ps1
```

<p><button onclick="navigator.clipboard.writeText('irm https://raw.githubusercontent.com/ashj-yf/conda_install_script/master/script/install_miniconda.ps1 -OutFile $env:TEMP\\install_miniconda.ps1; & $env:TEMP\\install_miniconda.ps1').then(()=>this.textContent='已复制 ✓').catch(()=>this.textContent='复制失败')">复制命令</button></p>
</details>

#### Gitee 源（国内推荐）

<details>
<summary><b>Linux / macOS</b></summary>

```bash
bash <(curl -fsSL https://gitee.com/ashj-yf/conda_install_script/raw/master/script/install_miniconda.sh)
```

<p><button onclick="navigator.clipboard.writeText('bash <(curl -fsSL https://gitee.com/ashj-yf/conda_install_script/raw/master/script/install_miniconda.sh)').then(()=>this.textContent='已复制 ✓').catch(()=>this.textContent='复制失败')">复制命令</button></p>
</details>

<details>
<summary><b>Windows (PowerShell)</b></summary>

```powershell
irm https://gitee.com/ashj-yf/conda_install_script/raw/master/script/install_miniconda.ps1 -OutFile $env:TEMP\install_miniconda.ps1; & $env:TEMP\install_miniconda.ps1
```

<p><button onclick="navigator.clipboard.writeText('irm https://gitee.com/ashj-yf/conda_install_script/raw/master/script/install_miniconda.ps1 -OutFile $env:TEMP\\install_miniconda.ps1; & $env:TEMP\\install_miniconda.ps1').then(()=>this.textContent='已复制 ✓').catch(()=>this.textContent='复制失败')">复制命令</button></p>
</details>

> [!TIP]
> 可在命令后追加参数，例如 `--force`（跳过检查）、`--path ~/miniconda3`（自定义路径）等。详见下方[参数说明](#参数说明)。

### Windows 开发环境一键安装

一次性安装 **Chrome + Java 21 + Git + Miniconda + Node.js + Allure 3**，并自动配置环境变量。

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
irm https://gitee.com/ashj-yf/conda_install_script/raw/master/install_dev_env.ps1 -OutFile $env:TEMP\install_dev_env.ps1; & $env:TEMP\install_dev_env.ps1
```

<p><button onclick="navigator.clipboard.writeText('irm https://gitee.com/ashj-yf/conda_install_script/raw/master/install_dev_env.ps1 -OutFile $env:TEMP\\install_dev_env.ps1; & $env:TEMP\\install_dev_env.ps1').then(()=>this.textContent='已复制 ✓').catch(()=>this.textContent='复制失败')">复制命令</button></p>
</details>

> [!NOTE]
> 脚本会**自动提权**到管理员权限（运行时弹出 UAC 确认窗口，点击「是」即可），无需手动以管理员身份运行。
>
> 命令采用「先下载到临时文件再执行」而非 `irm ... | iex`：脚本顶部的 `[CmdletBinding()]`/`param()` 块会被 `iex` 当作普通命令解析而报错（意外的属性 CmdletBinding），必须落地为 `.ps1` 文件执行。
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
| Node.js | 最新 LTS | `C:\ProgramData\nodejs` |
| Allure 3 | latest | npm 全局包（`npm ls -g allure`） |

> Allure 3 依赖 Node.js，所以编排顺序是 Node.js → Allure 3。若只想用 Allure 2，单独运行 `script\install_allure.ps1`（它依赖 Java，编排器不再调用它）。

**参数说明**

| 参数 | 说明 |
|------|------|
| `-Mirror github` | 使用 GitHub 源下载各子脚本 |
| `-Mirror gitee` | 使用 Gitee 源下载各子脚本（默认） |
| `-DryRun` | 仅打印配置信息，不实际安装 |
| `-Offline` | 离线模式，从脚本同目录加载本地 .ps1 文件，不发起网络请求 |

## 本地使用

### Linux / macOS

```bash
# 本地安装（默认路径 /opt/miniconda3，需要 sudo 或 /opt 目录有写入权限）
bash script/install_miniconda.sh

# 自定义安装路径
bash script/install_miniconda.sh --path ~/miniconda3

# 预览检测信息和下载地址（不实际执行）
bash script/install_miniconda.sh --dry-run

# 清除已下载的安装包
bash script/install_miniconda.sh --clean

# 强制安装（跳过已有 conda 检查）
bash script/install_miniconda.sh --force
```

### Windows (PowerShell)

```powershell
# === 一键安装全部（编排器） ===
.\install_dev_env.ps1                     # 默认 Gitee 源
.\install_dev_env.ps1 -Mirror github      # GitHub 源
.\install_dev_env.ps1 -DryRun             # 预览
.\install_dev_env.ps1 -Offline            # 离线模式（使用本地子脚本）

# === 单独安装 Miniconda ===
.\script\install_miniconda.ps1                   # 默认路径
.\script\install_miniconda.ps1 -Path "$env:USERPROFILE\miniconda3"
.\script\install_miniconda.ps1 -DryRun
.\script\install_miniconda.ps1 -Clean
.\script\install_miniconda.ps1 -Force

# === 单独安装 Java 21 ===
.\script\install_java.ps1                        # 默认路径 + 配置环境变量
.\script\install_java.ps1 -Path "D:\Java\jdk-21" -SkipEnv
.\script\install_java.ps1 -DryRun

# === 单独安装 Git ===
.\script\install_git.ps1
.\script\install_git.ps1 -Force

# === 单独安装 Chrome ===
.\script\install_chrome.ps1
.\script\install_chrome.ps1 -DryRun

# === 单独安装 Allure（需先装好 Java） ===
.\script\install_allure.ps1                      # 默认 2.45.0 + 加入 PATH
.\script\install_allure.ps1 -AllureVersion 2.44.1
.\script\install_allure.ps1 -Path "D:\Tools\allure" -SkipEnv
.\script\install_allure.ps1 -DryRun

# === 单独安装 Node.js ===
.\script\install_node.ps1                        # 最新 LTS + 加入 PATH
.\script\install_node.ps1 -NodeVersion v22.16.0
.\script\install_node.ps1 -Path "D:\nodejs" -SkipEnv
.\script\install_node.ps1 -DryRun
.\script\install_node.ps1 -Clean                 # 清理 TEMP 中缓存的 node zip

# === 单独安装 Allure 3（需先装好 Node.js） ===
.\script\install_allure3.ps1                     # latest + npmmirror 源
.\script\install_allure3.ps1 -AllureVersion 3.14.3
.\script\install_allure3.ps1 -Registry https://registry.npmjs.org
.\script\install_allure3.ps1 -DryRun
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

### install_allure.ps1（Windows）

| 参数 | 说明 |
|------|------|
| `-Force` | 强制重装，即使已检测到符合要求的 Allure |
| `-Path PATH` | 自定义安装路径（默认 `C:\ProgramData\Allure\allure-<版本>`） |
| `-AllureVersion VER` | 指定版本（默认 `2.45.0`，**必须大于 2.44.0**） |
| `-DownloadUrl URL` | 自定义下载地址（默认华为 Maven 镜像） |
| `-SkipEnv` | 跳过 PATH 配置 |
| `-DryRun` | 仅打印检测信息和下载 URL，不实际执行 |
| `-Clean` | 清除已下载的 ZIP 并退出 |
| `-Help` | 显示帮助信息 |
| `-Version` | 显示脚本版本 |

支持环境变量 `ALLURE_VERSION`、`ALLURE_INSTALL_PATH`、`ALLURE_DOWNLOAD_URL` 覆盖对应默认值。

> Allure 是 JVM 工具，运行前需要 Java 8+（`java.exe` 在 PATH 中或已设置 `JAVA_HOME`）。低于或等于 2.44.0 的已装版本会被自动升级，同时清理系统级 PATH 中指向旧版本的 `allure*\bin` 条目（用户级 PATH 不会被修改）。此脚本**不参与编排**，需单独运行。

### install_node.ps1（Windows）

| 参数 | 说明 |
|------|------|
| `-Force` | 强制重装，即使已检测到 Node.js |
| `-Path PATH` | 自定义安装路径（默认 `C:\ProgramData\nodejs`） |
| `-NodeVersion VER` | 指定版本，如 `v24.19.0`（默认：联网解析最新 LTS） |
| `-DownloadUrl URL` | 自定义下载地址（会覆盖镜像与版本） |
| `-SkipEnv` | 跳过 PATH 配置 |
| `-DryRun` | 仅打印检测信息和下载 URL，不实际执行 |
| `-Clean` | 清理 TEMP 中缓存的所有 `node-v*-win-*.zip` 并退出 |
| `-Help` / `-Version` | 帮助 / 脚本版本 |

支持环境变量 `NODE_INSTALL_PATH`、`NODE_VERSION`。

> 用**华为镜像**而非清华：清华的 `nodejs-release` 镜像已滞后（`index.json` 停在 `v24.1.0`，拉取更新的 LTS 会 404）。版本默认从 `index.json` 动态解析最新 LTS，联网失败时回退到脚本内固定的 `v24.19.0`。npm 随 Node 压缩包自带，无需单独安装。
>
> Node.js 24 的 Windows 包只有 x64 / arm64，**32 位系统会直接报错退出**。

### install_allure3.ps1（Windows）

| 参数 | 说明 |
|------|------|
| `-Force` | 强制重装，即使已是目标版本 |
| `-AllureVersion VER` | 指定版本，如 `3.14.3`（默认 `latest`） |
| `-Registry URL` | npm 源（默认 `https://registry.npmmirror.com`） |
| `-DryRun` | 仅打印将要执行的 npm 命令，不实际安装 |
| `-Help` / `-Version` | 帮助 / 脚本版本 |

支持环境变量 `ALLURE3_VERSION`、`ALLURE3_REGISTRY`。

> Allure 3 是 TypeScript 重写版，**只通过 npm 分发**（包名 `allure`），没有免运行时的独立包，因此**必须先有 Node.js**——脚本只检测不代装，缺失时报错并提示运行 `install_node.ps1`。
>
> 默认 `latest` 会先向 registry 查询最新版本号，再与已装版本比较：相同则跳过，不同则升级（`-Force` 可强制重装）。查询失败时退化为交给 npm 自己解析 `allure@latest`。
>
> 安装后若 npm 全局前缀不在 PATH 中会自动补上；若检测到 `allure` 命令解析到 npm 前缀之外（通常是 Allure 2 抢先），会给出冲突警告。

## 支持的平台

| 操作系统 | 架构 | 脚本 |
|----------|------|------|
| Linux | x86_64, aarch64, armv7l, ppc64le, s390x, x86 | `script/install_miniconda.sh` |
| macOS | x86_64 (Intel), arm64 (Apple Silicon) | `script/install_miniconda.sh` |
| Windows | x86_64, x86 | `script/install_miniconda.ps1` |

> ppc64le / s390x 的安装包不在中科大镜像上，脚本会自动回退到官方 `repo.anaconda.com` 下载。

## 镜像源配置

安装完成后，`~/.condarc` 会自动配置为中科大镜像源（清华 TUNA 已停止 Anaconda 仓库镜像）：

```yaml
channels:
  - nodefaults
custom_channels:
  conda-forge: https://mirrors.ustc.edu.cn/anaconda/cloud
  bioconda: https://mirrors.ustc.edu.cn/anaconda/cloud
show_channel_urls: true
```

> [!NOTE]
> 中科大镜像**不包含 Anaconda 官方仓库**（`pkgs/main`、`pkgs/r`、`pkgs/msys2` 等需商业授权的频道），因此配置中不含 `defaults`，日常 `conda install` 默认走 conda-forge，也未包含 pytorch 频道。需要 PyTorch 时建议使用 `pip install torch`，或显式 `conda install -c pytorch` 走官方频道。
>
> 配置后可运行 `conda clean -i` 清除索引缓存，再用 `conda create -n myenv numpy -c conda-forge` 验证。

## License

[Apache License 2.0](LICENSE)
