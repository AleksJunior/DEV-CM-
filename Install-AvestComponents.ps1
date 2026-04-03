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

param(
    [string]$ScriptPath
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

$configFolder = Join-Path $ScriptPath "config"
$avestFolder = Join-Path $ScriptPath "avest"
$archivesFolder = Join-Path $avestFolder "archives"
$unpackedFolder = Join-Path $avestFolder "unpacked"
$logsFolder = Join-Path $ScriptPath "logs"
$configFile = Join-Path $configFolder "avest_urls.ini"

foreach ($folder in @($configFolder, $avestFolder, $archivesFolder, $unpackedFolder, $logsFolder)) {
    if (!(Test-Path $folder)) { 
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Write-Host "  Создана папка: $folder" -ForegroundColor Gray
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
Write-Log -Message "Установка компонентов Авест" -LogFile $logFile
Write-Log -Message "========================================" -LogFile $logFile
Write-Log -Message "Путь скрипта: $ScriptPath" -LogFile $logFile
Write-Log -Message "Файл лога: $logFile" -LogFile $logFile

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
# 5. ПРЕДУПРЕЖДЕНИЕ ОБ АНТИВИРУСЕ
# ======================================================
Write-Host ("="*70) -ForegroundColor Cyan
Write-Host "  ВНИМАНИЕ!" -ForegroundColor Red
Write-Host "  Если антивирус блокирует установку," -ForegroundColor Yellow
Write-Host "  добавьте папку в исключения:" -ForegroundColor Yellow
Write-Host "  $ScriptPath" -ForegroundColor White
Write-Host ("="*70) -ForegroundColor Cyan
Write-Host ""
Start-Sleep -Seconds 3

# ======================================================
# 6. ФУНКЦИИ УСТАНОВКИ
# ======================================================
function Install-Component {
    param(
        [string]$Component,
        [hashtable]$Config,
        [bool]$ForceReinstall = $false
    )
    
    $archivePath = Join-Path $archivesFolder $Config.FileName
    $archiveExists = Test-Path $archivePath
    $targetFile = Join-Path $unpackedFolder $Config.InstallerName
    $fileExists = Test-Path $targetFile
    
    # Для AvPass/AvBign — если не найден, ищем рекурсивно
    if (-not $fileExists -and ($Component -eq "AvPass" -or $Component -eq "AvBign")) {
        $found = Get-ChildItem -Path $unpackedFolder -Recurse -Filter "AvPKISetup2.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            $targetFile = $found.FullName
            $fileExists = $true
            Write-Host "  Найден установщик (рекурсивно): $targetFile" -ForegroundColor Green
        }
    }
    
    # Проверка: архив есть, но нет распакованных файлов
    if ($archiveExists -and -not $fileExists) {
        Write-Host "`n[$Component] Архив найден, выполняю распаковку..." -ForegroundColor Yellow
        $extracted = Expand-Archive -ArchivePath $archivePath -DestinationPath $unpackedFolder
        if (-not $extracted) {
            Write-Host "  Не удалось распаковать архив" -ForegroundColor Red
            return $false
        }
        Write-Host "  Распаковка завершена!" -ForegroundColor Green
        $fileExists = Test-Path $targetFile
        
        # Повторный поиск для AvPass/AvBign
        if (-not $fileExists -and ($Component -eq "AvPass" -or $Component -eq "AvBign")) {
            $found = Get-ChildItem -Path $unpackedFolder -Recurse -Filter "AvPKISetup2.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                $targetFile = $found.FullName
                $fileExists = $true
            }
        }
    }
    
    # Проверка: нет архива и нет распакованных файлов
    if (-not $archiveExists -and -not $fileExists) {
        Write-Host "`n[$Component] Локальные файлы не найдены." -ForegroundColor Yellow
        
        if (Test-InternetConnection) {
            Write-Host "  Скачивание архива..." -ForegroundColor Gray
            $downloaded = Save-FileWithFallback -Config $Config -DestinationFolder $archivesFolder
            if (-not $downloaded) {
                Write-Host "  Не удалось скачать архив" -ForegroundColor Red
                Write-Host "  Пожалуйста, скачайте архив вручную и поместите в:" -ForegroundColor Yellow
                Write-Host "    $archivesFolder\$($Config.FileName)" -ForegroundColor Gray
                return $false
            }
            
            Write-Host "  Распаковка архива..." -ForegroundColor Gray
            $extracted = Expand-Archive -ArchivePath $archivePath -DestinationPath $unpackedFolder
            if (-not $extracted) {
                Write-Host "  Не удалось распаковать архив" -ForegroundColor Red
                return $false
            }
            Write-Host "  Распаковка завершена!" -ForegroundColor Green
            $fileExists = Test-Path $targetFile
            
            # Повторный поиск для AvPass/AvBign
            if (-not $fileExists -and ($Component -eq "AvPass" -or $Component -eq "AvBign")) {
                $found = Get-ChildItem -Path $unpackedFolder -Recurse -Filter "AvPKISetup2.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($found) {
                    $targetFile = $found.FullName
                    $fileExists = $true
                }
            }
        } else {
            Write-Host "  ОШИБКА: Нет доступа к интернету и архив отсутствует!" -ForegroundColor Red
            Write-Host "  Пожалуйста, скачайте архив вручную и поместите в:" -ForegroundColor Yellow
            Write-Host "    $archivesFolder\$($Config.FileName)" -ForegroundColor Gray
            return $false
        }
    }
    
    # Проверка повреждённых файлов
    if ((Test-Path $unpackedFolder) -and (-not $fileExists)) {
        Write-Host "`n[$Component] Обнаружены повреждённые файлы! Выполняю повторную распаковку..." -ForegroundColor Yellow
        if ($archiveExists) {
            Remove-Item -Path $unpackedFolder -Recurse -Force -ErrorAction SilentlyContinue
            New-Item -ItemType Directory -Path $unpackedFolder -Force | Out-Null
            $extracted = Expand-Archive -ArchivePath $archivePath -DestinationPath $unpackedFolder
            if (-not $extracted) {
                Write-Host "  Не удалось распаковать архив" -ForegroundColor Red
                return $false
            }
            Write-Host "  Повторная распаковка завершена!" -ForegroundColor Green
            $fileExists = Test-Path $targetFile
            
            if (-not $fileExists -and ($Component -eq "AvPass" -or $Component -eq "AvBign")) {
                $found = Get-ChildItem -Path $unpackedFolder -Recurse -Filter "AvPKISetup2.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($found) {
                    $targetFile = $found.FullName
                    $fileExists = $true
                }
            }
        }
    }
    
    # Переустановка
    if ($componentStatus[$Component] -and -not $ForceReinstall) {
        Write-Host "`n[$Component] УЖЕ УСТАНОВЛЕН" -ForegroundColor Yellow
        $reinstall = Confirm-Action -Message "Переустановить $Component?"
        if (-not $reinstall) {
            Write-Host "  Установка пропущена." -ForegroundColor Gray
            return $false
        }
    }
    
    # Финальная проверка
    if (-not $fileExists) {
        Write-Host "`n[$Component] ОШИБКА: Установщик не найден!" -ForegroundColor Red
        Write-Host "  Искали: $($Config.InstallerName)" -ForegroundColor Yellow
        Write-Host "  Содержимое папки распаковки:" -ForegroundColor Gray
        Get-ChildItem -Path $unpackedFolder -Recurse | ForEach-Object {
            Write-Host "    $($_.FullName)" -ForegroundColor Gray
        }
        Write-Host ""
        Write-Host "  Запустите установщик вручную из папки выше." -ForegroundColor Yellow
        Write-Host "  Нажмите Enter после завершения установки..." -ForegroundColor Gray
        Read-Host
        $componentStatus[$Component] = $true
        return $true
    }
    
    # Запуск установщика
    Write-Host "`n[$Component] Запуск установщика..." -ForegroundColor Yellow
    Write-Host "  Файл: $targetFile" -ForegroundColor Gray
    Write-Host "  Следуйте инструкциям мастера." -ForegroundColor Cyan
    Write-Host "  После завершения установки закройте окно установщика." -ForegroundColor Gray
    
    Start-Process -FilePath $targetFile -Wait
    
    Write-Host "  $Component установлен успешно!" -ForegroundColor Green
    $componentStatus[$Component] = $true
    return $true
}

