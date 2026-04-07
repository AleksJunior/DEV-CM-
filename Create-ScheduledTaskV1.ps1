<#
Copyright (c) 2026 Alex Bird
MIT License

.SYNOPSIS
    Создание задачи в планировщике для автозапуска обновления сертификатов.
.DESCRIPTION
    Параметры задачи:
    - Имя: Update-OnlyCertificatesV1
    - Триггер: при старте системы
    - Задержка: 2 минуты
    - Пользователь: SYSTEM
    - Права: HIGHEST
    - Действие: powershell.exe -File .\Update-OnlyCertificatesV1.ps1
    
    Создаётся временный скрипт-обёртка в TEMP с проверкой интернета
    (ожидание до 5 минут, 10 попыток по 30 сек).
    Старая задача удаляется, логи обёртки: C:\CM\logs\autostart_*.log
.NOTES
    Версия: 1.0
    Папка деплоя: C:\CM
    Требует права администратора
    Просмотр: taskschd.msc → Update-OnlyCertificatesV1
#>

# ======================================================
# ПРОВЕРКА ПРАВ АДМИНИСТРАТОРА
# ======================================================
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Запрос прав администратора..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# ======================================================
# 1. ОПРЕДЕЛЕНИЕ ПУТИ К СКРИПТУ
# ======================================================
# Получаем путь к папке, откуда запущен скрипт
if ($MyInvocation.MyCommand.CommandType -eq "ExternalScript") {
    $scriptPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
} else {
    $scriptPath = Split-Path -Parent -Path ([Environment]::GetCommandLineArgs()[0])
    if (!$scriptPath) { $scriptPath = "." }
}

# ======================================================
# 2. НАСТРОЙКА ПАРАМЕТРОВ ЗАДАЧИ
# ======================================================
# Путь к скрипту обновления и имя задачи в планировщике
$updateScript = Join-Path $scriptPath "Update-OnlyCertificatesV1.ps1"
$taskName = "Update-OnlyCertificatesV1"

# ======================================================
# 3. ПРОВЕРКА СУЩЕСТВОВАНИЯ СКРИПТА
# ======================================================
# Проверяем, существует ли файл скрипта обновления
if (!(Test-Path $updateScript)) { 
    Write-Host "Скрипт не найден: $updateScript" -ForegroundColor Red
    Write-Host "Убедитесь, что файл Update-OnlyCertificatesV1.ps1 находится в папке:" -ForegroundColor Yellow
    Write-Host "  $scriptPath" -ForegroundColor Gray
    pause
    exit 1
}

Write-Host "Скрипт найден: $updateScript" -ForegroundColor Green
Write-Host "Создание задачи в планировщике..." -ForegroundColor Yellow

# ======================================================
# 4. ПОДТВЕРЖДЕНИЕ СОЗДАНИЯ ЗАДАЧИ
# ======================================================
Write-Host ""
Write-Host "Будет создана задача '$taskName' со следующими параметрами:" -ForegroundColor Cyan
Write-Host "  - Запуск: при старте системы" -ForegroundColor Gray
Write-Host "  - Задержка: 2 минуты" -ForegroundColor Gray
Write-Host "  - Пользователь: SYSTEM" -ForegroundColor Gray
Write-Host "  - Действие: только обновление сертификатов" -ForegroundColor Gray
Write-Host "  - Проверка интернета: ДА (ожидание до 5 минут)" -ForegroundColor Gray
Write-Host ""
Write-Host "Продолжить? (д/н)" -ForegroundColor Yellow

$confirmation = Read-Host
if ($confirmation -ne "д" -and $confirmation -ne "Д" -and $confirmation -ne "y" -and $confirmation -ne "Y") {
    Write-Host "Операция отменена пользователем." -ForegroundColor Gray
    pause
    exit 0
}

# ======================================================
# 5. УДАЛЕНИЕ СТАРОЙ ЗАДАЧИ (ЕСЛИ СУЩЕСТВУЕТ)
# ======================================================
Write-Host "Удаление старой задачи (если существует)..." -ForegroundColor Gray
schtasks /delete /tn $taskName /f 2>$null

# ======================================================
# 6. СОЗДАНИЕ ВРЕМЕННОГО СКРИПТА-ОБЁРТКИ С ПРОВЕРКОЙ СЕТИ
# ======================================================
Write-Host "Создание временного скрипта-обёртки..." -ForegroundColor Gray
$tempScript = Join-Path $env:TEMP "check_network_and_run_v2.ps1"

