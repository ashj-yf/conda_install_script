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
irm https://gitee.com/ashj-yf/conda_install_script/raw/master/script/reset_password.ps1 -OutFile $env:TEMP\reset_password.ps1; & $env:TEMP\reset_password.ps1
```

## reset_password.sh
```bash
curl -fsSL https://gitee.com/ashj-yf/conda_install_script/raw/master/script/reset_password.sh -o /tmp/reset_password.sh && sudo bash /tmp/reset_password.sh
```

> 脚本需交互输入密码，采用先下载后执行的方式（`sudo bash <(curl ...)` 会因 sudo 关闭进程替换的 fd 而失败）。

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
irm https://raw.githubusercontent.com/ashj-yf/conda_install_script/master/script/reset_password.ps1 -OutFile $env:TEMP\reset_password.ps1; & $env:TEMP\reset_password.ps1
```

## reset_password.sh
```bash
curl -fsSL https://raw.githubusercontent.com/ashj-yf/conda_install_script/master/script/reset_password.sh -o /tmp/reset_password.sh && sudo bash /tmp/reset_password.sh
```

> 脚本需交互输入密码，采用先下载后执行的方式（`sudo bash <(curl ...)` 会因 sudo 关闭进程替换的 fd 而失败）。
