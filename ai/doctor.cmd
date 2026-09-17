@echo off
setlocal

if "%~1"=="" if /I "%CD%\"=="%~dp0" goto workspace
node "%~dp0doctor.mjs" --human %*
goto finish

:workspace
node "%~dp0doctor.mjs" --human --project-root "%~dp0..\.."

:finish
set "DOCTOR_EXIT_CODE=%ERRORLEVEL%"
echo.
if /I not "%KAFKA_AI_NO_PAUSE%"=="1" pause
exit /b %DOCTOR_EXIT_CODE%
