<#
Copyright (c) 2026 Alex Bird
MIT License

.SYNOPSIS
    Общие функции для всех скриптов Менеджера сертификатов V1.
.DESCRIPTION
    Содержит:
    - Write-Log / Write-ExitLog (логирование)
    - Test-InternetConnection (DNS + TCP + ping)
    - Save-FileWithFallback (скачивание через WebRequest, резервные URL)
    - Get-WinRARPath / Expand-Archive (ZIP через Expand-Archive, RAR через WinRAR)
    - Import-Config (парсинг INI)
    - Confirm-Action (запрос д/н)
    - Test-AvPass, Test-AvBign, Test-AvCSPBel, Test-AvCSPBign, Test-AvReg (реестр)
    
    Глобальные переменные: $script:NormalExit, $script:LogPath
    Trap перехватывает ошибки, регистрирует PowerShell.Exiting.
.NOTES
    Версия: 1.0
    Папка деплоя: C:\CM
    Используется во всех скриптах через . (точку)
#>

# ======================================================
# 1. ЛОГИРОВАНИЕ
# ======================================================
# Глобальные переменные для логирования
$script:NormalExit = $false
$script:LogPath = $null

# Функция записи сообщения в лог-файл
function Write-Log {
    param(
        [string]$Message,
        [string]$LogFile
    )
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "$timestamp - $Message" | Out-File $LogFile -Append -ErrorAction SilentlyContinue
        Write-Host $Message -ErrorAction SilentlyContinue
        $script:LogPath = $LogFile
    } catch {
        # Игнорируем ошибки логирования
    }
}

# Функция записи сообщения при завершении скрипта
function Write-ExitLog {
    param([string]$Message)
    if ($script:LogPath) {
        try {
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            "$timestamp - $Message" | Out-File $script:LogPath -Append -ErrorAction SilentlyContinue
        } catch {
            # Игнорируем
        }
    }
}

# ======================================================
# 2. ОБРАБОТЧИК ЗАВЕРШЕНИЯ
# ======================================================
# Обработчик закрытия окна PowerShell для корректного выхода
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
        Write-ExitLog -Message "СКРИПТ ЗАВЕРШЕН С ОШИБКОЙ: $_"
    }
    exit 1
}

# ======================================================
# 3. СЕТЕВЫЕ ФУНКЦИИ
# ======================================================
# Проверка доступа к интернету через DNS, TCP и ping
function Test-InternetConnection {
    $testTargets = @(
        "nces.by",
        "goszakupki.by",
        "1.1.1.1",
        "8.8.8.8"
    )
    
    foreach ($target in $testTargets) {
        try {
            if ($target -match '^[a-zA-Z]') {
                [System.Net.Dns]::GetHostEntry($target) | Out-Null
            }
            
            $port = if ($target -match '^\d+\.\d+\.\d+\.\d+$') { 53 } else { 443 }
            $tcp = New-Object System.Net.Sockets.TcpClient
            $tcp.Connect($target, $port)
            $tcp.Close()
            return $true
        } catch {
            continue
        }
    }
    
    try {
        $ping = Test-Connection -ComputerName "nces.by" -Count 1 -Quiet -ErrorAction SilentlyContinue
        if ($ping) { return $true }
    } catch { }
    
    return $false
}

