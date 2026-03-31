<#
.SYNOPSIS
    Графический интерфейс управления сертификатами и компонентами Авест
.DESCRIPTION
    Основной модуль приложения. Предоставляет графический интерфейс для:
    - Обновления сертификатов и списков отзыва (CRL) из all_certs_urls.txt
    - Установки компонентов Авест (AvPass, AvBign, AvCSPBel, AvCSPBign, AvReg)
    - Установки плагина AvCMXWebP для работы с порталами в IE Mode
    - Настройки автозапуска обновления сертификатов через планировщик заданий
    - Просмотра статуса установленных компонентов
    - Редактирования списка URL для скачивания сертификатов
    - Открытия папки программы для просмотра логов и конфигураций
    
    Интерфейс разделен на две колонки:
    - Левая (синие кнопки): основные функции обновления и установки
    - Правая (светлые кнопки): вспомогательные функции (информация, настройки)
    
    Все операции требуют прав администратора. При запуске скрипта окно PowerShell сворачивается,
    пользователь видит только графическую форму.
.NOTES
    Версия: 2.0
    Автор: Системный администратор
    Требования: 
        - PowerShell 5.0 или выше
        - Права администратора
        - Файл all_certs_urls.txt в папке со скриптом
        - Скрипты: Update-OnlyCertificates.ps1, Install-AvestComponents.ps1,
          Install-AvCMXWebP.ps1, Create-ScheduledTaskV2.ps1
    
    Логи всех операций сохраняются в папку .\logs\
    
    Особенности:
        - Блокировка повторного нажатия на кнопки во время выполнения операций
        - Автоматическое сворачивание консольного окна при запуске
        - Цветовая индикация статуса в строке состояния
        - Всплывающие окна с результатами операций
#>

