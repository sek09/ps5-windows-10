@echo off
set K=HKLM\SYSTEM\CurrentControlSet\Hardware Profiles\Current\System\CurrentControlSet\Services\vmx_svga\Device0
reg add "%K%" /v DefaultSettings.XResolution /t REG_DWORD /d 1920 /f
reg add "%K%" /v DefaultSettings.YResolution /t REG_DWORD /d 1080 /f
reg add "%K%" /v DefaultSettings.BitsPerPel /t REG_DWORD /d 32 /f
for /f "tokens=*" %%G in ('reg query HKLM\SYSTEM\CurrentControlSet\Control\Video') do (
  reg add "%%G\0000" /v DefaultSettings.XResolution /t REG_DWORD /d 1920 /f
  reg add "%%G\0000" /v DefaultSettings.YResolution /t REG_DWORD /d 1080 /f
  reg add "%%G\0000" /v DefaultSettings.BitsPerPel /t REG_DWORD /d 32 /f
)
reg query "%K%" > COM1
echo RESDONE > COM1
shutdown -r -t 3
