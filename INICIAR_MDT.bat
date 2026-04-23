@echo off
setlocal enabledelayedexpansion

:: =====================================================================
:: MDT-Direct Launcher (Estilo Microsoft Deployment Toolkit)
:: Este componente inicia o motor de implementacao localmente no PC alvo.
:: =====================================================================

title MDT ServiceDesk Launcher

:: 1. Verificar Admin
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [!] Solicitando privilegios de Administrador...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo [*] A iniciar MDT-Direct...
echo [*] Localizacao: %~dp0

:: 2. Executar Motor MDT (Start-MDT.ps1)
:: -File deve ser o caminho absoluto para o script na rede
powershell -NoProfile -ExecutionPolicy Bypass -Command "& { Set-Location '%~dp0'; . .\Start-MDT.ps1 -FromBat }"

pause
