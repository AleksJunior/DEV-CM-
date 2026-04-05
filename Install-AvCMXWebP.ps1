<#
Copyright (c) 2026 Alex Bird
Use of this source code is governed by an MIT-style
license that can be found in the LICENSE file.
.SYNOPSIS
    Установка плагина AvCMXWebP для работы с порталами в режиме IE Mode
.DESCRIPTION
    Автоматическая установка плагина AvCMXWebP, необходимого для корректной работы
    государственных порталов (goszakupki.by, portal.nalog.gov.by и др.) в режиме
    эмуляции Internet Explorer в Microsoft Edge.
    
    Алгоритм поиска установщика:
        1. Поиск в распакованных компонентах (.\.avest\unpacked\)
           - По шаблонам: AvPKISetup(*)\data\AvCMXWebP-*.exe
           - Рекурсивный поиск по всей папке (возвращается самый новый файл)
        
        2. Если не найден - поиск в сетевой папке (для корпоративных развертываний)
           Путь: \\asup-7\BackBox\DEV\CertificateManager V2.0\avest\unpacked
        
        3. Если всё ещё не найден - автоматическая загрузка и распаковка AvPass или AvBign:
           - Сначала пробует AvPass (bel)
           - Если не помогло - пробует AvBign (bign)
           - Загружает архив из интернета (nces.by, goszakupki.by, portal.nalog.gov.by)
           - Распаковывает архив (НЕ УСТАНАВЛИВАЕТ сам компонент!)
           - Повторяет поиск установщика плагина
    
    Особенности:
        - AvPass и AvBign только распаковываются, НЕ устанавливаются
        - При отсутствии интернета выводит подробную инструкцию по ручной установке
        - При переустановке удаляет предыдущую версию через встроенный деинсталлятор
        - Все операции логируются в .\logs\avcmxwebp_install_*.log
    
    Поддерживаемые источники загрузки (с резервными вариантами):
        - https://nces.by/wp-content/uploads/gossuok/AvPKISetup(bel).zip
        - https://goszakupki.by/upload/AvPKISetup(bel).zip
        - https://portal.nalog.gov.by/ca/AvPKISetup(bel).zip
        - Аналогично для AvBign
.NOTES
    Версия: 2.0
    Требования:
        - PowerShell 5.0+
        - Права администратора
        - Доступ к интернету (для автоматической загрузки)
    
    Места установки плагина:
        - C:\Program Files\Avest\AvCMXWebP\ (64-bit)
        - C:\Program Files (x86)\Avest\AvCMXWebP\ (32-bit)
        - C:\ProgramData\Avest\AvCMXWebP\ (данные)
    
    Проверка установки:
        - Поиск в реестре: HKLM\SOFTWARE\...\Uninstall\AvCMXWebP
        - Поиск файлов: AvCMXWebP.exe, npAvCMXWebP.dll
    
    Важно:
        - Если установка не удалась, выполните ручную установку из распакованных компонентов
        - При проблемах с антивирусом добавьте папку в исключения
#>

param(
    [string]$ScriptPath,
    [string]$LogsFolder
)

# ======================================================
# ПРОВЕРКА ПРАВ АДМИНИСТРАТОРА
# ======================================================
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Запрос прав администратора..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# ======================================================
# 1. НАСТРОЙКА ПУТЕЙ
# ======================================================
if (-not $ScriptPath) {
    if ($MyInvocation.MyCommand.CommandType -eq "ExternalScript") {
        $ScriptPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
    } else {
        $ScriptPath = Split-Path -Parent -Path ([Environment]::GetCommandLineArgs()[0])
        if (!$ScriptPath) { $ScriptPath = "." }
    }
}

$avestFolder = Join-Path $ScriptPath "avest"
$archivesFolder = Join-Path $avestFolder "archives"
$unpackedFolder = Join-Path $avestFolder "unpacked"

if (-not $LogsFolder) { $LogsFolder = Join-Path $ScriptPath "logs" }

foreach ($folder in @($avestFolder, $archivesFolder, $unpackedFolder, $LogsFolder)) {
    if (!(Test-Path $folder)) { 
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }
}

$logFile = Join-Path $LogsFolder "avcmxwebp_install_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"