# Свернуть окно PowerShell (простой способ)
Add-Type -Name Window -Namespace Console -MemberDefinition '
[DllImport("Kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
[DllImport("User32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'
$consoleHandle = [Console.Window]::GetConsoleWindow()
[Console.Window]::ShowWindow($consoleHandle, 2)  # 2 = SW_SHOWMINIMIZED

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if ($MyInvocation.MyCommand.CommandType -eq "ExternalScript") {
    $scriptPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
} else {
    $scriptPath = Split-Path -Parent -Path ([Environment]::GetCommandLineArgs()[0])
    if (!$scriptPath) { $scriptPath = "." }
}

# Переменные для блокировки повторных нажатий
$schedulerRunning = $false
$updateRunning = $false
$installRunning = $false
$folderWindowOpen = $false
$urlFileOpen = $false
$avestInstallRunning = $false

# Создаем форму
$form = New-Object System.Windows.Forms.Form
$form.Text = "Менеджер сертификатов V2.0"
$form.Size = New-Object System.Drawing.Size(515, 440)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)

# Заголовок
$label = New-Object System.Windows.Forms.Label
$label.Text = "Менеджер сертификатов V2.0"
$label.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$label.ForeColor = [System.Drawing.Color]::FromArgb(0, 102, 204)
$label.AutoSize = $true
$label.Location = New-Object System.Drawing.Point(95, 15)
$form.Controls.Add($label)

# Линия-разделитель
$line = New-Object System.Windows.Forms.Label
$line.Text = ""
$line.BorderStyle = [System.Windows.Forms.BorderStyle]::Fixed3D
$line.Size = New-Object System.Drawing.Size(460, 2)
$line.Location = New-Object System.Drawing.Point(20, 50)
$form.Controls.Add($line)

# Статус
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Готов"
$statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic)
$statusLabel.ForeColor = [System.Drawing.Color]::Gray
$statusLabel.Location = New-Object System.Drawing.Point(20, 60)
$statusLabel.Size = New-Object System.Drawing.Size(460, 25)
$statusLabel.AutoSize = $false
$statusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$form.Controls.Add($statusLabel)

# Панель для кнопок
$buttonPanel = New-Object System.Windows.Forms.Panel
$buttonPanel.Location = New-Object System.Drawing.Point(20, 95)
$buttonPanel.Size = New-Object System.Drawing.Size(460, 280)
$buttonPanel.BackColor = [System.Drawing.Color]::Transparent
$form.Controls.Add($buttonPanel)

# ======================================================
# ЛЕВАЯ КОЛОНКА (СИНИЕ КНОПКИ)
# ======================================================

# Кнопка обновления сертификатов
$updateBtn = New-Object System.Windows.Forms.Button
$updateBtn.Text = "Обновить сертификаты"
$updateBtn.Location = New-Object System.Drawing.Point(0, 0)
$updateBtn.Size = New-Object System.Drawing.Size(210, 42)
$updateBtn.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Regular)
$updateBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$updateBtn.ForeColor = [System.Drawing.Color]::White
$updateBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$updateBtn.FlatAppearance.BorderSize = 0
$updateBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
$updateBtn.Add_Click({
    if ($updateRunning) {
        [System.Windows.Forms.MessageBox]::Show("Обновление сертификатов уже выполняется. Пожалуйста, подождите.", "Внимание", "OK", "Information")
        return
    }
    
    $updateRunning = $true
    $statusLabel.Text = "Обновление сертификатов... Пожалуйста, подождите"
    $statusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
    $updateBtn.Enabled = $false
    $avcmxBtn.Enabled = $false
    $schedulerBtn.Enabled = $false
    $avestBtn.Enabled = $false
    
    try {
        $process = Start-Process -FilePath "powershell.exe" `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath\Update-OnlyCertificates.ps1`"" `
            -Verb RunAs -WindowStyle Normal -Wait -PassThru
        
        if ($process.ExitCode -eq 0) {
            $statusLabel.Text = "Обновление успешно завершено!"
            $statusLabel.ForeColor = [System.Drawing.Color]::Green
        } else {
            $statusLabel.Text = "Обновление завершено с ошибками. Проверьте логи."
            $statusLabel.ForeColor = [System.Drawing.Color]::Red
        }
    } catch {
        $statusLabel.Text = "Ошибка при обновлении: $($_.Exception.Message)"
        $statusLabel.ForeColor = [System.Drawing.Color]::Red
    } finally {
        $updateRunning = $false
        $updateBtn.Enabled = $true
        $avcmxBtn.Enabled = $true
        $schedulerBtn.Enabled = $true
        $avestBtn.Enabled = $true
        Start-Sleep -Seconds 2
        $statusLabel.Text = "Готов"
        $statusLabel.ForeColor = [System.Drawing.Color]::Gray
        [System.Windows.Forms.MessageBox]::Show("Процесс обновления сертификатов завершен.`nПроверьте логи для получения подробностей.", "Менеджер сертификатов", "OK", "Information")
    }
})
$buttonPanel.Controls.Add($updateBtn)

# Кнопка установки компонентов Авест
$avestBtn = New-Object System.Windows.Forms.Button
$avestBtn.Text = "Установить компоненты Авест"
$avestBtn.Location = New-Object System.Drawing.Point(0, 55)
$avestBtn.Size = New-Object System.Drawing.Size(210, 42)
$avestBtn.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Regular)
$avestBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$avestBtn.ForeColor = [System.Drawing.Color]::White
$avestBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$avestBtn.FlatAppearance.BorderSize = 0
$avestBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
$avestBtn.Add_Click({
    if ($avestInstallRunning) {
        [System.Windows.Forms.MessageBox]::Show("Установка компонентов уже выполняется. Пожалуйста, подождите.", "Внимание", "OK", "Information")
        return
    }
    
    $avestInstallRunning = $true
    $statusLabel.Text = "Установка компонентов Авест..."
    $statusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
    $updateBtn.Enabled = $false
    $avcmxBtn.Enabled = $false
    $schedulerBtn.Enabled = $false
    $avestBtn.Enabled = $false
    
    try {
        $installScript = Join-Path $scriptPath "Install-AvestComponents.ps1"
        
        if (!(Test-Path $installScript)) {
            throw "Install-AvestComponents.ps1 не найден"
        }
        
        $process = Start-Process -FilePath "powershell.exe" `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$installScript`" -ScriptPath `"$scriptPath`"" `
            -Verb RunAs -Wait -PassThru -WindowStyle Normal
        
        if ($process.ExitCode -eq 0) {
            $statusLabel.Text = "Компоненты Авест установлены успешно!"
            $statusLabel.ForeColor = [System.Drawing.Color]::Green
            [System.Windows.Forms.MessageBox]::Show("Компоненты Авест установлены успешно!", "Успех", "OK", "Information")
        } elseif ($process.ExitCode -eq 1) {
            $statusLabel.Text = "Установка не удалась. Проверьте логи."
            $statusLabel.ForeColor = [System.Drawing.Color]::Red
            [System.Windows.Forms.MessageBox]::Show("Установка не удалась. Проверьте логи в: $scriptPath\logs\", "Ошибка", "OK", "Error")
        } else {
            $statusLabel.Text = "Установка завершена."
            $statusLabel.ForeColor = [System.Drawing.Color]::Gray
        }
    } catch {
        $statusLabel.Text = "Ошибка: $($_.Exception.Message)"
        $statusLabel.ForeColor = [System.Drawing.Color]::Red
        [System.Windows.Forms.MessageBox]::Show("Ошибка: $($_.Exception.Message)", "Ошибка", "OK", "Error")
    } finally {
        $avestInstallRunning = $false
        $updateBtn.Enabled = $true
        $avcmxBtn.Enabled = $true
        $schedulerBtn.Enabled = $true
        $avestBtn.Enabled = $true
        Start-Sleep -Seconds 2
        $statusLabel.Text = "Готов"
        $statusLabel.ForeColor = [System.Drawing.Color]::Gray
    }
})
$buttonPanel.Controls.Add($avestBtn)

# Кнопка установки плагина AvCMXWebP
$avcmxBtn = New-Object System.Windows.Forms.Button
$avcmxBtn.Text = "Установить плагин AvCMXWebP"
$avcmxBtn.Location = New-Object System.Drawing.Point(0, 110)
$avcmxBtn.Size = New-Object System.Drawing.Size(210, 42)
$avcmxBtn.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Regular)
$avcmxBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$avcmxBtn.ForeColor = [System.Drawing.Color]::White
$avcmxBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$avcmxBtn.FlatAppearance.BorderSize = 0
$avcmxBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
$avcmxBtn.Add_Click({
    if ($installRunning) {
        [System.Windows.Forms.MessageBox]::Show("Установка плагина уже выполняется. Пожалуйста, подождите.", "Внимание", "OK", "Information")
        return
    }
    
    $installRunning = $true
    $statusLabel.Text = "Установка плагина AvCMXWebP..."
    $statusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
    $updateBtn.Enabled = $false
    $avcmxBtn.Enabled = $false
    $schedulerBtn.Enabled = $false
    $avestBtn.Enabled = $false
    
    try {
        $installScript = Join-Path $scriptPath "Install-AvCMXWebP.ps1"
        
        if (!(Test-Path $installScript)) {
            throw "Install-AvCMXWebP.ps1 не найден"
        }
        
        $process = Start-Process -FilePath "powershell.exe" `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$installScript`" -ScriptPath `"$scriptPath`" -LogsFolder `"$scriptPath\logs`"" `
            -Verb RunAs -Wait -PassThru -WindowStyle Normal
        
        if ($process.ExitCode -eq 0) {
            $statusLabel.Text = "Плагин AvCMXWebP установлен успешно!"
            $statusLabel.ForeColor = [System.Drawing.Color]::Green
            [System.Windows.Forms.MessageBox]::Show("Плагин AvCMXWebP установлен успешно!", "Успех", "OK", "Information")
        } elseif ($process.ExitCode -eq 1) {
            $statusLabel.Text = "Установка не удалась. Проверьте логи."
            $statusLabel.ForeColor = [System.Drawing.Color]::Red
            [System.Windows.Forms.MessageBox]::Show("Установка не удалась. Проверьте логи в: $scriptPath\logs\", "Ошибка", "OK", "Error")
        } else {
            $statusLabel.Text = "Установка завершена."
            $statusLabel.ForeColor = [System.Drawing.Color]::Gray
        }
    } catch {
        $statusLabel.Text = "Ошибка: $($_.Exception.Message)"
        $statusLabel.ForeColor = [System.Drawing.Color]::Red
        [System.Windows.Forms.MessageBox]::Show("Ошибка: $($_.Exception.Message)", "Ошибка", "OK", "Error")
    } finally {
        $installRunning = $false
        $updateBtn.Enabled = $true
        $avcmxBtn.Enabled = $true
        $schedulerBtn.Enabled = $true
        $avestBtn.Enabled = $true
        Start-Sleep -Seconds 2
        $statusLabel.Text = "Готов"
        $statusLabel.ForeColor = [System.Drawing.Color]::Gray
    }
})
$buttonPanel.Controls.Add($avcmxBtn)

# Кнопка настройки автозапуска (синяя, как и все в левой колонке)
$schedulerBtn = New-Object System.Windows.Forms.Button
$schedulerBtn.Text = "Запланировать автозапуск"
$schedulerBtn.Location = New-Object System.Drawing.Point(0, 165)
$schedulerBtn.Size = New-Object System.Drawing.Size(210, 42)
$schedulerBtn.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Regular)
$schedulerBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$schedulerBtn.ForeColor = [System.Drawing.Color]::White
$schedulerBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$schedulerBtn.FlatAppearance.BorderSize = 0
$schedulerBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
$schedulerBtn.Add_Click({
    if ($schedulerRunning) {
        [System.Windows.Forms.MessageBox]::Show("Настройка автозапуска уже выполняется. Пожалуйста, подождите.", "Внимание", "OK", "Information")
        return
    }
    
    $schedulerRunning = $true
    $schedulerBtn.Enabled = $false
    $statusLabel.Text = "Настройка автозапуска..."
    $statusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
    
    try {
        $process = Start-Process -FilePath "powershell.exe" `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath\Create-ScheduledTaskV2.ps1`"" `
            -Verb RunAs -WindowStyle Normal -Wait -PassThru
        
        if ($process.ExitCode -eq 0) {
            $statusLabel.Text = "Автозапуск настроен успешно"
            $statusLabel.ForeColor = [System.Drawing.Color]::Green
        } else {
            $statusLabel.Text = "Ошибка настройки автозапуска"
            $statusLabel.ForeColor = [System.Drawing.Color]::Red
        }
    } catch {
        $statusLabel.Text = "Ошибка: $($_.Exception.Message)"
        $statusLabel.ForeColor = [System.Drawing.Color]::Red
    } finally {
        $schedulerRunning = $false
        $schedulerBtn.Enabled = $true
        Start-Sleep -Seconds 2
        $statusLabel.Text = "Готов"
        $statusLabel.ForeColor = [System.Drawing.Color]::Gray
    }
})
$buttonPanel.Controls.Add($schedulerBtn)

# ======================================================
# ПРАВАЯ КОЛОНКА (КНОПКИ БЕЗ ЦВЕТА)
# ======================================================

# Кнопка редактирования файла URL
$editUrlsBtn = New-Object System.Windows.Forms.Button
$editUrlsBtn.Text = "URL сертификатов"
$editUrlsBtn.Location = New-Object System.Drawing.Point(250, 0)
$editUrlsBtn.Size = New-Object System.Drawing.Size(210, 42)
$editUrlsBtn.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Regular)
$editUrlsBtn.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
$editUrlsBtn.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$editUrlsBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$editUrlsBtn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
$editUrlsBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
$editUrlsBtn.Add_Click({
    if ($urlFileOpen) {
        [System.Windows.Forms.MessageBox]::Show("Файл URL уже открыт.", "Внимание", "OK", "Information")
        return
    }
    
    $urlFilePath = Join-Path $scriptPath "all_certs_urls.txt"
    if (-not (Test-Path $urlFilePath)) {
        [System.Windows.Forms.MessageBox]::Show("Файл all_certs_urls.txt не найден в папке: $scriptPath", "Ошибка", "OK", "Error")
        return
    }
    
    $urlFileOpen = $true
    $editUrlsBtn.Enabled = $false
    $statusLabel.Text = "Открытие файла URL..."
    $statusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
    
    try {
        Start-Process "notepad.exe" $urlFilePath
    } catch {
        $statusLabel.Text = "Ошибка открытия файла"
        $statusLabel.ForeColor = [System.Drawing.Color]::Red
    }
    
    # ИСПРАВЛЕНО: запускаем таймер с помощью Register-ObjectEvent
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 2000
    $timer.Add_Tick({
        $urlFileOpen = $false
        $editUrlsBtn.Enabled = $true
        $statusLabel.Text = "Готов"
        $statusLabel.ForeColor = [System.Drawing.Color]::Gray
        $timer.Stop()
        $timer.Dispose()
    }.GetNewClosure())
    $timer.Start()
})
$buttonPanel.Controls.Add($editUrlsBtn)

# Кнопка информации о компонентах Авест
$avestInfoBtn = New-Object System.Windows.Forms.Button
$avestInfoBtn.Text = "Инфо о компонентах"
$avestInfoBtn.Location = New-Object System.Drawing.Point(250, 55)
$avestInfoBtn.Size = New-Object System.Drawing.Size(210, 42)
$avestInfoBtn.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Regular)
$avestInfoBtn.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
$avestInfoBtn.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$avestInfoBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$avestInfoBtn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
$avestInfoBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
$avestInfoBtn.Add_Click({
    # Функции проверки компонентов (сокращены для читаемости, но оставлены все)
    function ПроверитьAvPass {
        $пути = @(
            "C:\Program Files\Avest\AvPCM\AvPCM.exe",
            "C:\Program Files (x86)\Avest\AvPCM\AvPCM.exe",
            "C:\Program Files\Avest\AvPCM_nces\AvPCM.exe",
            "C:\Program Files (x86)\Avest\AvPCM_nces\AvPCM.exe",
            "C:\Program Files\Avest\AvPCM_nces\MngCert.exe",
            "C:\Program Files (x86)\Avest\AvPCM_nces\MngCert.exe",
            "C:\Program Files\Avest\AvPCM_nces\AvCmUt4.exe"
        )
        foreach ($путь in $пути) { if (Test-Path $путь) { return $true } }
        $regPaths = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")
        foreach ($regPath in $regPaths) {
            $items = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                try {
                    $displayName = Get-ItemProperty -Path $item.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue
                    if ($displayName.DisplayName -like "*AvPCM*" -or $displayName.DisplayName -like "*Комплект Абонента*" -or $displayName.DisplayName -like "*AvUCK*") { return $true }
                } catch { }
            }
        }
        return $false
    }
    
    function ПроверитьAvBign {
        $пути = @("C:\Program Files\Avest\AvPCM\AvBign.exe", "C:\Program Files (x86)\Avest\AvPCM\AvBign.exe", "C:\Program Files\Avest\AvPCM_nces\AvBign.exe", "C:\Program Files (x86)\Avest\AvPCM_nces\AvBign.exe")
        foreach ($путь in $пути) { if (Test-Path $путь) { return $true } }
        $regPaths = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")
        foreach ($regPath in $regPaths) {
            $items = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                try {
                    $displayName = Get-ItemProperty -Path $item.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue
                    if ($displayName.DisplayName -like "*AvBign*") { return $true }
                } catch { }
            }
        }
        return $false
    }
    
    function ПроверитьAvCSPBel {
        $пути = @("C:\Program Files\Avest\Avest CSP Bel\AvCSPr.dll", "C:\Program Files (x86)\Avest\Avest CSP Bel\AvCSPr.dll", "C:\Program Files\Avest\Avest CSP Bel\AvCSPBel.dll", "C:\Program Files (x86)\Avest\Avest CSP Bel\AvCSPBel.dll")
        foreach ($путь in $пути) { if (Test-Path $путь) { return $true } }
        $regPaths = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")
        foreach ($regPath in $regPaths) {
            $items = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                try {
                    $displayName = Get-ItemProperty -Path $item.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue
                    if ($displayName.DisplayName -like "*AvCSPBel*" -or $displayName.DisplayName -like "*Avest CSP Bel*") { return $true }
                } catch { }
            }
        }
        return $false
    }
    
    function ПроверитьAvCSPBign {
        $пути = @("C:\Program Files\Avest\Avest CSP Bign\AvCSPr.dll", "C:\Program Files (x86)\Avest\Avest CSP Bign\AvCSPr.dll", "C:\Program Files\Avest\Avest CSP Bign\AvCSPBign.dll", "C:\Program Files (x86)\Avest\Avest CSP Bign\AvCSPBign.dll")
        foreach ($путь in $пути) { if (Test-Path $путь) { return $true } }
        $regPaths = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")
        foreach ($regPath in $regPaths) {
            $items = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                try {
                    $displayName = Get-ItemProperty -Path $item.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue
                    if ($displayName.DisplayName -like "*AvCSPBign*" -or $displayName.DisplayName -like "*Avest CSP Bign*") { return $true }
                } catch { }
            }
        }
        return $false
    }
    
    $avPassInstalled = ПроверитьAvPass
    $avBignInstalled = ПроверитьAvBign
    $cspBelInstalled = ПроверитьAvCSPBel
    $cspBignInstalled = ПроверитьAvCSPBign
    
    $infoForm = New-Object System.Windows.Forms.Form
    $infoForm.Text = "Информация о компонентах Авест"
    $infoForm.Size = New-Object System.Drawing.Size(480, 320)
    $infoForm.StartPosition = "CenterParent"
    $infoForm.FormBorderStyle = "FixedDialog"
    $infoForm.MaximizeBox = $false
    $infoForm.MinimizeBox = $false
    $infoForm.BackColor = [System.Drawing.Color]::White
    
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = "Компоненты Авест"
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $titleLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 102, 204)
    $titleLabel.AutoSize = $true
    $titleLabel.Location = New-Object System.Drawing.Point(20, 20)
    $infoForm.Controls.Add($titleLabel)
    
    $line = New-Object System.Windows.Forms.Label
    $line.Text = ""
    $line.BorderStyle = [System.Windows.Forms.BorderStyle]::Fixed3D
    $line.Size = New-Object System.Drawing.Size(420, 2)
    $line.Location = New-Object System.Drawing.Point(20, 55)
    $infoForm.Controls.Add($line)
    
    $richTextBox = New-Object System.Windows.Forms.RichTextBox
    $richTextBox.Location = New-Object System.Drawing.Point(20, 70)
    $richTextBox.Size = New-Object System.Drawing.Size(420, 150)
    $richTextBox.ReadOnly = $true
    $richTextBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $richTextBox.BackColor = [System.Drawing.Color]::White
    $richTextBox.Font = New-Object System.Drawing.Font("Consolas", 11, [System.Drawing.FontStyle]::Regular)
    
    $richTextBox.Clear()
    $richTextBox.SelectionColor = [System.Drawing.Color]::Black
    $richTextBox.AppendText("Комплект Абонента АВЕСТ (AvPass): ")
    if ($avPassInstalled) { $richTextBox.SelectionColor = [System.Drawing.Color]::Green; $richTextBox.AppendText("УСТАНОВЛЕН") } 
    else { $richTextBox.SelectionColor = [System.Drawing.Color]::Red; $richTextBox.AppendText("НЕ УСТАНОВЛЕН") }
    $richTextBox.AppendText("`n")
    
    $richTextBox.SelectionColor = [System.Drawing.Color]::Black
    $richTextBox.AppendText("Комплект Абонента АВЕСТ (AvBign): ")
    if ($avBignInstalled) { $richTextBox.SelectionColor = [System.Drawing.Color]::Green; $richTextBox.AppendText("УСТАНОВЛЕН") } 
    else { $richTextBox.SelectionColor = [System.Drawing.Color]::Red; $richTextBox.AppendText("НЕ УСТАНОВЛЕН") }
    $richTextBox.AppendText("`n")
    
    $richTextBox.SelectionColor = [System.Drawing.Color]::Black
    $richTextBox.AppendText("Криптопровайдер AvCSPBel: ")
    if ($cspBelInstalled) { $richTextBox.SelectionColor = [System.Drawing.Color]::Green; $richTextBox.AppendText("УСТАНОВЛЕН") } 
    else { $richTextBox.SelectionColor = [System.Drawing.Color]::Red; $richTextBox.AppendText("НЕ УСТАНОВЛЕН") }
    $richTextBox.AppendText("`n")
    
    $richTextBox.SelectionColor = [System.Drawing.Color]::Black
    $richTextBox.AppendText("Криптопровайдер AvCSPBign: ")
    if ($cspBignInstalled) { $richTextBox.SelectionColor = [System.Drawing.Color]::Green; $richTextBox.AppendText("УСТАНОВЛЕН") } 
    else { $richTextBox.SelectionColor = [System.Drawing.Color]::Red; $richTextBox.AppendText("НЕ УСТАНОВЛЕН") }
    $richTextBox.AppendText("`n`n")
    
    $richTextBox.SelectionColor = [System.Drawing.Color]::Gray
    $richTextBox.AppendText("Для установки компонентов:" + "`n")
    $richTextBox.AppendText("Нажмите кнопку 'Установить компоненты Авест'")
    
    $infoForm.Controls.Add($richTextBox)
    
    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "OK"
    $okButton.Size = New-Object System.Drawing.Size(80, 30)
    $okButton.Location = New-Object System.Drawing.Point(180, 235)
    $okButton.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $okButton.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $okButton.ForeColor = [System.Drawing.Color]::White
    $okButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $okButton.Add_Click({ $infoForm.Close() })
    $infoForm.Controls.Add($okButton)
    
    $infoForm.ShowDialog()
})
$buttonPanel.Controls.Add($avestInfoBtn)

# Кнопка информации о плагине
$infoBtn = New-Object System.Windows.Forms.Button
$infoBtn.Text = "Информация о плагине"
$infoBtn.Location = New-Object System.Drawing.Point(250, 110)
$infoBtn.Size = New-Object System.Drawing.Size(210, 42)
$infoBtn.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Regular)
$infoBtn.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
$infoBtn.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$infoBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$infoBtn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
$infoBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
$infoBtn.Add_Click({
    $installedVersion = "Не установлен"
    $registryPaths = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*")
    
    foreach ($regPath in $registryPaths) {
        $items = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            try {
                $displayName = Get-ItemProperty -Path $item.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue
                if ($displayName.DisplayName -like "*AvCMXWebP*") {
                    $ver = Get-ItemProperty -Path $item.PSPath -Name "DisplayVersion" -ErrorAction SilentlyContinue
                    if ($ver.DisplayVersion) { $installedVersion = $ver.DisplayVersion; break }
                }
            } catch { }
        }
        if ($installedVersion -ne "Не установлен") { break }
    }
    
    if ($installedVersion -eq "Не установлен") {
        $filePaths = @("C:\Program Files\Avest\AvCMXWebP\AvCMXWebP.exe", "C:\Program Files (x86)\Avest\AvCMXWebP\AvCMXWebP.exe")
        foreach ($path in $filePaths) {
            if (Test-Path $path) {
                try {
                    $fileInfo = Get-Item $path -ErrorAction SilentlyContinue
                    if ($fileInfo.VersionInfo.FileVersion) { $installedVersion = $fileInfo.VersionInfo.FileVersion } 
                    else { $installedVersion = "Установлен (версия неизвестна)" }
                    break
                } catch { $installedVersion = "Установлен (версия неизвестна)" }
            }
        }
    }
    
    $infoMsg = @"
Плагин AvCMXWebP
================================

Состояние: $installedVersion

Для установки или обновления:
Нажмите кнопку 'Установить плагин AvCMXWebP'
"@
    
    [System.Windows.Forms.MessageBox]::Show($infoMsg, "Информация о плагине", "OK", "Information")
})
$buttonPanel.Controls.Add($infoBtn)

