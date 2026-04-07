<#
Copyright (c) 2026 Alex Bird
MIT License

.SYNOPSIS
    Обновление сертификатов и CRL без установки компонентов.
.DESCRIPTION
    Только вызов Update-CertificatesV1_Core.ps1.
    Проверяет права администратора, при необходимости перезапускается с ними.
    Подходит для ручного запуска или планировщика.
    
    Параметр -ResultFile сохраняет результат в JSON.
    Коды возврата: 0 — успех, 1 — ошибка.
.NOTES
    Версия: 1.0
    Папка деплоя: C:\CM
    Зависит от Update-CertificatesV1_Core.ps1
#>

param(
    [string]$ResultFile
)

# ======================================================
# 0. EXIT HANDLER
# ======================================================
$script:NormalExit = $false

# Register window close handler
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -SupportEvent -Action {
    if (-not $script:NormalExit) {
        # Normal window close - exit with 0
        [Environment]::Exit(0)
    }
} | Out-Null

# ======================================================
# 1. SETUP PATHS
# ======================================================
if ($MyInvocation.MyCommand.CommandType -eq "ExternalScript") {
    $ScriptPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
} else {
    $ScriptPath = Split-Path -Parent -Path ([Environment]::GetCommandLineArgs()[0])
    if (!$ScriptPath) { $ScriptPath = "." }
}

$CoreScript = Join-Path $ScriptPath "Update-CertificatesV1_Core.ps1"

# ======================================================
# 2. CHECK ADMIN RIGHTS
# ======================================================
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Запрос прав администратора..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -File `"$PSCommandPath`" -ResultFile `"$ResultFile`"" -Verb RunAs
    exit
}

Write-Host ("="*70) -ForegroundColor Cyan
Write-Host "  ОБНОВЛЕНИЕ СЕРТИФИКАТОВ" -ForegroundColor Yellow
Write-Host "  Без установки компонентов Авест" -ForegroundColor White
Write-Host ("="*70) -ForegroundColor Cyan
Write-Host ""

# ======================================================
# 3. CHECK SCRIPT EXISTS
# ======================================================
if (-not (Test-Path $CoreScript)) {
    Write-Host "ОШИБКА: Скрипт обновления сертификатов не найден: $CoreScript" -ForegroundColor Red
    $script:NormalExit = $true
    exit 1
}

# ======================================================
# 4. RUN CERTIFICATE UPDATE
# ======================================================
Write-Host "Запуск обновления сертификатов..." -ForegroundColor Yellow
Write-Host ""

& $CoreScript -ResultFile $ResultFile
$exitCode = $LASTEXITCODE

$script:NormalExit = $true
exit $exitCode
