<#
Copyright (c) 2026 Alex Bird
Use of this source code is governed by an MIT-style
license that can be found in the LICENSE file.
.SYNOPSIS
    Развертывание Менеджера сертификатов V2.0 в целевой папке
.DESCRIPTION
    Скрипт для автоматического развертывания всего комплекса Менеджера сертификатов
    из сетевой папки на локальный компьютер.
    
    Алгоритм развертывания:
        1. Проверка прав администратора (требуются для установки)
        2. Проверка доступности сетевой папки-источника
        3. Создание целевой папки C:\CertificateManager V2.0 (или указанной)
        4. Создание структуры подпапок (logs, downloads, config, avest\archives, avest\unpacked)
        5. Копирование всех скриптов и конфигурационных файлов
        6. Создание ярлыка на рабочем столе
        7. Настройка автозапуска (запуск Create-ScheduledTaskV2.ps1)
        8. Автоматический запуск Менеджера сертификатов через 5 секунд
    
    Структура целевой папки:
        C:\CertificateManager V2.0\
        ├── logs\                     # Логи всех операций
        ├── downloads\                # Кэш скачанных сертификатов
        ├── config\                   # Конфигурационные файлы
        │   └── avest_urls.ini        # URL для скачивания компонентов Авест
        ├── avest\
        │   ├── archives\             # Архивы компонентов Авест
        │   └── unpacked\             # Распакованные компоненты
        ├── CertificateManagerV2.ps1  # Графический интерфейс
        ├── Update-OnlyCertificates.ps1   # Обновление сертификатов
        ├── Install-AvestComponents.ps1   # Установка компонентов
        ├── Install-AvCMXWebP.ps1         # Установка плагина
        ├── Create-ScheduledTaskV2.ps1    # Настройка автозапуска
        ├── Update-CertificatesV2.ps1     # Полное обновление
        ├── Update-CertificatesV2_Core.ps1 # Ядро обновления
        ├── all_certs_urls.txt            # Список URL сертификатов
        └── Common-Functions.ps1          # Общий модуль функций
    
    Параметры (встроенные):
        $source = "D:\BackBox\DEV\CertificateManager V2.0"   # Источник (сетевая папка)
        $target = "C:\CertificateManager V2.0"               # Целевая папка
    
    Особенности:
        - Архивы компонентов Авест НЕ входят в развертывание
        - Архивы скачиваются при первом запуске установки компонентов
        - Ярлык создаётся на рабочем столе текущего пользователя
        - Автозапуск настраивается автоматически
    
    Коды возврата:
        0 - успешное развертывание
        1 - ошибка (сетевая папка недоступна, недостаточно прав)
    
    После развертывания:
        - На рабочем столе появляется ярлык "Менеджер сертификатов V2.0"
        - В планировщике создаётся задача UpdateCertificatesV2
        - Автоматически запускается графический интерфейс
.NOTES
    Версия: 2.0
    Требования:
        - PowerShell 5.0+
        - Права администратора
        - Доступ к сетевой папке с установочными файлами
        - Свободное место на диске C: (минимум 100 МБ)
    
    Пример запуска:
        powershell.exe -ExecutionPolicy Bypass -File "Deploy-CertificateManagerV2.ps1"
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
# Источник (сетевая папка)
$source = "D:\BackBox\DEV\CertificateManager V2.0"

# Целевая папка
$target = "C:\CertificateManager V2.0"

# Список папок для создания
$foldersToCreate = @(
    "logs",
    "downloads",
    "config",
    "avest\archives",
    "avest\unpacked"
)

# Список файлов для копирования
$filesToCopy = @(
    "CertificateManagerV2.ps1",
    "Update-CertificatesV2.ps1",
    "Update-CertificatesV2_Core.ps1",
    "Update-OnlyCertificates.ps1",
    "Install-AvestComponents.ps1",
    "Install-AvCMXWebP.ps1",
    "Create-ScheduledTaskV2.ps1",
    "all_certs_urls.txt",
    "Common-Functions.ps1"
)

# Список конфигурационных файлов
$configFiles = @(
    "avest_urls.ini"
)

# ======================================================
# 3. НАЧАЛО РАЗВЕРТЫВАНИЯ
# ======================================================
Clear-Host
Write-Host ("="*70) -ForegroundColor Cyan
Write-Host "  РАЗВЕРТЫВАНИЕ МЕНЕДЖЕРА СЕРТИФИКАТОВ V2.0" -ForegroundColor Cyan
Write-Host ("="*70) -ForegroundColor Cyan
Write-Host "Источник: $source" -ForegroundColor White
Write-Host "Цель: $target" -ForegroundColor White
Write-Host ""

# 3.1. Проверка доступности сетевой папки
Write-Host "[1/5] Проверка доступности сетевой папки..." -ForegroundColor Yellow
if (!(Test-Path $source)) {
    Write-Host "  [X] ОШИБКА: Сетевая папка недоступна: $source" -ForegroundColor Red
    Write-Host "  Проверьте сетевое подключение и права доступа." -ForegroundColor Red
    Write-Host ""
    Write-Host "Нажмите любую клавишу для выхода..." -ForegroundColor Gray
    pause
    exit 1
}
Write-Host "  [+] Сетевая папка доступна" -ForegroundColor Green

# 3.2. Создание целевой папки
Write-Host ""
Write-Host "[2/5] Создание целевой папки..." -ForegroundColor Yellow
if (!(Test-Path $target)) {
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Write-Host "  [+] Папка создана: $target" -ForegroundColor Green
} else {
    Write-Host "  [!] Папка уже существует" -ForegroundColor Gray
}