# Кнопка открытия папки
$openFolderBtn = New-Object System.Windows.Forms.Button
$openFolderBtn.Text = "Открыть папку"
$openFolderBtn.Location = New-Object System.Drawing.Point(250, 165)
$openFolderBtn.Size = New-Object System.Drawing.Size(210, 42)
$openFolderBtn.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Regular)
$openFolderBtn.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
$openFolderBtn.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$openFolderBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$openFolderBtn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
$openFolderBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
$openFolderBtn.Add_Click({
    if ($folderWindowOpen) {
        [System.Windows.Forms.MessageBox]::Show("Окно папки уже открывается.", "Внимание", "OK", "Information")
        return
    }
    
    $folderWindowOpen = $true
    $openFolderBtn.Enabled = $false
    $statusLabel.Text = "Открытие папки..."
    $statusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
    
    try {
        Start-Process "explorer.exe" $scriptPath
    } catch {
        $statusLabel.Text = "Ошибка открытия папки"
        $statusLabel.ForeColor = [System.Drawing.Color]::Red
    }
    
    # ИСПРАВЛЕНО: запускаем таймер с помощью GetNewClosure()
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 2000
    $timer.Add_Tick({
        $folderWindowOpen = $false
        $openFolderBtn.Enabled = $true
        $statusLabel.Text = "Готов"
        $statusLabel.ForeColor = [System.Drawing.Color]::Gray
        $timer.Stop()
        $timer.Dispose()
    }.GetNewClosure())
    $timer.Start()
})
$buttonPanel.Controls.Add($openFolderBtn)

# ======================================================
# Кнопка выхода
# ======================================================
$exitBtn = New-Object System.Windows.Forms.Button
$exitBtn.Text = "Выход"
$exitBtn.Location = New-Object System.Drawing.Point(180, 230)
$exitBtn.Size = New-Object System.Drawing.Size(100, 42)
$exitBtn.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$exitBtn.BackColor = [System.Drawing.Color]::FromArgb(220, 220, 220)
$exitBtn.ForeColor = [System.Drawing.Color]::DarkRed
$exitBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$exitBtn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
$exitBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
$exitBtn.Add_Click({ $form.Close() })
$buttonPanel.Controls.Add($exitBtn)

# Футер с версией
$versionLabel = New-Object System.Windows.Forms.Label
$versionLabel.Text = "Версия 2.0 | Инструмент управления сертификатами"
$versionLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Regular)
$versionLabel.ForeColor = [System.Drawing.Color]::Gray
$versionLabel.AutoSize = $true
$versionLabel.Location = New-Object System.Drawing.Point(117, 385)
$form.Controls.Add($versionLabel)

$form.ShowDialog()