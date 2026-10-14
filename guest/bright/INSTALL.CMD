@echo off
echo Installing the brightness slider (the sun icon next to the clock).
if not exist "%ProgramFiles%\Brightness" mkdir "%ProgramFiles%\Brightness"
copy /y "%~d0\BRIGHT.EXE" "%ProgramFiles%\Brightness\bright.exe" >nul
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v Brightness /t REG_SZ /d "\"%ProgramFiles%\Brightness\bright.exe\"" /f >nul
start "" "%ProgramFiles%\Brightness\bright.exe"
echo.
echo Done. Click the sun icon next to the clock. It starts with Windows from now on.
pause
