<#
.SYNOPSIS
    Разрешение выполнения PowerShell сценариев.
.DESCRIPTION
    Устанавливает политику выполнения Unrestricted (LocalMachine или CurrentUser).
    Также разблокирует все .ps1 в папке скрипта (Unblock-File).
    Требует прав администратора.
.NOTES
    Версия: 1.0
    Папка деплоя: C:\CM
#>

# ======================================================
# ЗАПРОС ПРАВ АДМИНИСТРАТОРА
# ======================================================
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Запрос прав администратора..." -ForegroundColor Yellow
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -File `"$PSCommandPath`""
    exit
}

# ======================================================
# РАЗБЛОКИРОВКА СКРИПТОВ
# ======================================================
Write-Host "Разблокировка скриптов..." -ForegroundColor Yellow
Get-ChildItem -Path $PSScriptRoot -Filter "*.ps1" -Recurse | Unblock-File -ErrorAction SilentlyContinue
Write-Host "Готово!" -ForegroundColor Green
Write-Host ""

# ======================================================
# ОСНОВНАЯ ЛОГИКА
# ======================================================
Write-Host ("="*60) -ForegroundColor Cyan
Write-Host "  РАЗРЕШЕНИЕ ВЫПОЛНЕНИЯ POWERSHELL СЦЕНАРИЕВ" -ForegroundColor Cyan
Write-Host ("="*60) -ForegroundColor Cyan
Write-Host ""

$currentPolicy = Get-ExecutionPolicy
Write-Host "Текущая политика: $currentPolicy" -ForegroundColor Yellow

# Если политика уже Unrestricted
if ($currentPolicy -eq "Unrestricted") {
    Write-Host "Политика уже настроена правильно (Unrestricted)." -ForegroundColor Green
    Write-Host ""
    Write-Host "Нажмите любую клавишу для выхода..."
    pause
    exit 0
}

# Если политика RemoteSigned или Bypass - сообщаем что всё ок
if ($currentPolicy -eq "RemoteSigned" -or $currentPolicy -eq "Bypass") {
    Write-Host "Политика $currentPolicy - выполнение сценариев РАЗРЕШЕНО." -ForegroundColor Green
    Write-Host ""
    Write-Host "Для переключения на Unrestricted выполните:" -ForegroundColor Yellow
    Write-Host "  Set-ExecutionPolicy Unrestricted -Force" -ForegroundColor White
    Write-Host ""
    Write-Host "Нажмите любую клавишу для выхода..."
    pause
    exit 0
}

# Установка Unrestricted для остальных случаев (Restricted, AllSigned)
Write-Host "Установка политики Unrestricted..." -ForegroundColor Gray

try {
    Set-ExecutionPolicy Unrestricted -Scope LocalMachine -Force -ErrorAction Stop
    Write-Host "Политика установлена" -ForegroundColor Green
} catch {
    try {
        Set-ExecutionPolicy Unrestricted -Scope CurrentUser -Force -ErrorAction Stop
        Write-Host "Политика установлена для текущего пользователя" -ForegroundColor Green
    } catch {
        Write-Host ""
        Write-Host "ОШИБКА: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        Write-Host "Выполните вручную (от имени администратора):" -ForegroundColor Yellow
        Write-Host ("="*50) -ForegroundColor White
        Write-Host "Set-ExecutionPolicy Unrestricted -Force" -ForegroundColor White
        Write-Host ("="*50) -ForegroundColor White
    }
}

$newPolicy = Get-ExecutionPolicy
Write-Host ""
Write-Host "Текущая политика: $newPolicy" -ForegroundColor $(if ($newPolicy -eq "Unrestricted") { "Green" } else { "Yellow" })

Write-Host ""
Write-Host "Нажмите любую клавишу для выхода..."
pause