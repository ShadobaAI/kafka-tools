@echo off
setlocal
node "%~dp0doctor.mjs" %*
exit /b %ERRORLEVEL%
