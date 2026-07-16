@echo off
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -Command "$p='%~dp0HumanPinyinTyper.ps1'; $code=Get-Content -Raw -Encoding UTF8 -LiteralPath $p; Invoke-Expression $code"
