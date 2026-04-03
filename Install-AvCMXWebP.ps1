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
# 0. ОБРАБОТЧИК ЗАВЕРШЕНИЯ
# ======================================================
$script:NormalExit = $false
$script:LogPath = $null

# Регистрируем обработчик закрытия окна PowerShell
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -SupportEvent -Action {
    if (-not $script:NormalExit) {
        if ($script:LogPath) {
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            "$timestamp - СКРИПТ ЗАВЕРШЕН ПОЛЬЗОВАТЕЛЕМ (закрытие окна)" | Out-File $script:LogPath -Append -ErrorAction SilentlyContinue
        }
        [Environment]::Exit(0)
    }
} | Out-Null

# Перехват ошибок
trap {
    if (-not $script:NormalExit) {
        if ($script:LogPath) {
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            "$timestamp - СКРИПТ ЗАВЕРШЕН С ОШИБКОЙ: $_" | Out-File $script:LogPath -Append -ErrorAction SilentlyContinue
        }
    }
    exit 1
}

# ======================================================
# 1. НАСТРОЙКА ПУТЕЙ
# ======================================================
# Определяем путь к папке со скриптами
if (-not $ScriptPath) {
    if ($MyInvocation.MyCommand.CommandType -eq "ExternalScript") {
        $ScriptPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
    } else {
        $ScriptPath = Split-Path -Parent -Path ([Environment]::GetCommandLineArgs()[0])
        if (!$ScriptPath) { $ScriptPath = "." }
    }
}

# Основные папки
$avestFolder = Join-Path $ScriptPath "avest"
$archivesFolder = Join-Path $avestFolder "archives"
$unpackedFolder = Join-Path $avestFolder "unpacked"

# Папка для логов
if (-not $LogsFolder) { $LogsFolder = Join-Path $ScriptPath "logs" }

# Создаём все необходимые папки
foreach ($folder in @($avestFolder, $archivesFolder, $unpackedFolder, $LogsFolder)) {
    if (!(Test-Path $folder)) { 
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Write-Host "  Создана папка: $folder" -ForegroundColor Gray
    }
}

# Файл лога
$logFile = Join-Path $LogsFolder "avcmxwebp_install_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
$script:LogPath = $logFile

# Сетевая директория (опционально, может быть недоступна)
$networkSource = "\\asup-7\BackBox\DEV\CertificateManager V2.0\avest\unpacked"

# Ссылки для скачивания (с резервными вариантами)
$avPassUrls = @(
    "https://nces.by/wp-content/uploads/gossuok/AvPKISetup(bel).zip",
    "https://goszakupki.by/upload/AvPKISetup(bel).zip",
    "https://portal.nalog.gov.by/ca/AvPKISetup(bel).zip"
)

$avBignUrls = @(
    "https://nces.by/wp-content/uploads/gossuok/AvPKISetup(bign).zip",
    "https://goszakupki.by/upload/AvPKISetup(bign).zip",
    "https://portal.nalog.gov.by/ca/AvPKISetup(bign).zip"
)

# ======================================================
# 2. ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ======================================================

# Функция записи в лог
function Write-Log {
    param([string]$Message)
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "$timestamp - $Message" | Out-File $logFile -Append -ErrorAction SilentlyContinue
        Write-Host $Message -ErrorAction SilentlyContinue
    } catch { }
}

# Функция проверки доступа в интернет
function Test-InternetConnection {
    Write-Host "  Проверка доступа к интернету..." -ForegroundColor Gray
    Write-Log "Проверка доступа к интернету..."
    
    $testTargets = @(
        "nces.by",
        "goszakupki.by",
        "portal.nalog.gov.by",
        "1.1.1.1",
        "8.8.8.8"
    )
    
    foreach ($target in $testTargets) {
        try {
            Write-Host "    Проверка: $target" -ForegroundColor Gray
            # Проверяем DNS для доменных имён
            if ($target -match '^[a-zA-Z]') {
                [System.Net.Dns]::GetHostEntry($target) | Out-Null
            }
            
            # Проверяем TCP-соединение
            $port = if ($target -match '^\d+\.\d+\.\d+\.\d+$') { 53 } else { 443 }
            $tcp = New-Object System.Net.Sockets.TcpClient
            $tcp.Connect($target, $port)
            $tcp.Close()
            Write-Host "    Доступен: $target" -ForegroundColor Green
            Write-Log "Интернет доступен (проверка через $target)"
            return $true
        } catch {
            Write-Host "    Недоступен: $target" -ForegroundColor DarkGray
            continue
        }
    }
    
    Write-Host "  Интернет НЕ ДОСТУПЕН!" -ForegroundColor Red
    Write-Log "Интернет недоступен"
    return $false
}

