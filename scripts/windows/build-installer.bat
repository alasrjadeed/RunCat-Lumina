@echo off
setlocal EnableExtensions
cd /d "%~dp0..\.."
set "ROOT=%CD%"

for /f "usebackq delims=" %%v in ("%ROOT%\VERSION") do set "VERSION=%%v"

where pyinstaller >nul 2>nul
if errorlevel 1 (
  echo Installing PyInstaller...
  python -m pip install --quiet pyinstaller || goto :error
)

echo Building windowed executable...
pyinstaller --noconfirm --distpath "%ROOT%\dist\gui" --workpath "%ROOT%\build\gui" "%ROOT%\RunCat-Lumina.store.spec" || goto :error

set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if not exist "%ISCC%" set "ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe"
if not exist "%ISCC%" (
  echo Inno Setup 6 not found. Install it from https://jrsoftware.org/isdl.php
  goto :error
)

echo Building installer (version %VERSION%)...
"%ISCC%" /DAppVersion=%VERSION% "%ROOT%\packaging\windows\installer\RunCatLumina.iss" || goto :error

echo.
echo Created: dist\installer\RunCatLumina-%VERSION%-Setup.exe
goto :eof

:error
echo.
echo Build failed.
exit /b 1
