#enable_scripts.ps1

<#
.SYNOPSIS
    Разрешение выполнения PowerShell сценариев
.DESCRIPTION
    Устанавливает политику выполнения RemoteSigned
.NOTES
    Требует прав администратора.
#>

# ======================================================
# ЗАПРОС ПРАВ АДМИНИСТРАТОРА
# ======================================================
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Запрос прав администратора..." -ForegroundColor Yellow
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
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

# Если политика уже RemoteSigned
if ($currentPolicy -eq "RemoteSigned") {
    Write-Host "Политика уже настроена правильно." -ForegroundColor Green
    Write-Host ""
    Write-Host "Нажмите любую клавишу для выхода..."
    pause
    exit 0
}

# Если политика Bypass (самая свободная) - сообщаем что всё ок
if ($currentPolicy -eq "Bypass") {
    Write-Host "Политика Bypass - выполнение сценариев РАЗРЕШЕНО." -ForegroundColor Green
    Write-Host "Ограничений нет. Можете запускать любой скрипт." -ForegroundColor Green
    Write-Host ""
    Write-Host "При желании можно установить RemoteSigned (более безопасно):" -ForegroundColor Yellow
    Write-Host "  Set-ExecutionPolicy RemoteSigned -Force" -ForegroundColor White
    Write-Host ""
    Write-Host "Нажмите любую клавишу для выхода..."
    pause
    exit 0
}

# Установка RemoteSigned для остальных случаев
Write-Host "Установка политики RemoteSigned..." -ForegroundColor Gray

try {
    # Пробуем установить через Group Policy (обход ошибки)
    $regPath = "HKLM:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell"
    Set-ItemProperty -Path $regPath -Name "ExecutionPolicy" -Value "RemoteSigned" -Force -ErrorAction Stop
    Write-Host "Политика установлена через реестр" -ForegroundColor Green
} catch {
    try {
        Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force -ErrorAction Stop
        Write-Host "Политика установлена через Set-ExecutionPolicy" -ForegroundColor Green
    } catch {
        try {
            Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
            Write-Host "Политика установлена для текущего пользователя" -ForegroundColor Green
        } catch {
            Write-Host ""
            Write-Host "ОШИБКА: Не удалось установить политику" -ForegroundColor Red
            Write-Host ""
            Write-Host "Выполните вручную (от имени администратора):" -ForegroundColor Yellow
            Write-Host ("="*50) -ForegroundColor White
            Write-Host "Set-ExecutionPolicy RemoteSigned -Force" -ForegroundColor White
            Write-Host ("="*50) -ForegroundColor White
        }
    }
}

$newPolicy = Get-ExecutionPolicy
Write-Host ""
Write-Host "Текущая политика: $newPolicy" -ForegroundColor $(if ($newPolicy -eq "RemoteSigned") { "Green" } else { "Yellow" })

Write-Host ""
Write-Host "Нажмите любую клавишу для выхода..."
pause