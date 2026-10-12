@echo off
setlocal EnableExtensions
cd /d "%~dp0..\.."
set "ROOT=%CD%"
set "APPDIR=%LOCALAPPDATA%\RunCatLumina"
set "STARTMENU=%APPDATA%\Microsoft\Windows\Start Menu\Programs"
set "STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"

where py >nul 2>nul
if %ERRORLEVEL%==0 (
  set "PY=py -3"
) else (
  where python >nul 2>nul
  if %ERRORLEVEL%==0 (
    set "PY=python"
  ) else (
    echo Python 3 is required. Install from https://www.python.org/downloads/
    pause
    exit /b 1
  )
)

echo Installing RunCat Lumina to %APPDIR%
if not exist "%APPDIR%" mkdir "%APPDIR%"
if not exist "%APPDIR%\resources\cat" mkdir "%APPDIR%\resources\cat"
if not exist "%APPDIR%\scripts\windows" mkdir "%APPDIR%\scripts\windows"

copy /Y "%ROOT%\main.py" "%APPDIR%\main.py" >nul
copy /Y "%ROOT%\config.json" "%APPDIR%\config.json" >nul
copy /Y "%ROOT%\requirements.txt" "%APPDIR%\requirements.txt" >nul
copy /Y "%ROOT%\VERSION" "%APPDIR%\VERSION" >nul
copy /Y "%ROOT%\LICENSE" "%APPDIR%\LICENSE" >nul
copy /Y "%ROOT%\resources\cat\*.ico" "%APPDIR%\resources\cat\" >nul
copy /Y "%ROOT%\scripts\windows\start.bat" "%APPDIR%\scripts\windows\start.bat" >nul
copy /Y "%ROOT%\scripts\windows\uninstall.bat" "%APPDIR%\scripts\windows\uninstall.bat" >nul

if not exist "%APPDIR%\.venv\Scripts\python.exe" (
  %PY% -m venv "%APPDIR%\.venv"
)
"%APPDIR%\.venv\Scripts\python.exe" -m pip install -q --upgrade pip
"%APPDIR%\.venv\Scripts\python.exe" -m pip install -q -r "%APPDIR%\requirements.txt"

powershell -NoProfile -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut('%STARTMENU%\RunCat Lumina.lnk'); $s.TargetPath = '%APPDIR%\scripts\windows\start.bat'; $s.WorkingDirectory = '%APPDIR%'; $s.WindowStyle = 7; $s.Description = 'RunCat Lumina'; $s.Save()"

set /p AUTOSTART=Start RunCat Lumina when Windows starts? [Y/N]: 
if /I "%AUTOSTART%"=="Y" (
  powershell -NoProfile -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut('%STARTUP%\RunCat Lumina.lnk'); $s.TargetPath = '%APPDIR%\scripts\windows\start.bat'; $s.WorkingDirectory = '%APPDIR%'; $s.WindowStyle = 7; $s.Description = 'RunCat Lumina'; $s.Save()"
)

echo.
echo Installed.
echo Start Menu: RunCat Lumina
echo Run now: %APPDIR%\scripts\windows\start.bat
pause
