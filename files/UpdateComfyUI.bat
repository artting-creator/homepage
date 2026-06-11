@echo off
rem chcp 65001是讓命令提示字元在輸出時使用UTF-8
rem CMD解析指令時依然是用ANSI，所以用中文註解或者echo中文經常會出錯。
rem 不影響功能的錯誤可加nul隱藏 >nul
::

chcp 65001 >nul
setlocal enabledelayedexpansion

echo ========================
echo   ComfyUI 一鍵更新工具
echo ========================
set PIP_DISABLE_PIP_VERSION_CHECK=1

:: 設定路徑
set COMFY_PATH=C:\AI\ComfyUI_git

if not exist "%COMFY_PATH%" (
    echo [錯誤] 找不到 ComfyUI 路徑
	echo.
    echo 目前設定的路徑是 %COMFY_PATH%
    echo.

:INPUT_PATH
    set /p COMFY_PATH=請輸入 ComfyUI 路徑（例如 C:\ComfyUI_git）:
        if not exist "!COMFY_PATH!" (
            echo.
            echo [錯誤] !COMFY_PATH! 不存在！
            echo.
            goto INPUT_PATH
        )
    set COMFY_PATH=!COMFY_PATH!
)

if not exist "%COMFY_PATH%\main.py" (
    echo.
    echo [錯誤] %COMFY_PATH% 看起來不是 ComfyUI 的資料夾！
    echo.
    goto INPUT_PATH
)

cd /d "%COMFY_PATH%"

echo.
echo [1/5] 檢查虛擬環境...
echo.

if exist "venv\Scripts\python.exe" (
    echo 即將使用venv環境執行更新
    set "PYTHON=%COMFY_PATH%\venv\Scripts\python.exe"
    set "PIP=%COMFY_PATH%\venv\Scripts\pip.exe"

) else (
    echo 未偵測到 venv\Scripts\python.exe，將使用系統的 python 與 pip 更新套件
    set "PYTHON=python"
    set "PIP=pip"
:: 簡單檢查系統是否有 python ，錯誤則結束批次檔 >nul
    where python >nul 2>&1 || (
        echo [錯誤] 系統中找不到 python 指令！
		echo 請先安裝 Python 並加入 PATH
        pause
        exit /b 1
)
)
    echo.
    echo Python 路徑: %PYTHON%
	%PYTHON% -c "import sys; print('Python 版本:', sys.version.split()[0])" 2>nul
    echo PIP 路徑: %PIP%


echo.
echo 是否更新 custom_nodes？
echo [Y] update all
echo [N] main + new custom_nodes
echo [E] main only
echo 若想停止可關閉視窗結束
echo.
echo ... 10 秒後自動選 N ...
choice /c YNE /t 10 /d N
echo.

:: 判斷順序一定要倒著寫，因為 errorlevel 是「≥」，不是「=」
if errorlevel 3 (
    set SKIP_CUSTOM=1
    set FORCE_UPDATE_REQ=1
    echo [僅更新主程式]
) else if errorlevel 2 (
    set FORCE_UPDATE_REQ=0
    echo [更新主程式 + 新的插件]
) else (
    set FORCE_UPDATE_REQ=1
    echo [全部更新]
)

echo.
echo [2/5] 更新 ComfyUI 主程式...
echo.

if exist ".git" (
    git pull
    if errorlevel 1 (
        echo [錯誤] git pull 執行失敗！
		echo 可能是網路問題或有衝突。
        pause
        exit /b 1
    ) else (
        echo.
        echo [✔] ComfyUI 主程式更新完成
    )
) else (
    echo [錯誤] 此資料夾沒有 .git 資料夾，大概率不是 git 版本
    echo       可能是使用 Portable 版或手動下載的版本
    echo       無法自動更新主程式，請手動下載最新版或改用 git clone 安裝
        pause
        exit /b 1
)


if "%FORCE_UPDATE_REQ%"=="0" (
echo [3/5] 更新 custom_nodes...
cd custom_nodes

:: 比較當前和更新後的commit，記錄哪些node有更新 >nul
set UPDATED_NODES=
for /d %%i in (*) do (
    if exist "%%i\.git" (
        echo ==============================
        echo 正在檢查：%%i
        echo ==============================

        for /f %%a in ('git -C "%%i" rev-parse HEAD') do set OLD_COMMIT=%%a

        git -C "%%i" pull

        if errorlevel 1 (
            echo [錯誤] %%i 更新失敗！
        ) else (

            for /f %%a in ('git -C "%%i" rev-parse HEAD') do set NEW_COMMIT=%%a

            if "!OLD_COMMIT!"=="!NEW_COMMIT!" (
                echo %%i 已是最新
            ) else (
                echo [✔] %%i 有更新！
                set UPDATED_NODES=!UPDATED_NODES! %%i
            )
        )

        echo.
    )
)
cd ..
)

echo.
echo [4/5] 檢查主程式依賴...
%PIP% install -r requirements.txt | findstr /i "Installing Collecting ERROR Successfully"
:: 別加--upgrade這參數，會把torch更新成CPU版，那得另外移除再重裝CUDA版，很久。 >nul
:: findstr過濾訊息，讓它有更新或者有錯誤時才顯示。  >nul
::每次更新ComfyUI後，即使git沒有實際變更，還是會檢查一次依賴，以免requirements.txt有調整套件。在套件已滿足時速度很快，不會花太多時間。  >nul

echo.
echo 主程式依賴檢查完成

if defined SKIP_CUSTOM goto normalEnd

echo.
echo [5/5] 檢查插件依賴...

if "%FORCE_UPDATE_REQ%"=="1" (
cd custom_nodes
    for /d %%i in (*) do (
        if exist "%%i\requirements.txt" if exist "%%i\.git" (
            echo ==============================
            echo installing requirements: %%i
            echo ==============================

            %PIP% install -r "%%i\requirements.txt"
            echo.
        ) else (
            echo there is no requirements.txt in %%i
        )
		)
    )else (

if "%UPDATED_NODES%"=="" (
    echo 沒有任何插件更新，跳過安裝
) else (
    cd custom_nodes
    for %%i in (%UPDATED_NODES%) do (
        if exist "%%i\requirements.txt" (
            echo ==============================
            echo 安裝倚賴： %%i
            echo ==============================

            %PIP% install -r "%%i\requirements.txt"
            echo.
			) else (
            echo %%i 沒有 requirements.txt
        )
    )

    cd ..
)
)

:normalEnd
echo.
echo ==============================
echo   更新完成！可關閉視窗。
echo ==============================
pause