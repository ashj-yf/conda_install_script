# Gitee（国内推荐）

## install_allure.ps1
```powershell
irm https://gitee.com/ashj-yf/conda_install_script/raw/master/script/install_allure.ps1 -OutFile $env:TEMP\install_allure.ps1; & $env:TEMP\install_allure.ps1
```

## install_allure3.ps1
```powershell
irm https://gitee.com/ashj-yf/conda_install_script/raw/master/script/install_allure3.ps1 -OutFile $env:TEMP\install_allure3.ps1; & $env:TEMP\install_allure3.ps1
```

## install_chrome.ps1
```powershell
irm https://gitee.com/ashj-yf/conda_install_script/raw/master/script/install_chrome.ps1 -OutFile $env:TEMP\install_chrome.ps1; & $env:TEMP\install_chrome.ps1
```

## install_git.ps1
```powershell
irm https://gitee.com/ashj-yf/conda_install_script/raw/master/script/install_git.ps1 -OutFile $env:TEMP\install_git.ps1; & $env:TEMP\install_git.ps1
```

## install_huorong.ps1
```powershell
irm https://gitee.com/ashj-yf/conda_install_script/raw/master/script/install_huorong.ps1 -OutFile $env:TEMP\install_huorong.ps1; & $env:TEMP\install_huorong.ps1
```

## install_java.ps1
```powershell
irm https://gitee.com/ashj-yf/conda_install_script/raw/master/script/install_java.ps1 -OutFile $env:TEMP\install_java.ps1; & $env:TEMP\install_java.ps1
```

## install_miniconda.ps1
```powershell
irm https://gitee.com/ashj-yf/conda_install_script/raw/master/script/install_miniconda.ps1 -OutFile $env:TEMP\install_miniconda.ps1; & $env:TEMP\install_miniconda.ps1
```

## install_miniconda.sh
```bash
bash <(curl -fsSL https://gitee.com/ashj-yf/conda_install_script/raw/master/script/install_miniconda.sh)
```

## install_node.ps1
```powershell
irm https://gitee.com/ashj-yf/conda_install_script/raw/master/script/install_node.ps1 -OutFile $env:TEMP\install_node.ps1; & $env:TEMP\install_node.ps1
```

## reset_password.ps1
```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; irm https://gitee.com/ashj-yf/conda_install_script/raw/master/script/reset_password.ps1 -OutFile $env:TEMP\reset_password.ps1; & $env:TEMP\reset_password.ps1
```

> 命令开头强制启用 TLS 1.2：Windows PowerShell 5.1（.NET Framework）默认可能未启用，缺失时访问 HTTPS 会报「基础连接已经关闭：发送时发生错误」。
>
> 内网拦截 Gitee raw CDN 域（`raw.giteeusercontent.com`）时的兜底：改走 `gitee.com` 主域名的 API 链路下载（base64 解码），同样无需 clone：
>
> ```powershell
> [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $f = irm "https://gitee.com/api/v5/repos/ashj-yf/conda_install_script/contents/script/reset_password.ps1?ref=master"; [IO.File]::WriteAllText("$env:TEMP\reset_password.ps1", [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($f.content -replace '\s','')))); & "$env:TEMP\reset_password.ps1"
> ```

## reset_password.sh
```bash
curl -fsSL https://gitee.com/ashj-yf/conda_install_script/raw/master/script/reset_password.sh -o /tmp/reset_password.sh && sudo bash /tmp/reset_password.sh
```

> 内网拦截 Gitee raw CDN 域（`raw.giteeusercontent.com`）时的兜底：改走 `gitee.com` 主域名的 API 链路下载（base64 解码），同样无需 clone：
>
> ```bash
> curl -fsSL "https://gitee.com/api/v5/repos/ashj-yf/conda_install_script/contents/script/reset_password.sh?ref=master" | python3 -c "import sys,json,base64;print(base64.b64decode(json.load(sys.stdin)['content']).decode(),end='')" > /tmp/reset_password.sh && sudo bash /tmp/reset_password.sh
> ```

# GitHub

## install_allure.ps1
```powershell
irm https://raw.githubusercontent.com/ashj-yf/conda_install_script/master/script/install_allure.ps1 -OutFile $env:TEMP\install_allure.ps1; & $env:TEMP\install_allure.ps1
```

## install_allure3.ps1
```powershell
irm https://raw.githubusercontent.com/ashj-yf/conda_install_script/master/script/install_allure3.ps1 -OutFile $env:TEMP\install_allure3.ps1; & $env:TEMP\install_allure3.ps1
```

## install_chrome.ps1
```powershell
irm https://raw.githubusercontent.com/ashj-yf/conda_install_script/master/script/install_chrome.ps1 -OutFile $env:TEMP\install_chrome.ps1; & $env:TEMP\install_chrome.ps1
```

## install_git.ps1
```powershell
irm https://raw.githubusercontent.com/ashj-yf/conda_install_script/master/script/install_git.ps1 -OutFile $env:TEMP\install_git.ps1; & $env:TEMP\install_git.ps1
```

## install_huorong.ps1
```powershell
irm https://raw.githubusercontent.com/ashj-yf/conda_install_script/master/script/install_huorong.ps1 -OutFile $env:TEMP\install_huorong.ps1; & $env:TEMP\install_huorong.ps1
```

## install_java.ps1
```powershell
irm https://raw.githubusercontent.com/ashj-yf/conda_install_script/master/script/install_java.ps1 -OutFile $env:TEMP\install_java.ps1; & $env:TEMP\install_java.ps1
```

## install_miniconda.ps1
```powershell
irm https://raw.githubusercontent.com/ashj-yf/conda_install_script/master/script/install_miniconda.ps1 -OutFile $env:TEMP\install_miniconda.ps1; & $env:TEMP\install_miniconda.ps1
```

## install_miniconda.sh
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ashj-yf/conda_install_script/master/script/install_miniconda.sh)
```

## install_node.ps1
```powershell
irm https://raw.githubusercontent.com/ashj-yf/conda_install_script/master/script/install_node.ps1 -OutFile $env:TEMP\install_node.ps1; & $env:TEMP\install_node.ps1
```

## reset_password.ps1
```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; irm https://raw.githubusercontent.com/ashj-yf/conda_install_script/master/script/reset_password.ps1 -OutFile $env:TEMP\reset_password.ps1; & $env:TEMP\reset_password.ps1
```

## reset_password.sh
```bash
curl -fsSL https://raw.githubusercontent.com/ashj-yf/conda_install_script/master/script/reset_password.sh -o /tmp/reset_password.sh && sudo bash /tmp/reset_password.sh
```

> 脚本需交互输入密码，采用先下载后执行的方式（`sudo bash <(curl ...)` 会因 sudo 关闭进程替换的 fd 而失败）。
