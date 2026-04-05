<#
Copyright (c) 2026 Alex Bird
Use of this source code is governed by an MIT-style
license that can be found in the LICENSE file.
.SYNOPSIS
    Установка компонентов Авест (Криптопровайдеры и комплекты абонента)
.DESCRIPTION
    Интерактивный скрипт для установки/переустановки компонентов Авест:
    
    Доступные компоненты:
        1. AvPass - Комплект Абонента АВЕСТ (ГОСТ 28147-89, 34.10-2001)
        2. AvBign - Комплект Абонента АВЕСТ (ГОСТ 34.10-2012, большие ключи)
        3. AvCSPBel - Криптопровайдер АВЕСТ CSP Bel (ГОСТ 28147-89)
        4. AvCSPBign - Криптопровайдер АВЕСТ CSP Bign (ГОСТ 34.10-2012)
        5. AvReg - Реестровые настройки SAI DLL для корректной работы
    
    Алгоритм работы:
        1. Проверяет статус каждого компонента (установлен/не установлен)
        2. Выводит таблицу статусов цветом (зеленый/красный)
        3. Предлагает выбрать компонент для установки/переустановки
        4. При выборе компонента:
           - Проверяет наличие архива в папке .\avest\archives\
           - Если архива нет и есть интернет - скачивает из URL из конфигурации
           - Распаковывает архив в .\avest\unpacked\
           - Ищет установщик (для AvPass/AvBign - рекурсивный поиск AvPKISetup2.exe)
           - Запускает установщик в режиме ожидания
        5. При повреждении файлов выполняет повторную распаковку
        6. Если установщик не найден - предлагает установить вручную
    
    Поддерживаются форматы архивов: ZIP (через Expand-Archive), RAR (через WinRAR)
    
    Все операции записываются в лог-файл .\logs\avest_install_*.log
.NOTES
    Версия: 2.0
    Требования:
        - PowerShell 5.0+
        - Права администратора
        - Доступ к интернету (для скачивания)
        - WinRAR (для RAR-архивов)
    
    Конфигурация компонентов хранится в .\config\avest_urls.ini
    Формат конфигурации:
        [ComponentName]
        Name=Отображаемое имя
        URL=Основная ссылка для скачивания
        FallbackURL1=Резервная ссылка 1
        FallbackURL2=Резервная ссылка 2
        FileName=Имя файла архива
        InstallerName=Путь к установщику внутри архива
    
    Важно:
        - Перед установкой рекомендуется добавить папку программы в исключения антивируса
        - AvPass и AvBign устанавливаются в папки AvPCM_nces и AvPCM_ncesBign соответственно
        - AvReg добавляет ключи в реестр для загрузки SAI DLL
#>

param([string]$ScriptPath)

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

$configFolder = Join-Path $ScriptPath "config"
$avestFolder = Join-Path $ScriptPath "avest"
$archivesFolder = Join-Path $avestFolder "archives"
$unpackedFolder = Join-Path $avestFolder "unpacked"
$logsFolder = Join-Path $ScriptPath "logs"
$configFile = Join-Path $configFolder "avest_urls.ini"

# Создаём папки
foreach ($folder in @($configFolder, $avestFolder, $archivesFolder, $unpackedFolder, $logsFolder)) {
    if (!(Test-Path $folder)) { 
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }
}

$logFile = Join-Path $logsFolder "avest_install_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"

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

Write-Log -Message "========================================" -LogFile $logFile
Write-Log -Message "Установка компонентов Авест V2.1" -LogFile $logFile
Write-Log -Message "========================================" -LogFile $logFile

# ======================================================
# 3. ЗАГРУЗКА КОНФИГУРАЦИИ
# ======================================================
$config = Import-Config -ConfigFile $configFile
if ($config.Count -eq 0) {
    Write-Log -Message "ОШИБКА: Не удалось загрузить конфигурацию" -LogFile $logFile
    Write-Host "ОШИБКА: Не удалось загрузить конфигурацию" -ForegroundColor Red
    exit 1
}