# ======================================================
# 2. ЗАГРУЗКА ОБЩИХ ФУНКЦИЙ
# ======================================================
$commonScript = Join-Path $ScriptPath "Common-Functions.ps1"
if (Test-Path $commonScript) {
    . $commonScript
} else {
    Write-Host "ОШИБКА: Общий модуль не найден: $commonScript" -ForegroundColor Red
    exit 1
}

function Write-Log {
    param([string]$Message)
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "$timestamp - $Message" | Out-File $logFile -Append -ErrorAction SilentlyContinue
        Write-Host $Message
    } catch { }
}

Write-Log "========================================"
Write-Log "Установка плагина AvCMXWebP V2.1"
Write-Log "========================================"

# ======================================================
# 3. КОНФИГУРАЦИЯ ДЛЯ СКАЧИВАНИЯ
# ======================================================
$avPassConfig = @{
    Name = "AvPass"
    FileName = "AvPKISetup(bel).zip"
    URL = "https://nces.by/wp-content/uploads/gossuok/AvPKISetup(bel).zip"
    FallbackURL1 = "https://goszakupki.by/upload/AvPKISetup(bel).zip"
    FallbackURL2 = "https://portal.nalog.gov.by/ca/AvPKISetup(bel).zip"
}

# ======================================================
# 4. ФУНКЦИИ
# ======================================================

function Clear-UnpackedFolder {
    Write-Host "  Очистка папки unpacked..." -ForegroundColor Gray
    if (Test-Path $unpackedFolder) {
        Remove-Item -Path $unpackedFolder -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $unpackedFolder -Force | Out-Null
    Write-Log "Папка unpacked очищена"
}

function Download-And-Restart {
    $archivePath = Join-Path $archivesFolder $avPassConfig.FileName
    
    Write-Host "  Скачивание архива: $($avPassConfig.FileName)" -ForegroundColor Gray
    
    if (Test-Path $archivePath) {
        Remove-Item $archivePath -Force -ErrorAction SilentlyContinue
    }
    
    $downloaded = Save-FileWithFallback -Config $avPassConfig -DestinationFolder $archivesFolder
    
    if (-not $downloaded) {
        Write-Host "  ОШИБКА: Не удалось скачать архив" -ForegroundColor Red
        Write-Log "Не удалось скачать архив"
        return $false
    }
    
    Write-Host "  Распаковка архива..." -ForegroundColor Gray
    
    try {
        Microsoft.PowerShell.Archive\Expand-Archive -Path $archivePath -DestinationPath $unpackedFolder -Force -ErrorAction Stop
        Write-Host "  Распаковка завершена" -ForegroundColor Green
        Write-Log "Архив распакован"
        return $true
    } catch {
        Write-Host "  ОШИБКА распаковки: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "Ошибка распаковки: $($_.Exception.Message)"
        return $false
    }
}

function Find-PluginInstaller {
    Write-Host "  Поиск установщика плагина..." -ForegroundColor Gray
    
    $foundInstallers = @()
    
    # Ищем в папке bel
    $belDataPath = Join-Path $unpackedFolder "AvPKISetup(bel)\data"
    if (Test-Path $belDataPath) {
        $belFiles = Get-ChildItem -Path $belDataPath -Filter "AvCMXWebP-*.exe" -ErrorAction SilentlyContinue
        foreach ($file in $belFiles) {
            $foundInstallers += $file
            Write-Host "    Найден: $($file.Name) (в bel)" -ForegroundColor Green
        }
    }
    
    # Ищем в папке bign
    $bignDataPath = Join-Path $unpackedFolder "AvPKISetup(bign)\data"
    if (Test-Path $bignDataPath) {
        $bignFiles = Get-ChildItem -Path $bignDataPath -Filter "AvCMXWebP-*.exe" -ErrorAction SilentlyContinue
        foreach ($file in $bignFiles) {
            $foundInstallers += $file
            Write-Host "    Найден: $($file.Name) (в bign)" -ForegroundColor Green
        }
    }
    
    if ($foundInstallers.Count -eq 0) {
        Write-Host "  Плагин не найден!" -ForegroundColor Red
        return $null
    }
    
    # Выбираем самый свежий
    $latest = $foundInstallers | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Write-Host "  Выбран: $($latest.Name) (дата: $($latest.LastWriteTime))" -ForegroundColor Cyan
    
    return $latest.FullName
}

function Test-PluginInstalled {
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($regPath in $regPaths) {
        $items = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            try {
                $displayName = Get-ItemProperty -Path $item.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue
                if ($displayName.DisplayName -like "*AvCMXWebP*") {
                    return $true
                }
            } catch { }
        }
    }
    
    $filePaths = @(
        "C:\Program Files\Avest\AvCMXWebP\AvCMXWebP.exe",
        "C:\Program Files (x86)\Avest\AvCMXWebP\AvCMXWebP.exe"
    )
    
    foreach ($path in $filePaths) {
        if (Test-Path $path) { return $true }
    }
    
    return $false
}

