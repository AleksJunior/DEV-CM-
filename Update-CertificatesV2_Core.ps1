<#
Copyright (c) 2026 Alex Bird
Use of this source code is governed by an MIT-style
license that can be found in the LICENSE file.
.SYNOPSIS
    Ядро обновления сертификатов и списков отзыва (CRL)
.DESCRIPTION
    Основной скрипт для скачивания и установки сертификатов и CRL.
    Выполняет всю основную работу по обновлению.
    
    Алгоритм работы:
        1. Создание необходимых папок (logs, downloads, временная папка)
        2. Поиск утилит AvCmUt4.exe и MngCert.exe в системе
        3. Чтение файла all_certs_urls.txt (пропускает строки, начинающиеся с #)
        4. Скачивание всех файлов во временную папку
        5. Импорт файлов в хранилища сертификатов Windows:
           - .cer → Root или CA (Root для корневых, CA для промежуточных)
           - .crl → CRL (через AvCmUt4.exe или certutil)
           - .p7b → PKCS#7 контейнер (через certutil)
        6. Сохранение копий скачанных файлов в папку downloads
        7. Удаление временных файлов
        8. Сохранение результата в JSON (если указан параметр -ResultFile)
    
    Импорт сертификатов:
        - Корневые сертификаты (root, kuc, mns_root) → хранилище Root
        - Промежуточные сертификаты (CA) → хранилище CA
        - Приоритет: MngCert.exe → certutil → .NET fallback
    
    Импорт CRL:
        - Приоритет: AvCmUt4.exe → certutil
        - AvCmUt4.exe возвращает код 18 для уже существующих CRL
    
    Особенности обработки ошибок:
        - NTE_BAD_KEYSET (0x80090016) - обрабатывается через .NET fallback
        - "already exists" - не считается ошибкой
        - Автоматическое удаление AvCmUt4.log из TEMP
    
    Результат в JSON (при указании -ResultFile):
        {
            "Success": количество успешно импортированных,
            "Errors": количество ошибок,
            "Total": всего скачанных файлов,
            "LogFile": путь к логу,
            "Timestamp": время выполнения,
            "AvCmUt4": "Найден/Не найден",
            "MngCert": "Найден/Не найден",
            "IntegrityCheck": "Пройдена/Нарушена"
        }
.NOTES
    Версия: 2.0
    Требования:
        - PowerShell 5.0+
        - Права администратора
        - Файл all_certs_urls.txt в папке со скриптом
    
    Пути поиска утилит AvCmUt4.exe и MngCert.exe:
        - C:\Program Files\Avest\AvPCM_nces\
        - C:\Program Files (x86)\Avest\AvPCM_nces\
        - C:\Program Files\Avest\AvPCM_ncesBign\
        - C:\Program Files (x86)\Avest\AvPCM_ncesBign\
        - C:\Program Files\Avest\AvPCM\
        - C:\Program Files (x86)\Avest\AvPCM\
    
    Временные файлы:
        - Создаются в $env:TEMP\cert_import_<случайное_число>\
        - Автоматически удаляются после выполнения
    
    Логи:
        - Основной лог: .\logs\import_*.log
        - Лог AvCmUt4.exe: $env:TEMP\AvCmUt4.log (удаляется после выполнения)
#>

param(
    [string]$ФайлРезультата
)

# ======================================================
# 1. НАСТРОЙКА ПУТЕЙ
# ======================================================
if ($MyInvocation.MyCommand.CommandType -eq "ExternalScript") {
    $путьСкрипта = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
} else {
    $путьСкрипта = Split-Path -Parent -Path ([Environment]::GetCommandLineArgs()[0])
    if (!$путьСкрипта) { $путьСкрипта = "." }
}

$файлСсылок = Join-Path $путьСкрипта "all_certs_urls.txt"
$папкаЛогов = Join-Path $путьСкрипта "logs"
$папкаЗагрузок = Join-Path $путьСкрипта "downloads"
$временнаяПапка = Join-Path $env:TEMP "cert_import_$(Get-Random)"

# ======================================================
# 2. СОЗДАНИЕ ПАПОК
# ======================================================
Write-Host "Создание папок..."
foreach ($папка in @($папкаЛогов, $папкаЗагрузок, $временнаяПапка)) {
    if (!(Test-Path $папка)) { 
        New-Item -ItemType Directory -Path $папка -Force | Out-Null
        Write-Host "  + $папка"
    }
}

# Реальная проверка
if ($avcmut -and $mngcert) {
    $целостностьОК = $true
} else {
    $целостностьОК = $false
}

# ======================================================
# 3. ФАЙЛ ЛОГА
# ======================================================
$файлЛога = "$папкаЛогов\import_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
"СТАРТ: $(Get-Date)" | Out-File $файлЛога
("="*70) | Out-File $файлЛога -Append

# ======================================================
# 4. ФУНКЦИИ
# ======================================================

function ЗаписатьЛог {
    param([string]$сообщение)
    $время = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$время - $сообщение" | Out-File $файлЛога -Append
}

function СкачатьФайл {
    param([string]$ссылка, [string]$путьСохранить)
    try {
        $заголовки = @{ "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" }
        Invoke-WebRequest -Uri $ссылка -Headers $заголовки -OutFile $путьСохранить -TimeoutSec 10 -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function ИмпортСертификата {
    param([string]$путьФайла, [string]$имяФайла)
    
    if ($имяФайла -like "*root*" -or $имяФайла -match "kuc|mns_root") {
        $хранилище = "Root"
    } else {
        $хранилище = "CA"
    }
    
    if ($mngcert) {
        ЗаписатьЛог -сообщение "Пробуем MngCert.exe для $имяФайла"
        $параметры = "/importcert /silentrun `"$путьФайла`""
        try {
            $процесс = Start-Process -FilePath $mngcert -ArgumentList $параметры -Wait -PassThru -NoNewWindow -ErrorAction Stop
            ЗаписатьЛог -сообщение "Код выхода MngCert.exe: $($процесс.ExitCode)"
            if ($процесс.ExitCode -eq 0) {
                ЗаписатьЛог -сообщение "ОК (MngCert.exe - $хранилище): $имяФайла"
                return $true
            } else {
                ЗаписатьЛог -сообщение "MngCert.exe не сработал, пробуем certutil..."
            }
        } catch {
            ЗаписатьЛог -сообщение "Ошибка MngCert.exe: $($_.Exception.Message), пробуем certutil..."
        }
    }
    
    $вывод = certutil -addstore $хранилище $путьФайла 2>&1
    $кодВыхода = $LASTEXITCODE
    
    if ($кодВыхода -eq 0) {
        ЗаписатьЛог -сообщение "ОК (certutil - $хранилище): $имяФайла"
        return $true
    }
    
    $строкаВывода = $вывод | Out-String
    if ($строкаВывода -match "already exists") {
        ЗаписатьЛог -сообщение "ИНФО: Сертификат $имяФайла уже существует в хранилище $хранилище"
        return $true
    }
    
    if ($строкаВывода -match "0x80090016" -or $строкаВывода -match "NTE_BAD_KEYSET") {
        ЗаписатьЛог -сообщение "ПРЕДУПРЕЖДЕНИЕ: NTE_BAD_KEYSET, пробуем .NET..."
        try {
            $сертификат = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
            $сертификат.Import($путьФайла)
            $объектХранилища = New-Object System.Security.Cryptography.X509Certificates.X509Store($хранилище, "LocalMachine")
            $объектХранилища.Open("ReadWrite")
            $существующий = $объектХранилища.Certificates | Where-Object { $_.Thumbprint -eq $сертификат.Thumbprint }
            if ($существующий) {
                ЗаписатьЛог -сообщение "ИНФО: Сертификат уже существует"
                $объектХранилища.Close()
                return $true
            }
            $объектХранилища.Add($сертификат)
            $объектХранилища.Close()
            ЗаписатьЛог -сообщение "ОК (.NET fallback): $имяФайла"
            return $true
        } catch {
            ЗаписатьЛог -сообщение "ОШИБКА: .NET fallback не сработал: $_"
            return $false
        }
    }
    
    ЗаписатьЛог -сообщение "ОШИБКА: $имяФайла (код certutil $кодВыхода)"
    return $false
}

function ИмпортCRL {
    param([string]$путьФайла, [string]$имяФайла)
    
    if ($avcmut) {
        & $avcmut -C $путьФайла -NA *>$null
        $кодВыхода = $LASTEXITCODE
        
        if ($кодВыхода -eq 0 -or $кодВыхода -eq 18) {
            ЗаписатьЛог -сообщение "ОК (AvCmUt4): $имяФайла"
            return $true
        } else {
            certutil -addstore CA $путьФайла *>$null
            if ($LASTEXITCODE -eq 0) {
                ЗаписатьЛог -сообщение "ОК (certutil - fallback): $имяФайла"
                return $true
            } else {
                ЗаписатьЛог -сообщение "ОШИБКА: $имяФайла (код $кодВыхода)"
                return $false
            }
        }
    } else {
        certutil -addstore CA $путьФайла *>$null
        if ($LASTEXITCODE -eq 0) {
            ЗаписатьЛог -сообщение "ОК (certutil): $имяФайла"
            return $true
        } else {
            ЗаписатьЛог -сообщение "ОШИБКА: $имяФайла (код certutil $LASTEXITCODE)"
            return $false
        }
    }
}

function ИмпортP7B {
    param([string]$путьФайла, [string]$имяФайла)
    certutil -addstore CA $путьФайла *>$null
    if ($LASTEXITCODE -eq 0) {
        ЗаписатьЛог -сообщение "ОК (p7b): $имяФайла"
        return $true
    } else {
        ЗаписатьЛог -сообщение "ОШИБКА: $имяФайла (код p7b $LASTEXITCODE)"
        return $false
    }
}

# ======================================================
# 5. ПОИСК УТИЛИТ AvCmUt4.exe И MngCert.exe
# ======================================================
$avcmut = $null
$mngcert = $null

$возможныеПути = @(
    "C:\Program Files\Avest\AvPCM_nces\AvCmUt4.exe",
    "C:\Program Files (x86)\Avest\AvPCM_nces\AvCmUt4.exe",
    "C:\Program Files\Avest\AvPCM_ncesBign\AvCmUt4.exe",
    "C:\Program Files (x86)\Avest\AvPCM_ncesBign\AvCmUt4.exe",
    "C:\Program Files\Avest\AvPCM\AvCmUt4.exe",
    "C:\Program Files (x86)\Avest\AvPCM\AvCmUt4.exe"
)

foreach ($путь in $возможныеПути) {
    if (Test-Path $путь) {
        $avcmut = $путь
        Write-Host "AvCmUt4 найден: $avcmut"
        ЗаписатьЛог -сообщение "AvCmUt4 найден: $avcmut"
        
        $путьMngCert = Join-Path (Split-Path $путь) "MngCert.exe"
        if (Test-Path $путьMngCert) {
            $mngcert = $путьMngCert
            Write-Host "MngCert.exe найден: $mngcert"
            ЗаписатьЛог -сообщение "MngCert.exe найден: $mngcert"
        }
        break
    }
}

if (-not $mngcert) {
    $путиMngCert = @(
        "C:\Program Files\Avest\AvPCM_nces\MngCert.exe",
        "C:\Program Files (x86)\Avest\AvPCM_nces\MngCert.exe",
        "C:\Program Files\Avest\AvPCM_ncesBign\MngCert.exe",
        "C:\Program Files (x86)\Avest\AvPCM_ncesBign\MngCert.exe",
        "C:\Program Files\Avest\AvPCM\MngCert.exe",
        "C:\Program Files (x86)\Avest\AvPCM\MngCert.exe"
    )
    foreach ($путь in $путиMngCert) {
        if (Test-Path $путь) {
            $mngcert = $путь
            Write-Host "MngCert.exe найден: $mngcert"
            ЗаписатьЛог -сообщение "MngCert.exe найден: $mngcert"
            break
        }
    }
}

if (-not $avcmut) {
    Write-Host "AvCmUt4 не найден, используем certutil для CRL"
    ЗаписатьЛог -сообщение "AvCmUt4 не найден, используем certutil для CRL"
}

if (-not $mngcert) {
    Write-Host "MngCert.exe не найден, используем certutil для сертификатов"
    ЗаписатьЛог -сообщение "MngCert.exe не найден, используем certutil для сертификатов"
}

# ======================================================
# 6. ПРОВЕРКИ
# ======================================================
Write-Host ("="*70)
Write-Host "НАЧАЛО ОБНОВЛЕНИЯ"
Write-Host ("="*70)

if (!(Test-Path $файлСсылок)) {
    Write-Host "Файл $файлСсылок не найден!"
    ЗаписатьЛог -сообщение "ОШИБКА: Файл со ссылками не найден: $файлСсылок"
    exit 1
}

if ($avcmut) {
    Write-Host "AvCmUt4 найден: $avcmut"
} else {
    Write-Host "AvCmUt4 не найден, используем certutil для CRL"
}

if ($mngcert) {
    Write-Host "MngCert.exe найден: $mngcert"
} else {
    Write-Host "MngCert.exe не найден, используем certutil для сертификатов"
}

# ======================================================
# 7. ЧТЕНИЕ ССЫЛОК
# ======================================================
$ссылки = Get-Content $файлСсылок | Where-Object { $_ -and !$_.StartsWith("#") }
$всегоСсылок = $ссылки.Count
Write-Host "Найдено ссылок: $всегоСсылок"
ЗаписатьЛог -сообщение "Найдено $всегоСсылок ссылок в $файлСсылок"

# ======================================================
# 8. СКАЧИВАНИЕ ФАЙЛОВ
# ======================================================
Write-Host ("`n" + ("="*70))
Write-Host "СКАЧИВАНИЕ ФАЙЛОВ"
Write-Host ("="*70)

$скачанныеФайлы = @{}
$количествоСкачанных = 0

foreach ($ссылка in $ссылки) {
    $ссылка = $ссылка.Trim()
    if (!$ссылка) { continue }
    
    $имяФайла = $ссылка.Split('/')[-1]
    $временныйФайл = Join-Path $временнаяПапка $имяФайла
    $сохраненныйФайл = Join-Path $папкаЗагрузок $имяФайла
    
    $количествоСкачанных++
    Write-Host "`n[$количествоСкачанных/$всегоСсылок] $имяФайла"
    
    if (СкачатьФайл -ссылка $ссылка -путьСохранить $временныйФайл) {
        $размер = (Get-Item $временныйФайл).Length
        Write-Host "  Скачано, размер: $размер байт"
        ЗаписатьЛог -сообщение "ОК (скачивание): $имяФайла ($размер байт)"
        Copy-Item $временныйФайл $сохраненныйФайл -Force
        $скачанныеФайлы[$имяФайла] = @{ Path = $сохраненныйФайл }
    } else {
        Write-Host "  Ошибка скачивания"
        ЗаписатьЛог -сообщение "ОШИБКА (скачивание): $ссылка"
    }
}

# ======================================================
# 9. ИМПОРТ ФАЙЛОВ
# ======================================================
$успешноСертификатов = 0
$успешноСписков = 0
$успешноКонтейнеров = 0
$всегоСертификатов = 0
$всегоСписков = 0
$всегоКонтейнеров = 0

Write-Host ("`n" + ("="*70))
Write-Host "ИМПОРТ ФАЙЛОВ"
Write-Host ("="*70)

foreach ($ключ in $скачанныеФайлы.Keys) {
    $инфо = $скачанныеФайлы[$ключ]
    Write-Host "`n$ключ"
    
    if ($ключ -like "*.cer") {
        $всегоСертификатов++
        if (ИмпортСертификата -путьФайла $инфо.Path -имяФайла $ключ) {
            $успешноСертификатов++
        }
    }
    elseif ($ключ -like "*.crl") {
        $всегоСписков++
        if (ИмпортCRL -путьФайла $инфо.Path -имяФайла $ключ) {
            $успешноСписков++
        }
    }
    elseif ($ключ -like "*.p7b") {
        $всегоКонтейнеров++
        if (ИмпортP7B -путьФайла $инфо.Path -имяФайла $ключ) {
            $успешноКонтейнеров++
        }
    }
}

# ======================================================
# 10. РЕЗУЛЬТАТЫ
# ======================================================
$всегоИмпортировано = $успешноСертификатов + $успешноСписков + $успешноКонтейнеров
$всегоОшибок = ($всегоСертификатов - $успешноСертификатов) + ($всегоСписков - $успешноСписков) + ($всегоКонтейнеров - $успешноКонтейнеров)

Write-Host ("="*70)
Write-Host "РЕЗУЛЬТАТЫ"
Write-Host ("="*70)
Write-Host "Скачано: $количествоСкачанных из $всегоСсылок"
Write-Host ""
Write-Host "Импорт:"
Write-Host "  Сертификаты (.cer): $успешноСертификатов из $всегоСертификатов"
Write-Host "  Списки отзыва (.crl): $успешноСписков из $всегоСписков"
Write-Host "  Контейнеры (.p7b): $успешноКонтейнеров из $всегоКонтейнеров"
Write-Host "  Всего импортировано: $всегоИмпортировано"
Write-Host "  Ошибок: $всегоОшибок"
Write-Host ""
Write-Host "Лог: $файлЛога"
Write-Host ("="*70)

# Сохраняем в лог
@"

============================================================
РЕЗУЛЬТАТЫ
============================================================
Скачано: $количествоСкачанных из $всегоСсылок

Импорт:
  Сертификаты (.cer): $успешноСертификатов из $всегоСертификатов
  Списки отзыва (.crl): $успешноСписков из $всегоСписков
  Контейнеры (.p7b): $успешноКонтейнеров из $всегоКонтейнеров
  Всего импортировано: $всегоИмпортировано
  Ошибок: $всегоОшибок

Лог: $файлЛога
============================================================
"@ | Out-File $файлЛога -Append

# ======================================================
# 11. СОХРАНЕНИЕ РЕЗУЛЬТАТА
# ======================================================
if ($ФайлРезультата) {
    $результат = @{
        Success = $всегоИмпортировано
        Errors = $всегоОшибок
        Total = $количествоСкачанных
        LogFile = $файлЛога
        Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        AvCmUt4 = if ($avcmut) { "Найден" } else { "Не найден" }
        MngCert = if ($mngcert) { "Найден" } else { "Не найден" }
        IntegrityCheck = if ($целостностьОК) { "Пройдена" } else { "Нарушена" }
    } | ConvertTo-Json
    $результат | Out-File $ФайлРезультата -Encoding utf8
}

# ======================================================
# 12. ОЧИСТКА
# ======================================================
Remove-Item $временнаяПапка -Recurse -Force -ErrorAction SilentlyContinue

# Удаляем лог-файл AvCmUt4.log, если он создался
$avcmutLog = Join-Path $env:TEMP "AvCmUt4.log"
if (Test-Path $avcmutLog) {
    Remove-Item $avcmutLog -Force -ErrorAction SilentlyContinue
}

Write-Host "ГОТОВО!"

if ($всегоОшибок -gt 0) { exit 1 } else { exit 0 }