$scriptContent = @'
# Временный скрипт для проверки сети и запуска обновления V2.0
$updateScriptPath = "UPDATESCRIPT_PATH"
$logFile = "LOG_PATH"

function Write-Log {
    param([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $message" | Out-File $logFile -Append
}

function Test-Internet {
    $testUrls = @(
        "https://goszakupki.by",
        "https://nces.by",
        "https://www.portal.nalog.gov.by",
        "https://1.1.1.1"
    )
    
    foreach ($url in $testUrls) {
        try {
            $request = [System.Net.WebRequest]::Create($url)
            $request.Timeout = 5000
            $request.Method = "HEAD"
            $response = $request.GetResponse()
            $response.Close()
            return $true
        } catch {
            continue
        }
    }
    return $false
}

# Запись в лог о запуске
Write-Log "Запуск проверки интернета (V2.0)"

# Проверка интернета с ожиданием до 5 минут
$internetAvailable = Test-Internet
$attempt = 1
$maxAttempts = 10

while (-not $internetAvailable -and $attempt -le $maxAttempts) {
    Write-Log "Интернет недоступен. Попытка $attempt из $maxAttempts. Ожидание 30 секунд..."
    Start-Sleep -Seconds 30
    $internetAvailable = Test-Internet
    $attempt++
}

if ($internetAvailable) {
    Write-Log "Интернет доступен. Запуск скрипта обновления V2.0..."
    try {
        & $updateScriptPath
        Write-Log "Скрипт обновления V2.0 завершился с кодом: $LASTEXITCODE"
    } catch {
        Write-Log "Ошибка при запуске скрипта: $($_.Exception.Message)"
    }
} else {
    Write-Log "Интернет недоступен после $maxAttempts попыток. Скрипт не запущен."
}
'@

# Заменяем плейсхолдеры на реальные пути
$scriptContent = $scriptContent -replace "UPDATESCRIPT_PATH", $updateScript
$scriptContent = $scriptContent -replace "LOG_PATH", "$scriptPath\logs\autostart_$(Get-Date -Format 'yyyy-MM-dd').log"

# Сохраняем временный скрипт
$scriptContent | Out-File $tempScript -Encoding UTF8

# ======================================================
# 7. СОЗДАНИЕ ЗАДАЧИ, ЗАПУСКАЮЩЕЙ ВРЕМЕННЫЙ СКРИПТ
# ======================================================
Write-Host "Создание задачи в планировщике..." -ForegroundColor Gray
schtasks /create /tn $taskName `
    /tr "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$tempScript`"" `
    /sc onstart `
    /delay 0002:00 `
    /ru SYSTEM `
    /rl HIGHEST `
    /f

# ======================================================
# 8. ПРОВЕРКА РЕЗУЛЬТАТА
# ======================================================
if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "Задача '$taskName' создана успешно!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Параметры задачи:" -ForegroundColor Yellow
    Write-Host "  - Имя: $taskName" -ForegroundColor Gray
    Write-Host "  - Запуск: при старте системы" -ForegroundColor Gray
    Write-Host "  - Задержка: 2 минуты" -ForegroundColor Gray
    Write-Host "  - Пользователь: SYSTEM" -ForegroundColor Gray
    Write-Host "  - Проверка интернета: ДА (ожидание до 5 минут)" -ForegroundColor Gray
    Write-Host "  - Лог: $scriptPath\logs\autostart_*.log" -ForegroundColor Gray
    Write-Host ""
    
    # Запуск задачи для проверки
    Write-Host "Запуск задачи для проверки..." -ForegroundColor Yellow
    schtasks /run /tn $taskName
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Задача запущена успешно" -ForegroundColor Green
    } else {
        Write-Host "Не удалось запустить задачу (код: $LASTEXITCODE)" -ForegroundColor Yellow
        Write-Host "Проверьте правильность выполнения вручную через Планировщик заданий" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "Нажмите любую клавишу для выхода..." -ForegroundColor Gray
    pause
    exit 0
} else {
    Write-Host ""
    Write-Host "ОШИБКА: Не удалось создать задачу (код: $LASTEXITCODE)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Возможные причины:" -ForegroundColor Yellow
    Write-Host "  - Недостаточно прав (запустите скрипт от имени администратора)" -ForegroundColor Gray
    Write-Host "  - Планировщик заданий отключён" -ForegroundColor Gray
    Write-Host "  - Указан неверный путь к скрипту" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Нажмите любую клавишу для выхода..." -ForegroundColor Gray
    pause
    exit 1
}