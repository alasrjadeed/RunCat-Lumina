@echo off
setlocal EnableExtensions
cd /d "%~dp0..\.."
set "ROOT=%CD%"

where py >nul 2>nul
if %ERRORLEVEL%==0 (
  set "PY=py -3"
) else (
  where python >nul 2>nul
  if %ERRORLEVEL%==0 (
    set "PY=python"
  ) else (
    echo Python 3 is required. Install from https://www.python.org/downloads/
    echo Enable "Add python.exe to PATH" during setup.
    pause
    exit /b 1
  )
)

if not exist "%ROOT%\.venv\Scripts\python.exe" (
  echo Creating virtual environment...
  %PY% -m venv "%ROOT%\.venv"
)
"%ROOT%\.venv\Scripts\python.exe" -m pip install -q --upgrade pip
"%ROOT%\.venv\Scripts\python.exe" -m pip install -q -r "%ROOT%\requirements.txt"
"%ROOT%\.venv\Scripts\python.exe" "%ROOT%\main.py"