# 3.3. Создание структуры папок
Write-Host ""
Write-Host "[3/5] Создание структуры папок..." -ForegroundColor Yellow

foreach ($folder in $foldersToCreate) {
    $fullPath = Join-Path $target $folder
    if (!(Test-Path $fullPath)) {
        New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
        Write-Host "  [+] Создано: $folder" -ForegroundColor Green
    } else {
        Write-Host "  [!] Уже существует: $folder" -ForegroundColor Gray
    }
}

# 3.4. Копирование файлов скриптов
Write-Host ""
Write-Host "[4/5] Копирование файлов..." -ForegroundColor Yellow

$copied = 0
$skipped = 0

foreach ($fileName in $filesToCopy) {
    $sourceFile = Join-Path $source $fileName
    $destFile = Join-Path $target $fileName
    
    if (Test-Path $sourceFile) {
        Copy-Item -Path $sourceFile -Destination $destFile -Force
        Write-Host "  [+] Скопирован: $fileName" -ForegroundColor Green
        $copied++
    } else {
        Write-Host "  [X] Не найден: $fileName" -ForegroundColor Red
        $skipped++
    }
}

# 3.5. Копирование конфигурационных файлов
Write-Host ""
Write-Host "[5/5] Копирование конфигурационных файлов..." -ForegroundColor Yellow

foreach ($fileName in $configFiles) {
    $sourceFile = Join-Path $source "config" | Join-Path -ChildPath $fileName
    $destFile = Join-Path $target "config" | Join-Path -ChildPath $fileName
    
    if (Test-Path $sourceFile) {
        Copy-Item -Path $sourceFile -Destination $destFile -Force
        Write-Host "  [+] Скопирован: config\$fileName" -ForegroundColor Green
        $copied++
    } else {
        Write-Host "  [X] Не найден: config\$fileName" -ForegroundColor Red
        $skipped++
    }
}

Write-Host ""
Write-Host "  Результат: $copied скопировано, $skipped пропущено" -ForegroundColor Gray

# ======================================================
# 4. СОЗДАНИЕ ЯРЛЫКА НА РАБОЧЕМ СТОЛЕ
# ======================================================
Write-Host ""
Write-Host "Создание ярлыка на рабочем столе..." -ForegroundColor Yellow

$desktopPath = [Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktopPath "Менеджер сертификатов V2.0.lnk"
$targetScript = Join-Path $target "CertificateManagerV2.ps1"

if (Test-Path $targetScript) {
    if (!(Test-Path $shortcutPath)) {
        $wsh = New-Object -ComObject WScript.Shell
        $shortcut = $wsh.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = "powershell.exe"
        $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File `"$targetScript`""
        $shortcut.WorkingDirectory = $target
        $shortcut.IconLocation = "powershell.exe,0"
        $shortcut.Description = "Менеджер сертификатов V2.0"
        $shortcut.Save()
        Write-Host "  [+] Ярлык создан" -ForegroundColor Green
    } else {
        Write-Host "  [!] Ярлык уже существует" -ForegroundColor Gray
    }
} else {
    Write-Host "  [X] CertificateManagerV2.ps1 не найден" -ForegroundColor Red
}

# ======================================================
# 5. НАСТРОЙКА АВТОЗАПУСКА
# ======================================================
Write-Host ""
Write-Host "Настройка автозапуска..." -ForegroundColor Yellow

$autoStartScript = Join-Path $target "Create-ScheduledTaskV2.ps1"

if (Test-Path $autoStartScript) {
    Write-Host "  Запуск Create-ScheduledTaskV2.ps1..." -ForegroundColor Gray
    & $autoStartScript
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [+] Задача создана успешно" -ForegroundColor Green
    } else {
        Write-Host "  [!] Ошибка создания задачи (код: $LASTEXITCODE)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [X] Скрипт Create-ScheduledTaskV2.ps1 не найден" -ForegroundColor Red
    Write-Host "  Автозапуск не настроен" -ForegroundColor Yellow
}

# ======================================================
# 6. АВТОМАТИЧЕСКИЙ ЗАПУСК МЕНЕДЖЕРА
# ======================================================
Write-Host ""
Write-Host ("="*70) -ForegroundColor Cyan
Write-Host "  ЗАВЕРШЕНИЕ РАЗВЕРТЫВАНИЯ" -ForegroundColor Cyan
Write-Host ("="*70) -ForegroundColor Cyan
Write-Host ""

Write-Host "Развертывание завершено!" -ForegroundColor Green
Write-Host "Расположение: $target" -ForegroundColor White
Write-Host "Ярлык: $shortcutPath" -ForegroundColor White
Write-Host ""

Write-Host "Через 5 секунд будет запущен Менеджер сертификатов V2.0..." -ForegroundColor Yellow
Write-Host "Нажмите Ctrl+C, чтобы отменить запуск." -ForegroundColor Gray

$timer = 5
for ($i = $timer; $i -gt 0; $i--) {
    Write-Host "  `r$i секунд..." -NoNewline
    Start-Sleep -Seconds 1
}
Write-Host ""

# Запуск Менеджера
$managerScript = Join-Path $target "CertificateManagerV2.ps1"

if (Test-Path $managerScript) {
    Write-Host "Запуск Менеджера сертификатов..." -ForegroundColor Green
    Start-Process -FilePath "powershell.exe" `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File `"$managerScript`"" `
        -WorkingDirectory $target
    
    Write-Host "  [+] Менеджер сертификатов запущен" -ForegroundColor Green
} else {
    Write-Host "  [X] Не найден: $managerScript" -ForegroundColor Red
    Write-Host "  Запустите вручную ярлык на рабочем столе" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Нажмите любую клавишу для выхода..."
pause
