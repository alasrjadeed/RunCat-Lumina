@echo off
setlocal EnableExtensions
cd /d "%~dp0..\.."
set "ROOT=%CD%"
for /f "usebackq delims=" %%v in ("%ROOT%\VERSION") do set "VERSION=%%v"
set "OUT=%ROOT%\dist\windows"
set "STAGE=%OUT%\RunCatLumina-%VERSION%"

if not exist "%ROOT%\dist" mkdir "%ROOT%\dist"
if exist "%OUT%" rmdir /S /Q "%OUT%"
mkdir "%STAGE%\resources\cat"
mkdir "%STAGE%\scripts\windows"

copy /Y "%ROOT%\main.py" "%STAGE%\" >nul
copy /Y "%ROOT%\config.json" "%STAGE%\" >nul
copy /Y "%ROOT%\requirements.txt" "%STAGE%\" >nul
copy /Y "%ROOT%\VERSION" "%STAGE%\" >nul
copy /Y "%ROOT%\LICENSE" "%STAGE%\" >nul
copy /Y "%ROOT%\README.md" "%STAGE%\" >nul
copy /Y "%ROOT%\DEPLOY.md" "%STAGE%\" >nul
copy /Y "%ROOT%\resources\cat\*.ico" "%STAGE%\resources\cat\" >nul
copy /Y "%ROOT%\resources\icon.png" "%STAGE%\resources\" >nul
copy /Y "%ROOT%\scripts\windows\*.bat" "%STAGE%\scripts\windows\" >nul

powershell -NoProfile -Command "Compress-Archive -Path '%STAGE%\*' -DestinationPath '%OUT%\RunCatLumina-%VERSION%-windows.zip' -Force"
echo Created %OUT%\RunCatLumina-%VERSION%-windows.zip
echo To deploy: unzip, then run scripts\windows\install.bat
pause
