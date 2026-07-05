@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

title llama 啟動器

:: 可直接執行，批次檔會檢查本身目錄下，是否有llamacpp和模型
:: You can fix setting for yourself, near line 10 / line 420

set "DEFAULT_BASE_DIR=C:\AI\Chat Completion"
set "DEFAULT_API_KEY=temp"

echo.
if defined DEFAULT_BASE_DIR (
    set "BASE_DIR=%DEFAULT_BASE_DIR%"
) else (
    set "BASE_DIR=%~dp0"
)
set "BASE_DIR=%BASE_DIR:"=%"
if not "%BASE_DIR:~-1%"=="\" set "BASE_DIR=%BASE_DIR%\"
set "DIR_N=0"
set "MODEL_N=0"
set "MMPROJ_N=0"
set "API_KEY="
set "USE_JINJA=1"
set "USE_DRAFT_MTP=0"


:parse_args
if "%~1"=="" goto args_done

if /i "%~1"=="--api-key" (
    if "%~2"=="" (
        echo 參數錯誤：--api-key 後面必須接金鑰字串。
        exit /b 1
    )
    set "API_KEY=%~2"
    shift
    shift
    goto parse_args
)

if /i "%~1"=="-k" (
    if "%~2"=="" (
        echo 參數錯誤：-k 後面必須接金鑰字串。
        exit /b 1
    )
    set "API_KEY=%~2"
    shift
    shift
    goto parse_args
)

if /i "%~1"=="--no-api-key" (
    set "API_KEY="
    shift
    goto parse_args
)

echo 忽略未知參數：%~1
shift
goto parse_args

:args_done
if defined DEFAULT_API_KEY set "API_KEY=%DEFAULT_API_KEY%"

echo 基準路徑：%BASE_DIR%
echo.
echo ====== llama 版本目錄 ========
:scan_llama_dirs
set "DIR_N=0"
for /d %%D in ("%BASE_DIR%*") do (
    if exist "%%~fD\llama-server.exe" (
        set /a DIR_N+=1
        set "LLAMA_DIR[!DIR_N!]=%%~fD"
        set "LLAMA_NAME[!DIR_N!]=%%~nxD"
        echo   !DIR_N!. %%~nxD
    )
)

echo.

if "%DIR_N%"=="0" (
    echo 找不到任何包含 llama-server.exe 的資料夾。
    echo.
    call :ask_basedir
    if errorlevel 1 (
        echo.
		echo     已取消
        echo.
        pause
        exit /b
    )
    echo.
	echo 已更新基準目錄：!BASE_DIR!
    echo.
    goto scan_llama_dirs
)

if "%DIR_N%"=="1" goto auto_llama
goto choose_llama

:ask_basedir
set "NEW_BASE_DIR="
set /p NEW_BASE_DIR=請輸入基準路徑（可拖曳資料夾到視窗）：
if not defined NEW_BASE_DIR exit /b 1
set "NEW_BASE_DIR=!NEW_BASE_DIR:"=!"
if not exist "!NEW_BASE_DIR!\" (
    echo.
    echo Path does not exist. Please enter it again.
    echo.
    goto ask_basedir
)
set "BASE_DIR=!NEW_BASE_DIR!\"
exit /b 0

:auto_llama
set "TARGET_DIR=!LLAMA_DIR[1]!"
set "TARGET_DIR_NAME=!LLAMA_NAME[1]!"
echo 找到唯一一個 llama 版本，已自動選擇。
echo.
goto llama_selected

