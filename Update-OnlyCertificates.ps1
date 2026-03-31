<#
.SYNOPSIS
    Обновление сертификатов и списков отзыва (CRL) без установки компонентов
.DESCRIPTION
    Скрипт для обновления сертификатов и списков отзыва (CRL) из файла all_certs_urls.txt.
    
    Особенности:
        - НЕ затрагивает установку компонентов Авест
        - Только скачивание и импорт сертификатов и CRL
        - Подходит для регулярного обновления (например, через планировщик)
    
    Алгоритм работы:
        1. Проверка прав администратора (запуск с повышенными правами)
        2. Передача управления в Update-CertificatesV2_Core.ps1
        3. Ожидание завершения и возврат кода результата
    
    Использование:
        - Из графического интерфейса CertificateManagerV2.ps1
        - Из планировщика заданий (автоматическое обновление)
        - Из командной строки с параметром -ResultFile для сохранения результата
    
    Параметры:
        -ResultFile : путь к файлу для сохранения результата в формате JSON
                     (используется для интеграции с другими системами)
    
    Коды возврата:
        0 - успешное завершение (все сертификаты обновлены)
        1 - ошибка (проблемы с загрузкой или импортом)
    
    Логи:
        Основное логирование выполняется в Update-CertificatesV2_Core.ps1
        Логи сохраняются в .\logs\import_*.log
.NOTES
    Версия: 2.0
    Требования:
        - PowerShell 5.0+
        - Права администратора
        - Файл all_certs_urls.txt в папке со скриптом
    
    Пример запуска:
        .\Update-OnlyCertificates.ps1
        .\Update-OnlyCertificates.ps1 -ResultFile "C:\temp\result.json"
    
    Встроенная обработка:
        - Регистрация обработчика PowerShell.Exiting для корректного выхода
        - Автоматический запрос прав администратора при необходимости
    
    Используемые утилиты:
        - MngCert.exe (при наличии) - для импорта сертификатов
        - AvCmUt4.exe (при наличии) - для импорта CRL
        - certutil.exe (как резервный вариант)
#>

param(
    [string]$ResultFile
)

# ======================================================
# 0. EXIT HANDLER
# ======================================================
$script:NormalExit = $false

# Register window close handler
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -SupportEvent -Action {
    if (-not $script:NormalExit) {
        # Normal window close - exit with 0
        [Environment]::Exit(0)
    }
} | Out-Null

# ======================================================
# 1. SETUP PATHS
# ======================================================
if ($MyInvocation.MyCommand.CommandType -eq "ExternalScript") {
    $ScriptPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
} else {
    $ScriptPath = Split-Path -Parent -Path ([Environment]::GetCommandLineArgs()[0])
    if (!$ScriptPath) { $ScriptPath = "." }
}

$CoreScript = Join-Path $ScriptPath "Update-CertificatesV2_Core.ps1"

# ======================================================
# 2. CHECK ADMIN RIGHTS
# ======================================================
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Запрос прав администратора..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -ResultFile `"$ResultFile`"" -Verb RunAs
    exit
}

Write-Host ("="*70) -ForegroundColor Cyan
Write-Host "  ОБНОВЛЕНИЕ СЕРТИФИКАТОВ" -ForegroundColor Yellow
Write-Host "  Без установки компонентов Авест" -ForegroundColor White
Write-Host ("="*70) -ForegroundColor Cyan
Write-Host ""

# ======================================================
# 3. CHECK SCRIPT EXISTS
# ======================================================
if (-not (Test-Path $CoreScript)) {
    Write-Host "ОШИБКА: Скрипт обновления сертификатов не найден: $CoreScript" -ForegroundColor Red
    $script:NormalExit = $true
    exit 1
}

# ======================================================
# 4. RUN CERTIFICATE UPDATE
# ======================================================
Write-Host "Запуск обновления сертификатов..." -ForegroundColor Yellow
Write-Host ""

& $CoreScript -ResultFile $ResultFile
$exitCode = $LASTEXITCODE

$script:NormalExit = $true
exit $exitCode