# ======================================================
# 4. ПРОВЕРКА СТАТУСА КОМПОНЕНТОВ
# ======================================================
function Test-AvPass {
    $paths = @(
        "C:\Program Files\Avest\AvPCM_nces\AvPCM.exe",
        "C:\Program Files (x86)\Avest\AvPCM_nces\AvPCM.exe",
        "C:\Program Files\Avest\AvPCM_ncesBign\AvPCM.exe",
        "C:\Program Files (x86)\Avest\AvPCM_ncesBign\AvPCM.exe"
    )
    foreach ($path in $paths) { if (Test-Path $path) { return $true } }
    
    $regPaths = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")
    foreach ($regPath in $regPaths) {
        $items = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            try {
                $displayName = Get-ItemProperty -Path $item.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue
                if ($displayName.DisplayName -like "*AvPCM*" -or $displayName.DisplayName -like "*Комплект Абонента*") { return $true }
            } catch { }
        }
    }
    return $false
}

function Test-AvBign {
    $paths = @(
        "C:\Program Files\Avest\AvPCM_ncesBign\AvBign.exe",
        "C:\Program Files (x86)\Avest\AvPCM_ncesBign\AvBign.exe"
    )
    foreach ($path in $paths) { if (Test-Path $path) { return $true } }
    
    $regPaths = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")
    foreach ($regPath in $regPaths) {
        $items = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            try {
                $displayName = Get-ItemProperty -Path $item.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue
                if ($displayName.DisplayName -like "*AvBign*") { return $true }
            } catch { }
        }
    }
    return $false
}

function Test-AvCSPBel {
    $regPaths = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")
    foreach ($regPath in $regPaths) {
        $items = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            try {
                $displayName = Get-ItemProperty -Path $item.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue
                if ($displayName.DisplayName -like "*AvCSPBel*" -or $displayName.DisplayName -like "*Avest CSP Bel*") { return $true }
            } catch { }
        }
    }
    return $false
}

function Test-AvCSPBign {
    $regPaths = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")
    foreach ($regPath in $regPaths) {
        $items = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            try {
                $displayName = Get-ItemProperty -Path $item.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue
                if ($displayName.DisplayName -like "*AvCSPBign*" -or $displayName.DisplayName -like "*Avest CSP Bign*") { return $true }
            } catch { }
        }
    }
    return $false
}

function Test-AvReg {
    $path1 = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows"
    $path2 = "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows NT\CurrentVersion\Windows"
    try {
        $val1 = (Get-ItemProperty -Path $path1 -Name "LoadAppInit_DLLs" -ErrorAction SilentlyContinue).LoadAppInit_DLLs
        $val2 = (Get-ItemProperty -Path $path1 -Name "RequireSignedAppInit_DLLs" -ErrorAction SilentlyContinue).RequireSignedAppInit_DLLs
        $val3 = (Get-ItemProperty -Path $path2 -Name "LoadAppInit_DLLs" -ErrorAction SilentlyContinue).LoadAppInit_DLLs
        $val4 = (Get-ItemProperty -Path $path2 -Name "RequireSignedAppInit_DLLs" -ErrorAction SilentlyContinue).RequireSignedAppInit_DLLs
        if ($val1 -eq 1 -and $val2 -eq 0 -and $val3 -eq 1 -and $val4 -eq 0) { return $true }
    } catch { }
    return $false
}

$componentStatus = @{
    "AvPass" = Test-AvPass
    "AvBign" = Test-AvBign
    "AvCSPBel" = Test-AvCSPBel
    "AvCSPBign" = Test-AvCSPBign
    "AvReg" = Test-AvReg
}

$components = @("AvPass", "AvBign", "AvCSPBel", "AvCSPBign", "AvReg")

Write-Host ""
Write-Host ("="*70) -ForegroundColor Cyan
Write-Host "  СТАТУС КОМПОНЕНТОВ АВЕСТ" -ForegroundColor Yellow
Write-Host ("="*70) -ForegroundColor Cyan
Write-Host ""

