@echo off
setlocal
if not defined KAFKA_OPENVIKING_STATE_DIR (
  echo KAFKA_OPENVIKING_STATE_DIR is required for the local OpenViking index. 1>&2
  exit /b 2
)
node "%~dp0openviking\git-sync.mjs" --workspace-root "%~dp0..\.." --state-dir "%KAFKA_OPENVIKING_STATE_DIR%" --rebuild
exit /b %ERRORLEVEL%
