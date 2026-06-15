@echo off
pushd %~dp0

REM ===== 簡易防呆 =====
if not exist server.js (
    echo [ERROR] server.js not found!
    echo Please make sure this script is in the correct folder.
    pause
    popd
    exit /b 1
)

if not exist package.json (
    echo [ERROR] package.json not found!
    echo Please make sure this script is in the correct folder.
    pause
    popd
    exit /b 1
)


REM 快速檢查：只要 node_modules 存在就跳過安裝
if exist node_modules goto skip_install

echo node_modules missing, installing...
call npm install --no-save --no-audit --no-fund --loglevel=error --no-progress --omit=dev
if errorlevel 1 (
    pause
    popd
    exit /b 1
)

:skip_install
set NODE_ENV=production
node server.js %*

pause
popd
exit /b 0

:: 參數說明NODE_ENV=production
:: 會關閉 debug log，啟用效能優化

:: %* = 把在命令列輸入的參數全部傳進去
:: 例如輸入start.bat --port 3000
:: 會變成node server.js --port 3000
