@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" %*
set "FASTINK_BUILD_EXIT=%ERRORLEVEL%"
if not "%FASTINK_BUILD_EXIT%"=="0" echo Build failed. See the error above.
pause
exit /b %FASTINK_BUILD_EXIT%