# Скачивание файла с поддержкой резервных URL (всегда перезаписывает)
function Save-FileWithFallback {
    param(
        [hashtable]$Config,
        [string]$DestinationFolder
    )
    
    # Создаём папку назначения, если её нет
    $destinationDir = Join-Path $DestinationFolder $Config.FileName | Split-Path -Parent
    if (!(Test-Path $destinationDir)) {
        New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    }
    
    $destinationPath = Join-Path $DestinationFolder $Config.FileName
    
    # ВСЕГДА скачиваем заново (удаляем старый файл, если есть)
    if (Test-Path $destinationPath) {
        Remove-Item $destinationPath -Force -ErrorAction SilentlyContinue
    }
    
    $urls = @($Config.URL)
    if ($Config.FallbackURL1 -and $Config.FallbackURL1 -ne "") { $urls += $Config.FallbackURL1 }
    if ($Config.FallbackURL2 -and $Config.FallbackURL2 -ne "") { $urls += $Config.FallbackURL2 }
    
    foreach ($url in $urls) {
        Write-Host "  Попытка: $url" -ForegroundColor Gray
        Write-Log -Message "Попытка скачать $($Config.Name) из: $url" -LogFile $script:LogPath
        
        try {
            # Используем WebRequest (менее подозрительный, чем WebClient)
            $webRequest = [System.Net.WebRequest]::Create($url)
            $webRequest.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
            $webRequest.Timeout = 30000
            $response = $webRequest.GetResponse()
            $stream = $response.GetResponseStream()
            $fileStream = [System.IO.File]::Create($destinationPath)
            $stream.CopyTo($fileStream)
            $fileStream.Close()
            $stream.Close()
            $response.Close()
            
            $size = (Get-Item $destinationPath).Length
            Write-Host "    Успешно! ($([math]::Round($size/1KB, 0)) КБ)" -ForegroundColor Green
            Write-Log -Message "Скачан $($Config.Name) из $url, размер: $size байт" -LogFile $script:LogPath
            return $true
            
        } catch {
            Write-Host "    Ошибка: $($_.Exception.Message)" -ForegroundColor Red
            Write-Log -Message "Ошибка скачивания $($Config.Name) из $url : $($_.Exception.Message)" -LogFile $script:LogPath
            if (Test-Path $destinationPath) {
                Remove-Item $destinationPath -Force -ErrorAction SilentlyContinue
            }
            continue
        }
    }
    
    Write-Host "  Не удалось скачать $($Config.Name) ни из одного источника!" -ForegroundColor Red
    Write-Log -Message "НЕ УДАЛОСЬ скачать $($Config.Name) ни из одного источника" -LogFile $script:LogPath
    return $false
}

# ======================================================
# 4. ФУНКЦИИ РАБОТЫ С АРХИВАМИ
# ======================================================
# Поиск установленного WinRAR в системе
function Get-WinRARPath {
    $winrarPaths = @(
        "C:\Program Files\WinRAR\WinRAR.exe",
        "C:\Program Files (x86)\WinRAR\WinRAR.exe"
    )
    
    foreach ($path in $winrarPaths) {
        if (Test-Path $path) {
            return $path
        }
    }
    return $null
}