# ======================================================
# 7. ОСНОВНОЙ ЦИКЛ
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
    
    $choice = Read-Host "Введите номер компонента для установки (0-$($components.Count))"
    
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
            Write-Host "  [!] Компонент $selected не найден в конфигурации" -ForegroundColor Yellow
            continue
        }
        
        $componentConfig = $config[$selected]
        
        $action = if ($componentStatus[$selected]) { "переустановить" } else { "установить" }
        $confirmed = Confirm-Action -Message "$action $selected?"
        
        if (-not $confirmed) {
            Write-Host "  Операция отменена." -ForegroundColor Gray
            continue
        }
        
        $installed = Install-Component -Component $selected -Config $componentConfig -ForceReinstall $true
        
        if ($installed) {
            $componentStatus[$selected] = $true
        }
        
        try {
            Write-Host ""
            Write-Host "Нажмите Enter для продолжения..." -ForegroundColor Gray
            Read-Host -ErrorAction Stop
        } catch {
            Write-Host "`nЗавершение работы..." -ForegroundColor Gray
            $script:NormalExit = $true
            break
        }
        
    } else {
        Write-Host "Неверный выбор. Попробуйте снова." -ForegroundColor Red
    }
}

$script:NormalExit = $true
Write-Host "`nУстановка компонентов завершена." -ForegroundColor Green
exit 0