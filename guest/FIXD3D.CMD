@echo off
echo Speed fix for Direct3D games that run through WineD3D:
echo turns off WineD3D's error checking, which otherwise makes the game wait on the
echo graphics pass-through thousands of times per second (big FPS drop).
echo.
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v WINEDEBUG /t REG_SZ /d -all /f
echo.
echo Done. Now shut XP down (Start, Turn Off Computer, Turn Off) and start it again.
echo (Do not use Restart: it currently crashes the VM. See Known issues.)
pause