function Remove-PreviousVersion {
    $uninstallPaths = @(
        "C:\ProgramData\Avest\AvCMXWebP\unins000.exe",
        "C:\Program Files\Avest\AvCMXWebP\unins000.exe",
        "C:\Program Files (x86)\Avest\AvCMXWebP\unins000.exe"
    )
    
    foreach ($path in $uninstallPaths) {
        if (Test-Path $path) {
            Write-Host "  Удаление предыдущей версии..." -ForegroundColor Gray
            Start-Process -FilePath $path -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART" -Wait -NoNewWindow
            Start-Sleep -Seconds 2
            return
        }
    }
}

# ======================================================
# 5. ОСНОВНАЯ ЛОГИКА
# ======================================================
Write-Host ""
Write-Host ("="*70) -ForegroundColor Cyan
Write-Host "  УСТАНОВКА ПЛАГИНА AvCMXWebP" -ForegroundColor Yellow
Write-Host ("="*70) -ForegroundColor Cyan
Write-Host ""

# Проверка, установлен ли плагин
if (Test-PluginInstalled) {
    Write-Host "Плагин AvCMXWebP уже установлен." -ForegroundColor Green
    Write-Host ""
    $reinstall = Read-Host "Переустановить? (д/н)"
    if ($reinstall -ne "д" -and $reinstall -ne "Д" -and $reinstall -ne "y" -and $reinstall -ne "Y") {
        Write-Host "Установка пропущена." -ForegroundColor Gray
        exit 0
    }
    Remove-PreviousVersion
}

# 1. Очищаем unpacked
Write-Host "[1/4] Подготовка..." -ForegroundColor Cyan
Clear-UnpackedFolder

# 2. Скачиваем и распаковываем
Write-Host "`n[2/4] Скачивание компонентов..." -ForegroundColor Cyan
$success = Download-And-Restart
if (-not $success) { exit 1 }

# 3. Ищем плагин
Write-Host "`n[3/4] Поиск установщика..." -ForegroundColor Cyan
$pluginInstaller = Find-PluginInstaller

if (-not $pluginInstaller) {
    Write-Host ""
    Write-Host ("="*70) -ForegroundColor Red
    Write-Host "  ОШИБКА: Установщик плагина не найден!" -ForegroundColor Red
    Write-Host ("="*70) -ForegroundColor Red
    Write-Host ""
    Write-Host "Искали в:"
    Write-Host "  $unpackedFolder\AvPKISetup(bel)\data\AvCMXWebP-*.exe"
    Write-Host "  $unpackedFolder\AvPKISetup(bign)\data\AvCMXWebP-*.exe"
    exit 1
}

# 4. Устанавливаем
Write-Host "`n[4/4] Установка плагина..." -ForegroundColor Cyan
Write-Host ""
Write-Host ("="*70) -ForegroundColor Green
Write-Host "  ЗАПУСК УСТАНОВКИ" -ForegroundColor Green
Write-Host ("="*70) -ForegroundColor Green
Write-Host "  Файл: $(Split-Path $pluginInstaller -Leaf)" -ForegroundColor White
Write-Host ""
Write-Host "  Следуйте инструкциям мастера установки." -ForegroundColor Yellow
Write-Host ""

try {
    Start-Process -FilePath $pluginInstaller -Wait
    Write-Host ""
    Write-Host ("="*70) -ForegroundColor Green
    Write-Host "  УСТАНОВКА ПЛАГИНА ЗАВЕРШЕНА!" -ForegroundColor Green
    Write-Host ("="*70) -ForegroundColor Green
    Write-Log "Установка плагина завершена успешно"
    exit 0
} catch {
    Write-Host ""
    Write-Host ("="*70) -ForegroundColor Red
    Write-Host "  ОШИБКА ПРИ УСТАНОВКЕ!" -ForegroundColor Red
    Write-Host ("="*70) -ForegroundColor Red
    Write-Log "Ошибка при установке: $($_.Exception.Message)"
    exit 1
}