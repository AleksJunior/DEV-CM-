<#
Copyright (c) 2026 Alex Bird
MIT License

.SYNOPSIS
    Развертывание Менеджера сертификатов V1.0 в C:\CM
.DESCRIPTION
    Автоматическое развертывание из сетевой папки на локальный компьютер.
    
    Алгоритм:
    1. Проверка прав администратора
    2. Установка политики выполнения RemoteSigned (если нужно)
    3. Проверка доступности сетевой папки-источника
    4. Создание C:\CM и подпапок (logs, downloads, config, avest\archives, avest\unpacked)
    5. Копирование всех скриптов (V1) и конфигураций
    6. Разблокировка скриптов (Unblock-File)
    7. Создание ярлыка на рабочем столе
    8. Настройка автозапуска (Create-ScheduledTaskV1.ps1)
    9. Автоматический запуск CertificateManagerV1.ps1 через 5 секунд
    
    Коды возврата: 0 — успех, 1 — ошибка
.NOTES
    Версия: 1.0
    Папка деплоя: C:\CM
    Требует права администратора
    Источник: изменить переменную $source
#>

# ======================================================
# 1. ПРОВЕРКА ПРАВ АДМИНИСТРАТОРА
# ======================================================
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Запрос прав администратора..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# ======================================================
# 2. НАСТРОЙКА ПАРАМЕТРОВ
# ======================================================
# Источник (сетевая папка) — ИЗМЕНИТЕ ПОД СВОЮ СЕТЬ
$source = "D:\BackBox\DEV\DEV-CM-"

# Целевая папка
$target = "C:\CM"

# ======================================================
# 3. ПРОВЕРКА ДОСТУПНОСТИ ИСТОЧНИКА
# ======================================================
if (-not (Test-Path $source)) {
    Write-Host ""
    Write-Host ("="*70) -ForegroundColor Red
    Write-Host "  ОШИБКА: Сетевая папка недоступна!" -ForegroundColor Red
    Write-Host ("="*70) -ForegroundColor Red
    Write-Host ""
    Write-Host "Путь: $source" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Проверьте:" -ForegroundColor Cyan
    Write-Host "  1. Доступность компьютера в сети" -ForegroundColor Gray
    Write-Host "  2. Наличие общего доступа к папке" -ForegroundColor Gray
    Write-Host "  3. Правильность пути (отредактируйте переменную `$source)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Нажмите Enter для выхода..." -ForegroundColor Gray
    pause
    exit 1
}

# ======================================================
# 4. УСТАНОВКА ПОЛИТИКИ ВЫПОЛНЕНИЯ (ЕСЛИ НУЖНО)
# ======================================================
Clear-Host
Write-Host ("="*70) -ForegroundColor Cyan
Write-Host "  РАЗВЕРТЫВАНИЕ МЕНЕДЖЕРА СЕРТИФИКАТОВ V1.0" -ForegroundColor Cyan
Write-Host ("="*70) -ForegroundColor Cyan
Write-Host "Источник: $source" -ForegroundColor White
Write-Host "Цель: $target" -ForegroundColor White
Write-Host ""

Write-Host "[1/7] Проверка политики выполнения..." -ForegroundColor Yellow

$currentPolicy = Get-ExecutionPolicy
if ($currentPolicy -eq "Restricted") {
    Write-Host "  Текущая политика: Restricted (скрипты запрещены)" -ForegroundColor Red
    Write-Host "  Установка RemoteSigned..." -ForegroundColor Gray
    try {
        Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force -ErrorAction Stop
        Write-Host "  [+] Политика установлена: RemoteSigned" -ForegroundColor Green
    } catch {
        Write-Host "  [!] Не удалось изменить политику автоматически." -ForegroundColor Yellow
        Write-Host "  Выполните вручную от администратора: Set-ExecutionPolicy RemoteSigned -Force" -ForegroundColor Cyan
    }
} else {
    Write-Host "  [+] Политика уже разрешает скрипты: $currentPolicy" -ForegroundColor Green
}
Write-Host ""

# ======================================================
# 5. СОЗДАНИЕ ПАПОК
# ======================================================
Write-Host "[2/7] Создание целевой папки..." -ForegroundColor Yellow
if (!(Test-Path $target)) {
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Write-Host "  [+] Создано: $target" -ForegroundColor Green
} else {
    Write-Host "  [!] Папка уже существует: $target" -ForegroundColor Gray
}

Write-Host ""
Write-Host "[3/7] Создание структуры папок..." -ForegroundColor Yellow

$foldersToCreate = @(
    "logs",
    "downloads",
    "config",
    "avest\archives",
    "avest\unpacked"
)

foreach ($folder in $foldersToCreate) {
    $fullPath = Join-Path $target $folder
    if (!(Test-Path $fullPath)) {
        New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
        Write-Host "  [+] Создано: $folder" -ForegroundColor Green
    } else {
        Write-Host "  [!] Уже существует: $folder" -ForegroundColor Gray
    }
}

# ======================================================
# 6. КОПИРОВАНИЕ ФАЙЛОВ
# ======================================================
Write-Host ""
Write-Host "[4/7] Копирование файлов..." -ForegroundColor Yellow

