<#
Copyright (c) 2026 Alex Bird
Use of this source code is governed by an MIT-style
license that can be found in the LICENSE file.
.SYNOPSIS
    Полное обновление: установка компонентов Авест + сертификаты
.DESCRIPTION
    Комплексный скрипт для полного обновления:
        1. Установка/обновление компонентов Авест (AvPass, AvBign, криптопровайдеры)
        2. Обновление сертификатов и списков отзыва (CRL)
    
    Алгоритм работы:
        1. Проверка прав администратора (запуск с повышенными правами)
        2. Вызов Install-AvestComponentsV1.ps1 для установки компонентов
           - Интерактивный режим с выбором компонентов
           - Автоматическая загрузка недостающих архивов
        3. Вызов Update-CertificatesV1_Core.ps1 для обновления сертификатов
        4. Возврат кода выполнения
    
    Особенности:
        - Шаг 2 (установка компонентов) можно пропустить, если компоненты уже установлены
        - Если скрипт установки не найден, выполняется только обновление сертификатов
    
    Коды возврата:
        0 - успешное завершение
        1 - ошибка (проблемы с установкой компонентов или обновлением сертификатов)
    
    Использование:
        - Ручное полное обновление системы
        - Первоначальная настройка рабочего места
        - Восстановление после сбоев
.NOTES
    Версия: 2.0
    Требования:
        - PowerShell 5.0+
        - Права администратора
        - Доступ к интернету (для загрузки компонентов)
    
    Зависимости:
        - Install-AvestComponentsV1.ps1
        - Update-CertificatesV1_Core.ps1
        - Common-FunctionsV1.ps1
    
    Порядок выполнения:
        1. Сначала устанавливаются компоненты Авест (если требуется)
        2. Затем обновляются сертификаты
    
    Важно:
        - Рекомендуется запускать после первоначальной установки системы
        - При обновлении существующих компонентов будет предложена переустановка
        - Все операции логируются в папку .\logs\
#>

# ======================================================
# 1. НАСТРОЙКА ПУТЕЙ
# ======================================================
if ($MyInvocation.MyCommand.CommandType -eq "ExternalScript") {
    $scriptPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
} else {
    $scriptPath = Split-Path -Parent -Path ([Environment]::GetCommandLineArgs()[0])
    if (!$scriptPath) { $scriptPath = "." }
}

$installScript = Join-Path $scriptPath "Install-AvestComponentsV1.ps1"
$certScript = Join-Path $scriptPath "Update-CertificatesV1_Core.ps1"

Write-Host ("="*70) -ForegroundColor Cyan
Write-Host "  ПОЛНОЕ ОБНОВЛЕНИЕ" -ForegroundColor Yellow
Write-Host "  Установка компонентов Авест + сертификаты" -ForegroundColor White
Write-Host ("="*70) -ForegroundColor Cyan
Write-Host ""

# ======================================================
# 2. УСТАНОВКА КОМПОНЕНТОВ АВЕСТ
# ======================================================
if (Test-Path $installScript) {
    Write-Host "[1/2] Проверка и установка компонентов Авест..." -ForegroundColor Yellow
    & $installScript -ScriptPath $scriptPath
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Предупреждение: установка компонентов завершилась с ошибкой" -ForegroundColor Yellow
    }
} else {
    Write-Host "[1/2] Скрипт установки не найден: $installScript" -ForegroundColor Red
    Write-Host "  Установка компонентов пропущена" -ForegroundColor Yellow
}

# ======================================================
# 3. ОБНОВЛЕНИЕ СЕРТИФИКАТОВ
# ======================================================
Write-Host ""
Write-Host "[2/2] Обновление сертификатов..." -ForegroundColor Yellow

if (Test-Path $certScript) {
    & $certScript
    exit $LASTEXITCODE
} else {
    Write-Host "  ОШИБКА: Скрипт обновления сертификатов не найден: $certScript" -ForegroundColor Red
    exit 1
}