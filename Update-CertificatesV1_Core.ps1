<#
Copyright (c) 2026 Alex Bird
MIT License

.SYNOPSIS
    Ядро обновления сертификатов и CRL.
.DESCRIPTION
    Читает all_certs_urls.txt (пропускает строки с #).
    Для каждого URL:
    - Скачивает во временную папку (через WebRequest)
    - Копирует в .\downloads\
    - Импортирует в хранилища Windows:
      .cer → Root (если root/kuc/mns_root) или CA (остальные)
      .crl → через AvCmUt4.exe или certutil
      .p7b → certutil -addstore CA
    
    Ищет AvCmUt4.exe и MngCert.exe в C:\Program Files\Avest\AvPCM*\.
    При импорте проверяет "already exists", NTE_BAD_KEYSET (fallback через .NET).
    Перед импортом закрывает блокирующие процессы (AvPCM, MngCert, mmc, certmgr).
    Результат в JSON (если передан -ResultFile).
.NOTES
    Версия: 1.0
    Папка деплоя: C:\CM
    Логи: C:\CM\logs\import_*.log
    Временная папка: $env:TEMP\cert_import_*
#>

param(
    [string]$ResultFile
)

# ======================================================
# 1. НАСТРОЙКА ПУТЕЙ
# ======================================================
if ($MyInvocation.MyCommand.CommandType -eq "ExternalScript") {
    $scriptPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
} else {
    $scriptPath = Split-Path -Parent -Path ([Environment]::GetCommandLineArgs()[0])
    if (!$scriptPath) { $scriptPath = "." }
}

$urlsFile = Join-Path $scriptPath "all_certs_urls.txt"
$logsFolder = Join-Path $scriptPath "logs"
$downloadsFolder = Join-Path $scriptPath "downloads"
$tempFolder = Join-Path $env:TEMP "cert_import_$(Get-Random)"

# ======================================================
# 2. СОЗДАНИЕ ПАПОК
# ======================================================
Write-Host "Создание папок..."
foreach ($folder in @($logsFolder, $downloadsFolder, $tempFolder)) {
    if (!(Test-Path $folder)) { 
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Write-Host "  + $folder"
    }
}

# ======================================================
# 3. ФАЙЛ ЛОГА
# ======================================================
$logFile = "$logsFolder\import_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
"СТАРТ: $(Get-Date)" | Out-File $logFile
("="*70) | Out-File $logFile -Append

# ======================================================
# 4. ФУНКЦИИ
# ======================================================

function Write-LogEntry {
    param([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $message" | Out-File $logFile -Append
}

# Функция Save-File 
function Save-File {
    param([string]$url, [string]$savePath)
    try {
        $webRequest = [System.Net.WebRequest]::Create($url)
        $webRequest.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        $webRequest.Timeout = 30000
        $response = $webRequest.GetResponse()
        $stream = $response.GetResponseStream()
        $fileStream = [System.IO.File]::Create($savePath)
        $stream.CopyTo($fileStream)
        $fileStream.Close()
        $stream.Close()
        $response.Close()
        return $true
    } catch {
        return $false
    }
}

function Import-Certificate {
    param([string]$filePath, [string]$fileName)
    
    if ($fileName -like "*root*" -or $fileName -match "kuc|mns_root") {
        $store = "Root"
    } else {
        $store = "CA"
    }
    
    if ($mngCert) {
        Write-LogEntry "Пробуем MngCert.exe для $fileName"
        $params = "/importcert /silentrun `"$filePath`""
        try {
            $process = Start-Process -FilePath $mngCert -ArgumentList $params -Wait -PassThru -NoNewWindow -ErrorAction Stop
            Write-LogEntry "Код выхода MngCert.exe: $($process.ExitCode)"
            if ($process.ExitCode -eq 0) {
                Write-LogEntry "ОК (MngCert.exe - $store): $fileName"
                return $true
            } else {
                Write-LogEntry "MngCert.exe не сработал, пробуем certutil..."
            }
        } catch {
            Write-LogEntry "Ошибка MngCert.exe: $($_.Exception.Message), пробуем certutil..."
        }
    }
    
    $output = certutil -addstore $store $filePath 2>&1
    $exitCode = $LASTEXITCODE
    
    if ($exitCode -eq 0) {
        Write-LogEntry "ОК (certutil - $store): $fileName"
        return $true
    }
    
    $outputString = $output | Out-String
    if ($outputString -match "already exists") {
        Write-LogEntry "ИНФО: Сертификат $fileName уже существует в хранилище $store"
        return $true
    }
    
    if ($outputString -match "0x80090016" -or $outputString -match "NTE_BAD_KEYSET") {
        Write-LogEntry "ПРЕДУПРЕЖДЕНИЕ: NTE_BAD_KEYSET, пробуем .NET..."
        try {
            $certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
            $certificate.Import($filePath)
            $storeObject = New-Object System.Security.Cryptography.X509Certificates.X509Store($store, "LocalMachine")
            $storeObject.Open("ReadWrite")
            $existing = $storeObject.Certificates | Where-Object { $_.Thumbprint -eq $certificate.Thumbprint }
            if ($existing) {
                Write-LogEntry "ИНФО: Сертификат уже существует"
                $storeObject.Close()
                return $true
            }
            $storeObject.Add($certificate)
            $storeObject.Close()
            Write-LogEntry "ОК (.NET fallback): $fileName"
            return $true
        } catch {
            Write-LogEntry "ОШИБКА: .NET fallback не сработал: $_"
            return $false
        }
    }
    
    Write-LogEntry "ОШИБКА: $fileName (код certutil $exitCode)"
    return $false
}

function Import-CRL {
    param([string]$filePath, [string]$fileName)
    
    if ($avCmUt4) {
        & $avCmUt4 -C $filePath -NA *>$null
        $exitCode = $LASTEXITCODE
        
        if ($exitCode -eq 0 -or $exitCode -eq 18) {
            Write-LogEntry "ОК (AvCmUt4): $fileName"
            return $true
        } else {
            certutil -addstore CA $filePath *>$null
            if ($LASTEXITCODE -eq 0) {
                Write-LogEntry "ОК (certutil - fallback): $fileName"
                return $true
            } else {
                Write-LogEntry "ОШИБКА: $fileName (код $exitCode)"
                return $false
            }
        }
    } else {
        certutil -addstore CA $filePath *>$null
        if ($LASTEXITCODE -eq 0) {
            Write-LogEntry "ОК (certutil): $fileName"
            return $true
        } else {
            Write-LogEntry "ОШИБКА: $fileName (код certutil $LASTEXITCODE)"
            return $false
        }
    }
}

function Import-P7B {
    param([string]$filePath, [string]$fileName)
    certutil -addstore CA $filePath *>$null
    if ($LASTEXITCODE -eq 0) {
        Write-LogEntry "ОК (p7b): $fileName"
        return $true
    } else {
        Write-LogEntry "ОШИБКА: $fileName (код p7b $LASTEXITCODE)"
        return $false
    }
}

# ======================================================
# 5. ПОИСК УТИЛИТ AvCmUt4.exe И MngCert.exe
# ======================================================
$avCmUt4 = $null
$mngCert = $null

$possiblePaths = @(
    "C:\Program Files\Avest\AvPCM_nces\AvCmUt4.exe",
    "C:\Program Files (x86)\Avest\AvPCM_nces\AvCmUt4.exe",
    "C:\Program Files\Avest\AvPCM_ncesBign\AvCmUt4.exe",
    "C:\Program Files (x86)\Avest\AvPCM_ncesBign\AvCmUt4.exe",
    "C:\Program Files\Avest\AvPCM\AvCmUt4.exe",
    "C:\Program Files (x86)\Avest\AvPCM\AvCmUt4.exe"
)

foreach ($path in $possiblePaths) {
    if (Test-Path $path) {
        $avCmUt4 = $path
        Write-Host "AvCmUt4 найден: $avCmUt4"
        Write-LogEntry "AvCmUt4 найден: $avCmUt4"
        
        $mngCertPath = Join-Path (Split-Path $path) "MngCert.exe"
        if (Test-Path $mngCertPath) {
            $mngCert = $mngCertPath
            Write-Host "MngCert.exe найден: $mngCert"
            Write-LogEntry "MngCert.exe найден: $mngCert"
        }
        break
    }
}

if (-not $mngCert) {
    $mngCertPaths = @(
        "C:\Program Files\Avest\AvPCM_nces\MngCert.exe",
        "C:\Program Files (x86)\Avest\AvPCM_nces\MngCert.exe",
        "C:\Program Files\Avest\AvPCM_ncesBign\MngCert.exe",
        "C:\Program Files (x86)\Avest\AvPCM_ncesBign\MngCert.exe",
        "C:\Program Files\Avest\AvPCM\MngCert.exe",
        "C:\Program Files (x86)\Avest\AvPCM\MngCert.exe"
    )
    foreach ($path in $mngCertPaths) {
        if (Test-Path $path) {
            $mngCert = $path
            Write-Host "MngCert.exe найден: $mngCert"
            Write-LogEntry "MngCert.exe найден: $mngCert"
            break
        }
    }
}

if (-not $avCmUt4) {
    Write-Host "AvCmUt4 не найден, используем certutil для CRL"
    Write-LogEntry "AvCmUt4 не найден, используем certutil для CRL"
}

if (-not $mngCert) {
    Write-Host "MngCert.exe не найден, используем certutil для сертификатов"
    Write-LogEntry "MngCert.exe не найден, используем certutil для сертификатов"
}

# ======================================================
# 5.1. ПРОВЕРКА ЦЕЛОСТНОСТИ
# ======================================================
if ($avCmUt4 -and $mngCert) {
    $integrityOK = $true
} else {
    $integrityOK = $false
}

# ======================================================
# 6. ПРОВЕРКИ
# ======================================================
Write-Host ("="*70)
Write-Host "НАЧАЛО ОБНОВЛЕНИЯ"
Write-Host ("="*70)

if (!(Test-Path $urlsFile)) {
    Write-Host "Файл $urlsFile не найден!"
    Write-LogEntry "ОШИБКА: Файл со ссылками не найден: $urlsFile"
    exit 1
}

if ($avCmUt4) {
    Write-Host "AvCmUt4 найден: $avCmUt4"
} else {
    Write-Host "AvCmUt4 не найден, используем certutil для CRL"
}

if ($mngCert) {
    Write-Host "MngCert.exe найден: $mngCert"
} else {
    Write-Host "MngCert.exe не найден, используем certutil для сертификатов"
}

# ======================================================
# 7. ЧТЕНИЕ ССЫЛОК
# ======================================================
$urls = Get-Content $urlsFile | Where-Object { $_ -and !$_.StartsWith("#") }
$totalUrls = $urls.Count
Write-Host "Найдено ссылок: $totalUrls"
Write-LogEntry "Найдено $totalUrls ссылок в $urlsFile"

# ======================================================
# 8. СКАЧИВАНИЕ ФАЙЛОВ
# ======================================================
Write-Host ("`n" + ("="*70))
Write-Host "СКАЧИВАНИЕ ФАЙЛОВ"
Write-Host ("="*70)

$downloadedFiles = @{}
$downloadedCount = 0

foreach ($url in $urls) {
    $url = $url.Trim()
    if (!$url) { continue }
    
    $fileName = $url.Split('/')[-1]
    $tempFile = Join-Path $tempFolder $fileName
    $savedFile = Join-Path $downloadsFolder $fileName
    
    $downloadedCount++
    Write-Host "`n[$downloadedCount/$totalUrls] $fileName"
    
    if (Save-File -url $url -savePath $tempFile) {
        $size = (Get-Item $tempFile).Length
        Write-Host "  Скачано, размер: $size байт"
        Write-LogEntry "ОК (скачивание): $fileName ($size байт)"
        Copy-Item $tempFile $savedFile -Force
        $downloadedFiles[$fileName] = @{ Path = $savedFile }
    } else {
        Write-Host "  Ошибка скачивания"
        Write-LogEntry "ОШИБКА (скачивание): $url"
    }
}

# ======================================================
# 9. ИМПОРТ ФАЙЛОВ
# ======================================================
$successCertificates = 0
$successCRLs = 0
$successContainers = 0
$totalCertificates = 0
$totalCRLs = 0
$totalContainers = 0

Write-Host ("`n" + ("="*70))
Write-Host "ИМПОРТ ФАЙЛОВ"
Write-Host ("="*70)

# ======================================================
# ПРОВЕРКА ОТКРЫТЫХ ПРОГРАММ, БЛОКИРУЮЩИХ ХРАНИЛИЩЕ
# ======================================================
function Close-BlockingPrograms {
    $blockingProcesses = @(
        "certmgr",
        "mmc",
        "AvPCM",
        "MngCert",
        "AvCmUt4",
        "AvPKISetup2"
    )
    
    $foundProcesses = @()
    
    foreach ($procName in $blockingProcesses) {
        $procs = Get-Process -Name $procName -ErrorAction SilentlyContinue
        if ($procs) {
            $foundProcesses += $procs
        }
    }
    
    if ($foundProcesses.Count -gt 0) {
        Write-Host "`n" + ("="*70) -ForegroundColor Yellow
        Write-Host "  ВНИМАНИЕ: Обнаружены программы, блокирующие хранилище!" -ForegroundColor Yellow
        Write-Host ("="*70) -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Найдены процессы:" -ForegroundColor Cyan
        foreach ($proc in $foundProcesses) {
            Write-Host "  • $($proc.Name) (PID: $($proc.Id))" -ForegroundColor Gray
        }
        Write-Host ""
        Write-Host "Эти программы блокируют импорт сертификатов." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Пожалуйста, закройте:" -ForegroundColor Cyan
        Write-Host "  • Комплект Абонента Авест (AvPCM)" -ForegroundColor Gray
        Write-Host "  • Менеджер сертификатов Авест (MngCert)" -ForegroundColor Gray
        Write-Host "  • Управление сертификатами Windows (certmgr.msc)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Скрипт будет ждать закрытия... (Ctrl+C для отмены)" -ForegroundColor Gray
        Write-Host ""
        
        do {
            Write-Host "  Ожидание..." -ForegroundColor Gray
            Start-Sleep -Seconds 5
            
            $stillOpen = @()
            foreach ($procName in $blockingProcesses) {
                $procs = Get-Process -Name $procName -ErrorAction SilentlyContinue
                if ($procs) {
                    $stillOpen += $procs
                }
            }
        } while ($stillOpen.Count -gt 0)
        
        Write-Host ""
        Write-Host "  Все блокирующие программы закрыты. Продолжение..." -ForegroundColor Green
        Write-Host ""
        Start-Sleep -Seconds 2
    }
}

# Вызвать перед импортом
Close-BlockingPrograms

foreach ($key in $downloadedFiles.Keys) {
    $info = $downloadedFiles[$key]
    Write-Host "`n$key"
    
    if ($key -like "*.cer") {
        $totalCertificates++
        if (Import-Certificate -filePath $info.Path -fileName $key) {
            $successCertificates++
        }
    }
    elseif ($key -like "*.crl") {
        $totalCRLs++
        if (Import-CRL -filePath $info.Path -fileName $key) {
            $successCRLs++
        }
    }
    elseif ($key -like "*.p7b") {
        $totalContainers++
        if (Import-P7B -filePath $info.Path -fileName $key) {
            $successContainers++
        }
    }
}

# ======================================================
# 10. РЕЗУЛЬТАТЫ
# ======================================================
$totalImported = $successCertificates + $successCRLs + $successContainers
$totalErrors = ($totalCertificates - $successCertificates) + ($totalCRLs - $successCRLs) + ($totalContainers - $successContainers)

Write-Host ("="*70)
Write-Host "РЕЗУЛЬТАТЫ"
Write-Host ("="*70)
Write-Host "Скачано: $downloadedCount из $totalUrls"
Write-Host ""
Write-Host "Импорт:"
Write-Host "  Сертификаты (.cer): $successCertificates из $totalCertificates"
Write-Host "  Списки отзыва (.crl): $successCRLs из $totalCRLs"
Write-Host "  Контейнеры (.p7b): $successContainers из $totalContainers"
Write-Host "  Всего импортировано: $totalImported"
Write-Host "  Ошибок: $totalErrors"
Write-Host ""
Write-Host "Лог: $logFile"
Write-Host ("="*70)

# Сохраняем в лог
@"

============================================================
РЕЗУЛЬТАТЫ
============================================================
Скачано: $downloadedCount из $totalUrls

Импорт:
  Сертификаты (.cer): $successCertificates из $totalCertificates
  Списки отзыва (.crl): $successCRLs из $totalCRLs
  Контейнеры (.p7b): $successContainers из $totalContainers
  Всего импортировано: $totalImported
  Ошибок: $totalErrors

Лог: $logFile
============================================================
"@ | Out-File $logFile -Append

# ======================================================
# 11. СОХРАНЕНИЕ РЕЗУЛЬТАТА
# ======================================================
if ($ResultFile) {
    $result = @{
        Success = $totalImported
        Errors = $totalErrors
        Total = $downloadedCount
        LogFile = $logFile
        Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        AvCmUt4 = if ($avCmUt4) { "Найден" } else { "Не найден" }
        MngCert = if ($mngCert) { "Найден" } else { "Не найден" }
        IntegrityCheck = if ($integrityOK) { "Пройдена" } else { "Нарушена" }
    } | ConvertTo-Json
    $result | Out-File $ResultFile -Encoding utf8
}

# ======================================================
# 12. ОЧИСТКА
# ======================================================
Remove-Item $tempFolder -Recurse -Force -ErrorAction SilentlyContinue

# Удаляем лог-файл AvCmUt4.log, если он создался
$avCmUt4Log = Join-Path $env:TEMP "AvCmUt4.log"
if (Test-Path $avCmUt4Log) {
    Remove-Item $avCmUt4Log -Force -ErrorAction SilentlyContinue
}

Write-Host "ГОТОВО!"

if ($totalErrors -gt 0) { exit 1 } else { exit 0 }