$filesToCopy = @(
    "CertificateManagerV1.ps1",
    "Update-CertificatesV1.ps1",
    "Update-CertificatesV1_Core.ps1",
    "Update-OnlyCertificatesV1.ps1",
    "Install-AvestComponentsV1.ps1",
    "Install-AvCMXWebPV1.ps1",
    "Create-ScheduledTaskV1.ps1",
    "Common-FunctionsV1.ps1",
    "enable_scriptsV1.ps1",
    "disable_scriptsV1.ps1",
    "all_certs_urls.txt"
)

$configFiles = @(
    "avest_urls.ini"
)

$copied = 0
$missing = 0

foreach ($fileName in $filesToCopy) {
    $sourceFile = Join-Path $source $fileName
    $destFile = Join-Path $target $fileName
    
    if (Test-Path $sourceFile) {
        Copy-Item -Path $sourceFile -Destination $destFile -Force
        Write-Host "  [+] $fileName" -ForegroundColor Green
        $copied++
    } else {
        Write-Host "  [X] Не найден: $fileName" -ForegroundColor Red
        $missing++
    }
}

Write-Host ""
foreach ($fileName in $configFiles) {
    $sourceFile = Join-Path $source "config" | Join-Path -ChildPath $fileName
    $destFile = Join-Path $target "config" | Join-Path -ChildPath $fileName
    
    if (Test-Path $sourceFile) {
        Copy-Item -Path $sourceFile -Destination $destFile -Force
        Write-Host "  [+] config\$fileName" -ForegroundColor Green
        $copied++
    } else {
        Write-Host "  [X] Не найден: config\$fileName" -ForegroundColor Red
        $missing++
    }
}

Write-Host ""
Write-Host "  Итого: $copied скопировано, $missing отсутствует" -ForegroundColor Gray

# ======================================================
# 7. РАЗБЛОКИРОВКА СКРИПТОВ
# ======================================================
Write-Host ""
Write-Host "[5/7] Разблокировка скриптов..." -ForegroundColor Yellow

$psFiles = Get-ChildItem -Path $target -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
$unblocked = 0

if ($psFiles.Count -gt 0) {
    foreach ($file in $psFiles) {
        try {
            Unblock-File -Path $file.FullName -ErrorAction Stop
            $unblocked++
        } catch { }
    }
    Write-Host "  [+] Разблокировано: $unblocked из $($psFiles.Count)" -ForegroundColor Green
} else {
    Write-Host "  [!] Файлы .ps1 не найдены" -ForegroundColor Yellow
}

# ======================================================
# 8. СОЗДАНИЕ ЯРЛЫКА
# ======================================================
Write-Host ""
Write-Host "[6/7] Создание ярлыка на рабочем столе..." -ForegroundColor Yellow

$desktopPath = [Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktopPath "Менеджер сертификатов V1.0.lnk"
$targetScript = Join-Path $target "CertificateManagerV1.ps1"

if (Test-Path $targetScript) {
    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = "powershell.exe"
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File `"$targetScript`""
    $shortcut.WorkingDirectory = $target
    $shortcut.IconLocation = "powershell.exe,0"
    $shortcut.Description = "Менеджер сертификатов V1.0"
    $shortcut.Save()
    Write-Host "  [+] Ярлык создан: $shortcutPath" -ForegroundColor Green
} else {
    Write-Host "  [X] CertificateManagerV1.ps1 не найден" -ForegroundColor Red
}

# ======================================================
# 9. НАСТРОЙКА АВТОЗАПУСКА
# ======================================================
Write-Host ""
Write-Host "[7/7] Настройка автозапуска..." -ForegroundColor Yellow

$autoStartScript = Join-Path $target "Create-ScheduledTaskV1.ps1"

if (Test-Path $autoStartScript) {
    Write-Host "  Запуск Create-ScheduledTaskV1.ps1..." -ForegroundColor Gray
    & $autoStartScript
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [+] Задача создана" -ForegroundColor Green
    } else {
        Write-Host "  [!] Ошибка создания задачи" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [X] Create-ScheduledTaskV1.ps1 не найден" -ForegroundColor Red
}

# ======================================================
# 10. ЗАВЕРШЕНИЕ И ЗАПУСК
# ======================================================
Write-Host ""
Write-Host ("="*70) -ForegroundColor Cyan
Write-Host "  РАЗВЕРТЫВАНИЕ ЗАВЕРШЕНО" -ForegroundColor Cyan
Write-Host ("="*70) -ForegroundColor Cyan
Write-Host ""
Write-Host "Папка: $target" -ForegroundColor White
Write-Host "Ярлык: Менеджер сертификатов V1.0" -ForegroundColor White
Write-Host ""

Write-Host "Через 5 секунд будет запущен Менеджер..." -ForegroundColor Yellow
Write-Host "Нажмите Ctrl+C для отмены." -ForegroundColor Gray

for ($i = 5; $i -gt 0; $i--) {
    Write-Host "  `r$i..." -NoNewline
    Start-Sleep -Seconds 1
}
Write-Host ""

if (Test-Path $targetScript) {
    Write-Host "Запуск CertificateManagerV1.ps1..." -ForegroundColor Green
    Start-Process -FilePath "powershell.exe" `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File `"$targetScript`"" `
        -WorkingDirectory $target
    Write-Host "  [+] Менеджер запущен" -ForegroundColor Green
} else {
    Write-Host "  [X] CertificateManagerV1.ps1 не найден" -ForegroundColor Red
}

Write-Host ""
Write-Host "Нажмите Enter для выхода..."
pause