# Распаковка ZIP и RAR архивов (RAR требует WinRAR)
function Expand-Archive {
    param(
        [string]$ArchivePath,
        [string]$DestinationPath
    )
    
    # Проверяем существование архива
    if (!(Test-Path $ArchivePath)) {
        Write-Log -Message "Архив не найден: $ArchivePath" -LogFile $script:LogPath
        Write-Host "  Архив не найден: $ArchivePath" -ForegroundColor Red
        return $false
    }
    
    $extension = [System.IO.Path]::GetExtension($ArchivePath).ToLower()
    
    # ZIP архивы
    if ($extension -eq ".zip") {
        try {
            if (!(Test-Path $DestinationPath)) {
                New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
            }
            # ВАЖНО: вызываем ВСТРОЕННЫЙ командлет, а не самих себя!
            Microsoft.PowerShell.Archive\Expand-Archive -Path $ArchivePath -DestinationPath $DestinationPath -Force -ErrorAction Stop
            Write-Log -Message "Архив ZIP распакован в: $DestinationPath" -LogFile $script:LogPath
            return $true
        } catch {
            Write-Log -Message "Ошибка распаковки ZIP: $($_.Exception.Message)" -LogFile $script:LogPath
            Write-Host "  Ошибка распаковки ZIP: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }
    
    # RAR архивы
    if ($extension -eq ".rar") {
        $winrar = Get-WinRARPath
        if ($winrar) {
            try {
                if (!(Test-Path $DestinationPath)) {
                    New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
                }
                $arguments = "x `"$ArchivePath`" `"$DestinationPath`" -ibck -y"
                $process = Start-Process -FilePath $winrar -ArgumentList $arguments -Wait -NoNewWindow -PassThru
                if ($process.ExitCode -eq 0) {
                    Write-Log -Message "Архив RAR распакован в: $DestinationPath (WinRAR)" -LogFile $script:LogPath
                    return $true
                } else {
                    Write-Log -Message "WinRAR вернул код ошибки: $($process.ExitCode)" -LogFile $script:LogPath
                    Write-Host "  WinRAR ошибка: код $($process.ExitCode)" -ForegroundColor Red
                    return $false
                }
            } catch {
                Write-Log -Message "Ошибка распаковки RAR: $($_.Exception.Message)" -LogFile $script:LogPath
                Write-Host "  Ошибка распаковки RAR: $($_.Exception.Message)" -ForegroundColor Red
                return $false
            }
        } else {
            Write-Log -Message "WinRAR не найден! Не могу распаковать .rar архив" -LogFile $script:LogPath
            Write-Host "  WinRAR не найден! Пожалуйста, установите WinRAR или используйте ZIP архив" -ForegroundColor Red
            return $false
        }
    }
    
    Write-Log -Message "Неподдерживаемый формат архива: $extension" -LogFile $script:LogPath
    Write-Host "  Неподдерживаемый формат архива: $extension" -ForegroundColor Red
    return $false
}

# ======================================================
# 5. КОНФИГУРАЦИЯ
# ======================================================
# Загрузка INI-файлов конфигурации в хеш-таблицу
function Import-Config {
    param([string]$ConfigFile)
    
    $config = @{}
    
    if (!(Test-Path $ConfigFile)) {
        Write-Log -Message "ОШИБКА: Файл конфигурации не найден: $ConfigFile" -LogFile $script:LogPath
        return $config
    }
    
    $currentSection = $null
    $currentObject = $null
    
    Get-Content $ConfigFile | ForEach-Object {
        $line = $_.Trim()
        
        if ($line -eq "" -or $line.StartsWith(";") -or $line.StartsWith("#")) { return }
        
        if ($line -match '^\[(.+)\]$') {
            if ($currentSection -and $currentObject) {
                $config[$currentSection] = $currentObject
            }
            $currentSection = $matches[1]
            $currentObject = @{}
            return
        }
        
        if ($currentSection -and $line -match '^([^=]+)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            $currentObject[$key] = $value
        }
    }
    
    if ($currentSection -and $currentObject) {
        $config[$currentSection] = $currentObject
    }
    
    return $config
}

# ======================================================
# 6. ЗАПРОС ПОДТВЕРЖДЕНИЯ
# ======================================================
# Запрос подтверждения действия с ответом "д/н"
function Confirm-Action {
    param([string]$Message)
    
    Write-Host ""
    Write-Host $Message -ForegroundColor Yellow
    try {
        $response = Read-Host "Установить? (д/н)" -ErrorAction Stop
        return ($response -eq "д" -or $response -eq "Д" -or $response -eq "y" -or $response -eq "Y")
    } catch {
        $script:NormalExit = $true
        [Environment]::Exit(0)
        return $false
    }
}

# ======================================================
# 7. ПРОВЕРКА КОМПОНЕНТОВ АВЕСТ
# ======================================================

# Проверка установки AvPass (только реестр)
function Test-AvPass {
    Write-Log -Message "Проверка AvPass через реестр..." -LogFile $script:LogPath
    
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    
    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $items = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                try {
                    $displayName = Get-ItemProperty -Path $item.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue
                    if ($displayName.DisplayName) {
                        if ($displayName.DisplayName -match "AvPCM|Комплект Абонента|AvUCK") {
                            Write-Log -Message "  AvPass найден в реестре: $($displayName.DisplayName)" -LogFile $script:LogPath
                            return $true
                        }
                    }
                } catch { }
            }
        }
    }
    
    Write-Log -Message "  AvPass не найден" -LogFile $script:LogPath
    return $false
}

