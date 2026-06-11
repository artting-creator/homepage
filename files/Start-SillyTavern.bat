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

set NODE_ENV=production
set STAMP_FILE=.package-json.timestamp

set NEED_INSTALL=0
set REASON=

REM 取得 package.json 修改時間
for %%A in (package.json) do set PACKAGE_TIME=%%~tA

REM 檢查 node_modules
if not exist node_modules (
    set NEED_INSTALL=1
    set REASON=node_modules missing
)

REM 檢查 timestamp 檔
if not exist %STAMP_FILE% (
    set NEED_INSTALL=1
    if defined REASON (
        set REASON=%REASON% ^& no timestamp
    ) else (
        set REASON=no timestamp
    )
)

REM 檢查 package.json 是否變更
if exist %STAMP_FILE% (
    set /p LAST_PACKAGE_TIME=<%STAMP_FILE%
    if not "%LAST_PACKAGE_TIME%"=="%PACKAGE_TIME%" (
        set NEED_INSTALL=1
        if defined REASON (
            set REASON=%REASON% ^& package.json changed
        ) else (
            set REASON=package.json changed
        )
    )
)

REM 根據結果執行
if "%NEED_INSTALL%"=="1" (
    echo Installing dependencies... (%REASON%)
    
    call npm install --no-save --no-audit --no-fund --loglevel=error --no-progress --omit=dev

    if errorlevel 1 (
        echo npm install failed.
        pause
        popd
        exit /b 1
    )

    echo %PACKAGE_TIME%>%STAMP_FILE%
) else (
    echo Dependencies up-to-date, skipping install.
)

node server.js %*

pause
popd

::參數說明
::--no-save
::安裝套件時，不要修改或更新 package.json 檔案。
::（舊版 npm 預設會寫入 dependencies，這個旗標防止它亂改你的 package.json。SillyTavern 現在已經比較少用到，但保留相容性。）

::--no-audit
::跳過安全性稽核（audit）。
::npm 每次 install 都會自動檢查套件是否有已知漏洞，並連網送資料給 npm 伺服器。
::這個旗標關掉它，可以加快速度、減少網路請求，也避免跳出一堆安全警告（對大多數人來說這些警告沒什麼實質幫助）。

::--no-fund
::不要顯示贊助/捐款提示。
::某些套件作者會在 install 結束時跳出「請贊助我」的訊息。這個旗標把這些提示全部關掉，讓畫面乾淨很多。

::--loglevel=error
::只顯示錯誤訊息，其他正常資訊（例如正在下載哪個套件、警告等）全部隱藏。
::這樣畫面不會刷一堆文字，看起來比較清爽。只有真的出問題時才會顯示紅色錯誤。

::--no-progress
::不要顯示進度條。
::npm 安裝時本來會顯示每個套件的下載進度條，這個旗標關掉它，避免畫面一直跳動。

::--omit=dev
::不要安裝開發用的依賴套件（devDependencies）。
::SillyTavern 本身是生產環境（production），不需要那些只用來開發、測試、打包的套件（例如 eslint、webpack 等）。
::只安裝真正執行時需要的套件，可以大幅減少安裝時間、節省磁碟空間，也更安全。

::%* = 把在命令列輸入的參數全部傳進去
::例如start.bat --port 3000
::變成node server.js --port 3000
