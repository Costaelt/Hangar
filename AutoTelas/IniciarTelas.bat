@echo off
rem AutoTelas - chamado pelo atalho na pasta Inicializar (shell:startup)
start "" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0IniciarTelas.ps1"
