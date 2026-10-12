@echo off
setlocal EnableExtensions
set "APPDIR=%LOCALAPPDATA%\RunCatLumina"
set "STARTMENU=%APPDATA%\Microsoft\Windows\Start Menu\Programs\RunCat Lumina.lnk"
set "STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\RunCat Lumina.lnk"

echo Uninstalling RunCat Lumina
if exist "%STARTMENU%" del /F /Q "%STARTMENU%"
if exist "%STARTUP%" del /F /Q "%STARTUP%"
if exist "%APPDIR%" (
  echo Close RunCat Lumina if it is running, then press a key.
  pause
  rmdir /S /Q "%APPDIR%"
)
echo Removed.
pause
