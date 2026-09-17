@echo off
setlocal
node "%~dp0update-openviking.mjs" %*
set "UPDATE_EXIT_CODE=%ERRORLEVEL%"

echo.
if /I not "%KAFKA_AI_NO_PAUSE%"=="1" pause
exit /b %UPDATE_EXIT_CODE%
