@echo off
setlocal
title MDT Lite - Iniciando Servidor

:: Verificar se tem privilegios de administrador
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"

if '%errorlevel%' NEQ '0' (
    echo [MDT] Solicitando privilegios de administrador...
    goto UACPrompt
) else ( goto gotAdmin )

:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    set params = %*:"=""
    echo UAC.ShellExecute "cmd.exe", "/c %~s0 %params%", "", "runas", 1 >> "%temp%\getadmin.vbs"

    "%temp%\getadmin.vbs"
    del "%temp%\getadmin.vbs"
    exit /B

:gotAdmin
    pushd "%~dp0"
    cls
    echo ===================================================
    echo           MDT LITE - LANÇADOR PROFISSIONAL
    echo ===================================================
    echo.
    echo [MDT] Iniciando o servidor PowerShell...
    echo.
    
    :: Executar o PowerShell com Bypass e ignorando o perfil para maior velocidade
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-MDT.ps1" -FromBat

    if '%errorlevel%' NEQ '0' (
        echo.
        echo [ERRO] O servidor falhou ao iniciar.
        pause
    )
    popd