# Проверка установки AvBign (только реестр)
function Test-AvBign {
    Write-Log -Message "Проверка AvBign через реестр..." -LogFile $script:LogPath
    
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    
    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $items = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                try {
                    $displayName = Get-ItemProperty -Path $item.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue
                    if ($displayName.DisplayName) {
                        if ($displayName.DisplayName -match "AvBign") {
                            Write-Log -Message "  AvBign найден в реестре: $($displayName.DisplayName)" -LogFile $script:LogPath
                            return $true
                        }
                    }
                } catch { }
            }
        }
    }
    
    Write-Log -Message "  AvBign не найден" -LogFile $script:LogPath
    return $false
}

# Проверка установки AvCSPBel (только реестр)
function Test-AvCSPBel {
    Write-Log -Message "Проверка AvCSPBel..." -LogFile $script:LogPath
    
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    
    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $items = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                try {
                    $displayName = Get-ItemProperty -Path $item.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue
                    if ($displayName.DisplayName) {
                        if ($displayName.DisplayName -match "AvCSPBel|Avest CSP Bel") {
                            Write-Log -Message "  AvCSPBel найден в реестре: $($displayName.DisplayName)" -LogFile $script:LogPath
                            return $true
                        }
                    }
                } catch { }
            }
        }
    }
    
    Write-Log -Message "  AvCSPBel не найден" -LogFile $script:LogPath
    return $false
}

# Проверка установки AvCSPBign (только реестр)
function Test-AvCSPBign {
    Write-Log -Message "Проверка AvCSPBign..." -LogFile $script:LogPath
    
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    
    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $items = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                try {
                    $displayName = Get-ItemProperty -Path $item.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue
                    if ($displayName.DisplayName) {
                        if ($displayName.DisplayName -match "AvCSPBign|Avest CSP Bign") {
                            Write-Log -Message "  AvCSPBign найден в реестре: $($displayName.DisplayName)" -LogFile $script:LogPath
                            return $true
                        }
                    }
                } catch { }
            }
        }
    }
    
    Write-Log -Message "  AvCSPBign не найден" -LogFile $script:LogPath
    return $false
}

# Проверка реестровых настроек SAI DLL
function Test-AvReg {
    Write-Log -Message "Проверка AvReg..." -LogFile $script:LogPath
    
    $path1 = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows"
    $path2 = "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows NT\CurrentVersion\Windows"
    
    try {
        $val1 = (Get-ItemProperty -Path $path1 -Name "LoadAppInit_DLLs" -ErrorAction SilentlyContinue).LoadAppInit_DLLs
        $val2 = (Get-ItemProperty -Path $path1 -Name "RequireSignedAppInit_DLLs" -ErrorAction SilentlyContinue).RequireSignedAppInit_DLLs
        $val3 = (Get-ItemProperty -Path $path2 -Name "LoadAppInit_DLLs" -ErrorAction SilentlyContinue).LoadAppInit_DLLs
        $val4 = (Get-ItemProperty -Path $path2 -Name "RequireSignedAppInit_DLLs" -ErrorAction SilentlyContinue).RequireSignedAppInit_DLLs
        
        if ($val1 -eq 1 -and $val2 -eq 0 -and $val3 -eq 1 -and $val4 -eq 0) { 
            Write-Log -Message "  AvReg найден в реестре: LoadAppInit_DLLs=1, RequireSignedAppInit_DLLs=0" -LogFile $script:LogPath
            return $true 
        }
    } catch { 
        Write-Log -Message "  AvReg не найден (ошибка доступа к реестру)" -LogFile $script:LogPath
    }
    
    Write-Log -Message "  AvReg не найден" -LogFile $script:LogPath
    return $false
}