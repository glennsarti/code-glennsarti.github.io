@ECHO OFF

for /f "skip=1 tokens=3" %%k in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v EditionID') do (
  set Edition=%%k
)
Echo Windows_Edition_external=%Edition%
