<#
Copyright (c) 2026 Alex Bird
Use of this source code is governed by an MIT-style
license that can be found in the LICENSE file.
.SYNOPSIS
    Общий модуль функций для Менеджера сертификатов V2.0
.DESCRIPTION
    Набор общих функций, используемых всеми скриптами проекта:
    
    Логирование:
        - Write-Log: запись сообщений в лог-файл с временной меткой
        - Write-ExitLog: запись сообщения при завершении скрипта
        - Автоматический обработчик завершения PowerShell.Exiting
    
    Сетевые функции:
        - Test-InternetConnection: проверка доступа к интернету через DNS, TCP и ping
        - Download-FileWithFallback: скачивание файла с поддержкой резервных URL
    
    Работа с архивами:
        - Get-WinRARPath: поиск установленного WinRAR в системе
        - Extract-Archive: распаковка ZIP и RAR архивов (RAR требует WinRAR)
    
    Конфигурация:
        - Load-Config: загрузка INI-файлов конфигурации в хеш-таблицу
    
    Взаимодействие с пользователем:
        - Confirm-Action: запрос подтверждения действия с ответом "д/н"
    
    Проверка компонентов Авест:
        - Check-AvPass: проверка установки Комплекта Абонента АВЕСТ (AvPass)
        - Check-AvBign: проверка установки Комплекта Абонента АВЕСТ (AvBign)
        - Check-AvCSPBel: проверка криптопровайдера AvCSPBel
        - Check-AvCSPBign: проверка криптопровайдера AvCSPBign
        - Check-AvReg: проверка реестровых настроек SAI DLL
    
    Все функции имеют встроенное логирование и обработку ошибок.
.NOTES
    Версия: 2.0
    Используется во всех скриптах проекта через точку (.)
    Глобальные переменные:
        - $script:NormalExit: флаг нормального завершения скрипта
        - $script:LogPath: путь к текущему лог-файлу
    
    Обработка завершения:
        - Регистрируется обработчик PowerShell.Exiting для корректного выхода при закрытии окна
        - Trap перехватывает все ошибки и записывает их в лог
    
    Проверка компонентов выполняется по:
        - Файловой системе (проверка наличия исполняемых файлов и DLL)
        - Реестру (поиск в Uninstall ключах)
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