# Функция скачивания файла с резервными ссылками
function Save-FileWithFallback {
    param(
        [string[]]$Urls,
        [string]$DestinationPath,
        [string]$ComponentName
    )
    
    Write-Log "Попытка скачать $ComponentName..."
    
    foreach ($url in $Urls) {
        if ([string]::IsNullOrEmpty($url)) { continue }
        
        try {
            Write-Host "    Попытка: $url" -ForegroundColor Gray
            $webClient = New-Object System.Net.WebClient
            $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
            $webClient.DownloadFile($url, $DestinationPath)
            $webClient.Dispose()
            
            $size = (Get-Item $DestinationPath).Length
            Write-Host "    Успешно! ($([math]::Round($size/1KB, 0)) КБ)" -ForegroundColor Green
            Write-Log "$ComponentName скачан из $url, размер: $size байт"
            return $true
            
        } catch {
            Write-Host "    Ошибка: $($_.Exception.Message)" -ForegroundColor Red
            Write-Log "Ошибка скачивания $ComponentName из $url : $($_.Exception.Message)"
            
            # Удаляем частично скачанный файл
            if (Test-Path $DestinationPath) {
                Remove-Item $DestinationPath -Force -ErrorAction SilentlyContinue
            }
            continue
        }
    }
    
    Write-Log "НЕ УДАЛОСЬ скачать $ComponentName ни из одного источника"
    return $false
}

# Функция скачивания AvPass (с резервными ссылками)
function Save-AvPass {
    Write-Log "Загрузка AvPass из интернета..."
    Write-Host "`n[1/3] Загрузка AvPass..." -ForegroundColor Yellow
    
    $archivePath = Join-Path $archivesFolder "AvPKISetup(bel).zip"
    
    $result = Save-FileWithFallback -Urls $avPassUrls -DestinationPath $archivePath -ComponentName "AvPass"
    
    if ($result) {
        Write-Host "  AvPass скачан успешно!" -ForegroundColor Green
    } else {
        Write-Host "  Не удалось скачать AvPass ни из одного источника!" -ForegroundColor Red
    }
    
    return $result
}

# Функция скачивания AvBign (резервный вариант)
function Save-AvBign {
    Write-Log "Загрузка AvBign из интернета..."
    Write-Host "`n[2/3] Загрузка AvBign (резервный вариант)..." -ForegroundColor Yellow
    
    $archivePath = Join-Path $archivesFolder "AvPKISetup(bign).zip"
    
    $result = Save-FileWithFallback -Urls $avBignUrls -DestinationPath $archivePath -ComponentName "AvBign"
    
    if ($result) {
        Write-Host "  AvBign скачан успешно!" -ForegroundColor Green
    } else {
        Write-Host "  Не удалось скачать AvBign ни из одного источника!" -ForegroundColor Red
    }
    
    return $result
}