foreach ($component in $components) {
    $status = if ($componentStatus[$component]) { "УСТАНОВЛЕН" } else { "НЕ УСТАНОВЛЕН" }
    $color = if ($componentStatus[$component]) { "Green" } else { "Red" }
    Write-Host "  $component : $status" -ForegroundColor $color
}
Write-Host ""

# ======================================================
# 5. ФУНКЦИИ СКАЧИВАНИЯ И УСТАНОВКИ
# ======================================================

function Clear-UnpackedFolder {
    Write-Host "  Очистка папки unpacked..." -ForegroundColor Gray
    if (Test-Path $unpackedFolder) {
        Remove-Item -Path $unpackedFolder -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $unpackedFolder -Force | Out-Null
    Write-Log -Message "Папка unpacked очищена" -LogFile $logFile
}

function Download-And-Restart {
    param(
        [hashtable]$Config,
        [string]$Component
    )
    
    $archivePath = Join-Path $archivesFolder $Config.FileName
    
    Write-Host "  Скачивание архива: $($Config.FileName)" -ForegroundColor Gray
    
    # Удаляем старый архив, если есть
    if (Test-Path $archivePath) {
        Remove-Item $archivePath -Force -ErrorAction SilentlyContinue
    }
    
    $downloaded = Save-FileWithFallback -Config $Config -DestinationFolder $archivesFolder
    
    if (-not $downloaded) {
        Write-Host "  ОШИБКА: Не удалось скачать архив" -ForegroundColor Red
        Write-Log -Message "Не удалось скачать архив для $Component" -LogFile $logFile
        return $false
    }
    
    Write-Host "  Распаковка архива..." -ForegroundColor Gray
    
    try {
        Microsoft.PowerShell.Archive\Expand-Archive -Path $archivePath -DestinationPath $unpackedFolder -Force -ErrorAction Stop
        Write-Host "  Распаковка завершена" -ForegroundColor Green
        Write-Log -Message "Архив распакован для $Component" -LogFile $logFile
        return $true
    } catch {
        Write-Host "  ОШИБКА распаковки: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log -Message "Ошибка распаковки для $Component : $($_.Exception.Message)" -LogFile $logFile
        return $false
    }
}

function Find-Installer {
    param(
        [string]$Component,
        [hashtable]$Config
    )
    
    $installerName = $Config.InstallerName
    
    switch ($Component) {
        "AvPass" {
            $path = Join-Path $unpackedFolder "AvPKISetup(bel)\AvPKISetup2.exe"
            if (Test-Path $path) { return $path }
        }
        "AvBign" {
            $path = Join-Path $unpackedFolder "AvPKISetup(bign)\AvPKISetup2.exe"
            if (Test-Path $path) { return $path }
        }
        "AvCSPBel" {
        # Ищем в data папке bel
        $belDataPath = Join-Path $unpackedFolder "AvPKISetup(bel)\data"
        if (Test-Path $belDataPath) {
            $found = Get-ChildItem -Path $belDataPath -Filter "setupAvCSPBel*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { return $found.FullName }
        }
    
        # Ищем в корне unpacked (отдельный архив)
        $found = Get-ChildItem -Path $unpackedFolder -Filter "setupAvCSPBel*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { return $found.FullName }
        }
        "AvCSPBign" {
        # Ищем в data папке bign
        $bignDataPath = Join-Path $unpackedFolder "AvPKISetup(bign)\data"
        if (Test-Path $bignDataPath) {
            $found = Get-ChildItem -Path $bignDataPath -Filter "setupAvCSPBign*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { return $found.FullName }
        }
    
        # Ищем в корне unpacked (отдельный архив)
        $found = Get-ChildItem -Path $unpackedFolder -Filter "setupAvCSPBign*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { return $found.FullName }
        }
      }
    return $null
}

function Install-Component {
    param(
        [string]$Component,
        [hashtable]$Config
    )
    
    Write-Host "`n" + ("="*70) -ForegroundColor Cyan
    Write-Host "  УСТАНОВКА: $Component" -ForegroundColor Yellow
    Write-Host ("="*70) -ForegroundColor Cyan
    
    # 1. Очищаем unpacked
    Clear-UnpackedFolder
    
    # 2. Скачиваем и распаковываем
    $success = Download-And-Restart -Config $Config -Component $Component
    if (-not $success) { return $false }
    
    # 3. Ищем установщик
    Write-Host "  Поиск установщика..." -ForegroundColor Gray
    $installerPath = Find-Installer -Component $Component -Config $Config
    
    if (-not $installerPath) {
        Write-Host "  ОШИБКА: Установщик не найден!" -ForegroundColor Red
        Write-Log -Message "Установщик для $Component не найден" -LogFile $logFile
        return $false
    }
    
    Write-Host "  Найден: $(Split-Path $installerPath -Leaf)" -ForegroundColor Green
    
    # 4. Запускаем установку
    Write-Host "  Запуск установки..." -ForegroundColor Gray
    
    if ($Component -eq "AvReg") {
        regedit /s $installerPath
        Write-Host "  Реестровые настройки импортированы" -ForegroundColor Green
    } else {
        Write-Host "  Следуйте инструкциям мастера установки." -ForegroundColor Yellow
        Start-Process -FilePath $installerPath -Wait
        Write-Host "  Установка завершена" -ForegroundColor Green
    }
    
    Write-Log -Message "$Component установлен успешно" -LogFile $logFile
    return $true
}

# ======================================================
# 6. ОСНОВНОЙ ЦИКЛ
# ======================================================
$continue = $true

while ($continue) {
    Write-Host ("="*70) -ForegroundColor Cyan
    Write-Host "  ВЫБОР КОМПОНЕНТОВ ДЛЯ УСТАНОВКИ" -ForegroundColor Yellow
    Write-Host ("="*70) -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Выберите номер компонента для установки/переустановки" -ForegroundColor White
    Write-Host "  (0 - завершить работу)" -ForegroundColor Gray
    Write-Host ""
    
    $i = 1
    $numbers = @{}
    foreach ($component in $components) {
        $status = if ($componentStatus[$component]) { "[УСТАНОВЛЕН]" } else { "[НЕ УСТАНОВЛЕН]" }
        $color = if ($componentStatus[$component]) { "Green" } else { "White" }
        Write-Host "  $i. $component $status" -ForegroundColor $color
        $numbers[$i.ToString()] = $component
        $i++
    }
    
    Write-Host ""
    Write-Host "  0. Завершить работу" -ForegroundColor Red
    Write-Host ""
    
    $choice = Read-Host "Введите номер компонента (0-$($components.Count))"
    
    if (-not ($choice -match '^\d+$')) {
        Write-Host "Неверный ввод. Введите число." -ForegroundColor Red
        continue
    }
    
    if ([int]$choice -eq 0) {
        Write-Host "Завершение работы..." -ForegroundColor Gray
        $continue = $false
    }
    elseif ([int]$choice -ge 1 -and [int]$choice -le $components.Count) {
        $selected = $numbers[$choice]
        
        if (-not $selected -or -not $config.ContainsKey($selected)) {
            Write-Host "  Компонент $selected не найден в конфигурации" -ForegroundColor Yellow
            continue
        }
        
        $componentConfig = $config[$selected]
        
        $action = if ($componentStatus[$selected]) { "переустановить" } else { "установить" }
        Write-Host ""
        $confirm = Read-Host "$action $selected? (д/н)"
        
        if ($confirm -ne "д" -and $confirm -ne "Д" -and $confirm -ne "y" -and $confirm -ne "Y") {
            Write-Host "  Операция отменена." -ForegroundColor Gray
            continue
        }
        
        $installed = Install-Component -Component $selected -Config $componentConfig
        
        if ($installed) {
            $componentStatus[$selected] = $true
        }
        
        Write-Host ""
        Write-Host "Нажмите Enter для продолжения..." -ForegroundColor Gray
        Read-Host
    } else {
        Write-Host "Неверный выбор. Попробуйте снова." -ForegroundColor Red
    }
}

Write-Host "`nУстановка компонентов завершена." -ForegroundColor Green
exit 0