@echo off
chcp 65001 >nul

echo ======================
echo.
echo Local http Serve (Official)
echo.
echo ======================
echo.
npx serve@latest -l 8080 --no-clipboard
pause