:choose_llama
set "llama_choice="
set /p llama_choice=請輸入 llama 版本編號（或輸入 X 離開）：
if /i "!llama_choice!"=="X" goto user_cancelled
echo(!llama_choice!| findstr /r "^[0-9][0-9]*$" >nul
if errorlevel 1 (
    echo.
    echo 請輸入純數字編號。
    goto choose_llama
)

if not defined LLAMA_DIR[%llama_choice%] (
    echo.
    echo 編號錯誤，請重新輸入。
    goto choose_llama
)

set "TARGET_DIR=!LLAMA_DIR[%llama_choice%]!"
set "TARGET_DIR_NAME=!LLAMA_NAME[%llama_choice%]!"

:llama_selected
echo.
echo 已選擇 llama 版本：!TARGET_DIR_NAME!
echo.
echo ======= 模型清單 =======

for /r "%BASE_DIR%" %%F in (*.gguf) do (
    echo %%~nxF | findstr /i "mmproj" >nul
    if errorlevel 1 (
        set /a MODEL_N+=1
        set "MODEL_PATH[!MODEL_N!]=%%~fF"
        set "MODEL_NAME[!MODEL_N!]=%%~nxF"
        echo   !MODEL_N!. %%~nxF
    )
)

echo.

if "%MODEL_N%"=="0" (
    echo 找不到任何一般 .gguf 模型檔。
    echo 請確認模型檔放在批次檔所在資料夾或其子資料夾內。
    echo.
    pause
    exit /b
)

:choose_model
set "model_choice="
set /p model_choice=請輸入模型編號（或輸入 X 離開）：
if /i "!model_choice!"=="X" goto user_cancelled
echo(!model_choice!| findstr /r "^[0-9][0-9]*$" >nul
if errorlevel 1 (
    echo.
    echo 請輸入純數字編號。
    goto choose_model
)

if not defined MODEL_PATH[%model_choice%] (
    echo.
    echo 編號錯誤，請重新輸入。
    goto choose_model
)

set "TARGET_MODEL=!MODEL_PATH[%model_choice%]!"
set "TARGET_MODEL_NAME=!MODEL_NAME[%model_choice%]!"

echo.
echo 已選擇模型：!TARGET_MODEL_NAME!
echo.
echo ====== 是否啟用多模態視覺模型
echo.
echo mmproj 跟原來的模型必需是配對的，不能隨便混搭。
echo.
echo   Y. 啟用，模型可識別圖片（並非生圖能力）
echo   N. 不啟用，模型只有純文字功能
echo.
echo 5 秒後自動選 N

choice /c YN /n /t 5 /d N /m "[Y/N]？ "

if errorlevel 2 (
    set "USE_VISION=0"
    goto api_key_menu
)

if errorlevel 1 (
    set "USE_VISION=1"
    goto scan_mmproj
)


:scan_mmproj
echo.
echo === mmproj 視覺投影模型清單 ==============
echo === 唯一且檔名 75%% 以上相似會自動選擇 ===
echo.

set "MODEL_BASENAME=!TARGET_MODEL_NAME!"
set "MODEL_BASENAME=!MODEL_BASENAME:.gguf=!"
set "MODEL_PREFIX=!MODEL_BASENAME!"
set "BEST_MATCH_ID="
set "BEST_MATCH_SCORE=0"

:: 取得模型名稱長度
set "MODEL_LEN=0"
call :strlen MODEL_PREFIX MODEL_LEN

for /r "%BASE_DIR%" %%F in (*.gguf) do (
    echo %%~nxF | findstr /i "mmproj" >nul
    if not errorlevel 1 (
        set /a MMPROJ_N+=1
        set "MMPROJ_PATH[!MMPROJ_N!]=%%~fF"
        set "MMPROJ_NAME[!MMPROJ_N!]=%%~nxF"
        
        :: 使用不同的變數名稱，避免衝突
        set "THIS_MMPROJ=%%~nxF"
        set "THIS_MMPROJ=!THIS_MMPROJ:.gguf=!"
        set "THIS_MMPROJ=!THIS_MMPROJ:mmproj-=!"
        set "THIS_MMPROJ=!THIS_MMPROJ:MMPROJ-=!"
        
        :: 計算匹配分數
        set "SCORE=0"
        for /l %%i in (0,1,!MODEL_LEN!) do (
            if "!MODEL_PREFIX:~%%i,1!"=="!THIS_MMPROJ:~%%i,1!" (
                if not "!MODEL_PREFIX:~%%i,1!"=="" (
                    set /a SCORE+=1
                )
            )
        )

        :: 計算百分比
        set "PERCENT=0"
        if !MODEL_LEN! gtr 0 (
            set /a "PERCENT=!SCORE! * 100 / !MODEL_LEN!"
        )
        
        echo   !MMPROJ_N!. %%~nxF（匹配度：!SCORE!/!MODEL_LEN! = !PERCENT! %% ）
        if !SCORE! gtr !BEST_MATCH_SCORE! (
            set "BEST_MATCH_SCORE=!SCORE!"
            set "BEST_MATCH_ID=!MMPROJ_N!"
            set "BEST_MATCH_NAME=%%~nxF"
        )
    )
)

echo.

if "%MMPROJ_N%"=="0" (
    echo 找不到 mmproj .gguf 檔案。
    echo 將改用純文字模式啟動。
    set "USE_VISION=0"
    goto api_key_menu
)

set /A "MATCH_THRESHOLD=!MODEL_LEN! * 75 / 100"
if "%MMPROJ_N%"=="1" (
if defined BEST_MATCH_ID (
    if !BEST_MATCH_SCORE! geq !MATCH_THRESHOLD! (
        set "TARGET_MMPROJ=!MMPROJ_PATH[%BEST_MATCH_ID%]!"
        set "TARGET_MMPROJ_NAME=!BEST_MATCH_NAME!"
        echo 找到唯一符合的模型，已自動選擇：
        echo !TARGET_MMPROJ_NAME!
        goto api_key_menu
    )
)
)

:: 多個，或者唯一但匹配不達標
goto choose_mmproj

:: String length calculation function
:strlen
setlocal enabledelayedexpansion
set "str=!%~1!"
set "len=0"
if defined str (
    for /l %%i in (0,1,100) do (
        if "!str:~%%i,1!"=="" (
            set "len=%%i"
            goto :break
        )
    )
)
:break
endlocal & set "%~2=%len%"
exit /b 0


:choose_mmproj
set "mmproj_choice="
set /p mmproj_choice=請輸入模型編號（數字），或者輸入 N 跳過，輸入 X 離開。
if /i "!mmproj_choice!"=="X" goto user_cancelled
if /i not "!mmproj_choice!"=="N" (
    echo(!mmproj_choice!| findstr /r "^[0-9][0-9]*$" >nul
    if errorlevel 1 (
        echo.
        goto choose_mmproj
    )
)

if /i "%mmproj_choice%"=="N" (
    echo.
    echo 已跳過多模態視覺模型，改用純文字模式。
    set "USE_VISION=0"
    set "TARGET_MMPROJ="
    set "TARGET_MMPROJ_NAME="
    goto api_key_menu
)

if not defined MMPROJ_PATH[%mmproj_choice%] (
    echo.
    echo 編號錯誤，請重新輸入。
    goto choose_mmproj
)

set "TARGET_MMPROJ=!MMPROJ_PATH[%mmproj_choice%]!"
set "TARGET_MMPROJ_NAME=!MMPROJ_NAME[%mmproj_choice%]!"

echo 已選擇 mmproj 模型：
echo !TARGET_MMPROJ_NAME!


:api_key_menu
echo.
echo.
echo ====== API Key 設定 ======
if defined API_KEY (
    echo.
    echo 已由參數或預設值帶入 API Key：!API_KEY!
    goto jinja_menu
)

echo.
echo 5 秒後自動選 N
choice /c YN /n /t 5 /d N /m "使用 API Key？[Y/N] "

if errorlevel 2 (
    set "API_KEY="
    goto jinja_menu
)

:input_api_key
echo.
set "API_KEY="
set /p API_KEY=請輸入 API Key（不可空白）：
if not defined API_KEY (
    echo API Key 不可為空，請重新輸入。
    goto input_api_key
)

goto jinja_menu

:jinja_menu
echo.
echo.
echo == jinja 參數（聊天模板） ========
echo == 模型自帶模板的，通常都會開啟 ==
echo.
echo 使用參數 --jinja？ 5 秒後自動選 Y
choice /c YN /n /t 5 /d Y /m " [Y/N] "

if errorlevel 2 (
    set "USE_JINJA=0"
    goto draft_mtp_menu
)

set "USE_JINJA=1"
goto draft_mtp_menu

:draft_mtp_menu
echo.
echo.
echo == draft-mtp 參數（推測解碼功能） ===
echo == 模型本身就支援 MTP 的架構才有效 ==
echo.
echo 啟用 --spec-type draft-mtp？ 5 秒後自動選 N
choice /c YN /n /t 5 /d N /m " [Y/N] "

if errorlevel 2 (
    set "USE_DRAFT_MTP=0"
    goto gpu_menu
)

set "USE_DRAFT_MTP=1"
goto gpu_menu

:gpu_menu
:: 調高 BATCH 和 UBATCH 可加快處理效率但可能不穩定
set "BATCH=2048"
set "UBATCH=512"
echo.
echo.
echo ====== 設定啟動參數 ======
echo 主要調整 CTX（上下文限制）和 PREDICT（輸出上限）
echo.

call :add_gpu_profile 1 "一檔-上下文8K-輸出2k" "auto" "1:建議  8GB VRAM 的顯示卡： CTX=8192 PREDICT=2048"

call :add_gpu_profile 2 "二檔-上下文32K-輸出8k" "auto" "2:建議 12GB VRAM 的顯示卡： CTX=32768 PREDICT=8192"

call :add_gpu_profile 3 "三檔-上下文65K-輸出16k" "auto" "3:建議 16GB VRAM 的顯示卡： CTX=65536 PREDICT=16384"

call :add_gpu_profile 4 "四檔-上下文131K-輸出32k" "auto" "4:建議 20GB VRAM 的顯示卡： CTX=131072 PREDICT=32768"

call :add_gpu_profile 5 "五檔-上下文262K-輸出65k" "auto" "5:建議 24GB VRAM 的顯示卡： CTX=262144 PREDICT=65536"
echo.

call :add_gpu_profile 11 "test-1M-262k" "999" "test_11： CTX=1048576 PREDICT=262144"

call :add_gpu_profile 12 "測試用-131k-不限" "auto" "測試用編號12： CTX=131072 PREDICT=-1"
echo.

if defined GPU_PROFILE_ERROR (
    echo.
    echo 啟動參數設定有缺漏，請修正上方檔位說明列。
    pause
    exit /b 1
)
goto choose_gpu

:choose_gpu
set "gpu_choice="
set /p gpu_choice=請選擇編號（或輸入 X 離開）：
if /i "!gpu_choice!"=="X" goto user_cancelled
echo(!gpu_choice!| findstr /r "^[0-9][0-9]*$" >nul
if errorlevel 1 (
    echo.
    echo 請輸入純數字編號。
    goto choose_gpu
)

if not defined GPU_LINE[!gpu_choice!] (
    echo.
    echo 編號錯誤，請重新輸入。
    goto choose_gpu
)

call :select_gpu_profile "!gpu_choice!"
goto launch
:user_cancelled
echo.
echo 已取消。
pause
exit /b

:launch
echo.
echo ======= !GPU_LEVEL! 的啟動參數 =======
echo.
echo   llama-server.exe
echo   -m "!TARGET_MODEL!"
if "!USE_VISION!"=="1" (
  echo   --mmproj "!TARGET_MMPROJ!"
)
echo   -ngl !NGL!
echo   -c !CTX!
echo   -n !PREDICT!
echo   -b !BATCH!
echo   -ub !UBATCH!
if defined API_KEY echo   --api-key "!API_KEY!"
if "!USE_JINJA!"=="1" (
  echo   --jinja
) else (
  echo   --no-jinja
)
if "!USE_DRAFT_MTP!"=="1" (
  echo   --spec-type draft-mtp
)
echo   -lv 3
echo   --host 127.0.0.1
echo   --port 8080
echo.
echo 10 秒後自動啟動
choice /c YN /n /t 10 /d Y /m " 立即開始？[Y/N] "

echo.

if errorlevel 2 (
    echo 已取消
	pause
    exit /b
)

set "API_KEY_ARG="
if defined API_KEY set "API_KEY_ARG=--api-key ""!API_KEY!"""
set "JINJA_ARG=--no-jinja"
if "!USE_JINJA!"=="1" set "JINJA_ARG=--jinja"
set "DRAFT_MTP_ARG="
if "!USE_DRAFT_MTP!"=="1" set "DRAFT_MTP_ARG=--spec-type draft-mtp"

pushd "!TARGET_DIR!"

if "!USE_VISION!"=="1" (
    llama-server.exe ^
        -m "!TARGET_MODEL!" ^
        --mmproj "!TARGET_MMPROJ!" ^
        -ngl !NGL! ^
        -c !CTX! ^
        -n !PREDICT! ^
        -b !BATCH! ^
        -ub !UBATCH! ^
        !JINJA_ARG! ^
        -lv 3 ^
        --host 127.0.0.1 ^
        --port 8080 !API_KEY_ARG! !DRAFT_MTP_ARG!
) else (
    llama-server.exe ^
        -m "!TARGET_MODEL!" ^
        -ngl !NGL! ^
        -c !CTX! ^
        -n !PREDICT! ^
        -b !BATCH! ^
        -ub !UBATCH! ^
        !JINJA_ARG! ^
        -lv 3 ^
        --host 127.0.0.1 ^
        --port 8080 !API_KEY_ARG! !DRAFT_MTP_ARG!
)

if errorlevel 1 (
    echo.
    echo llama-server.exe 可能啟動失敗，請檢視上方錯誤訊息。
)

pause
popd
endlocal
exit /b

:add_gpu_profile
set "GPU_ID=%~1"
set "GPU_LEVEL[%~1]=%~2"
set "NGL[%~1]=%~3"
set "GPU_LINE[%~1]=%~4"
echo %~4
call :read_gpu_profile_value "%~1" "%~4" "CTX"
call :read_gpu_profile_value "%~1" "%~4" "PREDICT"
exit /b 0

:read_gpu_profile_value
set "PROFILE_ID=%~1"
set "PROFILE_LINE=%~2"
set "PROFILE_KEY=%~3"
set "VALUE="

:: 強力解析：取出 KEY= 後面到下一個空格前的值
for /f "tokens=*" %%L in ("!PROFILE_LINE!") do (
    set "LINE=%%L"
    set "TEMP=!LINE:*%PROFILE_KEY%==!"
    for /f "tokens=1 delims= " %%V in ("!TEMP!") do set "VALUE=%%V"
)

if defined VALUE (
    set "!PROFILE_KEY![!PROFILE_ID!]=!VALUE!"
) else (
    echo.
    echo 設定錯誤：檔位 !PROFILE_ID! 找不到 !PROFILE_KEY!=...。
    set "GPU_PROFILE_ERROR=1"
)
exit /b 0

:select_gpu_profile
set "PROFILE_ID=%~1"
set "GPU_LEVEL=!GPU_LEVEL[%PROFILE_ID%]!"
set "NGL=!NGL[%PROFILE_ID%]!"
set "CTX=!CTX[%PROFILE_ID%]!"
set "PREDICT=!PREDICT[%PROFILE_ID%]!"

:: ===== 新增：清理參數（去除多餘的 = 和後面文字）=====
call :clean_param CTX
call :clean_param PREDICT
call :clean_param NGL
exit /b 0

:clean_param
set "VAR_NAME=%~1"
set "VALUE=!%VAR_NAME%!"

:: 如果是 auto 就直接保留
if /i "!VALUE!"=="auto" (
    exit /b 0
)

:: 取出第一個數字或 -1（支援負數）
for /f "tokens=1 delims== " %%A in ("!VALUE!") do set "CLEANED=%%A"
set "%VAR_NAME%=!CLEANED!"
exit /b 0
