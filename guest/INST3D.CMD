@echo off
rem qemu-3dfx guest side: pass-through driver + Glide DLLs into system32, then start the driver
set D=%~dp03DFX
copy /y "%D%\fxptl.sys" %SystemRoot%\system32\drivers\
copy /y "%D%\glide.dll" %SystemRoot%\system32\
copy /y "%D%\glide2x.dll" %SystemRoot%\system32\
copy /y "%D%\glide3x.dll" %SystemRoot%\system32\
"%D%\instdrv.exe" > COM1
if exist C:\OA\openarena.exe copy /y "%D%\opengl32.dll" C:\OA\
echo INST3DDONE > COM1
