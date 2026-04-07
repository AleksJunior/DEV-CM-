<#
Copyright (c) 2026 Alex Bird
MIT License

.SYNOPSIS
    Интерактивная установка компонентов Авест.
.DESCRIPTION
    Читает config\avest_urls.ini, предлагает выбор:
    AvPass, AvBign, AvCSPBel, AvCSPBign, AvReg.
    Для каждого:
    - Очистка .\avest\unpacked\
    - Скачивание ZIP (с резервными URL)
    - Распаковка в unpacked
    - Поиск установщика (AvPKISetup2.exe, setupAvCSP*.exe, *.reg)
    - Запуск установки (для .reg — reg import)
    
    Требует интернет, права администратора.
.NOTES
    Версия: 1.0
    Папка деплоя: C:\CM
    Зависит от Common-FunctionsV1.ps1
    Логи: C:\CM\logs\avest_install_*.log
#>

param([string]$ScriptPath)

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
$commonScript = Join-Path $ScriptPath "Common-FunctionsV1.ps1"
if (Test-Path $commonScript) {
    . $commonScript
} else {
    Write-Host "ОШИБКА: Общий модуль не найден: $commonScript" -ForegroundColor Red
    exit 1
}

Write-Log -Message "========================================" -LogFile $logFile
Write-Log -Message    "Установка компонентов Авест V1.0" -LogFile $logFile
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

$components = @("AvPass", "AvBign", "AvCSPBel", "AvCSPBign", "AvReg")

# ======================================================
# 4. ФУНКЦИИ УСТАНОВКИ
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
        "AvReg" {
            $path = Join-Path $unpackedFolder "requireSAI_DLL.reg"
            if (Test-Path $path) { return $path }
        }
    }
    return $null
}

function Install-Component {
    param(
        [string]$Component,
        [hashtable]$Config
    )
    
    Write-Host ("`n" + ("="*45)) -ForegroundColor Cyan
    Write-Host "  УСТАНОВКА: $Component" -ForegroundColor Yellow
    Write-Host ("="*45) -ForegroundColor Cyan
    
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
        reg import $installerPath
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Реестровые настройки импортированы" -ForegroundColor Green
        } else {
            Write-Host "  Ошибка импорта реестра" -ForegroundColor Red
            Write-Log -Message "Ошибка импорта реестра: $installerPath" -LogFile $logFile
            return $false
        }
    } else {
        Write-Host "  Следуйте инструкциям мастера установки." -ForegroundColor Yellow
        Start-Process -FilePath $installerPath -Wait
        Write-Host "  Установка завершена" -ForegroundColor Green
    }
    
    Write-Log -Message "$Component установлен успешно" -LogFile $logFile
    return $true
}

# ======================================================
# 5. ОСНОВНОЙ ЦИКЛ
# ======================================================
$continue = $true

while ($continue) {
    Write-Host ("="*41) -ForegroundColor Cyan
    Write-Host "  ВЫБОР КОМПОНЕНТОВ ДЛЯ УСТАНОВКИ" -ForegroundColor Yellow
    Write-Host ("="*41) -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Выберите номер компонента для установки" -ForegroundColor White
    Write-Host "  (0 - завершить работу)" -ForegroundColor Gray
    Write-Host ""
    
    $i = 1
    $numbers = @{}
    foreach ($component in $components) {
        Write-Host "  $i. $component" -ForegroundColor White
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
        
        Write-Host ""
        $confirm = Read-Host "Установить $selected? (д/н)"
        
        if ($confirm -ne "д" -and $confirm -ne "Д" -and $confirm -ne "y" -and $confirm -ne "Y") {
            Write-Host "  Операция отменена." -ForegroundColor Gray
            continue
        }
        
        $installed = Install-Component -Component $selected -Config $componentConfig
        
        Write-Host ""
        Write-Host "Нажмите Enter для продолжения..." -ForegroundColor Gray
        Read-Host
    } else {
        Write-Host "Неверный выбор. Попробуйте снова." -ForegroundColor Red
    }
}

Write-Host "`nУстановка компонентов завершена." -ForegroundColor Green
exit 0