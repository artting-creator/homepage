@echo off
setlocal

set "CHROME_PATH=C:\Program Files\Google\Chrome\Application\chrome.exe"
set "DEBUG_PROFILE=C:\temp\chrome-debug-profile"

if not exist "%CHROME_PATH%" (
  echo Chrome not found at:
  echo %CHROME_PATH%
  pause
  exit /b 1
)

if not exist "C:\temp" mkdir "C:\temp"

start "" "%CHROME_PATH%" --remote-debugging-port=9222 --remote-debugging-address=127.0.0.1 --user-data-dir="%DEBUG_PROFILE%" about:blank

echo Chrome started with remote debugging on 9222.
echo Test URL: http://127.0.0.1:9222/json/version
endlocal