# Скачивание файла с поддержкой резервных URL
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
    
    if (Test-Path $destinationPath) {
        Write-Host "  Файл уже существует: $($Config.FileName)" -ForegroundColor Green
        Write-Log -Message "Файл уже существует: $destinationPath" -LogFile $script:LogPath
        return $true
    }
    
    $urls = @($Config.URL)
    if ($Config.FallbackURL1 -and $Config.FallbackURL1 -ne "") { $urls += $Config.FallbackURL1 }
    if ($Config.FallbackURL2 -and $Config.FallbackURL2 -ne "") { $urls += $Config.FallbackURL2 }
    
    foreach ($url in $urls) {
        Write-Host "  Попытка: $url" -ForegroundColor Gray
        Write-Log -Message "Попытка скачать $($Config.Name) из: $url" -LogFile $script:LogPath
        
        try {
            $webClient = New-Object System.Net.WebClient
            $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
            $webClient.DownloadFile($url, $destinationPath)
            $webClient.Dispose()
            
            $size = (Get-Item $destinationPath).Length
            Write-Host "    Успешно! ($([math]::Round($size/1KB, 0)) КБ)" -ForegroundColor Green
            Write-Log -Message "Скачан $($Config.Name) из $url, размер: $size байт" -LogFile $script:LogPath
            return $true
            
        } catch {
            Write-Host "    Ошибка: $($_.Exception.Message)" -ForegroundColor Red
            Write-Log -Message "Ошибка скачивания $($Config.Name) из $url : $($_.Exception.Message)" -LogFile $script:LogPath
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
    
    if (!(Test-Path $ArchivePath)) {
        Write-Log -Message "Архив не найден: $ArchivePath" -LogFile $script:LogPath
        return $false
    }
    
    $extension = [System.IO.Path]::GetExtension($ArchivePath).ToLower()
    
    if ($extension -eq ".zip") {
        try {
            if (!(Test-Path $DestinationPath)) {
                New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
            }
            Expand-Archive -Path $ArchivePath -DestinationPath $DestinationPath -Force -ErrorAction Stop
            Write-Log -Message "Архив ZIP распакован в: $DestinationPath" -LogFile $script:LogPath
            return $true
        } catch {
            Write-Log -Message "Ошибка распаковки ZIP: $($_.Exception.Message)" -LogFile $script:LogPath
            return $false
        }
    }
    
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
                    return $false
                }
            } catch {
                Write-Log -Message "Ошибка распаковки RAR: $($_.Exception.Message)" -LogFile $script:LogPath
                return $false
            }
        } else {
            Write-Log -Message "WinRAR не найден! Не могу распаковать .rar архив" -LogFile $script:LogPath
            Write-Host "  WinRAR не найден! Пожалуйста, установите WinRAR или используйте ZIP архив" -ForegroundColor Red
            return $false
        }
    }
    
    Write-Log -Message "Неподдерживаемый формат архива: $extension" -LogFile $script:LogPath
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
# Проверка установки AvPass
function Test-AvPass {
    Write-Log -Message "Проверка AvPass..." -LogFile $script:LogPath
    
    # 1. Проверка файловой системы
    $paths = @(
        "C:\Program Files\Avest\AvPCM\AvPCM.exe",
        "C:\Program Files (x86)\Avest\AvPCM\AvPCM.exe",
        "C:\Program Files\Avest\AvPCM_nces\AvPCM.exe",
        "C:\Program Files (x86)\Avest\AvPCM_nces\AvPCM.exe",
        "C:\Program Files\Avest\AvPCM_ncesBign\AvPCM.exe",
        "C:\Program Files (x86)\Avest\AvPCM_ncesBign\AvPCM.exe",
        "C:\Program Files\Avest\AvPCM_nces\MngCert.exe",
        "C:\Program Files (x86)\Avest\AvPCM_nces\MngCert.exe",
        "C:\Program Files\Avest\AvPCM_ncesBign\MngCert.exe",
        "C:\Program Files (x86)\Avest\AvPCM_ncesBign\MngCert.exe",
        "C:\Program Files\Avest\AvPCM_nces\AvCmUt4.exe",
        "C:\Program Files (x86)\Avest\AvPCM_nces\AvCmUt4.exe",
        "C:\Program Files\Avest\AvPCM_ncesBign\AvCmUt4.exe",
        "C:\Program Files (x86)\Avest\AvPCM_ncesBign\AvCmUt4.exe"
    )
    foreach ($path in $paths) {
        if (Test-Path $path) { 
            Write-Log -Message "  AvPass найден по пути: $path" -LogFile $script:LogPath
            return $true 
        }
    }
    
    # 2. Проверка через реестр по DisplayName
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

# Проверка установки AvBign
function Save-AvBign {
    Write-Log -Message "Проверка AvBign..." -LogFile $script:LogPath
    
    # 1. Проверка файловой системы
    $paths = @(
        "C:\Program Files\Avest\AvPCM\AvBign.exe",
        "C:\Program Files (x86)\Avest\AvPCM\AvBign.exe",
        "C:\Program Files\Avest\AvPCM_nces\AvBign.exe",
        "C:\Program Files (x86)\Avest\AvPCM_nces\AvBign.exe",
        "C:\Program Files\Avest\AvPCM_ncesBign\AvBign.exe",
        "C:\Program Files (x86)\Avest\AvPCM_ncesBign\AvBign.exe",
        "C:\Program Files\Avest\AvPCM_ncesBign\MngCert.exe",
        "C:\Program Files (x86)\Avest\AvPCM_ncesBign\MngCert.exe",
        "C:\Program Files\Avest\AvPCM_ncesBign\AvCmUt4.exe",
        "C:\Program Files (x86)\Avest\AvPCM_ncesBign\AvCmUt4.exe"
    )
    foreach ($path in $paths) {
        if (Test-Path $path) { 
            Write-Log -Message "  AvBign найден по пути: $path" -LogFile $script:LogPath
            return $true 
        }
    }
    
    # 2. Проверка через реестр по DisplayName
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

# Проверка установки AvCSPBel
function Test-AvCSPBel {
    Write-Log -Message "Проверка AvCSPBel..." -LogFile $script:LogPath
    
    # 1. Проверка файловой системы
    $paths = @(
        "C:\Program Files\Avest\Avest CSP Bel\AvCSPr.dll",
        "C:\Program Files (x86)\Avest\Avest CSP Bel\AvCSPr.dll",
        "C:\Program Files\Avest\Avest CSP Bel\AvCSPBel.dll",
        "C:\Program Files (x86)\Avest\Avest CSP Bel\AvCSPBel.dll"
    )
    foreach ($path in $paths) {
        if (Test-Path $path) { 
            Write-Log -Message "  AvCSPBel найден по пути: $path" -LogFile $script:LogPath
            return $true 
        }
    }
    
    # 2. Проверка через реестр по DisplayName
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

# Проверка установки AvCSPBign
function Test-AvCSPBign {
    Write-Log -Message "Проверка AvCSPBign..." -LogFile $script:LogPath
    
    # 1. Проверка файловой системы
    $paths = @(
        "C:\Program Files\Avest\Avest CSP Bign\AvCSPr.dll",
        "C:\Program Files (x86)\Avest\Avest CSP Bign\AvCSPr.dll",
        "C:\Program Files\Avest\Avest CSP Bign\AvCSPBign.dll",
        "C:\Program Files (x86)\Avest\Avest CSP Bign\AvCSPBign.dll"
    )
    foreach ($path in $paths) {
        if (Test-Path $path) { 
            Write-Log -Message "  AvCSPBign найден по пути: $path" -LogFile $script:LogPath
            return $true 
        }
    }
    
    # 2. Проверка через реестр по DisplayName
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