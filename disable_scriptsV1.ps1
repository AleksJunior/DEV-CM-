<#
.SYNOPSIS
    Отключение выполнения PowerShell сценариев.
.DESCRIPTION
    Устанавливает политику выполнения Restricted (запрет любых .ps1).
    Требует прав администратора.
    ВНИМАНИЕ: Менеджер сертификатов перестанет работать!
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
# ПОДТВЕРЖДЕНИЕ
# ======================================================
Write-Host ("="*60) -ForegroundColor Red
Write-Host "  ВНИМАНИЕ!" -ForegroundColor Red
Write-Host ("="*60) -ForegroundColor Red
Write-Host ""
Write-Host "Это действие ОТКЛЮЧИТ выполнение всех PowerShell сценариев." -ForegroundColor Yellow
Write-Host "После этого вы НЕ СМОЖЕТЕ запускать .ps1 файлы." -ForegroundColor Yellow
Write-Host ""
Write-Host "Менеджер сертификатов перестанет работать." -ForegroundColor Red
Write-Host ""
Write-Host "Продолжить? (д/н)" -ForegroundColor Cyan

$confirmation = Read-Host
if ($confirmation -ne "д" -and $confirmation -ne "Д" -and $confirmation -ne "y" -and $confirmation -ne "Y") {
    Write-Host "Операция отменена." -ForegroundColor Gray
    pause
    exit 0
}

# ======================================================
# ОСНОВНАЯ ЛОГИКА
# ======================================================
Write-Host ""
Write-Host ("="*60) -ForegroundColor Cyan
Write-Host "  ОТКЛЮЧЕНИЕ ВЫПОЛНЕНИЯ POWERSHELL СЦЕНАРИЕВ" -ForegroundColor Cyan
Write-Host ("="*60) -ForegroundColor Cyan
Write-Host ""

$currentPolicy = Get-ExecutionPolicy
Write-Host "Текущая политика: $currentPolicy" -ForegroundColor Yellow

# Если уже Restricted
if ($currentPolicy -eq "Restricted") {
    Write-Host "Политика уже установлена в Restricted (сценарии запрещены)." -ForegroundColor Green
    Write-Host ""
    Write-Host "Нажмите любую клавишу для выхода..."
    pause
    exit 0
}

# Установка Restricted
Write-Host "Установка политики Restricted..." -ForegroundColor Gray

try {
    Set-ExecutionPolicy Restricted -Scope LocalMachine -Force -ErrorAction Stop
    Write-Host "Политика установлена" -ForegroundColor Green
} catch {
    try {
        Set-ExecutionPolicy Restricted -Scope CurrentUser -Force -ErrorAction Stop
        Write-Host "Политика установлена для текущего пользователя" -ForegroundColor Green
    } catch {
        Write-Host ""
        Write-Host "ОШИБКА: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        Write-Host "Выполните вручную (от имени администратора):" -ForegroundColor Yellow
        Write-Host ("="*50) -ForegroundColor White
        Write-Host "Set-ExecutionPolicy Restricted -Force" -ForegroundColor White
        Write-Host ("="*50) -ForegroundColor White
        pause
        exit 1
    }
}

$newPolicy = Get-ExecutionPolicy
Write-Host ""
Write-Host ("="*60) -ForegroundColor Red
Write-Host "  ГОТОВО!" -ForegroundColor Red
Write-Host "  Новая политика: $newPolicy" -ForegroundColor Red
Write-Host ("="*60) -ForegroundColor Red
Write-Host ""
Write-Host "ВЫПОЛНЕНИЕ СЦЕНАРИЕВ ОТКЛЮЧЕНО" -ForegroundColor Red
Write-Host ""

Write-Host "Нажмите любую клавишу для выхода..."
pause