# Функция распаковки архива (ZIP)
function Expand-Archive {
    param(
        [string]$ArchivePath,
        [string]$DestinationPath,
        [string]$ComponentName
    )
    
    Write-Log "Распаковка $ComponentName..."
    
    if (!(Test-Path $ArchivePath)) {
        Write-Log "Архив не найден: $ArchivePath"
        return $false
    }
    
    try {
        # Создаём папку для распаковки, если её нет
        if (!(Test-Path $DestinationPath)) {
            New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
        }
        
        # Распаковываем архив
        Microsoft.PowerShell.Archive\Expand-Archive -Path $ArchivePath -DestinationPath $DestinationPath -Force -ErrorAction Stop
        Write-Host "  Распаковка $ComponentName завершена" -ForegroundColor Green
        Write-Log "$ComponentName распакован в: $DestinationPath"
        return $true
        
    } catch {
        Write-Log "Ошибка распаковки $ComponentName : $($_.Exception.Message)"
        Write-Host "  Ошибка распаковки: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Функция поиска установщика плагина в распакованных компонентах
function Find-InUnpacked {
    param([string]$UnpackedFolder)
    
    Write-Log "Поиск установщика AvCMXWebP в папке: $UnpackedFolder"
    
    # Сначала выполняем рекурсивный поиск всех установщиков
    $allInstallers = Get-ChildItem -Path $UnpackedFolder -Recurse -Filter "AvCMXWebP-*.exe" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    
    if ($allInstallers.Count -gt 0) {
        Write-Log "Найден установщик при рекурсивном поиске: $($allInstallers[0].Name)"
        Write-Host "  Найден: $($allInstallers[0].Name)" -ForegroundColor Green
        return $allInstallers[0]
    }
    
    # Если не нашли, пробуем поиск по шаблонам
    $searchPatterns = @(
        "AvPKISetup(bign)\data\AvCMXWebP-*.exe",
        "AvPKISetup(bel)\data\AvCMXWebP-*.exe"
    )
    
    foreach ($pattern in $searchPatterns) {
        $fullPattern = Join-Path $UnpackedFolder $pattern
        $files = Get-ChildItem -Path $fullPattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        if ($files.Count -gt 0) {
            Write-Log "Найден установщик по шаблону $pattern : $($files[0].Name)"
            Write-Host "  Найден: $($files[0].Name)" -ForegroundColor Green
            return $files[0]
        }
    }
    
    Write-Log "Установщик плагина не найден"
    Write-Host "  Установщик не найден" -ForegroundColor Yellow
    return $null
}

# Функция копирования из сетевой папки
function Copy-FromNetwork {
    param(
        [string]$NetworkPath,
        [string]$TargetFolder
    )
    
    # Проверяем доступность сетевой папки
    if (!(Test-Path $NetworkPath)) {
        Write-Log "Сетевая папка недоступна: $NetworkPath"
        Write-Host "  Сетевая папка недоступна" -ForegroundColor Yellow
        return $null
    }
    
    Write-Log "Поиск в сетевой папке: $NetworkPath"
    Write-Host "  Поиск в сетевой папке..." -ForegroundColor Gray
    
    $searchPatterns = @(
        "AvPKISetup(bign)\data\AvCMXWebP-*.exe",
        "AvPKISetup(bel)\data\AvCMXWebP-*.exe"
    )
    
    foreach ($pattern in $searchPatterns) {
        $fullPattern = Join-Path $NetworkPath $pattern
        $files = Get-ChildItem -Path $fullPattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        if ($files.Count -gt 0) {
            $sourceFile = $files[0]
            $targetFile = Join-Path $TargetFolder $pattern
            $targetDir = Split-Path $targetFile -Parent
            
            # Создаём папку назначения, если её нет
            if (!(Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }
            
            Copy-Item -Path $sourceFile.FullName -Destination $targetFile -Force
            Write-Log "Скопирован из сети: $($sourceFile.Name) -> $targetFile"
            Write-Host "  Скопирован из сетевой папки: $($sourceFile.Name)" -ForegroundColor Green
            return Get-Item $targetFile
        }
    }
    
    Write-Log "Установщик не найден в сетевой папке"
    Write-Host "  В сетевой папке не найден" -ForegroundColor Yellow
    return $null
}

# Функция проверки установленного плагина
function Test-PluginInstalled {
    Write-Log "Проверка наличия установленного AvCMXWebP..."
    
    # Проверка в реестре
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($regPath in $regPaths) {
        $items = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            try {
                $displayName = Get-ItemProperty -Path $item.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue
                if ($displayName.DisplayName -like "*AvCMXWebP*") {
                    Write-Log "Найдено в реестре: $($displayName.DisplayName)"
                    return $true
                }
            } catch { }
        }
    }
    
    # Проверка файловой системы
    $filePaths = @(
        "C:\Program Files\Avest\AvCMXWebP\AvCMXWebP.exe",
        "C:\Program Files (x86)\Avest\AvCMXWebP\AvCMXWebP.exe",
        "C:\ProgramData\Avest\AvCMXWebP\x64\npAvCMXWebP.dll"
    )
    
    foreach ($path in $filePaths) {
        if (Test-Path $path) {
            Write-Log "Найдено в файловой системе: $path"
            return $true
        }
    }
    
    Write-Log "Установленный плагин не найден"
    return $false
}

# Функция удаления предыдущей версии
function Remove-PreviousVersion {
    Write-Log "Поиск деинсталлятора..."
    
    $uninstallPaths = @(
        "C:\ProgramData\Avest\AvCMXWebP\unins000.exe",
        "C:\Program Files\Avest\AvCMXWebP\unins000.exe",
        "C:\Program Files (x86)\Avest\AvCMXWebP\unins000.exe"
    )
    
    $uninstaller = $null
    foreach ($path in $uninstallPaths) {
        if (Test-Path $path) {
            $uninstaller = $path
            break
        }
    }
    
    if ($uninstaller) {
        Write-Log "Запуск деинсталлятора: $uninstaller /VERYSILENT /SUPPRESSMSGBOXES /NORESTART"
        try {
            $process = Start-Process -FilePath $uninstaller -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART" -Wait -PassThru -NoNewWindow -ErrorAction Stop
            Write-Log "Код выхода деинсталлятора: $($process.ExitCode)"
            if ($process.ExitCode -eq 0) {
                Write-Log "Предыдущая версия успешно удалена"
                Write-Host "  Предыдущая версия удалена" -ForegroundColor Green
            }
            Start-Sleep -Seconds 2
            return $true
        } catch {
            Write-Log "Не удалось запустить деинсталлятор: $($_.Exception.Message)"
        }
    } else {
        Write-Log "Деинсталлятор не найден"
    }
    return $false
}

# Функция попытки загрузки и распаковки компонента
function DownloadAndExtract {
    param(
        [string]$ComponentType,
        [scriptblock]$DownloadFunc,
        [string]$ArchiveName,
        [string]$DisplayName
    )
    
    Write-Host "`n[Попытка $ComponentType] Загрузка и распаковка $DisplayName..." -ForegroundColor Cyan
    
    # Скачиваем компонент
    $downloadSuccess = & $DownloadFunc
    if (-not $downloadSuccess) {
        Write-Host "  Не удалось скачать $DisplayName" -ForegroundColor Red
        Write-Log "Не удалось скачать $DisplayName"
        return $false
    }
    
    # Распаковываем компонент (без установки!)
    $archivePath = Join-Path $archivesFolder $ArchiveName
    $extractSuccess = Expand-Archive -ArchivePath $archivePath -DestinationPath $unpackedFolder -ComponentName $DisplayName
    
    if (-not $extractSuccess) {
        Write-Host "  Не удалось распаковать $DisplayName" -ForegroundColor Red
        Write-Log "Не удалось распаковать $DisplayName"
        return $false
    }
    
    Write-Host "  $DisplayName успешно распакован (установка НЕ выполнялась)" -ForegroundColor Green
    Write-Log "$DisplayName успешно распакован"
    return $true
}

# ======================================================
# 3. ОСНОВНАЯ ЛОГИКА
# ======================================================
Write-Log "========================================"
Write-Log "Скрипт установки AvCMXWebP"
Write-Log "========================================"
Write-Log "Путь скрипта: $ScriptPath"
Write-Log "Папка с распакованными компонентами: $unpackedFolder"
Write-Log "Файл лога: $logFile"

Write-Host ("="*70) -ForegroundColor Cyan
Write-Host "  УСТАНОВКА ПЛАГИНА AvCMXWebP" -ForegroundColor Yellow
Write-Host ("="*70) -ForegroundColor Cyan
Write-Host ""

# ======================================================
# 4. ПРОВЕРКА, УСТАНОВЛЕН ЛИ ПЛАГИН
# ======================================================
$alreadyInstalled = Test-PluginInstalled

if ($alreadyInstalled) {
    Write-Host "Плагин AvCMXWebP уже установлен." -ForegroundColor Green
    Write-Host ""
    Write-Host "Переустановить? (д/н)" -ForegroundColor Yellow
    try {
        $reinstall = Read-Host "Установить? (д/н)" -ErrorAction Stop
        if ($reinstall -ne "д" -and $reinstall -ne "Д" -and $reinstall -ne "y" -and $reinstall -ne "Y") {
            Write-Host "Установка пропущена." -ForegroundColor Gray
            $script:NormalExit = $true
            exit 0
        }
        Write-Host "Выполняется переустановка..." -ForegroundColor Yellow
        Remove-PreviousVersion
    } catch {
        Write-Host "Завершение работы..." -ForegroundColor Gray
        $script:NormalExit = $true
        exit 0
    }
}

# ======================================================
# 5. ПОИСК УСТАНОВЩИКА ПЛАГИНА
# ======================================================
Write-Host "Шаг 1: Поиск установщика AvCMXWebP..." -ForegroundColor Cyan
$installer = Find-InUnpacked -UnpackedFolder $unpackedFolder

# Шаг 2: Если не нашли, пробуем скопировать из сетевой папки
if (-not $installer) {
    Write-Host "`nШаг 2: Поиск в сетевой папке..." -ForegroundColor Cyan
    $installer = Copy-FromNetwork -NetworkPath $networkSource -TargetFolder $unpackedFolder
}

# Шаг 3: Если всё ещё не нашли, проверяем интернет
if (-not $installer) {
    Write-Host "`nШаг 3: Установщик не найден в локальных папках и сетевой папке." -ForegroundColor Yellow
    Write-Host "Попытка загрузки из интернета..." -ForegroundColor Yellow
    
    # Проверяем интернет
    if (-not (Test-InternetConnection)) {
        Write-Host ("`n" + ("="*70)) -ForegroundColor Red
        Write-Host "  ОШИБКА: НЕТ ДОСТУПА К ИНТЕРНЕТУ!" -ForegroundColor Red
        Write-Host ("="*70) -ForegroundColor Red
        Write-Host ""
        Write-Host "Невозможно скачать компоненты для получения установщика плагина." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Возможные решения:" -ForegroundColor Cyan
        Write-Host "  1. Подключитесь к интернету и повторите попытку" -ForegroundColor Gray
        Write-Host "  2. Скопируйте установщик вручную в папку:" -ForegroundColor Gray
        Write-Host "     $unpackedFolder\AvPKISetup(bel)\data\" -ForegroundColor White
        Write-Host "     или" -ForegroundColor Gray
        Write-Host "     $unpackedFolder\AvPKISetup(bign)\data\" -ForegroundColor White
        Write-Host "  3. Обеспечьте доступность сетевой папки:" -ForegroundColor Gray
        Write-Host "     $networkSource" -ForegroundColor White
        Write-Host ""
        exit 1
    }
    
    # Шаг 3.1: Пробуем скачать и распаковать AvPass
    Write-Host "`n[Вариант А] Попытка загрузки AvPass..." -ForegroundColor Cyan
    $avPassSuccess = DownloadAndExtract -ComponentType "AvPass" -DownloadFunc { Save-AvPass } -ArchiveName "AvPKISetup(bel).zip" -DisplayName "AvPass"
    
    if ($avPassSuccess) {
        Write-Host "`n  Повторный поиск установщика AvCMXWebP..." -ForegroundColor Yellow
        $installer = Find-InUnpacked -UnpackedFolder $unpackedFolder
    }
    
    # Шаг 3.2: Если AvPass не помог, пробуем AvBign
    if (-not $installer) {
        Write-Host "`n[Вариант Б] AvPass не помог, пробуем AvBign..." -ForegroundColor Cyan
        $avBignSuccess = DownloadAndExtract -ComponentType "AvBign" -DownloadFunc { Save-AvBign } -ArchiveName "AvPKISetup(bign).zip" -DisplayName "AvBign"
        
        if ($avBignSuccess) {
            Write-Host "`n  Повторный поиск установщика AvCMXWebP..." -ForegroundColor Yellow
            $installer = Find-InUnpacked -UnpackedFolder $unpackedFolder
        }
    }
}

# Финальная проверка
if (-not $installer) {
    Write-Host ("`n" + ("="*70)) -ForegroundColor Red
    Write-Host "  ОШИБКА: УСТАНОВЩИК ПЛАГИНА НЕ НАЙДЕН!" -ForegroundColor Red
    Write-Host ("="*70) -ForegroundColor Red
    Write-Host ""
    Write-Host "Поиск выполнялся в следующих местах:" -ForegroundColor Yellow
    Write-Host "  • Локальная папка: $unpackedFolder" -ForegroundColor Gray
    Write-Host "  • Сетевая папка: $networkSource" -ForegroundColor Gray
    Write-Host "  • После загрузки AvPass" -ForegroundColor Gray
    Write-Host "  • После загрузки AvBign" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Возможные причины:" -ForegroundColor Cyan
    Write-Host "  1. В загруженных архивах отсутствует файл AvCMXWebP-*.exe" -ForegroundColor Gray
    Write-Host "  2. Изменилась структура архивов на сайте nces.by" -ForegroundColor Gray
    Write-Host "  3. Нет доступа к интернету или сетевой папке" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Ручное решение:" -ForegroundColor Cyan
    Write-Host "  Скопируйте установщик плагина вручную в одну из папок:" -ForegroundColor Gray
    Write-Host "  • $unpackedFolder\AvPKISetup(bel)\data\" -ForegroundColor White
    Write-Host "  • $unpackedFolder\AvPKISetup(bign)\data\" -ForegroundColor White
    Write-Host "  Затем запустите скрипт снова." -ForegroundColor Gray
    Write-Host ""
    
    Write-Log "КРИТИЧЕСКАЯ ОШИБКА: Установщик плагина не найден после всех попыток"
    exit 1
}

# ======================================================
# 6. УСТАНОВКА ПЛАГИНА
# ======================================================
Write-Host ("`n" + ("="*70)) -ForegroundColor Green
Write-Host "  УСТАНОВКА ПЛАГИНА" -ForegroundColor Green
Write-Host ("="*70) -ForegroundColor Green
Write-Host ""
Write-Host "Найден установщик: $($installer.Name)" -ForegroundColor Green
Write-Host "Путь: $($installer.FullName)" -ForegroundColor Gray
Write-Host ""
Write-Host "Запуск установки..." -ForegroundColor Yellow
Write-Host "Пожалуйста, следуйте инструкциям мастера установки." -ForegroundColor Gray
Write-Host ""

try {
    $process = Start-Process -FilePath $installer.FullName -Wait
    
    Write-Host ("`n" + ("="*70)) -ForegroundColor Green
    Write-Host "  УСТАНОВКА ПЛАГИНА AvCMXWebP ЗАВЕРШЕНА!" -ForegroundColor Green
    Write-Host ("="*70) -ForegroundColor Green
    Write-Log "Установка плагина завершена с кодом: $($process.ExitCode)"
    $script:NormalExit = $true
    exit 0
} catch {
    Write-Log "ОШИБКА при установке: $($_.Exception.Message)"
    Write-Host ("`n" + ("="*70)) -ForegroundColor Red
    Write-Host "  ОШИБКА ПРИ УСТАНОВКЕ ПЛАГИНА!" -ForegroundColor Red
    Write-Host ("="*70) -ForegroundColor Red
    Write-Host ""
    Write-Host "Сообщение об ошибке: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Проверьте лог для получения подробностей: $logFile" -ForegroundColor Gray
    $script:NormalExit = $true
    exit 1
}