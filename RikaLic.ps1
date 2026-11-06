# Requires RunAsAdministrator
param()

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

function Get-DecodedWindowsKey {
    try {
        $hex = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'DigitalProductId' -ErrorAction SilentlyContinue).DigitalProductId
        if ($null -eq $hex -or $hex.Length -lt 67) { return $null }
        $b = $hex[52..66]
        $c = "BCDFGHJKMPQRTVWXY2346789"
        $isWin8 = [math]::truncate($hex[66] / 6) -band 1
        $b[14] = ($b[14] -band 247) -bor (($isWin8 -band 2) * 4)
        $key = ""
        $last = 0
        for ($i = 24; $i -ge 0; $i--) {
            $k = 0
            for ($j = 14; $j -ge 0; $j--) {
                $k = ($k * 256) -bxor $b[$j]
                $b[$j] = [math]::truncate($k / 24)
                $k = $k % 24
            }
            $key = $c[$k] + $key
            $last = $k
        }
        if ($isWin8 -ne 0) {
            $first = $key.Substring(0, 1)
            $key = $key.Substring(1).Insert($last, $first)
        }
        $key = $key.Insert(5, '-').Insert(11, '-').Insert(17, '-').Insert(23, '-')
        return $key
    } catch { return $null }
}


# --- 1. TỰ ĐỘNG XIN QUYỀN ADMINISTRATOR & ẨN CỬA SỔ CMD ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    if ($PSCommandPath) {
        # Chạy từ file cứng (.ps1)
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"" -Verb RunAs
    } else {
        # Chạy file-less từ lệnh irm | iex trên RAM
        $webCmd = "irm lic.bachkhoapc.vn | iex"
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"$webCmd`"" -Verb RunAs
    }
    Exit
}

# Ẩn hoàn toàn cửa sổ dòng lệnh PowerShell (màu xanh/đen) chạy nền
if (-not ("Console.Window" -as [type])) {
    Add-Type -Name Window -Namespace Console -MemberDefinition '
    [DllImport("Kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
    '
}
[Console.Window]::ShowWindow([Console.Window]::GetConsoleWindow(), 0) | Out-Null

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- 2. THIẾT LẬP GIAO DIỆN CHÍNH (WINFORMS) ---
$form = New-Object System.Windows.Forms.Form
$form.SuspendLayout() # Bắt đầu tối ưu tốc độ render UI
$form.Text = "BKC Lic - By TranHa v3.0 Ultimate - Trình Quản Lý Bản Quyền Nâng Cao"
$form.Size = New-Object System.Drawing.Size(900, 780)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(245, 246, 250)

# Định nghĩa Font chữ hiện đại
$fontSection = New-Object System.Drawing.Font("Segoe UI Semibold", 10.5, [System.Drawing.FontStyle]::Bold)
$fontBtn     = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$fontCode    = New-Object System.Drawing.Font("Consolas", 10.5)
$fontSmall   = New-Object System.Drawing.Font("Segoe UI", 9)
$fontNormal  = New-Object System.Drawing.Font("Segoe UI", 10)

# --- KHUNG HIỂN THỊ LOG (CỐ ĐỊNH TRÊN CÙNG) ---
$lblLogTitle = New-Object System.Windows.Forms.Label
$lblLogTitle.Text = "Nhật ký hoạt động (System Log):"
$lblLogTitle.Font = $fontSection
$lblLogTitle.Location = New-Object System.Drawing.Point(20, 12)
$lblLogTitle.AutoSize = $true
$form.Controls.Add($lblLogTitle)


$btnClearLog = New-Object System.Windows.Forms.Button
$btnClearLog.Text = "Xóa Log"
$btnClearLog.Font = $fontSmall
$btnClearLog.Location = New-Object System.Drawing.Point(645, 8)
$btnClearLog.Size = New-Object System.Drawing.Size(95, 28)
$btnClearLog.BackColor = [System.Drawing.Color]::White
$btnClearLog.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnClearLog.Add_Click({ $txtLog.Text = "" })
$form.Controls.Add($btnClearLog)

$btnCopyLog = New-Object System.Windows.Forms.Button
$btnCopyLog.Text = "Copy Log"
$btnCopyLog.Font = $fontSmall
$btnCopyLog.Location = New-Object System.Drawing.Point(750, 8)
$btnCopyLog.Size = New-Object System.Drawing.Size(95, 28)
$btnCopyLog.BackColor = [System.Drawing.Color]::White
$btnCopyLog.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnCopyLog.Add_Click({
    if ($txtLog.Text) {
        [System.Windows.Forms.Clipboard]::SetText($txtLog.Text)
        Write-Log "Đã sao chép toàn bộ nhật ký vào Clipboard!" "CLEAN"
    }
})
$form.Controls.Add($btnCopyLog)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.ReadOnly = $true
$txtLog.Location = New-Object System.Drawing.Point(20, 45)
$txtLog.Size = New-Object System.Drawing.Size(840, 240)
$txtLog.Font = $fontCode
$txtLog.BackColor = [System.Drawing.Color]::White
$txtLog.ForeColor = [System.Drawing.Color]::FromArgb(40, 40, 40)
$form.Controls.Add($txtLog)

# --- CÁC HÀM TIỆN ÍCH ---
function Write-Log ($text, $level="INFO") {
    $prefix = switch ($level) {
        "CLEAN" { "[OK]   " }
        "WARN"  { "[! WARN] " }
        "CRIT"  { "[X CRIT] " }
        default { "[i INFO] " }
    }
    $txtLog.AppendText("$prefix $text`r`n")
    $txtLog.SelectionStart = $txtLog.Text.Length
    $txtLog.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Invoke-CScript ($ScriptPath, $Arguments) {
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = "cscript.exe"
    $processInfo.Arguments = "//nologo `"$ScriptPath`" $Arguments"
    $processInfo.RedirectStandardOutput = $true
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    $process.Start() | Out-Null
    
    $output = $process.StandardOutput.ReadToEnd()
    $process.WaitForExit()
    
    return $output -split "`r`n" | Where-Object { $_ -match "\S" }
}

function Get-OsppPath {
    $paths = @(
        "$env:ProgramFiles\Microsoft Office\Office16\ospp.vbs",
        "${env:ProgramFiles(x86)}\Microsoft Office\Office16\ospp.vbs",
        "$env:ProgramFiles\Microsoft Office\root\Office16\ospp.vbs",
        "${env:ProgramFiles(x86)}\Microsoft Office\root\Office16\ospp.vbs",
        "$env:ProgramFiles\Microsoft Office\Office15\ospp.vbs",
        "${env:ProgramFiles(x86)}\Microsoft Office\Office15\ospp.vbs",
        "$env:ProgramFiles\Microsoft Office\root\Office15\ospp.vbs",
        "${env:ProgramFiles(x86)}\Microsoft Office\root\Office15\ospp.vbs",
        "$env:ProgramFiles\Microsoft Office\Office14\ospp.vbs",
        "${env:ProgramFiles(x86)}\Microsoft Office\Office14\ospp.vbs"
    )
    foreach ($p in $paths) { if (Test-Path $p) { return $p } }
    return $null
}

function Validate-Key($key) { return ($key -match "^[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}$") }

$allButtons = @()
function Toggle-Buttons($state) {
    foreach ($btn in $allButtons) { if ($btn) { $btn.Enabled = $state } }
    [System.Windows.Forms.Application]::DoEvents()
}

# --- CÁC HÀM XỬ LÝ CHÍNH ---

function Invoke-LicenseScan {
    $txtLog.Text = ""
    Write-Log ">>> ĐANG QUÉT THÔNG TIN BẢN QUYỀN WINDOWS..." "INFO"
    try {
        $bios = (Get-CimInstance -Query "Select * from SoftwareLicensingService" -ErrorAction Stop).OA3xOriginalProductKey
        if ($bios) { Write-Log "Key BIOS (OEM nhúng Mainboard): $bios" "CLEAN" }
    } catch {}
    $regKey = Get-DecodedWindowsKey
    if ($regKey) { Write-Log "[OK]    Key dự phòng (Registry): $regKey" "CLEAN" }


    $winLic = Get-CimInstance SoftwareLicensingProduct -Filter "Name LIKE 'Windows%' AND PartialProductKey IS NOT NULL"
    if ($winLic) {
        foreach ($l in $winLic) {
            $status = if ($l.LicenseStatus -eq 1) { "Đã kích hoạt vĩnh viễn / Hợp lệ" } else { "Chưa kích hoạt" }
            $type = if ($l.Description -match "VOLUME_KMSCLIENT") { "KMS Client (Dễ bị crack)" } elseif ($l.Description -match "OEM") { "OEM Bản quyền số" } else { "Retail / MAK Bản quyền chuẩn" }
            $level = if ($type -match "KMS") { "WARN" } else { "CLEAN" }
            Write-Log "Phiên bản : $($l.Name)" "INFO"
            Write-Log "Phân loại : $type ($($l.Description))" $level
            Write-Log "Trạng thái: $status (5 số cuối Key: $($l.PartialProductKey))" $level
        }
    } else { Write-Log "Windows chưa được cài đặt Product Key." "WARN" }

    Write-Log "------------------------------------------------------------" "INFO"
    Write-Log ">>> ĐANG QUÉT THÔNG TIN BẢN QUYỀN MICROSOFT OFFICE..." "INFO"
    
    # 1. Quét Office 365 / M365 (User-Based Subscription)
    $m365Found = $false
    $identityPath = "HKCU:\Software\Microsoft\Office\16.0\Common\Identity\Identities"
    if (Test-Path $identityPath) {
        $identities = Get-ChildItem -Path $identityPath -ErrorAction SilentlyContinue
        foreach ($id in $identities) {
            $email = (Get-ItemProperty -Path $id.PSPath -Name "EmailAddress" -ErrorAction SilentlyContinue).EmailAddress
            if ($email -and $email -match "@") {
                Write-Log "Phát hiện M365/Office 365 (Đăng nhập Email): $email" "CLEAN"
                $m365Found = $true
            }
        }
    }
    if ($m365Found) {
        Write-Log "Loại: Thuê bao Subscription đám mây (User-based Activation)" "CLEAN"
    }
    
    # 2. Quét Office Volume/Retail qua OSPP
    $ospp = Get-OsppPath
    if (!$ospp) { 
        if (!$m365Found) { Write-Log "Không tìm thấy công cụ OSPP. Office chưa cài đặt." "WARN" }
        return 
    }
    
    $officeOutput = Invoke-CScript $ospp "/dstatus"
    $foundOffice = $false
    foreach ($line in $officeOutput) {
        if ($line -match "LICENSE NAME") { Write-Log ($line.Replace("LICENSE NAME: ", "Tên gói: ")) "INFO"; $foundOffice = $true }
        if ($line -match "LICENSE DESCRIPTION") { Write-Log ($line.Replace("LICENSE DESCRIPTION: ", "Loại: ")) "INFO" }
        if ($line -match "LICENSE STATUS") { 
            $lvl = if ($line -match "LICENSED") { "CLEAN" } else { "WARN" }
            Write-Log ($line.Replace("LICENSE STATUS: ", "Trạng thái: ")) $lvl 
        }
        if ($line -match "Last 5 characters") { Write-Log ($line.Replace("Last 5 characters of installed product key: ", "5 số cuối Key: ")) "INFO" }
    }
    if (!$foundOffice -and !$m365Found) { Write-Log "Không tìm thấy giấy phép Office OSPP nào đang hoạt động." "WARN" }
}

function Clear-WinLicenses {
    $txtLog.Text = ""
    Write-Log ">>> ĐANG DỌN DẸP BẢN QUYỀN WINDOWS..." "INFO"
    Invoke-CScript "$env:SystemRoot\System32\slmgr.vbs" "/upk" | Out-Null
    Invoke-CScript "$env:SystemRoot\System32\slmgr.vbs" "/cpky" | Out-Null
    Invoke-CScript "$env:SystemRoot\System32\slmgr.vbs" "/ckms" | Out-Null
    Write-Log "Đã dọn dẹp sạch sẽ cấu hình bản quyền Windows!" "CLEAN"
}

function Clear-OfficeLicenses {
    $txtLog.Text = ""
    Write-Log ">>> ĐANG DỌN DẸP BẢN QUYỀN / TÀN DƯ CRACK OFFICE..." "INFO"
    $ospp = Get-OsppPath
    if (!$ospp) { Write-Log "Không tìm thấy OSPP. Office chưa cài đặt." "WARN"; return }
    Invoke-CScript $ospp "/remhst" | Out-Null
    $output = Invoke-CScript $ospp "/dstatus"
    $count = 0
    foreach ($line in $output) {
        if ($line -match "Last 5 characters of installed product key:\s*([A-Z0-9]{5})") {
            $key = $matches[1].Trim()
            Invoke-CScript $ospp "/unpkey:$key" | Out-Null
            Write-Log "-> Đã gỡ thành công Key đuôi: $key" "CLEAN"
            $count++
        }
    }
    if ($count -eq 0) { Write-Log "Không tìm thấy Key Office nào cần gỡ." "INFO" }
    Write-Log "Hoàn tất dọn dẹp bản quyền Office!" "CLEAN"
}

function Show-OfficeUninstaller {
    $txtLog.Text = ""
    Write-Log ">>> ĐANG QUÉT CÁC PHIÊN BẢN OFFICE ĐÃ CÀI..." "INFO"
    
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    $officeApps = Get-ItemProperty $paths -ErrorAction SilentlyContinue | Where-Object { 
        $_.DisplayName -match "Microsoft Office|Microsoft 365|Microsoft LTSC" -and 
        $_.DisplayName -notmatch "Language Pack|Proofing|MUI|Click-to-Run Component"
    }

    if (!$officeApps -or $officeApps.Count -eq 0) {
        Write-Log "Không tìm thấy phần mềm Microsoft Office nào trên máy." "WARN"
        [System.Windows.Forms.MessageBox]::Show("Không tìm thấy phần mềm Microsoft Office nào được cài đặt trên máy này.","Thông báo", 0, [System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }

    $formUn = New-Object System.Windows.Forms.Form
    $formUn.Text = "Gỡ Cài Đặt Office"
    $formUn.Size = New-Object System.Drawing.Size(420, 180)
    $formUn.StartPosition = "CenterParent"
    $formUn.FormBorderStyle = "FixedDialog"
    $formUn.MaximizeBox = $false
    $formUn.MinimizeBox = $false

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Chọn phiên bản Office cần gỡ cài đặt:"
    $lbl.Location = New-Object System.Drawing.Point(20, 20)
    $lbl.AutoSize = $true
    $formUn.Controls.Add($lbl)

    $combo = New-Object System.Windows.Forms.ComboBox
    $combo.Location = New-Object System.Drawing.Point(20, 45)
    $combo.Size = New-Object System.Drawing.Size(360, 30)
    $combo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    
    foreach ($app in $officeApps) {
        [void]$combo.Items.Add($app.DisplayName)
    }
    $combo.SelectedIndex = 0
    $formUn.Controls.Add($combo)

    $btnUn = New-Object System.Windows.Forms.Button
    $btnUn.Text = "Tiến Hành Gỡ Cài Đặt"
    $btnUn.Location = New-Object System.Drawing.Point(120, 90)
    $btnUn.Size = New-Object System.Drawing.Size(160, 35)
    $btnUn.BackColor = [System.Drawing.Color]::FromArgb(211, 47, 47)
    $btnUn.ForeColor = [System.Drawing.Color]::White
    $btnUn.FlatStyle = "Flat"
    $btnUn.Cursor = "Hand"
    $btnUn.Add_Click({
        $selectedName = $combo.SelectedItem
        $selectedApp = $officeApps | Where-Object { $_.DisplayName -eq $selectedName } | Select-Object -First 1
        
        $uninstallCmd = $selectedApp.UninstallString
        if ($uninstallCmd) {
            Write-Log "Đang mở trình gỡ cài đặt cho: $selectedName" "INFO"
            Start-Process cmd.exe -ArgumentList "/c $uninstallCmd"
            $formUn.Close()
        } else {
            [System.Windows.Forms.MessageBox]::Show("Không tìm thấy lệnh gỡ cài đặt cho bản này!","Lỗi", 0, 16)
        }
    })
    $formUn.Controls.Add($btnUn)

    $formUn.ShowDialog() | Out-Null
}

function Install-WinKeyOnline {
    $k = $txtKey.Text.Trim()
    if (Validate-Key $k) {
        Write-Log "Đang nạp Key Windows: $k..." "INFO"
        Invoke-CScript "$env:SystemRoot\System32\slmgr.vbs" "/ipk $k" | Out-Null
        Write-Log "Đang liên hệ máy chủ. Vui lòng chờ..." "INFO"
        $result = Invoke-CScript "$env:SystemRoot\System32\slmgr.vbs" "/ato"
        if ($result -match "successfully" -or $result -match "thành công") { Write-Log "KÍCH HOẠT WINDOWS ONLINE THÀNH CÔNG!" "CLEAN" }
        else { Write-Log "Kích hoạt Windows thất bại:" "CRIT"; foreach ($r in $result) { Write-Log "  $r" "WARN" } }
    } else { Write-Log "Key không hợp lệ! Cần 25 ký tự." "WARN" }
}

function Install-OfficeKeyOnline {
    $k = $txtKey.Text.Trim()
    if (Validate-Key $k) {
        $ospp = Get-OsppPath
        if ($ospp) {
            Write-Log "Đang nạp Key Office: $k..." "INFO"
            Invoke-CScript $ospp "/inpkey:$k" | Out-Null
            Write-Log "Đang liên hệ máy chủ. Vui lòng chờ..." "INFO"
            $result = Invoke-CScript $ospp "/act"
            if ($result -match "successful" -or $result -match "thành công" -or ($result -join " ") -match "Product activation successful") { Write-Log "KÍCH HOẠT OFFICE ONLINE THÀNH CÔNG!" "CLEAN" }
            else { Write-Log "Kích hoạt Office thất bại:" "CRIT"; foreach ($r in $result) { Write-Log "  $r" "WARN" } }
        } else { Write-Log "Không tìm thấy OSPP." "WARN" }
    } else { Write-Log "Key không hợp lệ! Cần 25 ký tự." "WARN" }
}

function Format-IIDGrouped ($iid) {
    if (-not $iid) { return "" }
    $clean = $iid -replace '\D', ''
    if ($clean.Length -eq 63) {
        $groups = for ($i = 0; $i -lt 63; $i += 7) { $clean.Substring($i, 7) }
        return ($groups -join " - ")
    } elseif ($clean.Length -eq 54) {
        $groups = for ($i = 0; $i -lt 54; $i += 6) { $clean.Substring($i, 6) }
        return ($groups -join " - ")
    } elseif ($clean.Length -gt 7) {
        $chunks = @()
        for ($i = 0; $i -lt $clean.Length; $i += 7) {
            $len = [Math]::Min(7, $clean.Length - $i)
            $chunks += $clean.Substring($i, $len)
        }
        return ($chunks -join " - ")
    }
    return $clean
}

function Format-CIDGrouped ($cid) {
    if (-not $cid) { return "" }
    $clean = $cid -replace '\D', ''
    if ($clean.Length -eq 48) {
        $letters = @('A','B','C','D','E','F','G','H')
        $groups = for ($i = 0; $i -lt 48; $i += 6) {
            "[$($letters[$i/6])] $($clean.Substring($i, 6))"
        }
        return ($groups -join "  ")
    } elseif ($clean.Length -gt 0) {
        $letters = @('A','B','C','D','E','F','G','H')
        $groups = @()
        for ($i = 0; $i -lt $clean.Length; $i += 6) {
            $len = [Math]::Min(6, $clean.Length - $i)
            $idx = [Math]::Floor($i / 6)
            $lbl = if ($idx -lt 8) { $letters[$idx] } else { "?" }
            $groups += "[$lbl] $($clean.Substring($i, $len))"
        }
        return ($groups -join "  ")
    }
    return $clean
}

function Update-PhoneValidationUI {
    if ($null -ne $txtIID -and $null -ne $lblIIDCount -and $null -ne $lblIIDPreview) {
        $rawIID = if ($txtIID.Text) { $txtIID.Text.Trim() } else { "" }
        $cleanIID = $rawIID -replace '\D', ''
        if ($cleanIID.Length -eq 63) {
            $lblIIDCount.Text = "[HỢP LỆ: 63/63 SỐ (9x7)]"
            $lblIIDCount.ForeColor = [System.Drawing.Color]::FromArgb(46, 125, 50)
            $lblIIDPreview.Text = Format-IIDGrouped $cleanIID
        } elseif ($cleanIID.Length -eq 54) {
            $lblIIDCount.Text = "[HỢP LỆ: 54/54 SỐ (9x6)]"
            $lblIIDCount.ForeColor = [System.Drawing.Color]::FromArgb(46, 125, 50)
            $lblIIDPreview.Text = Format-IIDGrouped $cleanIID
        } elseif ($cleanIID.Length -eq 0) {
            $lblIIDCount.Text = "[CHƯA CÓ IID]"
            $lblIIDCount.ForeColor = [System.Drawing.Color]::FromArgb(120, 144, 156)
            $lblIIDPreview.Text = "(IID Dạng Khối 9 nhóm x 7 số để đọc qua điện thoại sẽ hiển thị tại đây)"
        } else {
            $lblIIDCount.Text = "[CHƯA ĐỦ: $($cleanIID.Length)/63 SỐ]"
            $lblIIDCount.ForeColor = [System.Drawing.Color]::FromArgb(230, 81, 0)
            $lblIIDPreview.Text = Format-IIDGrouped $cleanIID
        }
    }
    if ($null -ne $txtCID -and $null -ne $lblCIDCount -and $null -ne $lblCIDPreview) {
        $rawCID = if ($txtCID.Text) { $txtCID.Text.Trim() } else { "" }
        $cleanCID = $rawCID -replace '\D', ''
        if ($cleanCID.Length -eq 48) {
            $lblCIDCount.Text = "[HỢP LỆ: 48/48 SỐ (8 KHỐI A-H)]"
            $lblCIDCount.ForeColor = [System.Drawing.Color]::FromArgb(46, 125, 50)
            $lblCIDPreview.Text = Format-CIDGrouped $cleanCID
        } elseif ($cleanCID.Length -eq 0) {
            $lblCIDCount.Text = "[CHƯA CÓ CID]"
            $lblCIDCount.ForeColor = [System.Drawing.Color]::FromArgb(120, 144, 156)
            $lblCIDPreview.Text = "(CID Dạng Khối 8 nhóm [A] - [H] sẽ hiển thị tại đây)"
        } else {
            $lblCIDCount.Text = "[CHƯA ĐỦ: $($cleanCID.Length)/48 SỐ]"
            $lblCIDCount.ForeColor = [System.Drawing.Color]::FromArgb(230, 81, 0)
            $lblCIDPreview.Text = Format-CIDGrouped $cleanCID
        }
    }
}

function Get-WinIID {
    $txtLog.Text = ""; Write-Log "Đang lấy Installation ID Windows..." "INFO"
    $result = Invoke-CScript "$env:SystemRoot\System32\slmgr.vbs" "/dti"
    $iid = $result | Where-Object { $_ -match "\d{20,}" } | ForEach-Object { [regex]::match($_, "\d{20,}").Value } | Select-Object -First 1
    if ($iid) {
        $txtIID.Text = $iid
        [System.Windows.Forms.Clipboard]::SetText($iid)
        Update-PhoneValidationUI
        Write-Log "Lấy IID Windows thành công và đã copy vào Clipboard: $iid" "CLEAN"
        $grouped = Format-IIDGrouped $iid
        Write-Log "IID Dạng khối (đọc điện thoại): $grouped" "INFO"
    } else {
        Write-Log "Lỗi lấy IID. Vui lòng nạp Key Phone trước (dùng nút 'Nạp Key Phone Mới')." "WARN"
    }
}

function Install-WinCID {
    $cleanCID = $txtCID.Text -replace '\D', ''
    if ($cleanCID.Length -eq 48) {
        $txtCID.Text = $cleanCID
        Update-PhoneValidationUI
        Write-Log "Đang nạp CID Windows: $cleanCID..." "INFO"
        $result = Invoke-CScript "$env:SystemRoot\System32\slmgr.vbs" "/atp $cleanCID"
        if ($result -match "successfully" -or $result -match "thành công") {
            Write-Log "KÍCH HOẠT WINDOWS BY PHONE THÀNH CÔNG!" "CLEAN"
            Check-TargetStatus
        } else {
            Write-Log "Nạp CID thất bại:" "CRIT"
            foreach ($r in $result) { Write-Log "  $r" "WARN" }
        }
    } else {
        Write-Log "CID không hợp lệ! Phải đủ 48 số (hiện có $($cleanCID.Length) số)." "WARN"
    }
}

function Get-OfficeIID {
    $txtLog.Text = ""; Write-Log "Đang lấy Installation ID Office..." "INFO"
    $ospp = Get-OsppPath
    if (!$ospp) { Write-Log "Không tìm thấy OSPP. Office chưa cài đặt." "WARN"; return }
    $output = Invoke-CScript $ospp "/dti"
    $joined = ($output -join " "); $iid = $null
    if ($joined -match "(\d{63}|\d{54}|\d{48}|\d{36}|\d{20,})") { $iid = $matches[1] }
    if ($iid) {
        $txtIID.Text = $iid
        [System.Windows.Forms.Clipboard]::SetText($iid)
        Update-PhoneValidationUI
        Write-Log "Lấy IID Office thành công và đã copy vào Clipboard: $iid" "CLEAN"
        $grouped = Format-IIDGrouped $iid
        Write-Log "IID Dạng khối (đọc điện thoại): $grouped" "INFO"
    } else {
        Write-Log "Lỗi lấy IID Office. Hãy nạp Key Phone trước (dùng nút 'Nạp Key Phone Mới')." "WARN"
        foreach ($l in $output) { Write-Log "  $l" "INFO" }
    }
}

function Install-OfficeCID {
    $ospp = Get-OsppPath
    if (!$ospp) { Write-Log "Không tìm thấy OSPP." "WARN"; return }
    $cleanCID = $txtCID.Text -replace '\D', ''
    if ($cleanCID.Length -eq 48) {
        $txtCID.Text = $cleanCID
        Update-PhoneValidationUI
        Write-Log "Đang nạp CID Office: $cleanCID..." "INFO"
        $result = Invoke-CScript $ospp "/actcid:$cleanCID"
        if ($result -match "successful" -or $result -match "thành công" -or ($result -join " ") -match "successfully") {
            Write-Log "KÍCH HOẠT OFFICE BY PHONE THÀNH CÔNG!" "CLEAN"
            Check-TargetStatus
        } else {
            Write-Log "Nạp CID thất bại:" "CRIT"
            foreach ($r in $result) { Write-Log "  $r" "WARN" }
        }
    } else {
        Write-Log "CID không hợp lệ! Phải đủ 48 số (hiện có $($cleanCID.Length) số)." "WARN"
    }
}

function Get-TargetIID {
    if ($rbTargetWin.Checked) {
        Get-WinIID
    } else {
        Get-OfficeIID
    }
}

function Install-TargetCID {
    if ($rbTargetWin.Checked) {
        Install-WinCID
    } else {
        Install-OfficeCID
    }
}

function Invoke-SmartPasteAndInstallCID {
    if (-not [System.Windows.Forms.Clipboard]::ContainsText()) {
        Write-Log "Clipboard đang trống, không tìm thấy mã CID nào!" "WARN"
        [System.Windows.Forms.MessageBox]::Show("Clipboard đang trống! Vui lòng sao chép mã Confirmation ID (CID) 48 số trước.", "Thông báo", 0, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    $clip = [System.Windows.Forms.Clipboard]::GetText().Trim()
    $clean = $clip -replace '\D', ''
    if ($clean.Length -ge 48) {
        $cid48 = $clean.Substring(0, 48)
        $txtCID.Text = $cid48
        Update-PhoneValidationUI
        Write-Log "ĐÃ NHẬN DIỆN CID TỪ CLIPBOARD (48 SỐ): $cid48" "CLEAN"
        $grouped = Format-CIDGrouped $cid48
        Write-Log "Dạng khối A-H: $grouped" "INFO"
        Install-TargetCID
    } else {
        Write-Log "Nội dung trong Clipboard không đủ 48 số CID (chỉ tìm thấy $($clean.Length) số)." "WARN"
        [System.Windows.Forms.MessageBox]::Show("Nội dung Clipboard không đủ 48 số CID (chỉ có $($clean.Length) số). Vui lòng kiểm tra lại mã đã sao chép!", "CID Không Hợp Lệ", 0, [System.Windows.Forms.MessageBoxIcon]::Warning)
    }
}

function Check-TargetStatus {
    $txtLog.Text = ""
    if ($rbTargetWin.Checked) {
        Write-Log ">>> KIỂM TRA TRẠNG THÁI BẢN QUYỀN WINDOWS..." "INFO"
        $resXpr = Invoke-CScript "$env:SystemRoot\System32\slmgr.vbs" "/xpr"
        foreach ($l in $resXpr) {
            $lvl = if ($l -match "permanently|vĩnh viễn") { "CLEAN" } else { "INFO" }
            Write-Log $l $lvl
        }
        $resDli = Invoke-CScript "$env:SystemRoot\System32\slmgr.vbs" "/dli"
        foreach ($l in $resDli) {
            if ($l -match "Name:|Description:|Partial Product Key:|License Status:") {
                $lvl = if ($l -match "Licensed") { "CLEAN" } else { "INFO" }
                Write-Log $l $lvl
            }
        }
    } else {
        Write-Log ">>> KIỂM TRA TRẠNG THÁI BẢN QUYỀN MICROSOFT OFFICE..." "INFO"
        $ospp = Get-OsppPath
        if (!$ospp) { Write-Log "Không tìm thấy OSPP. Office chưa cài đặt." "WARN"; return }
        $resOffice = Invoke-CScript $ospp "/dstatus"
        foreach ($l in $resOffice) {
            if ($l -match "LICENSE NAME|LICENSE DESCRIPTION|LICENSE STATUS|Last 5 characters") {
                $lvl = if ($l -match "LICENSED") { "CLEAN" } else { "INFO" }
                Write-Log $l $lvl
            }
        }
    }
}

function Open-SpecificWebCID ($url, $name) {
    $clean = if ($txtIID.Text) { $txtIID.Text.Trim() -replace '\D', '' } else { "" }
    if (-not $clean) {
        Get-TargetIID
        $clean = if ($txtIID.Text) { $txtIID.Text.Trim() -replace '\D', '' } else { "" }
    }
    if ($clean) {
        [System.Windows.Forms.Clipboard]::SetText($clean)
        Write-Log "ĐÃ TỰ ĐỘNG SAO CHÉP IID VÀO CLIPBOARD: $clean" "CLEAN"
    }
    Write-Log "Đang mở trang web Get CID: $name ($url)..." "INFO"
    Write-Log "HƯỚNG DẪN: Nhấn Ctrl+V để dán IID vào trang web để lấy mã CID." "CLEAN"
    if ($url -match "khoatoantin") {
        Write-Log "LƯU Ý KHOATOANTIN: Tài khoản đăng nhập nếu có hỏi: trogiup24h | Mật khẩu: PHO" "INFO"
    }
    try {
        Start-Process $url
    } catch {
        Write-Log "Không thể tự mở trình duyệt. Vui lòng truy cập thủ công: $url" "WARN"
    }
}

function Invoke-AutoGetCIDFromIID {
    $iid = $txtIID.Text.Trim() -replace '\D', ''
    if (-not ($iid.Length -eq 63 -or $iid.Length -eq 54)) {
        Write-Log "IID không hợp lệ! Vui lòng bấm 'Lấy IID' trước (phải đủ 63 hoặc 54 số)." "WARN"
        return $false
    }
    
    Write-Log ">>> BẮT ĐẦU YÊU CẦU GET CID TỰ ĐỘNG CHO IID: $iid" "INFO"
    Write-Log "Đang liên hệ hệ thống Web API..." "INFO"
    [System.Windows.Forms.Application]::DoEvents()
    
    $endpoints = @(
        @{ Name = "KhoaToanTin CIDMS"; Url = "https://khoatoantin.com/ajax/cidms_api?iids=$iid&username=trogiup24h&password=PHO" },
        @{ Name = "GetCID.vn"; Url = "https://getcid.vn/api?iid=$iid" },
        @{ Name = "GetCID.info"; Url = "https://getcid.info/api/cid?iid=$iid" }
    )
    
    $cid = $null
    foreach ($ep in $endpoints) {
        try {
            Write-Log "Thử máy chủ: $($ep.Name)..." "INFO"
            $res = Invoke-RestMethod -Uri $ep.Url -Method Get -TimeoutSec 10 -ErrorAction Stop
            $raw = "$res"
            if ($res.cid) { $raw = "$($res.cid)" }
            $clean = $raw -replace '\D', ''
            if ($clean.Length -eq 48) {
                $cid = $clean
                Write-Log "=> Nhận CID thành công từ $($ep.Name)!" "CLEAN"
                break
            }
        } catch {
            Write-Log "  - Máy chủ $($ep.Name) không phản hồi hoặc yêu cầu xác thực riêng." "WARN"
        }
    }
    
    if ($cid -and $cid.Length -eq 48) {
        $txtCID.Text = $cid
        Update-PhoneValidationUI
        Write-Log "CID (48 số): $cid" "CLEAN"
        $grouped = Format-CIDGrouped $cid
        Write-Log "Dạng khối A-H: $grouped" "INFO"
        return $true
    } else {
        Write-Log "Các Web API tự động đang yêu cầu captcha hoặc bảo vệ Cloudflare." "WARN"
        Write-Log "-> ĐÃ TỰ ĐỘNG SAO CHÉP IID VÀO CLIPBOARD: $iid" "CLEAN"
        Write-Log "GỢI Ý: Bấm nút 'Mở Web Get CID' để mở web lấy CID và ấn Ctrl+V, hoặc dùng 'Trợ Lý Hotline'!" "INFO"
        return $false
    }
}

function Invoke-1ClickFullAutoPhone {
    $txtLog.Text = ""
    $targetName = if ($rbTargetWin.Checked) { "Windows" } else { "Microsoft Office" }
    Write-Log "=== BẮT ĐẦU QUY TRÌNH AUTO ACTIVE BY PHONE 1-CLICK: $targetName ===" "INFO"
    
    # 1. Lấy IID
    Get-TargetIID
    $iid = $txtIID.Text.Trim() -replace '\D', ''
    if (-not ($iid.Length -eq 63 -or $iid.Length -eq 54)) {
        Write-Log "Không lấy được IID hợp lệ. Hãy kiểm tra xem bạn đã nạp Key Phone chưa!" "CRIT"
        return
    }
    
    # 2. Lấy CID tự động
    $ok = Invoke-AutoGetCIDFromIID
    if ($ok -and $txtCID.Text.Trim().Length -eq 48) {
        # 3. Nạp CID
        Install-TargetCID
    } else {
        # Mở Web lấy CID tự động nếu API thất bại
        Open-SpecificWebCID "https://getcid.vn" "GetCID.vn"
    }
}

function Invoke-AutoWinPhone {
    $rbTargetWin.Checked = $true
    Invoke-1ClickFullAutoPhone
}

function Invoke-AutoOfficePhone {
    $rbTargetOffice.Checked = $true
    Invoke-1ClickFullAutoPhone
}

function Invoke-AutoGetCID {
    Invoke-AutoGetCIDFromIID
}

function Save-PhoneActivationBackup {
    $targetName = if ($rbTargetWin.Checked) { "Windows" } else { "Microsoft Office" }
    $iid = $txtIID.Text.Trim()
    $cid = $txtCID.Text.Trim()
    
    if (-not $iid -and -not $cid) {
        Write-Log "Chưa có thông tin IID hoặc CID để sao lưu!" "WARN"
        [System.Windows.Forms.MessageBox]::Show("Chưa có thông tin IID hoặc CID để sao lưu!", "Thông báo", 0, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    
    $desktop = [Environment]::GetFolderPath("Desktop")
    $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $fileName = "BKC_Phone_Lic_$($targetName -replace '\s','_')_$timestamp.txt"
    $filePath = Join-Path $desktop $fileName
    
    $groupedIID = Format-IIDGrouped $iid
    $groupedCID = Format-CIDGrouped $cid
    
    $content = @"
================================================================================
           BKC LIC - THÔNG TIN SAO LƯU BẢN QUYỀN BY PHONE
================================================================================
Thời gian sao lưu : $((Get-Date).ToString("dd/MM/yyyy HH:mm:ss"))
Đối tượng         : $targetName
Máy tính (Host)   : $env:COMPUTERNAME
Người dùng        : $env:USERNAME

--- THÔNG TIN CHI TIẾT ---
Installation ID (IID - Thô)  : $iid
Installation ID (Dạng khối)   : $groupedIID

Confirmation ID (CID - Thô)  : $cid
Confirmation ID (Dạng khối)   : $groupedCID

--- HƯỚNG DẪN TÁI SỬ DỤNG ---
Khi cài đặt lại hệ điều hành hoặc Office trên máy này:
1. Nạp lại đúng Product Key tương ứng.
2. Nạp lại Confirmation ID (CID) ở trên bằng công cụ BKC Lic hoặc lệnh:
   - Windows: slmgr.vbs /atp $cid
   - Office : ospp.vbs /actcid:$cid
Bản quyền sẽ được kích hoạt lại ngay lập tức mà không cần gọi điện thoại nữa!
================================================================================
Phát triển bởi: Trần Hà (BKC) - lic.bachkhoapc.vn
================================================================================
"@

    try {
        [System.IO.File]::WriteAllText($filePath, $content, [System.Text.Encoding]::UTF8)
        Write-Log "ĐÃ SAO LƯU THÀNH CÔNG VÀO DESKTOP:" "CLEAN"
        Write-Log "  -> $filePath" "CLEAN"
        [System.Diagnostics.Process]::Start("notepad.exe", "`"$filePath`"") | Out-Null
    } catch {
        Write-Log "Lỗi ghi file sao lưu: $($_.Exception.Message)" "CRIT"
    }
}

function Show-QuickKeyDialog {
    $targetName = if ($rbTargetWin.Checked) { "Windows" } else { "Microsoft Office" }
    
    $formKey = New-Object System.Windows.Forms.Form
    $formKey.Text = "Nạp Key Phone Cho $targetName"
    $formKey.Size = New-Object System.Drawing.Size(460, 200)
    $formKey.StartPosition = "CenterParent"
    $formKey.FormBorderStyle = "FixedDialog"
    $formKey.MaximizeBox = $false
    $formKey.MinimizeBox = $false
    $formKey.BackColor = [System.Drawing.Color]::FromArgb(245, 246, 250)
    
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Nhập Product Key 25 ký tự (XXXXX-XXXXX-...):"
    $lbl.Location = New-Object System.Drawing.Point(20, 20)
    $lbl.AutoSize = $true
    $lbl.Font = $fontNormal
    $formKey.Controls.Add($lbl)
    
    $txtInput = New-Object System.Windows.Forms.TextBox
    $txtInput.Location = New-Object System.Drawing.Point(20, 50)
    $txtInput.Size = New-Object System.Drawing.Size(400, 28)
    $txtInput.Font = $fontCode
    $txtInput.CharacterCasing = "Upper"
    $formKey.Controls.Add($txtInput)
    
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "Nạp Key Ngay"
    $btnOk.Location = New-Object System.Drawing.Point(140, 100)
    $btnOk.Size = New-Object System.Drawing.Size(160, 36)
    $btnOk.BackColor = [System.Drawing.Color]::FromArgb(0, 150, 136)
    $btnOk.ForeColor = [System.Drawing.Color]::White
    $btnOk.FlatStyle = "Flat"
    $btnOk.Cursor = "Hand"
    $btnOk.Font = $fontBtn
    $btnOk.Add_Click({
        $k = $txtInput.Text.Trim()
        if (Validate-Key $k) {
            $formKey.Close()
            $txtKey.Text = $k
            Write-Log "Đang nạp Key cho $($targetName): $k..." "INFO"
            if ($rbTargetWin.Checked) {
                Invoke-CScript "$env:SystemRoot\System32\slmgr.vbs" "/ipk $k" | Out-Null
                Write-Log "Đã nạp Key Windows thành công. Hãy bấm 'Lấy IID'!" "CLEAN"
            } else {
                $ospp = Get-OsppPath
                if ($ospp) {
                    Invoke-CScript $ospp "/inpkey:$k" | Out-Null
                    Write-Log "Đã nạp Key Office thành công. Hãy bấm 'Lấy IID'!" "CLEAN"
                } else {
                    Write-Log "Không tìm thấy OSPP. Office chưa cài đặt." "WARN"
                }
            }
            Get-TargetIID
        } else {
            [System.Windows.Forms.MessageBox]::Show("Product Key không hợp lệ! Vui lòng nhập đúng định dạng 25 ký tự XXXXX-XXXXX-XXXXX-XXXXX-XXXXX.", "Lỗi Định Dạng", 0, [System.Windows.Forms.MessageBoxIcon]::Warning)
        }
    })
    $formKey.Controls.Add($btnOk)
    
    $formKey.ShowDialog() | Out-Null
}

function Show-CallCenterAssistantDialog {
    $targetName = if ($rbTargetWin.Checked) { "Windows" } else { "Microsoft Office" }
    
    # Đảm bảo có IID
    $cleanIID = if ($txtIID.Text) { $txtIID.Text.Trim() -replace '\D', '' } else { "" }
    if (-not $cleanIID) {
        Get-TargetIID
        $cleanIID = if ($txtIID.Text) { $txtIID.Text.Trim() -replace '\D', '' } else { "" }
    }
    
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Trợ Lý Kích Hoạt By Phone - Tổng Đài Microsoft: 1800 400 470"
    $dlg.Size = New-Object System.Drawing.Size(860, 560)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.BackColor = [System.Drawing.Color]::FromArgb(245, 246, 250)
    $dlg.Font = $fontNormal

    # Header Panel
    $pnlHeader = New-Object System.Windows.Forms.Panel
    $pnlHeader.Location = New-Object System.Drawing.Point(0, 0)
    $pnlHeader.Size = New-Object System.Drawing.Size(860, 68)
    $pnlHeader.BackColor = [System.Drawing.Color]::FromArgb(26, 35, 126)
    $dlg.Controls.Add($pnlHeader)

    $lblDlgTitle = New-Object System.Windows.Forms.Label
    $lblDlgTitle.Text = "TRỢ LÝ GỌI TỔNG ĐÀI MICROSOFT VIỆT NAM (1800 400 470)"
    $lblDlgTitle.Font = New-Object System.Drawing.Font("Segoe UI", 11.5, [System.Drawing.FontStyle]::Bold)
    $lblDlgTitle.ForeColor = [System.Drawing.Color]::White
    $lblDlgTitle.Location = New-Object System.Drawing.Point(18, 10)
    $lblDlgTitle.Size = New-Object System.Drawing.Size(820, 24)
    $pnlHeader.Controls.Add($lblDlgTitle)

    $lblDlgSub = New-Object System.Windows.Forms.Label
    $lblDlgSub.Text = "Hotline MIỄN PHÍ CƯỚC 100% (24/7)  •  Bấm 1 (Tiếng Việt) -> Bấm 1 (Cá nhân) -> Đọc 9 nhóm IID -> Ghi nhận 8 khối CID"
    $lblDlgSub.Font = $fontSmall
    $lblDlgSub.ForeColor = [System.Drawing.Color]::FromArgb(200, 215, 255)
    $lblDlgSub.UseMnemonic = $false
    $lblDlgSub.Location = New-Object System.Drawing.Point(18, 36)
    $lblDlgSub.Size = New-Object System.Drawing.Size(820, 22)
    $pnlHeader.Controls.Add($lblDlgSub)

    # --- KHUNG BƯỚC 1: HIỂN THỊ 9 NHÓM SỐ IID ---
    $grpIID = New-Object System.Windows.Forms.GroupBox
    $grpIID.Text = " BƯỚC 1: ĐỌC 9 NHÓM SỐ INSTALLATION ID (IID) CHO TỔNG ĐÀI (BẤM TRÊN BÀN PHÍM ĐIỆN THOẠI) "
    $grpIID.Font = $fontSection
    $grpIID.ForeColor = [System.Drawing.Color]::FromArgb(21, 101, 192)
    $grpIID.Location = New-Object System.Drawing.Point(15, 78)
    $grpIID.Size = New-Object System.Drawing.Size(815, 125)
    $dlg.Controls.Add($grpIID)

    # 9 nhóm IID
    $iidGroups = @()
    if ($cleanIID.Length -eq 63) {
        for ($i = 0; $i -lt 63; $i += 7) { $iidGroups += $cleanIID.Substring($i, 7) }
    } elseif ($cleanIID.Length -eq 54) {
        for ($i = 0; $i -lt 54; $i += 6) { $iidGroups += $cleanIID.Substring($i, 6) }
    }
    
    $boxWidth = 78
    $boxGap = 9
    $startX = 18
    for ($i = 0; $i -lt 9; $i++) {
        $x = $startX + ($i * ($boxWidth + $boxGap))
        
        $lblG = New-Object System.Windows.Forms.Label
        $lblG.Text = "Nhóm $($i + 1)"
        $lblG.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
        $lblG.ForeColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
        $lblG.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $lblG.Location = New-Object System.Drawing.Point($x, 26)
        $lblG.Size = New-Object System.Drawing.Size($boxWidth, 18)
        $grpIID.Controls.Add($lblG)

        $txtG = New-Object System.Windows.Forms.TextBox
        $txtG.ReadOnly = $true
        $txtG.BackColor = [System.Drawing.Color]::FromArgb(240, 247, 255)
        $txtG.ForeColor = [System.Drawing.Color]::FromArgb(13, 71, 161)
        $txtG.Font = New-Object System.Drawing.Font("Consolas", 11, [System.Drawing.FontStyle]::Bold)
        $txtG.TextAlign = [System.Windows.Forms.HorizontalAlignment]::Center
        $txtG.Location = New-Object System.Drawing.Point($x, 48)
        $txtG.Size = New-Object System.Drawing.Size($boxWidth, 26)
        $txtG.Text = if ($i -lt $iidGroups.Count) { $iidGroups[$i] } else { "-------" }
        $grpIID.Controls.Add($txtG)
    }

    $lblIIDHelp = New-Object System.Windows.Forms.Label
    $lblIIDHelp.Text = "Mẹo: Tổng đài hỏi số máy tính muốn cài -> Bấm 1. Khi tổng đài yêu cầu nhập nhóm 1, bấm 7 số trên phím thoại rồi chờ..."
    $lblIIDHelp.Font = $fontSmall
    $lblIIDHelp.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
    $lblIIDHelp.Location = New-Object System.Drawing.Point(18, 86)
    $lblIIDHelp.Size = New-Object System.Drawing.Size(780, 24)
    $grpIID.Controls.Add($lblIIDHelp)

    # --- KHUNG BƯỚC 2: NHẬP 8 KHỐI CID ---
    $grpCID = New-Object System.Windows.Forms.GroupBox
    $grpCID.Text = " BƯỚC 2: NHẬP 8 KHỐI CONFIRMATION ID (CID) TỪ TỔNG ĐÀI ĐỌC (TỰ ĐỘNG CHUYỂN Ô) "
    $grpCID.Font = $fontSection
    $grpCID.ForeColor = [System.Drawing.Color]::FromArgb(46, 125, 50)
    $grpCID.Location = New-Object System.Drawing.Point(15, 215)
    $grpCID.Size = New-Object System.Drawing.Size(815, 175)
    $dlg.Controls.Add($grpCID)

    $cidLetters = @('A','B','C','D','E','F','G','H')
    $cidBoxes = @()
    $cidBoxWidth = 86
    $cidBoxGap = 12
    $cidStartX = 20

    # Lấy dữ liệu CID hiện tại nếu có
    $existingCID = if ($txtCID.Text) { $txtCID.Text.Trim() -replace '\D', '' } else { "" }

    for ($i = 0; $i -lt 8; $i++) {
        $x = $cidStartX + ($i * ($cidBoxWidth + $cidBoxGap))

        $lblC = New-Object System.Windows.Forms.Label
        $lblC.Text = "Khối [$($cidLetters[$i])]"
        $lblC.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $lblC.ForeColor = [System.Drawing.Color]::FromArgb(46, 125, 50)
        $lblC.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $lblC.Location = New-Object System.Drawing.Point($x, 26)
        $lblC.Size = New-Object System.Drawing.Size($cidBoxWidth, 20)
        $grpCID.Controls.Add($lblC)

        $txtC = New-Object System.Windows.Forms.TextBox
        $txtC.Font = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Bold)
        $txtC.TextAlign = [System.Windows.Forms.HorizontalAlignment]::Center
        $txtC.Location = New-Object System.Drawing.Point($x, 50)
        $txtC.Size = New-Object System.Drawing.Size($cidBoxWidth, 28)
        $txtC.MaxLength = 6
        $txtC.Tag = $i
        if ($existingCID.Length -ge (($i + 1) * 6)) {
            $txtC.Text = $existingCID.Substring($i * 6, 6)
        }
        $grpCID.Controls.Add($txtC)
        $cidBoxes += $txtC
    }

    # Gán sự kiện tự động chuyển ô cho 8 ô CID
    for ($i = 0; $i -lt 8; $i++) {
        $box = $cidBoxes[$i]
        $box.Add_TextChanged({
            param($s, $e)
            $clean = $s.Text -replace '\D', ''
            if ($s.Text -ne $clean) {
                $pos = $s.SelectionStart
                $s.Text = $clean
                $s.SelectionStart = [Math]::Min($pos, $s.Text.Length)
            }
            if ($clean.Length -ge 6) {
                $idx = [int]$s.Tag
                if ($idx -lt 7) {
                    $cidBoxes[$idx + 1].Focus()
                    $cidBoxes[$idx + 1].SelectAll()
                }
            }
            # Cập nhật số lượng
            $tot = 0
            foreach ($b in $cidBoxes) { $tot += ($b.Text -replace '\D', '').Length }
            if ($tot -eq 48) {
                $lblCidStatus.Text = "[HỢP LỆ: ĐÃ ĐỦ 48/48 SỐ (8 KHỐI A-H)]"
                $lblCidStatus.ForeColor = [System.Drawing.Color]::FromArgb(46, 125, 50)
            } else {
                $lblCidStatus.Text = "Đã nhập: $tot/48 số (Cần đủ 6 số cho mỗi khối)"
                $lblCidStatus.ForeColor = [System.Drawing.Color]::FromArgb(230, 81, 0)
            }
        })
        $box.Add_KeyDown({
            param($s, $e)
            if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Back -and $s.Text.Length -eq 0) {
                $idx = [int]$s.Tag
                if ($idx -gt 0) {
                    $cidBoxes[$idx - 1].Focus()
                    $cidBoxes[$idx - 1].SelectionStart = $cidBoxes[$idx - 1].Text.Length
                }
            }
        })
    }

    # Thanh công cụ bên dưới khối CID
    $btnPasteAllCID = New-Object System.Windows.Forms.Button
    $btnPasteAllCID.Text = "Dán Chuỗi 48 Số (Paste All)"
    $btnPasteAllCID.Font = $fontSmall
    $btnPasteAllCID.Location = New-Object System.Drawing.Point(20, 92)
    $btnPasteAllCID.Size = New-Object System.Drawing.Size(190, 30)
    $btnPasteAllCID.BackColor = [System.Drawing.Color]::White
    $btnPasteAllCID.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnPasteAllCID.Add_Click({
        if ([System.Windows.Forms.Clipboard]::ContainsText()) {
            $raw = [System.Windows.Forms.Clipboard]::GetText() -replace '\D', ''
            if ($raw.Length -ge 48) {
                for ($j = 0; $j -lt 8; $j++) {
                    $cidBoxes[$j].Text = $raw.Substring($j * 6, 6)
                }
            } else {
                [System.Windows.Forms.MessageBox]::Show("Clipboard không đủ 48 số CID (chỉ có $($raw.Length) số).", "Thông báo", 0, [System.Windows.Forms.MessageBoxIcon]::Warning)
            }
        }
    })
    $grpCID.Controls.Add($btnPasteAllCID)

    $btnClear8Boxes = New-Object System.Windows.Forms.Button
    $btnClear8Boxes.Text = "Xóa Trắng 8 Khối"
    $btnClear8Boxes.Font = $fontSmall
    $btnClear8Boxes.Location = New-Object System.Drawing.Point(220, 92)
    $btnClear8Boxes.Size = New-Object System.Drawing.Size(130, 30)
    $btnClear8Boxes.BackColor = [System.Drawing.Color]::White
    $btnClear8Boxes.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnClear8Boxes.Add_Click({
        foreach ($b in $cidBoxes) { $b.Text = "" }
        $cidBoxes[0].Focus()
    })
    $grpCID.Controls.Add($btnClear8Boxes)

    $lblCidStatus = New-Object System.Windows.Forms.Label
    $lblCidStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $lblCidStatus.Location = New-Object System.Drawing.Point(365, 96)
    $lblCidStatus.Size = New-Object System.Drawing.Size(430, 24)
    $lblCidStatus.ForeColor = [System.Drawing.Color]::FromArgb(120, 144, 156)
    $lblCidStatus.Text = "Chưa có CID. Nhập các số tổng đài đọc theo từng khối từ A đến H."
    $grpCID.Controls.Add($lblCidStatus)

    $lblCIDNote = New-Object System.Windows.Forms.Label
    $lblCIDNote.Text = "Lưu ý: Bàn phím tự động chuyển sang khối tiếp theo ngay khi gõ đủ 6 số. Bấm Backspace khi ô trống để lùi về ô trước."
    $lblCIDNote.Font = $fontSmall
    $lblCIDNote.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
    $lblCIDNote.Location = New-Object System.Drawing.Point(20, 134)
    $lblCIDNote.Size = New-Object System.Drawing.Size(775, 26)
    $grpCID.Controls.Add($lblCIDNote)

    # --- KHUNG NÚT BẤM DƯỚI CÙNG ---
    $pnlBottom = New-Object System.Windows.Forms.Panel
    $pnlBottom.Location = New-Object System.Drawing.Point(15, 405)
    $pnlBottom.Size = New-Object System.Drawing.Size(815, 95)
    $dlg.Controls.Add($pnlBottom)

    $btnApplyAndInstall = New-Object System.Windows.Forms.Button
    $btnApplyAndInstall.Text = "GỘP & NẠP CID KÍCH HOẠT NGAY"
    $btnApplyAndInstall.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $btnApplyAndInstall.ForeColor = [System.Drawing.Color]::White
    $btnApplyAndInstall.BackColor = [System.Drawing.Color]::FromArgb(46, 125, 50)
    $btnApplyAndInstall.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnApplyAndInstall.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnApplyAndInstall.Location = New-Object System.Drawing.Point(10, 8)
    $btnApplyAndInstall.Size = New-Object System.Drawing.Size(370, 44)
    $btnApplyAndInstall.Add_Click({
        $fullCID = ""
        foreach ($b in $cidBoxes) { $fullCID += ($b.Text.Trim() -replace '\D', '') }
        if ($fullCID.Length -eq 48) {
            $txtCID.Text = $fullCID
            Update-PhoneValidationUI
            $dlg.Close()
            Toggle-Buttons $false
            Install-TargetCID
            Toggle-Buttons $true
        } else {
            [System.Windows.Forms.MessageBox]::Show("CID chưa đủ 48 số (hiện có $($fullCID.Length) số)! Vui lòng kiểm tra lại 8 khối A đến H.", "Chưa Đủ Số CID", 0, [System.Windows.Forms.MessageBoxIcon]::Warning)
        }
    })
    $pnlBottom.Controls.Add($btnApplyAndInstall)

    $btnCopyJoinedCID = New-Object System.Windows.Forms.Button
    $btnCopyJoinedCID.Text = "Copy Chuỗi 48 Số"
    $btnCopyJoinedCID.Font = $fontBtn
    $btnCopyJoinedCID.ForeColor = [System.Drawing.Color]::White
    $btnCopyJoinedCID.BackColor = [System.Drawing.Color]::FromArgb(25, 118, 210)
    $btnCopyJoinedCID.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnCopyJoinedCID.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnCopyJoinedCID.Location = New-Object System.Drawing.Point(395, 8)
    $btnCopyJoinedCID.Size = New-Object System.Drawing.Size(180, 44)
    $btnCopyJoinedCID.Add_Click({
        $fullCID = ""
        foreach ($b in $cidBoxes) { $fullCID += ($b.Text.Trim() -replace '\D', '') }
        if ($fullCID.Length -gt 0) {
            [System.Windows.Forms.Clipboard]::SetText($fullCID)
            Write-Log "Đã copy chuỗi CID ($($fullCID.Length) số) vào Clipboard." "CLEAN"
            [System.Windows.Forms.MessageBox]::Show("Đã copy chuỗi CID ($($fullCID.Length) số) vào Clipboard!", "Đã Copy", 0, [System.Windows.Forms.MessageBoxIcon]::Information)
        }
    })
    $pnlBottom.Controls.Add($btnCopyJoinedCID)

    $btnCloseDlg = New-Object System.Windows.Forms.Button
    $btnCloseDlg.Text = "Đóng"
    $btnCloseDlg.Font = $fontBtn
    $btnCloseDlg.ForeColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $btnCloseDlg.BackColor = [System.Drawing.Color]::FromArgb(238, 238, 238)
    $btnCloseDlg.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnCloseDlg.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnCloseDlg.Location = New-Object System.Drawing.Point(685, 8)
    $btnCloseDlg.Size = New-Object System.Drawing.Size(120, 44)
    $btnCloseDlg.Add_Click({ $dlg.Close() })
    $pnlBottom.Controls.Add($btnCloseDlg)

    $lblBottomHelp = New-Object System.Windows.Forms.Label
    $lblBottomHelp.Text = "Sau khi kích hoạt thành công, hãy bấm 'Lưu Key & CID Ra Desktop' trên giao diện chính để lưu bản quyền vĩnh viễn!"
    $lblBottomHelp.Font = $fontSmall
    $lblBottomHelp.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
    $lblBottomHelp.Location = New-Object System.Drawing.Point(10, 60)
    $lblBottomHelp.Size = New-Object System.Drawing.Size(790, 24)
    $pnlBottom.Controls.Add($lblBottomHelp)

    # Hiển thị ban đầu
    $initCount = 0
    foreach ($b in $cidBoxes) { $initCount += ($b.Text -replace '\D', '').Length }
    if ($initCount -eq 48) {
        $lblCidStatus.Text = "[HỢP LỆ: ĐÃ ĐỦ 48/48 SỐ (8 KHỐI A-H)]"
        $lblCidStatus.ForeColor = [System.Drawing.Color]::FromArgb(46, 125, 50)
    }

    $dlg.ShowDialog() | Out-Null
}


function Invoke-DeepScan {
    $txtLog.Text = ""; Write-Log ">>> KHỞI ĐỘNG TRÌNH QUÉT BẢO MẬT DẤU VẾT CRACK..." "INFO"; $isCrack = $false
    $badSvc = @("AutoKMS", "KMSELDI", "SppExtComObjHook", "SECOH-QAD", "KMS-R@1n")
    $foundSvcs = Get-Service -Name $badSvc -ErrorAction SilentlyContinue
    if ($foundSvcs) { foreach ($s in $foundSvcs) { Write-Log "Phát hiện Service Crack: $($s.Name)" "CRIT" }; $isCrack = $true }
    $tasks = Get-ScheduledTask -TaskName "AutoKMS*", "KMSAuto*", "SppExtComObjHook*" -ErrorAction SilentlyContinue
    if ($tasks) { foreach ($t in $tasks) { Write-Log "Phát hiện Task Crack: $($t.TaskName)" "CRIT" }; $isCrack = $true }
    $reg = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\Software Protection Platform"
    try { if ((Get-ItemProperty $reg -Name "NoGenTicket" -ErrorAction Stop).NoGenTicket -eq 1) { Write-Log "Registry NoGenTicket = 1 (Chặn kích hoạt)." "CRIT"; $isCrack = $true } } catch {}
    $port = Get-NetTCPConnection -LocalPort 1688 -State Listen -ErrorAction SilentlyContinue
    if ($port) { Write-Log "Cổng mạng KMS ảo 1688 đang mở." "CRIT"; $isCrack = $true }
    if (-not $isCrack) { Write-Log "HỆ THỐNG SẠCH: Không phát hiện Crack!" "CLEAN" }
}

function Invoke-FixHosts {
    $txtLog.Text = ""; Write-Log ">>> ĐANG KIỂM TRA FILE HOSTS..." "INFO"
    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
    if (Test-Path $hostsPath) {
        $lines = Get-Content $hostsPath
        $msDomainPatterns = @("activation\.sls\.microsoft\.com","kms\.core\.windows\.net","displaycatalog\.mp\.microsoft\.com","licensing\.mp\.microsoft\.com","go\.microsoft\.com","sls\.microsoft\.com")
        $blockedLines = @(); $cleanLines = @()
        foreach ($line in $lines) {
            $isBlocked = $false
            foreach ($pattern in $msDomainPatterns) { if ($line -match $pattern -and $line -notmatch "^\s*#") { $isBlocked = $true; $blockedLines += $line; break } }
            if (-not $isBlocked) { $cleanLines += $line }
        }
        if ($blockedLines.Count -gt 0) {
            foreach ($b in $blockedLines) { Write-Log "[CHẶN] $b" "WARN" }
            try { Set-Content -Path $hostsPath -Value $cleanLines -Force; Write-Log "Đã xóa các dòng chặn khỏi file hosts!" "CLEAN" }
            catch { Write-Log "Không thể lưu file hosts." "CRIT" }
        } else { Write-Log "File hosts SẠCH." "CLEAN" }
    } else { Write-Log "Không tìm thấy file hosts." "WARN" }
}

function Restart-LicensingServices {
    $txtLog.Text = ""; Write-Log ">>> ĐANG KHỞI ĐỘNG LẠI DỊCH VỤ BẢN QUYỀN..." "INFO"
    try { Stop-Service "sppsvc" -Force -ErrorAction SilentlyContinue; Start-Sleep -Ms 400; Start-Service "sppsvc" -ErrorAction Stop; Write-Log "Dịch vụ sppsvc đã restart." "CLEAN" } catch {}
    try { if (Get-Service "osppsvc" -ErrorAction SilentlyContinue) { Stop-Service "osppsvc" -Force -ErrorAction SilentlyContinue; Start-Sleep -Ms 400; Start-Service "osppsvc" -ErrorAction Stop; Write-Log "Dịch vụ osppsvc đã restart." "CLEAN" } } catch {}
    Write-Log "Hoàn tất khởi động lại dịch vụ!" "CLEAN"
}

function Invoke-ForceRemoveOffice {
    $txtLog.Text = ""
    $msg = "Bạn có CHẮC CHẮN muốn gỡ cài đặt và xóa tận gốc Microsoft Office không?`n`n" +
           "Quy trình gỡ thông minh (Smart Uninstall) sẽ được áp dụng:`n" +
           "1. Cố gắng chạy trình gỡ cài đặt chuẩn của Windows trước.`n" +
           "2. Quét sâu và xóa sổ mọi file, thư mục, Registry còn sót lại.`n`n" +
           "LƯU Ý QUAN TRỌNG: Quá trình quét sâu có thể XÓA MẤT CÁC PROFILE OUTLOOK CŨ và dữ liệu cấu hình ứng dụng nếu bạn chưa sao lưu. Hãy đảm bảo bạn đã Backup dữ liệu Outlook (file PST/OST) trước khi tiếp tục."
    $confirm = [System.Windows.Forms.MessageBox]::Show($msg, "CẢNH BÁO: Xóa tận gốc Office & Dữ liệu", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($confirm -ne 'Yes') { Write-Log "Đã hủy thao tác xóa tận gốc Office." "INFO"; return }

    Write-Log ">>> ĐANG KHỞI ĐỘNG TIẾN TRÌNH SMART UNINSTALL OFFICE..." "INFO"
    
    # Bước 1: Gỡ chuẩn
    Write-Log "Đang tìm kiếm trình gỡ cài đặt chuẩn của Office trong hệ thống..." "INFO"
    $uninstallPaths = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall")
    $foundUninstaller = $false
    foreach ($up in $uninstallPaths) {
        $officeKeys = Get-ChildItem -Path $up -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "O365" -or $_.Name -match "Office" -or $_.Name -match "ClickToRun" -or $_.Name -match "ProPlus" }
        foreach ($key in $officeKeys) {
            $uninstallString = (Get-ItemProperty -Path $key.PSPath -Name "UninstallString" -ErrorAction SilentlyContinue).UninstallString
            if ($uninstallString) {
                Write-Log "Đã tìm thấy trình gỡ cài đặt gốc. Đang khởi chạy..." "CLEAN"
                Write-Log "Vui lòng làm theo các bước trên màn hình (nếu có) để gỡ Office..." "INFO"
                $foundUninstaller = $true
                try {
                    $proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c ""$uninstallString""" -Wait -PassThru -WindowStyle Hidden
                    Write-Log "Trình gỡ cài đặt gốc đã hoàn tất." "CLEAN"
                } catch {
                    Write-Log "Lỗi khi chạy trình gỡ gốc, tự động chuyển sang chế độ Force Remove..." "WARN"
                }
                break
            }
        }
        if ($foundUninstaller) { break }
    }
    if (-not $foundUninstaller) { Write-Log "Không tìm thấy trình gỡ chuẩn, tiến hành dọn dẹp sâu..." "WARN" }

    # Bước 2: Dừng dịch vụ & tiến trình
    Write-Log "Đang dừng các dịch vụ nền của Office..." "INFO"
    Stop-Service -Name "ClickToRunSvc" -Force -ErrorAction SilentlyContinue
    Stop-Service -Name "osppsvc" -Force -ErrorAction SilentlyContinue
    
    Write-Log "Đang ép đóng các tiến trình Office đang chạy..." "INFO"
    $procs = @("winword", "excel", "powerpnt", "outlook", "msaccess", "onenote", "mspub", "lync", "OfficeClickToRun", "OfficeC2RClient")
    foreach ($p in $procs) { Stop-Process -Name $p -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2

    # Bước 3: Xóa thư mục
    Write-Log "Đang dọn dẹp thư mục cài đặt Office (Bao gồm C2R, MSI, Repack)..." "INFO"
    $folders = @(
        "$env:ProgramFiles\Microsoft Office", 
        "${env:ProgramFiles(x86)}\Microsoft Office", 
        "$env:ProgramFiles\Common Files\Microsoft Shared\ClickToRun", 
        "$env:ProgramFiles\Common Files\Microsoft Shared\OFFICE14",
        "$env:ProgramFiles\Common Files\Microsoft Shared\OFFICE15",
        "$env:ProgramFiles\Common Files\Microsoft Shared\OFFICE16",
        "$env:ProgramData\Microsoft\ClickToRun",
        "$env:ProgramData\Microsoft\Office"
    )
    foreach ($f in $folders) { if (Test-Path $f) { Remove-Item -Path $f -Recurse -Force -ErrorAction SilentlyContinue } }

    # Bước 4: Xóa Registry
    Write-Log "Đang quét sâu và dọn dẹp Registry của Office (2010-365)..." "INFO"
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Office",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office",
        "HKLM:\SOFTWARE\Microsoft\AppVISV",
        "HKCU:\Software\Microsoft\Office"
    )
    foreach ($r in $regPaths) { if (Test-Path $r) { Remove-Item -Path $r -Recurse -Force -ErrorAction SilentlyContinue } }

    # Bước 5: Gỡ UI Control Panel
    Write-Log "Đang gỡ tàn dư thông tin cài đặt khỏi Control Panel..." "INFO"
    foreach ($up in $uninstallPaths) {
        Get-ChildItem -Path $up -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "O365" -or $_.Name -match "Office" -or $_.Name -match "ClickToRun" -or $_.Name -match "ProPlus" } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    Write-Log "HOÀN TẤT: Đã gỡ bỏ tận gốc toàn bộ tàn dư Office trên hệ thống!" "CLEAN"
}

function Invoke-ResetWU {
    $txtLog.Text = ""; Write-Log "Đang làm sạch và Reset Windows Update..." "INFO"
    Stop-Service wuauserv, cryptSvc, bits, msiserver -Force -ErrorAction SilentlyContinue
    Rename-Item -Path "$env:windir\SoftwareDistribution" -NewName "SoftwareDistribution.old" -ErrorAction SilentlyContinue
    Rename-Item -Path "$env:windir\System32\catroot2" -NewName "catroot2.old" -ErrorAction SilentlyContinue
    Start-Service wuauserv, cryptSvc, bits, msiserver -ErrorAction SilentlyContinue
    Write-Log "Đã Reset Windows Update thành công!" "CLEAN"
}

function Invoke-SystemRepair {
    $txtLog.Text = ""; Write-Log "Đang chạy quét lỗi hệ thống SFC và DISM (Sẽ mất nhiều thời gian)..." "INFO"
    Write-Log "Vui lòng xem tiến trình trên cửa sổ CMD vừa hiện..." "INFO"
    $cmd = "cmd.exe /c echo Dang chay SFC... && sfc /scannow && echo Dang chay DISM... && dism /online /cleanup-image /restorehealth"
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c $cmd" -Wait
    Write-Log "Hoàn tất quét và sửa lỗi file hệ thống!" "CLEAN"
}

function Invoke-RegisterLicDLLs {
    $txtLog.Text = ""; Write-Log "Đang đăng ký lại thư viện cấp phép (Licensing DLLs)..." "INFO"
    $dlls = "slc.dll", "slcext.dll", "sppwmi.dll", "sppsvc.exe"
    foreach ($dll in $dlls) {
        Start-Process "regsvr32.exe" -ArgumentList "/s $dll" -Wait -WindowStyle Hidden
    }
    Start-Process "mofcomp.exe" -ArgumentList "$env:windir\System32\wbem\sppWmi.mof" -Wait -WindowStyle Hidden
    Write-Log "Đăng ký lại Licensing DLLs và WMI thành công!" "CLEAN"
}

function Invoke-ResetNetwork {
    $txtLog.Text = ""; Write-Log "Đang khởi chạy tiến trình Reset Network & Firewall toàn diện..." "INFO"
    Write-Log "Quá trình này sẽ ngắt kết nối mạng trong vài giây..." "WARN"
    [System.Windows.Forms.Application]::DoEvents()
    
    $commands = @(
        "ipconfig /release",
        "ipconfig /flushdns",
        "ipconfig /registerdns",
        "arp -d *",
        "nbtstat -R",
        "nbtstat -RR",
        "netsh winsock reset",
        "netsh int ip reset",
        "netsh int tcp reset",
        "netsh interface ipv4 reset",
        "netsh interface ipv6 reset",
        "netsh winhttp reset proxy",
        "netsh advfirewall reset",
        "certutil -urlcache * delete",
        "ipconfig /renew"
    )
    
    foreach ($c in $commands) {
        Write-Log "Đang thực thi: $c" "INFO"
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c $c" -Wait -WindowStyle Hidden
    }
    
    Write-Log "Hoàn tất dọn dẹp, cấp mới IP, Reset Winsock, TCP/IP, Proxy và Firewall!" "CLEAN"
}

function Invoke-BackupTokens {
    if (-not $chkBackupTokens.Checked -and -not $chkBackupDrivers.Checked) {
        Write-Log "Chưa chọn thành phần nào để sao lưu!" "WARN"; return
    }
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Chọn thư mục lưu Backup"
    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $basePath = $dialog.SelectedPath
    if ($chkBackupTokens.Checked) {
        $backupPath = Join-Path $basePath "WinLic_Backup"; $sppPath = "$env:windir\System32\spp\store\2.0"
        Write-Log "Đang chuẩn bị sao lưu Bản Quyền (Tokens)..." "INFO"
        if (Test-Path $sppPath) {
            if (-not (Test-Path $backupPath)) { New-Item -ItemType Directory -Force -Path $backupPath | Out-Null }
            Stop-Service "sppsvc" -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 1
            try { Copy-Item -Path "$sppPath\*" -Destination $backupPath -Recurse -Force -ErrorAction Stop; Write-Log "  -> Sao lưu Bản quyền THÀNH CÔNG!" "CLEAN" } catch { Write-Log "  -> Lỗi: $($_.Exception.Message)" "CRIT" }
            Start-Service "sppsvc" -ErrorAction SilentlyContinue
        }
    }
    if ($chkBackupDrivers.Checked) {
        $driverPath = Join-Path $basePath "Drivers_Backup"
        Write-Log "Đang xuất Drivers (Có thể mất vài phút)..." "INFO"
        if (-not (Test-Path $driverPath)) { New-Item -ItemType Directory -Force -Path $driverPath | Out-Null }
        try { $d = Start-Process "dism.exe" "/online /export-driver /destination:`"$driverPath`"" -Wait -WindowStyle Hidden -PassThru; if ($d.ExitCode -eq 0) { Write-Log "  -> Sao lưu Drivers THÀNH CÔNG!" "CLEAN" } else { Write-Log "  -> Lỗi Backup Drivers" "CRIT" } } catch { Write-Log "  -> Lỗi: $($_.Exception.Message)" "CRIT" }
    }
    Write-Log "Hoàn tất tiến trình sao lưu!" "INFO"
}


function Invoke-RestoreTokens {
    if (-not $chkBackupTokens.Checked -and -not $chkBackupDrivers.Checked) {
        Write-Log "Chưa chọn thành phần để phục hồi!" "WARN"; return
    }
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Chọn thư mục GỐC chứa Backup"
    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $basePath = $dialog.SelectedPath
    $confirm = [System.Windows.Forms.MessageBox]::Show("Xác nhận GHI ĐÈ phục hồi?", "Xác Nhận", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($confirm -ne "Yes") { return }
    if ($chkBackupTokens.Checked) {
        $backupPath = Join-Path $basePath "WinLic_Backup"; $sppPath = "$env:windir\System32\spp\store\2.0"
        if (Test-Path $backupPath) {
            Write-Log "Đang PHỤC HỒI Bản Quyền..." "INFO"
            Stop-Service "sppsvc" -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2
            try { Start-Process "cmd.exe" "/c takeown /f `"$sppPath`" /r /d y && icacls `"$sppPath`" /grant administrators:F /t" -Wait -WindowStyle Hidden; Copy-Item -Path "$backupPath\*" -Destination $sppPath -Recurse -Force -ErrorAction Stop; Write-Log "  -> Phục hồi Tokens THÀNH CÔNG!" "CLEAN" } catch { Write-Log "  -> Lỗi: $($_.Exception.Message)" "CRIT" }
            Start-Service "sppsvc" -ErrorAction SilentlyContinue; Start-Sleep -Seconds 1; Invoke-CScript "$env:SystemRoot\System32\slmgr.vbs" "/ato" | Out-Null
        }
    }
    if ($chkBackupDrivers.Checked) {
        $driverPath = Join-Path $basePath "Drivers_Backup"
        if (Test-Path $driverPath) {
            Write-Log "Đang cài đặt lại Drivers (Có thể mất vài phút)..." "INFO"
            try { Start-Process "pnputil.exe" "/add-driver `"$driverPath\*.inf`" /subdirs /install" -Wait -WindowStyle Hidden; Write-Log "  -> Phục hồi Drivers HOÀN TẤT! Vui lòng Restart máy" "CLEAN" } catch { Write-Log "  -> Lỗi: $($_.Exception.Message)" "CRIT" }
        }
    }
    Write-Log "Hoàn tất phục hồi!" "INFO"
}


function Invoke-PIDChecker {
    $k = $txtPIDKey.Text.Trim()
    if (-not ($k -match "^[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}$")) {
        Write-Log "Định dạng Key kiểm tra không hợp lệ." "WARN"
        return
    }
    
    $txtLog.Text = ""
    Write-Log "Đang gửi yêu cầu kiểm tra Key (PID Checker) lên Web API..." "INFO"
    [System.Windows.Forms.Application]::DoEvents()
    
    try {
        $apiUrl = "https://pidkey.com/api/check?key=$k"
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get -TimeoutSec 15 -ErrorAction Stop
        
        Write-Log "==== KẾT QUẢ KIỂM TRA KEY ====" "INFO"
        Write-Log "Product Key: $k" "INFO"
        if ($response.Description) { Write-Log "Phiên bản: $($response.Description)" "CLEAN" }
        if ($response.SubType) { Write-Log "Loại Key (Channel): $($response.SubType)" "CLEAN" }
        if ($response.MAKCount -ne $null) { Write-Log "Lượt kích hoạt còn lại (MAK Count): $($response.MAKCount)" "CLEAN" }
        Write-Log "================================" "INFO"
    } catch {
        Write-Log "Lỗi kết nối hoặc API PID Checker tạm thời ngưng hoạt động." "CRIT"
        Write-Log $_.Exception.Message "WARN"
    }
}

function Invoke-HardwareScan {
    $txtLog.Text = ""
    Write-Log ">>> ĐANG QUÉT CẤU HÌNH HỆ THỐNG..." "INFO"
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $cpu = Get-CimInstance Win32_Processor
        $mainboard = Get-CimInstance Win32_BaseBoard
        
        $ramArr = Get-CimInstance Win32_PhysicalMemoryArray
        $ramSticks = Get-CimInstance Win32_PhysicalMemory
        $ram = $ramSticks | Measure-Object -Property Capacity -Sum
        $ramGb = [Math]::Round($ram.Sum / 1GB, 2)
        
        $totalSlots = 0
        if ($ramArr) { foreach ($r in $ramArr) { $totalSlots += $r.MemoryDevices } }
        $usedSlots = @($ramSticks).Count
        $freeSlots = if ($totalSlots -gt 0) { $totalSlots - $usedSlots } else { "Không rõ" }
        
        $vga = Get-CimInstance Win32_VideoController
        
        Write-Log "Hệ điều hành: $($os.Caption) $($os.OSArchitecture)" "CLEAN"
        
        $mainName = if ($mainboard.Product) { $mainboard.Product } else { "Không rõ" }
        $mainMfg = if ($mainboard.Manufacturer) { $mainboard.Manufacturer } else { "Không rõ" }
        try {
            $serial = (Get-CimInstance Win32_BIOS -ErrorAction Stop).SerialNumber
            if ($serial -and $serial -ne "System Serial Number" -and $serial -ne "To be filled by O.E.M.") { Write-Log "Serial Number (S/N): $serial" "CLEAN" }
        } catch {}

        Write-Log "Mainboard: $mainMfg - $mainName" "CLEAN"
        
        Write-Log "CPU: $($cpu.Name)" "CLEAN"
        Write-Log "RAM: $ramGb GB (Đã cắm $usedSlots khe / Trống $freeSlots khe)" "CLEAN"
        
        Write-Log "VGA / Card đồ họa:" "CLEAN"
        foreach ($v in $vga) {
            $vram = ""
            if ($v.AdapterRAM) { 
                $vramGb = [Math]::Round($v.AdapterRAM / 1GB, 2)
                $vramMb = [Math]::Round($v.AdapterRAM / 1MB, 0)
                $vram = if ($vramGb -ge 1) { " - VRAM: $vramGb GB" } else { " - VRAM: $vramMb MB" }
            }
            Write-Log "  - $($v.Name)$vram" "CLEAN"
        }

        try {
            $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
            if ($battery) {
                Write-Log "Pin (Battery):" "CLEAN"
                foreach ($b in $battery) {
                    $status = if ($b.BatteryStatus -eq 2) { "Đang cắm sạc (AC)" } elseif ($b.BatteryStatus -eq 1) { "Đang dùng Pin" } else { "Không rõ" }
                    $charge = if ($b.EstimatedChargeRemaining) { "$($b.EstimatedChargeRemaining)%" } else { "Không rõ" }
                    Write-Log "  - Dung lượng hiện tại: $charge ($status)" "CLEAN"
                }
            }
        } catch {}

        Write-Log "Ổ đĩa vật lý:" "CLEAN"
        try {
            $disks = Get-PhysicalDisk
            foreach ($d in $disks) {
                $size = [Math]::Round($d.Size / 1GB, 2)
                $type = $d.MediaType
                if ([string]::IsNullOrWhiteSpace($type) -or $type -eq "Unspecified") { $type = "Không xác định" }
                Write-Log "  - $($d.FriendlyName) (Loại: $type - $size GB)" "CLEAN"
            }
        } catch {
            Write-Log "  - (Không thể đọc thông tin SSD/HDD trên hệ thống này)" "WARN"
        }

        Write-Log "Hoàn tất quét cấu hình máy tính!" "INFO"
    } catch {
        Write-Log "Lỗi quét cấu hình: $($_.Exception.Message)" "CRIT"
    }
}

# =========================================================================
# PHÂN HỆ ARTCRAFT OFFICE (WORDCRAFT, GRIDCRAFT, DECKCRAFT)
# =========================================================================

function Get-ArtCraftAppStatus ($targetName) {
    try {
        # 1. Kiểm tra trong Registry Uninstall (cả 32-bit & 64-bit & User)
        $regPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        $installed = Get-ItemProperty -Path $regPaths -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -and ($_.DisplayName -like "*$targetName*") }
        if ($installed) {
            $item = $installed | Select-Object -First 1
            $v = if ($item.DisplayVersion) { "v$($item.DisplayVersion)" } else { "Đã cài" }
            return @{ Installed = $true; Version = $v; ProductCode = $item.PSChildName; UninstallString = $item.UninstallString }
        }

        # 2. Kiểm tra đường dẫn thư mục cài đặt mặc định
        $paths = @(
            "$env:ProgramFiles\$targetName\$targetName.exe",
            "${env:ProgramFiles(x86)}\$targetName\$targetName.exe",
            "$env:LOCALAPPDATA\Programs\$targetName\$targetName.exe",
            "$env:ProgramFiles\ArtCraft\$targetName\$targetName.exe",
            "$env:ProgramFiles\ArtCraft\$targetName.exe"
        )
        foreach ($p in $paths) {
            if (Test-Path $p) {
                return @{ Installed = $true; Version = "Đã cài"; Path = $p }
            }
        }

        # 3. Kiểm tra Start Menu Shortcut (.lnk)
        $shortcuts = Get-ChildItem -Path "$env:ProgramData\Microsoft\Windows\Start Menu\Programs", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs" -Filter "*$targetName*.lnk" -Recurse -ErrorAction SilentlyContinue
        if ($shortcuts) {
            return @{ Installed = $true; Version = "Đã cài"; Shortcut = $shortcuts[0].FullName }
        }
    } catch { }

    return @{ Installed = $false; Version = "Chưa cài đặt" }
}

function Start-ArtCraftApp ($targetName, $displayName) {
    try {
        # Thử mở shortcut
        $shortcuts = Get-ChildItem -Path "$env:ProgramData\Microsoft\Windows\Start Menu\Programs", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs" -Filter "*$targetName*.lnk" -Recurse -ErrorAction SilentlyContinue
        if ($shortcuts) {
            Start-Process $shortcuts[0].FullName
            Write-Log "Đã khởi chạy $displayName từ Shortcut." "CLEAN"
            return
        }

        # Thử tìm file .exe
        $paths = @(
            "$env:ProgramFiles\$targetName\$targetName.exe",
            "${env:ProgramFiles(x86)}\$targetName\$targetName.exe",
            "$env:LOCALAPPDATA\Programs\$targetName\$targetName.exe",
            "$env:ProgramFiles\ArtCraft\$targetName\$targetName.exe",
            "$env:ProgramFiles\ArtCraft\$targetName.exe"
        )
        foreach ($p in $paths) {
            if (Test-Path $p) {
                Start-Process $p
                Write-Log "Đã khởi chạy $displayName ($p)." "CLEAN"
                return
            }
        }

        # Thử qua command PATH
        $cmd = Get-Command $targetName -ErrorAction SilentlyContinue
        if ($cmd) {
            Start-Process $cmd.Source
            Write-Log "Đã khởi chạy $displayName." "CLEAN"
            return
        }

        Write-Log "Chưa tìm thấy tệp thực thi của $displayName. Vui lòng mở ứng dụng từ Start Menu." "WARN"
    } catch {
        Write-Log "Lỗi khi mở $displayName`: $($_.Exception.Message)" "CRIT"
    }
}

function Install-ArtCraftApp ($targetName, $displayName) {
    try {
        $arch = if ([System.Environment]::Is64BitOperatingSystem) {
            if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "x64" }
        } else { "x86" }

        Write-Log ">>> BẮT ĐẦU CÀI ĐẶT: $displayName (Kiến trúc: $arch)..." "INFO"
        Write-Log "Đang truy vấn phiên bản mới nhất từ GitHub (storytold/$targetName)..." "INFO"

        $apiUrl = "https://api.github.com/repos/storytold/$targetName/releases/latest"
        $release = Invoke-RestMethod -Uri $apiUrl -Headers @{ "User-Agent" = "BKC-Lic" } -ErrorAction Stop
        $tag = $release.tag_name

        # Ưu tiên gói windows-$arch.msi
        $msiAsset = $release.assets | Where-Object { $_.name -match "windows-$arch\.msi$" } | Select-Object -First 1
        if (-not $msiAsset) {
            # Dự phòng tìm bất kỳ file .msi cho windows
            $msiAsset = $release.assets | Where-Object { $_.name -match "\.msi$" -and $_.name -match "windows" } | Select-Object -First 1
        }

        if (-not $msiAsset) {
            Write-Log "Không tìm thấy gói MSI Windows tương thích cho $displayName trên GitHub!" "CRIT"
            return $false
        }

        $tempMsi = Join-Path $env:TEMP $msiAsset.name
        Write-Log "Đang tải xuống: $($msiAsset.name) ($tag)..." "INFO"

        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "BKC-Lic")
        $wc.DownloadFile($msiAsset.browser_download_url, $tempMsi)

        if (-not (Test-Path $tempMsi)) {
            Write-Log "Lỗi: Không tải được tệp MSI về thư mục tạm!" "CRIT"
            return $false
        }

        Write-Log "Đang thực thi cài đặt ngầm $displayName (MSI Silent Install)..." "INFO"
        $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$tempMsi`" /qn /norestart" -Wait -PassThru

        # Dọn dẹp tệp tạm
        Remove-Item $tempMsi -Force -ErrorAction SilentlyContinue

        if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
            Write-Log "CÀI ĐẶT THÀNH CÔNG: $displayName ($tag)!" "CLEAN"
            return $true
        } else {
            Write-Log "Cài đặt $displayName hoàn tất với mã thoát: $($proc.ExitCode)" "WARN"
            return $false
        }
    } catch {
        Write-Log "Lỗi khi cài đặt $displayName`: $($_.Exception.Message)" "CRIT"
        return $false
    }
}

function Install-ArtCraftSuite {
    $txtLog.Text = ""
    Write-Log "==========================================================" "INFO"
    Write-Log " BẮT ĐẦU CÀI TRỌN BỘ ARTCRAFT OFFICE (WORD, EXCEL, PPT)" "INFO"
    Write-Log "==========================================================" "INFO"

    $apps = @(
        @{ Target = "wordcraft"; Name = "WordCraft (Word - Soạn thảo văn bản)" },
        @{ Target = "gridcraft"; Name = "GridCraft (Excel - Bảng tính dữ liệu)" },
        @{ Target = "deckcraft"; Name = "DeckCraft (PowerPoint - Trình chiếu slide)" }
    )

    $successCount = 0
    foreach ($app in $apps) {
        $ok = Install-ArtCraftApp -targetName $app.Target -displayName $app.Name
        if ($ok) { $successCount++ }
        Write-Log "----------------------------------------------------------" "INFO"
    }

    if ($successCount -eq 3) {
        Write-Log "CHÚC MỪNG: Đã cài đặt hoàn tất trọn bộ 3 ứng dụng ArtCraft Office!" "CLEAN"
        Write-Log "Tất cả ứng dụng đã sẵn sàng sử dụng trên hệ thống." "CLEAN"
    } else {
        Write-Log "Hoàn thành: $successCount/3 ứng dụng được cài đặt thành công." "WARN"
    }

    Update-ArtCraftStatusUI
}

function Uninstall-ArtCraftApp ($targetName, $displayName) {
    try {
        Write-Log "Đang kiểm tra thông tin gỡ bỏ của $displayName..." "INFO"
        $status = Get-ArtCraftAppStatus $targetName
        if (-not $status.Installed) {
            Write-Log "Không tìm thấy $displayName được cài đặt trên hệ thống." "WARN"
            return
        }

        if ($status.ProductCode -match '^\{[0-9A-Fa-f-]+\}$') {
            Write-Log "Đang gỡ cài đặt $displayName (Mã gói: $($status.ProductCode))..." "INFO"
            $p = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$($status.ProductCode)`" /qn /norestart" -Wait -PassThru
            if ($p.ExitCode -eq 0) {
                Write-Log "Gỡ cài đặt $displayName thành công!" "CLEAN"
            } else {
                Write-Log "Gỡ cài đặt $displayName kết thúc với mã thoát: $($p.ExitCode)" "WARN"
            }
        } elseif ($status.UninstallString) {
            Write-Log "Đang chạy lệnh gỡ bỏ của $displayName..." "INFO"
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$($status.UninstallString)`"" -Wait
            Write-Log "Đã gửi lệnh gỡ cài đặt $displayName." "CLEAN"
        } else {
            Write-Log "Không tìm thấy mã ProductCode MSI để tự gỡ. Vui lòng gỡ trong Windows Settings." "WARN"
        }
    } catch {
        Write-Log "Lỗi khi gỡ cài đặt $displayName`: $($_.Exception.Message)" "CRIT"
    }
    Update-ArtCraftStatusUI
}

function Update-ArtCraftStatusUI {
    try {
        if (-not $lblWordStatus) { return }

        # 1. WordCraft
        $stWord = Get-ArtCraftAppStatus "wordcraft"
        if ($stWord.Installed) {
            $lblWordStatus.Text = "● Đã cài đặt ($($stWord.Version))"
            $lblWordStatus.ForeColor = [System.Drawing.Color]::FromArgb(46, 125, 50)
            $btnRunWord.Enabled = $true
            $btnUninstallWord.Enabled = $true
        } else {
            $lblWordStatus.Text = "○ Chưa cài đặt"
            $lblWordStatus.ForeColor = [System.Drawing.Color]::FromArgb(198, 40, 40)
            $btnRunWord.Enabled = $false
            $btnUninstallWord.Enabled = $false
        }

        # 2. GridCraft
        $stGrid = Get-ArtCraftAppStatus "gridcraft"
        if ($stGrid.Installed) {
            $lblGridStatus.Text = "● Đã cài đặt ($($stGrid.Version))"
            $lblGridStatus.ForeColor = [System.Drawing.Color]::FromArgb(46, 125, 50)
            $btnRunGrid.Enabled = $true
            $btnUninstallGrid.Enabled = $true
        } else {
            $lblGridStatus.Text = "○ Chưa cài đặt"
            $lblGridStatus.ForeColor = [System.Drawing.Color]::FromArgb(198, 40, 40)
            $btnRunGrid.Enabled = $false
            $btnUninstallGrid.Enabled = $false
        }

        # 3. DeckCraft
        $stDeck = Get-ArtCraftAppStatus "deckcraft"
        if ($stDeck.Installed) {
            $lblDeckStatus.Text = "● Đã cài đặt ($($stDeck.Version))"
            $lblDeckStatus.ForeColor = [System.Drawing.Color]::FromArgb(46, 125, 50)
            $btnRunDeck.Enabled = $true
            $btnUninstallDeck.Enabled = $true
        } else {
            $lblDeckStatus.Text = "○ Chưa cài đặt"
            $lblDeckStatus.ForeColor = [System.Drawing.Color]::FromArgb(198, 40, 40)
            $btnRunDeck.Enabled = $false
            $btnUninstallDeck.Enabled = $false
        }
    } catch { }
}


# -------------------------------------------------------------------------
# DANH MỤC TOÀN BỘ KHO ỨNG DỤNG ARTCRAFT (STORYTOLD ECOSYSTEM)
# -------------------------------------------------------------------------
$artCraftCatalog = @(
    # --- Văn Phòng & Tiện Ích ---
    @{ Target = "craft-launcher"; Name = "ArtCraft Launcher"; Role = "Trình quản lý & launcher trung tâm toàn bộ kho ArtCraft"; Category = "Tiện Ích & Hệ Thống"; Color = [System.Drawing.Color]::FromArgb(38, 50, 56) },
    @{ Target = "wordcraft"; Name = "WordCraft"; Role = "Thay thế Microsoft Word (Soạn thảo văn bản)"; Category = "Văn Phòng & Tài Liệu"; Color = [System.Drawing.Color]::FromArgb(24, 90, 189) },
    @{ Target = "gridcraft"; Name = "GridCraft"; Role = "Thay thế Microsoft Excel (Bảng tính dữ liệu)"; Category = "Văn Phòng & Tài Liệu"; Color = [System.Drawing.Color]::FromArgb(16, 124, 65) },
    @{ Target = "deckcraft"; Name = "DeckCraft"; Role = "Thay thế Microsoft PowerPoint (Trình chiếu slide)"; Category = "Văn Phòng & Tài Liệu"; Color = [System.Drawing.Color]::FromArgb(196, 62, 28) },
    @{ Target = "pdfcraft"; Name = "PdfCraft"; Role = "Thay thế Adobe Acrobat (Đọc & chỉnh sửa PDF)"; Category = "Văn Phòng & Tài Liệu"; Color = [System.Drawing.Color]::FromArgb(229, 57, 53) },
    @{ Target = "designcraft"; Name = "DesignCraft"; Role = "Thay thế Adobe InDesign (Dàn trang sách báo & in ấn)"; Category = "Văn Phòng & Tài Liệu"; Color = [System.Drawing.Color]::FromArgb(171, 71, 188) },

    # --- Thiết Kế & Đồ Họa 2D ---
    @{ Target = "photocraft"; Name = "PhotoCraft"; Role = "Thay thế Adobe Photoshop (Chỉnh sửa ảnh chuyên nghiệp)"; Category = "Thiết Kế & Đồ Họa 2D"; Color = [System.Drawing.Color]::FromArgb(2, 119, 189) },
    @{ Target = "lightcraft"; Name = "LightCraft"; Role = "Thay thế Adobe Lightroom (Chỉnh màu & ảnh RAW phi phá hủy)"; Category = "Thiết Kế & Đồ Họa 2D"; Color = [System.Drawing.Color]::FromArgb(0, 150, 136) },
    @{ Target = "vectorcraft"; Name = "VectorCraft"; Role = "Thay thế Adobe Illustrator (Đồ họa vector)"; Category = "Thiết Kế & Đồ Họa 2D"; Color = [System.Drawing.Color]::FromArgb(239, 108, 0) },
    @{ Target = "figcraft"; Name = "FigCraft"; Role = "Thay thế Figma (Thiết kế giao diện UI/UX & Prototype)"; Category = "Thiết Kế & Đồ Họa 2D"; Color = [System.Drawing.Color]::FromArgb(123, 31, 162) },

    # --- Video & Âm Thanh ---
    @{ Target = "filmcraft"; Name = "FilmCraft"; Role = "Thay thế Adobe Premiere Pro (Biên tập video chuyên nghiệp)"; Category = "Video & Âm Thanh"; Color = [System.Drawing.Color]::FromArgb(142, 36, 170) },
    @{ Target = "effectcraft"; Name = "EffectCraft"; Role = "Thay thế Adobe After Effects (Kỹ xảo Motion Graphics)"; Category = "Video & Âm Thanh"; Color = [System.Drawing.Color]::FromArgb(74, 20, 140) },
    @{ Target = "soundcraft"; Name = "SoundCraft"; Role = "Thay thế Avid Pro Tools (Thu âm & biên tập âm thanh)"; Category = "Video & Âm Thanh"; Color = [System.Drawing.Color]::FromArgb(67, 160, 71) },

    # --- 3D & Kỹ Thuật CAD ---
    @{ Target = "cadcraft"; Name = "CADCraft"; Role = "Thay thế AutoCAD (Vẽ kỹ thuật & thiết kế 2D/3D CAD)"; Category = "3D & Kỹ Thuật CAD"; Color = [System.Drawing.Color]::FromArgb(198, 40, 40) },
    @{ Target = "texturecraft"; Name = "TextureCraft"; Role = "Thay thế Substance Painter (Vẽ chất liệu & texture 3D)"; Category = "3D & Kỹ Thuật CAD"; Color = [System.Drawing.Color]::FromArgb(255, 143, 0) },
    @{ Target = "materialcraft"; Name = "MaterialCraft"; Role = "Thay thế Substance Designer (Tạo vật liệu 3D Node-based)"; Category = "3D & Kỹ Thuật CAD"; Color = [System.Drawing.Color]::FromArgb(0, 131, 143) }
)

function Show-ArtCraftStoreDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Kho Ứng Dụng Mở Rộng ArtCraft (Storytold Ecosystem) - Trình Quản Lý & Cài Đặt"
    $dlg.Size = New-Object System.Drawing.Size(920, 710)
    $dlg.StartPosition = 'CenterScreen'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.BackColor = [System.Drawing.Color]::FromArgb(245, 246, 250)
    $dlg.Font = $fontNormal

    # Header Panel
    $pnlHeader = New-Object System.Windows.Forms.Panel
    $pnlHeader.Location = New-Object System.Drawing.Point(0, 0)
    $pnlHeader.Size = New-Object System.Drawing.Size(920, 80)
    $pnlHeader.BackColor = [System.Drawing.Color]::FromArgb(26, 35, 126)
    $dlg.Controls.Add($pnlHeader)

    $lblDlgTitle = New-Object System.Windows.Forms.Label
    $lblDlgTitle.Text = "KHO ỨNG DỤNG MỞ RỘNG ARTCRAFT (PURE RUST - MÃ NGUỒN MỞ)"
    $lblDlgTitle.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $lblDlgTitle.ForeColor = [System.Drawing.Color]::White
    $lblDlgTitle.Location = New-Object System.Drawing.Point(20, 14)
    $lblDlgTitle.Size = New-Object System.Drawing.Size(870, 26)
    $pnlHeader.Controls.Add($lblDlgTitle)

    $lblDlgSub = New-Object System.Windows.Forms.Label
    $lblDlgSub.Text = "Hệ sinh thái phần mềm mã nguồn mở viết bằng Pure Rust thay thế trọn bộ Microsoft Office & Adobe Suite. Tự do, miễn phí, không lo bản quyền."
    $lblDlgSub.Font = $fontSmall
    $lblDlgSub.ForeColor = [System.Drawing.Color]::FromArgb(200, 215, 255)
    $lblDlgSub.UseMnemonic = $false
    $lblDlgSub.Location = New-Object System.Drawing.Point(20, 42)
    $lblDlgSub.Size = New-Object System.Drawing.Size(870, 30)
    $pnlHeader.Controls.Add($lblDlgSub)

    # Toolbar
    $chkSelectAll = New-Object System.Windows.Forms.CheckBox
    $chkSelectAll.Text = "Chọn Tất Cả"
    $chkSelectAll.Font = $fontBtn
    $chkSelectAll.Location = New-Object System.Drawing.Point(20, 92)
    $chkSelectAll.Size = New-Object System.Drawing.Size(125, 28)
    $dlg.Controls.Add($chkSelectAll)

    $btnInstallSelected = New-Object System.Windows.Forms.Button
    $btnInstallSelected.Text = "Cài Đặt Đã Chọn"
    $btnInstallSelected.Font = $fontBtn
    $btnInstallSelected.Location = New-Object System.Drawing.Point(155, 88)
    $btnInstallSelected.Size = New-Object System.Drawing.Size(170, 34)
    $btnInstallSelected.BackColor = [System.Drawing.Color]::FromArgb(49, 27, 146)
    $btnInstallSelected.ForeColor = [System.Drawing.Color]::White
    $btnInstallSelected.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnInstallSelected.Cursor = [System.Windows.Forms.Cursors]::Hand
    $dlg.Controls.Add($btnInstallSelected)

    $btnRefreshStore = New-Object System.Windows.Forms.Button
    $btnRefreshStore.Text = "Quét Lại Trạng Thái"
    $btnRefreshStore.Font = $fontBtn
    $btnRefreshStore.Location = New-Object System.Drawing.Point(335, 88)
    $btnRefreshStore.Size = New-Object System.Drawing.Size(175, 34)
    $btnRefreshStore.BackColor = [System.Drawing.Color]::FromArgb(0, 137, 123)
    $btnRefreshStore.ForeColor = [System.Drawing.Color]::White
    $btnRefreshStore.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnRefreshStore.Cursor = [System.Windows.Forms.Cursors]::Hand
    $dlg.Controls.Add($btnRefreshStore)

    $lblFilter = New-Object System.Windows.Forms.Label
    $lblFilter.Text = "Tìm kiếm:"
    $lblFilter.Location = New-Object System.Drawing.Point(545, 95)
    $lblFilter.Size = New-Object System.Drawing.Size(70, 24)
    $dlg.Controls.Add($lblFilter)

    $txtSearch = New-Object System.Windows.Forms.TextBox
    $txtSearch.Location = New-Object System.Drawing.Point(620, 92)
    $txtSearch.Size = New-Object System.Drawing.Size(265, 26)
    $dlg.Controls.Add($txtSearch)

    # Scrollable App Container Panel
    $pnlApps = New-Object System.Windows.Forms.Panel
    $pnlApps.Location = New-Object System.Drawing.Point(20, 130)
    $pnlApps.Size = New-Object System.Drawing.Size(865, 490)
    $pnlApps.AutoScroll = $true
    $pnlApps.BackColor = [System.Drawing.Color]::White
    $pnlApps.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $dlg.Controls.Add($pnlApps)

    # Populate Cards
    $rowControls = @()
    $yPos = 8
    foreach ($app in $artCraftCatalog) {
        $pnlCard = New-Object System.Windows.Forms.Panel
        $pnlCard.Location = New-Object System.Drawing.Point(10, $yPos)
        $pnlCard.Size = New-Object System.Drawing.Size(825, 54)
        $pnlCard.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 252)
        $pnlCard.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

        $chkItem = New-Object System.Windows.Forms.CheckBox
        $chkItem.Location = New-Object System.Drawing.Point(10, 17)
        $chkItem.Size = New-Object System.Drawing.Size(20, 20)
        $pnlCard.Controls.Add($chkItem)

        $lblAppName = New-Object System.Windows.Forms.Label
        $lblAppName.Text = $app.Name
        $lblAppName.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        $lblAppName.ForeColor = $app.Color
        $lblAppName.Location = New-Object System.Drawing.Point(36, 6)
        $lblAppName.Size = New-Object System.Drawing.Size(175, 20)
        $pnlCard.Controls.Add($lblAppName)

        $lblAppRole = New-Object System.Windows.Forms.Label
        $lblAppRole.Text = "$($app.Role)  •  [$($app.Category)]"
        $lblAppRole.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
        $lblAppRole.ForeColor = [System.Drawing.Color]::FromArgb(97, 97, 97)
        $lblAppRole.Location = New-Object System.Drawing.Point(36, 28)
        $lblAppRole.Size = New-Object System.Drawing.Size(350, 18)
        $lblAppRole.UseMnemonic = $false
        $pnlCard.Controls.Add($lblAppRole)

        $lblStatus = New-Object System.Windows.Forms.Label
        $lblStatus.Text = "Đang kiểm tra..."
        $lblStatus.Font = $fontSmall
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
        $lblStatus.Location = New-Object System.Drawing.Point(395, 17)
        $lblStatus.Size = New-Object System.Drawing.Size(125, 20)
        $pnlCard.Controls.Add($lblStatus)

        $btnInstall = New-Object System.Windows.Forms.Button
        $btnInstall.Text = "Cài Đặt"
        $btnInstall.Font = $fontSmall
        $btnInstall.Location = New-Object System.Drawing.Point(525, 10)
        $btnInstall.Size = New-Object System.Drawing.Size(95, 32)
        $btnInstall.BackColor = $app.Color
        $btnInstall.ForeColor = [System.Drawing.Color]::White
        $btnInstall.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $btnInstall.Cursor = [System.Windows.Forms.Cursors]::Hand
        $pnlCard.Controls.Add($btnInstall)

        $btnRun = New-Object System.Windows.Forms.Button
        $btnRun.Text = "Mở App"
        $btnRun.Font = $fontSmall
        $btnRun.Location = New-Object System.Drawing.Point(625, 10)
        $btnRun.Size = New-Object System.Drawing.Size(75, 32)
        $btnRun.BackColor = [System.Drawing.Color]::FromArgb(69, 90, 100)
        $btnRun.ForeColor = [System.Drawing.Color]::White
        $btnRun.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $btnRun.Cursor = [System.Windows.Forms.Cursors]::Hand
        $btnRun.Enabled = $false
        $pnlCard.Controls.Add($btnRun)

        $btnUninst = New-Object System.Windows.Forms.Button
        $btnUninst.Text = "Gỡ"
        $btnUninst.Font = $fontSmall
        $btnUninst.Location = New-Object System.Drawing.Point(705, 10)
        $btnUninst.Size = New-Object System.Drawing.Size(55, 32)
        $btnUninst.BackColor = [System.Drawing.Color]::White
        $btnUninst.ForeColor = [System.Drawing.Color]::FromArgb(198, 40, 40)
        $btnUninst.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $btnUninst.Cursor = [System.Windows.Forms.Cursors]::Hand
        $btnUninst.Enabled = $false
        $pnlCard.Controls.Add($btnUninst)

        $btnGit = New-Object System.Windows.Forms.Button
        $btnGit.Text = "Web"
        $btnGit.Font = $fontSmall
        $btnGit.Location = New-Object System.Drawing.Point(765, 10)
        $btnGit.Size = New-Object System.Drawing.Size(45, 32)
        $btnGit.BackColor = [System.Drawing.Color]::FromArgb(236, 239, 241)
        $btnGit.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $btnGit.Cursor = [System.Windows.Forms.Cursors]::Hand
        $pnlCard.Controls.Add($btnGit)

        # Gán sự kiện cho từng dòng
        $targetName = $app.Target
        $displayName = $app.Name

        $btnInstall.Add_Click({
            param($s, $e)
            $btnInstall.Enabled = $false
            Install-ArtCraftApp -targetName $targetName -displayName $displayName
            & $refreshCardStatus $rowRef
            $btnInstall.Enabled = $true
            Update-ArtCraftStatusUI
        })

        $btnRun.Add_Click({
            param($s, $e)
            Start-ArtCraftApp -targetName $targetName -displayName $displayName
        })

        $btnUninst.Add_Click({
            param($s, $e)
            $btnUninst.Enabled = $false
            Uninstall-ArtCraftApp -targetName $targetName -displayName $displayName
            & $refreshCardStatus $rowRef
            $btnUninst.Enabled = $true
            Update-ArtCraftStatusUI
        })

        $btnGit.Add_Click({
            param($s, $e)
            [System.Diagnostics.Process]::Start("https://github.com/storytold/$targetName") | Out-Null
        })

        $pnlApps.Controls.Add($pnlCard)
        $rowRef = @{
            App = $app
            Panel = $pnlCard
            CheckBox = $chkItem
            LabelStatus = $lblStatus
            BtnInstall = $btnInstall
            BtnRun = $btnRun
            BtnUninst = $btnUninst
            BtnGit = $btnGit
        }
        $rowControls += $rowRef

        $yPos += 60
    }

    # Hàm cập nhật trạng thái của 1 thẻ
    $refreshCardStatus = {
        param($rc)
        $st = Get-ArtCraftAppStatus $rc.App.Target
        if ($st.Installed) {
            $rc.LabelStatus.Text = "Đã cài ($($st.Version))"
            $rc.LabelStatus.ForeColor = [System.Drawing.Color]::FromArgb(46, 125, 50)
            $rc.BtnRun.Enabled = $true
            $rc.BtnUninst.Enabled = $true
        } else {
            $rc.LabelStatus.Text = "Chưa cài đặt"
            $rc.LabelStatus.ForeColor = [System.Drawing.Color]::FromArgb(198, 40, 40)
            $rc.BtnRun.Enabled = $false
            $rc.BtnUninst.Enabled = $false
        }
    }

    # Hàm quét toàn bộ trạng thái
    $refreshAllRows = {
        foreach ($rc in $rowControls) {
            & $refreshCardStatus $rc
        }
    }

    $btnRefreshStore.Add_Click({
        & $refreshAllRows
        Update-ArtCraftStatusUI
        Write-Log "Đã quét lại trạng thái toàn bộ 16 ứng dụng trong kho ArtCraft." "CLEAN"
    })

    # Sự kiện Chọn Tất Cả
    $chkSelectAll.Add_CheckedChanged({
        $isChecked = $chkSelectAll.Checked
        foreach ($rc in $rowControls) {
            $rc.CheckBox.Checked = $isChecked
        }
    })

    # Sự kiện Cài đặt các ứng dụng đã chọn
    $btnInstallSelected.Add_Click({
        $selected = $rowControls | Where-Object { $_.CheckBox.Checked }
        if ($selected.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Vui lòng chọn ít nhất 1 ứng dụng trong danh sách để cài đặt.", "Thông Báo", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            return
        }

        $btnInstallSelected.Enabled = $false
        $btnRefreshStore.Enabled = $false
        Write-Log "==========================================================" "INFO"
        Write-Log "BẮT ĐẦU CÀI ĐẶT $($selected.Count) ỨNG DỤNG ĐƯỢC CHỌN TRONG KHO ARTCRAFT..." "INFO"
        Write-Log "==========================================================" "INFO"

        $cnt = 0
        foreach ($rc in $selected) {
            $ok = Install-ArtCraftApp -targetName $rc.App.Target -displayName $rc.App.Name
            if ($ok) { $cnt++ }
            & $refreshCardStatus $rc
            Write-Log "----------------------------------------------------------" "INFO"
        }

        Write-Log "Hoàn tất cài đặt: $cnt/$($selected.Count) ứng dụng thành công!" "CLEAN"
        Update-ArtCraftStatusUI
        $btnInstallSelected.Enabled = $true
        $btnRefreshStore.Enabled = $true
    })

    # Sự kiện Tìm kiếm thời gian thực
    $txtSearch.Add_TextChanged({
        $q = $txtSearch.Text.Trim().ToLower()
        $currY = 8
        foreach ($rc in $rowControls) {
            $match = [string]::IsNullOrEmpty($q) -or 
                     $rc.App.Name.ToLower().Contains($q) -or 
                     $rc.App.Role.ToLower().Contains($q) -or 
                     $rc.App.Category.ToLower().Contains($q)
            $rc.Panel.Visible = $match
            if ($match) {
                $rc.Panel.Location = New-Object System.Drawing.Point(10, $currY)
                $currY += 60
            }
        }
    })

    # Footer
    $lblFooter = New-Object System.Windows.Forms.Label
    $lblFooter.Text = "Nguồn mở bởi storytold (github.com/storytold) • Pure Rust native binaries • Tự động lấy bản MSI mới nhất."
    $lblFooter.Font = $fontSmall
    $lblFooter.ForeColor = [System.Drawing.Color]::FromArgb(120, 120, 120)
    $lblFooter.Location = New-Object System.Drawing.Point(20, 632)
    $lblFooter.Size = New-Object System.Drawing.Size(730, 25)
    $dlg.Controls.Add($lblFooter)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Đóng"
    $btnClose.Font = $fontBtn
    $btnClose.Location = New-Object System.Drawing.Point(775, 628)
    $btnClose.Size = New-Object System.Drawing.Size(110, 34)
    $btnClose.BackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
    $btnClose.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnClose.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnClose.Add_Click({ $dlg.Close() })
    $dlg.Controls.Add($btnClose)

    $dlg.Add_Shown({
        & $refreshAllRows
    })

    $dlg.ShowDialog() | Out-Null
    Update-ArtCraftStatusUI
}

# =========================================================================
# THƯ VIỆN PHẦN MỀM THIẾT YẾU & VĂN PHÒNG (KIỂU ANHDV BOOT SOFTWARE LIBRARY)
# =========================================================================

$softwareCatalog = @(
    # --- 1. THIẾT YẾU (ESSENTIAL) ---
    @{
        Name = "Google Chrome"
        Size = "144 MB"
        MB = 144
        Category = "Thiết yếu"
        AltCategory = "Internet"
        Desc = "Trình duyệt web phổ biến nhất thế giới"
        WingetId = "Google.Chrome"
        CheckReg = "Google Chrome"
        CheckPath = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
        Url = "https://dl.google.com/chrome/install/standalone/service/ChromeStandaloneSetup64.exe"
        FileName = "ChromeSetup64.exe"
        SilentArgs = "/silent /install"
    },
    @{
        Name = "Zalo PC"
        Size = "169 MB"
        MB = 169
        Category = "Thiết yếu"
        AltCategory = "Internet"
        Desc = "Ứng dụng nhắn tin và gọi điện văn phòng số 1 Việt Nam"
        WingetId = "VNG.Zalo"
        CheckReg = "Zalo"
        CheckPath = "$env:LOCALAPPDATA\Programs\Zalo\Zalo.exe"
        Url = "https://res-zalo.zadn.vn/download/ZaloSetup.exe"
        FileName = "ZaloSetup.exe"
        SilentArgs = "/S"
    },
    @{
        Name = "UltraViewer"
        Size = "4 MB"
        MB = 4
        Category = "Thiết yếu"
        AltCategory = "Internet"
        Desc = "Phần mềm điều khiển máy tính từ xa hỗ trợ kỹ thuật"
        WingetId = "UltraViewer.UltraViewer"
        CheckReg = "UltraViewer"
        CheckPath = "$env:ProgramFiles(x86)\UltraViewer\UltraViewer_Desktop.exe"
        Url = "https://ultraviewer.net/vi/UltraViewer_setup_6.6_vi.exe"
        FileName = "UltraViewer_setup.exe"
        SilentArgs = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART"
    },
    @{
        Name = "7-Zip"
        Size = "2 MB"
        MB = 2
        Category = "Thiết yếu"
        AltCategory = "Tiện ích"
        Desc = "Trình nén và giải nén dữ liệu mã nguồn mở siêu tốc"
        WingetId = "7zip.7zip"
        CheckReg = "7-Zip"
        CheckPath = "$env:ProgramFiles\7-Zip\7zFM.exe"
        Url = "https://www.7-zip.org/a/7z2408-x64.exe"
        FileName = "7z_setup.exe"
        SilentArgs = "/S"
    },
    @{
        Name = "WinRAR"
        Size = "4 MB"
        MB = 4
        Category = "Thiết yếu"
        AltCategory = "Tiện ích"
        Desc = "Trình nén và giải nén file RAR/ZIP kinh điển"
        WingetId = "RARLab.WinRAR"
        CheckReg = "WinRAR"
        CheckPath = "$env:ProgramFiles\WinRAR\WinRAR.exe"
        Url = "https://www.rarlab.com/rar/winrar-x64-701.exe"
        FileName = "winrar-x64.exe"
        SilentArgs = "/S"
    },
    @{
        Name = "Foxit PDF Reader"
        Size = "376 MB"
        MB = 376
        Category = "Thiết yếu"
        AltCategory = "Văn phòng"
        Desc = "Trình đọc và ghi chú tài liệu PDF văn phòng chuyên nghiệp"
        WingetId = "Foxit.FoxitReader"
        CheckReg = "Foxit PDF Reader"
        CheckPath = "$env:ProgramFiles(x86)\Foxit Software\Foxit PDF Reader\FoxitPDFReader.exe"
        Url = "https://cdn01.foxitsoftware.com/product/reader/desktop/win/12.1.3/FoxitPDFReader1213_enu_Setup_Prom.exe"
        FileName = "FoxitReader_Setup.exe"
        SilentArgs = "/VERYSILENT /NORESTART"
    },
    @{
        Name = "SumatraPDF"
        Size = "11 MB"
        MB = 11
        Category = "Thiết yếu"
        AltCategory = "Văn phòng"
        Desc = "Trình đọc PDF siêu nhẹ, khởi động tức thì"
        WingetId = "Zeniko.SumatraPDF"
        CheckReg = "SumatraPDF"
        CheckPath = "$env:LOCALAPPDATA\SumatraPDF\SumatraPDF.exe"
        Url = "https://www.sumatrapdfreader.org/dl/SumatraPDF-3.5.2-64-install.exe"
        FileName = "SumatraPDF-install.exe"
        SilentArgs = "-s"
    },
    @{
        Name = "VLC Media Player"
        Size = "44 MB"
        MB = 44
        Category = "Thiết yếu"
        AltCategory = "Tiện ích"
        Desc = "Trình phát video và âm thanh đa năng mọi định dạng"
        WingetId = "VideoLAN.VLC"
        CheckReg = "VLC media player"
        CheckPath = "$env:ProgramFiles\VideoLAN\VLC\vlc.exe"
        Url = "https://get.videolan.org/vlc/3.0.21/win64/vlc-3.0.21-win64.exe"
        FileName = "vlc-setup.exe"
        SilentArgs = "/S"
    },
    @{
        Name = "K-Lite Codec Pack Standard"
        Size = "39 MB"
        MB = 39
        Category = "Thiết yếu"
        AltCategory = "Tiện ích"
        Desc = "Bộ giải mã codec toàn diện cho mọi video và phim ảnh"
        WingetId = "CodecGuide.K-LiteCodecPack.Standard"
        CheckReg = "K-Lite Codec Pack"
        CheckPath = "$env:ProgramFiles(x86)\K-Lite Codec Pack\MPC-HC64\mpc-hc64.exe"
        Url = "https://files3.codecguide.com/K-Lite_Codec_Pack_1860_Standard.exe"
        FileName = "klcp_standard.exe"
        SilentArgs = "/verysilent"
    },
    @{
        Name = "Unikey"
        Size = "1 MB"
        MB = 1
        Category = "Thiết yếu"
        AltCategory = "Văn phòng"
        Desc = "Bộ gõ tiếng Việt chuẩn quốc gia gọn nhẹ nhất"
        WingetId = ""
        CheckReg = "UniKey"
        CheckPath = "$env:ProgramFiles\UniKey\UniKeyNT.exe"
        CheckProc = "UniKeyNT"
        Url = "https://www.unikey.org/assets/release/unikey43RC5-200929-win64.zip"
        FileName = "unikey43RC5-win64.zip"
        IsZip = $true
        InstallSubDir = "UniKey"
    },
    @{
        Name = "EVKey"
        Size = "1 MB"
        MB = 1
        Category = "Thiết yếu"
        AltCategory = "Văn phòng"
        Desc = "Bộ gõ tiếng Việt hiện đại chống kẹt phím trên trình duyệt"
        WingetId = ""
        CheckReg = "EVKey"
        CheckPath = "$env:ProgramFiles\EVKey\EVKey64.exe"
        CheckProc = "EVKey64"
        Url = "https://github.com/lamquangminh/EVKey/releases/download/v5.4.7/EVKeySetup.exe"
        FileName = "EVKeySetup.exe"
        SilentArgs = "/VERYSILENT"
    },
    @{
        Name = "ONLYOFFICE Desktop Editors"
        Size = "206 MB"
        MB = 206
        Category = "Thiết yếu"
        AltCategory = "Văn phòng"
        Desc = "Bộ ứng dụng văn phòng tương thích 100% Microsoft Office (Word, Excel, PPT)"
        WingetId = "ONLYOFFICE.DesktopEditors"
        CheckReg = "ONLYOFFICE Desktop Editors"
        CheckPath = "$env:ProgramFiles\ONLYOFFICE\DesktopEditors\DesktopEditors.exe"
        Url = "https://github.com/ONLYOFFICE/DesktopEditors/releases/latest/download/DesktopEditors_x64.exe"
        FileName = "DesktopEditors_x64.exe"
        SilentArgs = "/VERYSILENT"
    },

    # --- 2. INTERNET ---
    @{
        Name = "Mozilla Firefox"
        Size = "83 MB"
        MB = 83
        Category = "Internet"
        Desc = "Trình duyệt web bảo mật cao và tôn trọng quyền riêng tư"
        WingetId = "Mozilla.Firefox"
        CheckReg = "Mozilla Firefox"
        CheckPath = "$env:ProgramFiles\Mozilla Firefox\firefox.exe"
        Url = "https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=vi"
        FileName = "FirefoxSetup.exe"
        SilentArgs = "-ms"
    },
    @{
        Name = "Brave Browser"
        Size = "1 MB"
        MB = 1
        Category = "Internet"
        Desc = "Trình duyệt chặn quảng cáo và bảo mật dữ liệu siêu nhanh"
        WingetId = "Brave.Brave"
        CheckReg = "Brave"
        CheckPath = "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe"
        Url = "https://laptop-updates.brave.com/latest/winx64"
        FileName = "BraveBrowserSetup.exe"
        SilentArgs = "/silent /install"
    },
    @{
        Name = "Telegram Desktop"
        Size = "57 MB"
        MB = 57
        Category = "Internet"
        Desc = "Ứng dụng nhắn tin bảo mật, lưu trữ file không giới hạn"
        WingetId = "Telegram.TelegramDesktop"
        CheckReg = "Telegram Desktop"
        CheckPath = "$env:APPDATA\Telegram Desktop\Telegram.exe"
        Url = "https://telegram.org/dl/desktop/win64"
        FileName = "tsetup.exe"
        SilentArgs = "/VERYSILENT"
    },
    @{
        Name = "Discord"
        Size = "154 MB"
        MB = 154
        Category = "Internet"
        Desc = "Nền tảng giao tiếp bằng giọng nói, video và văn bản cộng đồng"
        WingetId = "Discord.Discord"
        CheckReg = "Discord"
        CheckPath = "$env:LOCALAPPDATA\Discord\Update.exe"
        Url = "https://discord.com/api/download?platform=win"
        FileName = "DiscordSetup.exe"
        SilentArgs = "/s"
    },
    @{
        Name = "AnyDesk"
        Size = "8 MB"
        MB = 8
        Category = "Internet"
        Desc = "Phần mềm điều khiển máy tính từ xa siêu nhẹ và ổn định"
        WingetId = "AnyDeskSoftwareGmbH.AnyDesk"
        CheckReg = "AnyDesk"
        CheckPath = "$env:ProgramFiles(x86)\AnyDesk\AnyDesk.exe"
        Url = "https://download.anydesk.com/AnyDesk.exe"
        FileName = "AnyDesk.exe"
        SilentArgs = "--install ""$env:ProgramFiles(x86)\AnyDesk"" --start-with-win --silent"
    },
    @{
        Name = "TeamViewer"
        Size = "77 MB"
        MB = 77
        Category = "Internet"
        Desc = "Giải pháp kết nối và hỗ trợ từ xa toàn cầu"
        WingetId = "TeamViewer.TeamViewer"
        CheckReg = "TeamViewer"
        CheckPath = "$env:ProgramFiles\TeamViewer\TeamViewer.exe"
        Url = "https://download.teamviewer.com/download/TeamViewer_Setup_x64.exe"
        FileName = "TeamViewer_Setup_x64.exe"
        SilentArgs = "/S"
    },
    @{
        Name = "RustDesk"
        Size = "25 MB"
        MB = 25
        Category = "Internet"
        Desc = "Phần mềm điều khiển từ xa mã nguồn mở viết bằng Rust"
        WingetId = "RustDesk.RustDesk"
        CheckReg = "RustDesk"
        CheckPath = "$env:ProgramFiles\RustDesk\rustdesk.exe"
        Url = "https://github.com/rustdesk/rustdesk/releases/latest/download/rustdesk-x86_64.exe"
        FileName = "rustdesk-setup.exe"
        SilentArgs = "--silent-install"
    },

    # --- 3. TIỆN ÍCH & VĂN PHÒNG ---
    @{
        Name = "Notepad++"
        Size = "5 MB"
        MB = 5
        Category = "Tiện ích"
        AltCategory = "Văn phòng"
        Desc = "Trình soạn thảo văn bản và mã nguồn đa năng nhẹ nhàng"
        WingetId = "Notepad++.Notepad++"
        CheckReg = "Notepad++"
        CheckPath = "$env:ProgramFiles\Notepad++\notepad++.exe"
        Url = "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/latest/download/npp.Installer.x64.exe"
        FileName = "npp_setup.exe"
        SilentArgs = "/S"
    },
    @{
        Name = "Visual Studio Code"
        Size = "95 MB"
        MB = 95
        Category = "Tiện ích"
        Desc = "Trình biên tập code hàng đầu của Microsoft cho lập trình viên"
        WingetId = "Microsoft.VisualStudioCode"
        CheckReg = "Visual Studio Code"
        CheckPath = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe"
        Url = "https://update.code.visualstudio.com/latest/win32-x64-user/stable"
        FileName = "VSCodeSetup-x64.exe"
        SilentArgs = "/VERYSILENT /MERGETASKS=!runcode,addcontextmenufiles,addcontextmenufolders"
    },
    @{
        Name = "Everything (Voidtools)"
        Size = "2 MB"
        MB = 2
        Category = "Tiện ích"
        Desc = "Công cụ tìm kiếm file và folder theo thời gian thực siêu tốc"
        WingetId = "voidtools.Everything"
        CheckReg = "Everything"
        CheckPath = "$env:ProgramFiles\Everything\Everything.exe"
        Url = "https://www.voidtools.com/Everything-1.4.1.1026.x64-Setup.exe"
        FileName = "Everything_setup.exe"
        SilentArgs = "/S"
    },
    @{
        Name = "Rufus"
        Size = "2 MB"
        MB = 2
        Category = "Tiện ích"
        Desc = "Công cụ định dạng và tạo USB Boot cứu hộ cài Windows"
        WingetId = "Rufus.Rufus"
        CheckReg = "Rufus"
        CheckPath = "$env:ProgramFiles\BKC_Tools\rufus.exe"
        Url = "https://github.com/pbatard/rufus/releases/latest/download/rufus-4.5.exe"
        FileName = "rufus.exe"
        SilentArgs = ""
        IsPortable = $true
    },

    # --- 4. HỆ THỐNG & RUNTIMES ---
    @{
        Name = "Visual C++ Redistributable AIO"
        Size = "31 MB"
        MB = 31
        Category = "Hệ thống"
        Desc = "Trọn bộ Visual C++ 2005 đến 2022 (x86 & x64) sửa triệt để lỗi thiếu DLL"
        WingetId = "abbodi1406.vcredist"
        CheckReg = "Visual C++"
        CheckPath = ""
        Url = "https://github.com/abbodi1406/vcredist/releases/latest/download/VisualCppRedist_AIO_x86_x64.exe"
        FileName = "VisualCppRedist_AIO_x86_x64.exe"
        SilentArgs = "/ai /gm2"
    },
    @{
        Name = ".NET Desktop Runtime 6 LTS"
        Size = "27 MB"
        MB = 27
        Category = "Hệ thống"
        Desc = "Thư viện Microsoft .NET Desktop Runtime phiên bản 6.0 LTS"
        WingetId = "Microsoft.DotNet.DesktopRuntime.6"
        CheckReg = "Microsoft .NET Desktop Runtime - 6"
        CheckPath = ""
        Url = "https://aka.ms/dotnet/6.0/windowsdesktop-runtime-win-x64.exe"
        FileName = "dotnet-runtime-6-win-x64.exe"
        SilentArgs = "/install /quiet /norestart"
    },
    @{
        Name = ".NET Desktop Runtime 8 LTS"
        Size = "28 MB"
        MB = 28
        Category = "Hệ thống"
        Desc = "Thư viện Microsoft .NET Desktop Runtime phiên bản 8.0 LTS mới nhất"
        WingetId = "Microsoft.DotNet.DesktopRuntime.8"
        CheckReg = "Microsoft .NET Desktop Runtime - 8"
        CheckPath = ""
        Url = "https://aka.ms/dotnet/8.0/windowsdesktop-runtime-win-x64.exe"
        FileName = "dotnet-runtime-8-win-x64.exe"
        SilentArgs = "/install /quiet /norestart"
    },
    @{
        Name = "DirectX End-User Runtime"
        Size = "96 MB"
        MB = 96
        Category = "Hệ thống"
        Desc = "Thư viện DirectX 9/11 hỗ trợ đồ họa cho phần mềm và game"
        WingetId = "Microsoft.DirectX"
        CheckReg = "DirectX"
        CheckPath = "$env:SystemRoot\System32\d3dx9_43.dll"
        Url = "https://download.microsoft.com/download/1/7/1/1718CCC4-6315-4D8E-9543-8E28A4E18C4C/dxwebsetup.exe"
        FileName = "dxwebsetup.exe"
        SilentArgs = "/Q"
    },
    @{
        Name = "OpenJDK 17 LTS (Temurin)"
        Size = "191 MB"
        MB = 191
        Category = "Hệ thống"
        Desc = "Máy ảo Java 17 LTS hỗ trợ phần mềm khai thuế và kế toán văn phòng"
        WingetId = "EclipseAdoptium.Temurin.17.JDK"
        CheckReg = "Temurin"
        CheckPath = ""
        Url = "https://github.com/adoptium/temurin17-binaries/releases/latest/download/OpenJDK17U-jdk_x64_windows_hotspot.msi"
        FileName = "OpenJDK17_x64.msi"
        SilentArgs = "/quiet /norestart"
    },
    @{
        Name = "Microsoft Edge WebView2"
        Size = "2 MB"
        MB = 2
        Category = "Hệ thống"
        Desc = "Thư viện WebView2 cần thiết cho Zalo, Teams và các app hiện đại"
        WingetId = "Microsoft.EdgeWebView2Runtime"
        CheckReg = "Microsoft Edge WebView2 Runtime"
        CheckPath = "$env:ProgramFiles(x86)\Microsoft\EdgeWebView\Application"
        Url = "https://go.microsoft.com/fwlink/p/?LinkId=2124703"
        FileName = "MicrosoftEdgeWebview2Setup.exe"
        SilentArgs = "/silent /install"
    }
)

function Get-SoftwareAppStatus ($app, $installedRegList) {
    if ($app.CheckPath -and (Test-Path $app.CheckPath -ErrorAction SilentlyContinue)) {
        return $true
    }
    if ($app.CheckProc) {
        $p = Get-Process $app.CheckProc -ErrorAction SilentlyContinue
        if ($p) { return $true }
    }
    if ($app.CheckReg -and $installedRegList) {
        $pattern = "*$($app.CheckReg)*"
        $match = $installedRegList | Where-Object { $_.DisplayName -like $pattern } | Select-Object -First 1
        if ($match) { return $true }
    }
    return $false
}

function Install-CatalogSoftware ($app, $downloadOnly, $keepFiles, $targetDir) {
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }
    
    $localFile = Join-Path $targetDir $app.FileName
    Write-Log ">>> [PHẦN MỀM] Bắt đầu xử lý: $($app.Name)..." "INFO"

    # 1. Nếu chỉ tải về
    if ($downloadOnly) {
        if (-not (Test-Path $localFile)) {
            Write-Log "Đang tải xuống: $($app.Name) (~$($app.Size))..." "INFO"
            try {
                Invoke-WebRequest -Uri $app.Url -OutFile $localFile -UseBasicParsing -TimeoutSec 180
                Write-Log "Đã tải về thành công: $localFile" "CLEAN"
            } catch {
                Write-Log "Lỗi khi tải $($app.Name): $($_.Exception.Message)" "CRIT"
            }
        } else {
            Write-Log "Tệp đã có sẵn trong thư mục: $localFile" "INFO"
        }
        return
    }

    # 2. Nếu cài đặt: Thử file cục bộ trước nếu đã có sẵn
    if (Test-Path $localFile) {
        Write-Log "Tìm thấy tệp cài đặt cục bộ: $localFile. Bắt đầu cài đặt..." "INFO"
        try {
            if ($app.IsZip) {
                $destDir = "$env:ProgramFiles\$($app.InstallSubDir)"
                Expand-Archive -Path $localFile -DestinationPath $destDir -Force -ErrorAction SilentlyContinue
                Write-Log "Đã giải nén $($app.Name) vào $destDir" "CLEAN"
            } elseif ($app.IsPortable) {
                $destDir = "$env:ProgramFiles\BKC_Tools"
                if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
                Copy-Item $localFile "$destDir\$($app.FileName)" -Force -ErrorAction SilentlyContinue
                Write-Log "Đã lưu $($app.Name) vào $destDir" "CLEAN"
            } else {
                Start-Process -FilePath $localFile -ArgumentList $app.SilentArgs -Wait
                Write-Log "CÀI ĐẶT THÀNH CÔNG: $($app.Name)!" "CLEAN"
            }
            if (-not $keepFiles -and -not $app.IsPortable) {
                Remove-Item $localFile -Force -ErrorAction SilentlyContinue
            }
            return
        } catch {
            Write-Log "Lỗi cài đặt từ tệp cục bộ: $($_.Exception.Message)" "WARN"
        }
    }

    # 3. Thử qua Winget nếu máy có winget và app có WingetId
    $hasWinget = (Get-Command winget -ErrorAction SilentlyContinue)
    if ($app.WingetId -and $hasWinget) {
        Write-Log "Đang cài đặt $($app.Name) qua Windows Package Manager (winget: $($app.WingetId))..." "INFO"
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "winget"
            $psi.Arguments = "install --id $($app.WingetId) --silent --accept-package-agreements --accept-source-agreements --disable-interactivity"
            $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
            $psi.CreateNoWindow = $true
            $psi.UseShellExecute = $false
            $proc = [System.Diagnostics.Process]::Start($psi)
            $proc.WaitForExit(180000)
            if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                Write-Log "CÀI ĐẶT THÀNH CÔNG: $($app.Name) (qua winget)!" "CLEAN"
                return
            } else {
                Write-Log "Winget thoát với mã $($proc.ExitCode). Đang chuyển sang tải trực tiếp..." "WARN"
            }
        } catch {
            Write-Log "Lỗi winget: $($_.Exception.Message). Đang chuyển sang tải trực tiếp..." "WARN"
        }
    }

    # 4. Tải trực tiếp từ URL và cài đặt ngầm
    if ($app.Url) {
        Write-Log "Đang tải xuống $($app.Name) từ CDN chính thức (~$($app.Size))..." "INFO"
        try {
            Invoke-WebRequest -Uri $app.Url -OutFile $localFile -UseBasicParsing -TimeoutSec 180
            Write-Log "Tải về hoàn tất. Đang tiến hành cài đặt ngầm..." "INFO"
            
            if ($app.IsZip) {
                $destDir = "$env:ProgramFiles\$($app.InstallSubDir)"
                Expand-Archive -Path $localFile -DestinationPath $destDir -Force -ErrorAction SilentlyContinue
                Write-Log "Đã giải nén $($app.Name) vào $destDir" "CLEAN"
            } elseif ($app.IsPortable) {
                $destDir = "$env:ProgramFiles\BKC_Tools"
                if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
                Copy-Item $localFile "$destDir\$($app.FileName)" -Force -ErrorAction SilentlyContinue
                Write-Log "Đã lưu $($app.Name) vào $destDir" "CLEAN"
            } else {
                Start-Process -FilePath $localFile -ArgumentList $app.SilentArgs -Wait
                Write-Log "CÀI ĐẶT THÀNH CÔNG: $($app.Name)!" "CLEAN"
            }
            if (-not $keepFiles -and -not $app.IsPortable) {
                Remove-Item $localFile -Force -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Log "Lỗi cài đặt $($app.Name): $($_.Exception.Message)" "CRIT"
        }
    }
}

function Show-SoftwareLibraryDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Thư Viện Phần Mềm - Quản Lý Tải Xuống & Cài Đặt"
    $dlg.Size = New-Object System.Drawing.Size(950, 715)
    $dlg.StartPosition = 'CenterScreen'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $dlg.Font = $fontNormal

    # Thư mục tải mặc định
    $defaultDownloadDir = Join-Path $env:USERPROFILE "Downloads\BKC_Software"
    if (-not (Test-Path $defaultDownloadDir)) {
        New-Item -ItemType Directory -Path $defaultDownloadDir -Force | Out-Null
    }

    # Bảng trạng thái chọn
    $selectedMap = @{}
    foreach ($a in $softwareCatalog) { $selectedMap[$a.Name] = $false }

    # Quét danh sách phần mềm đã cài đặt
    $getRegInstalled = {
        return @(Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue) +
               @(Get-ItemProperty "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue) +
               @(Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue) |
               Select-Object DisplayName, DisplayVersion, Publisher
    }
    $script:cachedInstalled = & $getRegInstalled

    # --- HEADER PANEL ---
    $pnlHeader = New-Object System.Windows.Forms.Panel
    $pnlHeader.Location = New-Object System.Drawing.Point(0, 0)
    $pnlHeader.Size = New-Object System.Drawing.Size(950, 68)
    $pnlHeader.BackColor = [System.Drawing.Color]::White
    $pnlHeader.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $dlg.Controls.Add($pnlHeader)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "Thư viện phần mềm"
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
    $lblTitle.Location = New-Object System.Drawing.Point(20, 10)
    $lblTitle.Size = New-Object System.Drawing.Size(320, 28)
    $pnlHeader.Controls.Add($lblTitle)

    $lblSub = New-Object System.Windows.Forms.Label
    $lblSub.Text = "Quản lý tải xuống và cài đặt phần mềm"
    $lblSub.Font = $fontSmall
    $lblSub.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
    $lblSub.Location = New-Object System.Drawing.Point(21, 38)
    $lblSub.Size = New-Object System.Drawing.Size(350, 20)
    $pnlHeader.Controls.Add($lblSub)

    $lblSearch = New-Object System.Windows.Forms.Label
    $lblSearch.Text = "Tìm kiếm:"
    $lblSearch.Font = $fontSmall
    $lblSearch.Location = New-Object System.Drawing.Point(545, 23)
    $lblSearch.Size = New-Object System.Drawing.Size(65, 22)
    $pnlHeader.Controls.Add($lblSearch)

    $txtSearch = New-Object System.Windows.Forms.TextBox
    $txtSearch.Location = New-Object System.Drawing.Point(615, 20)
    $txtSearch.Size = New-Object System.Drawing.Size(210, 26)
    $txtSearch.Font = $fontNormal
    $pnlHeader.Controls.Add($txtSearch)

    $btnRefresh = New-Object System.Windows.Forms.Button
    $btnRefresh.Text = "Làm mới"
    $btnRefresh.Font = $fontBtn
    $btnRefresh.Location = New-Object System.Drawing.Point(835, 18)
    $btnRefresh.Size = New-Object System.Drawing.Size(85, 30)
    $btnRefresh.BackColor = [System.Drawing.Color]::White
    $btnRefresh.ForeColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
    $btnRefresh.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnRefresh.Cursor = [System.Windows.Forms.Cursors]::Hand
    $pnlHeader.Controls.Add($btnRefresh)

    # --- CATEGORY PILLS BAR ---
    $pnlPills = New-Object System.Windows.Forms.Panel
    $pnlPills.Location = New-Object System.Drawing.Point(15, 76)
    $pnlPills.Size = New-Object System.Drawing.Size(915, 46)
    $dlg.Controls.Add($pnlPills)

    $categories = @(
        @{ Key = "Thiết yếu";  Label = "Thiết yếu (12)" },
        @{ Key = "Internet";   Label = "Internet (11)" },
        @{ Key = "Tiện ích";   Label = "Tiện ích (10)" },
        @{ Key = "Văn phòng";  Label = "Văn phòng (7)" },
        @{ Key = "Hệ thống";   Label = "Hệ thống (6)" },
        @{ Key = "Tất cả";     Label = "Tất cả (30+)" }
    )
    $script:activeCategory = "Thiết yếu"
    $pillButtons = @()

    # --- SCROLLABLE SOFTWARE CARDS CONTAINER ---
    $pnlCards = New-Object System.Windows.Forms.Panel
    $pnlCards.Location = New-Object System.Drawing.Point(15, 126)
    $pnlCards.Size = New-Object System.Drawing.Size(915, 455)
    $pnlCards.AutoScroll = $true
    $pnlCards.BackColor = [System.Drawing.Color]::White
    $pnlCards.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $dlg.Controls.Add($pnlCards)

    # --- BOTTOM STATUS & TOOLBAR AREA ---
    $pnlBottom = New-Object System.Windows.Forms.Panel
    $pnlBottom.Location = New-Object System.Drawing.Point(15, 588)
    $pnlBottom.Size = New-Object System.Drawing.Size(915, 82)
    $dlg.Controls.Add($pnlBottom)

    # Dòng 1: Thư mục tải
    $lblDirTag = New-Object System.Windows.Forms.Label
    $lblDirTag.Text = "Thư mục tải:"
    $lblDirTag.Font = $fontSmall
    $lblDirTag.ForeColor = [System.Drawing.Color]::FromArgb(71, 85, 105)
    $lblDirTag.Location = New-Object System.Drawing.Point(5, 6)
    $lblDirTag.Size = New-Object System.Drawing.Size(85, 20)
    $pnlBottom.Controls.Add($lblDirTag)

    $script:currentDownloadDir = $defaultDownloadDir
    $lblDirVal = New-Object System.Windows.Forms.Label
    $lblDirVal.Text = $script:currentDownloadDir
    $lblDirVal.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic)
    $lblDirVal.ForeColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
    $lblDirVal.Location = New-Object System.Drawing.Point(92, 6)
    $lblDirVal.Size = New-Object System.Drawing.Size(620, 20)
    $pnlBottom.Controls.Add($lblDirVal)

    $btnChangeDir = New-Object System.Windows.Forms.Button
    $btnChangeDir.Text = "Đổi thư mục"
    $btnChangeDir.Font = $fontSmall
    $btnChangeDir.Location = New-Object System.Drawing.Point(720, 2)
    $btnChangeDir.Size = New-Object System.Drawing.Size(100, 26)
    $btnChangeDir.BackColor = [System.Drawing.Color]::White
    $btnChangeDir.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnChangeDir.Cursor = [System.Windows.Forms.Cursors]::Hand
    $pnlBottom.Controls.Add($btnChangeDir)

    $btnOpenDir = New-Object System.Windows.Forms.Button
    $btnOpenDir.Text = "Mở"
    $btnOpenDir.Font = $fontSmall
    $btnOpenDir.Location = New-Object System.Drawing.Point(828, 2)
    $btnOpenDir.Size = New-Object System.Drawing.Size(75, 26)
    $btnOpenDir.BackColor = [System.Drawing.Color]::White
    $btnOpenDir.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnOpenDir.Cursor = [System.Windows.Forms.Cursors]::Hand
    $pnlBottom.Controls.Add($btnOpenDir)

    $btnChangeDir.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.SelectedPath = $script:currentDownloadDir
        if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:currentDownloadDir = $fbd.SelectedPath
            $lblDirVal.Text = $script:currentDownloadDir
        }
    })

    $btnOpenDir.Add_Click({
        if (-not (Test-Path $script:currentDownloadDir)) {
            New-Item -ItemType Directory -Path $script:currentDownloadDir -Force | Out-Null
        }
        [System.Diagnostics.Process]::Start("explorer.exe", $script:currentDownloadDir) | Out-Null
    })

    # Dòng 2: Checkboxes, stats và nút Cài đặt
    $chkKeepFiles = New-Object System.Windows.Forms.CheckBox
    $chkKeepFiles.Text = "Giữ file sau khi cài"
    $chkKeepFiles.Font = $fontSmall
    $chkKeepFiles.Checked = $true
    $chkKeepFiles.Location = New-Object System.Drawing.Point(5, 42)
    $chkKeepFiles.Size = New-Object System.Drawing.Size(140, 24)
    $pnlBottom.Controls.Add($chkKeepFiles)

    $chkOnlyDownload = New-Object System.Windows.Forms.CheckBox
    $chkOnlyDownload.Text = "Chỉ tải về"
    $chkOnlyDownload.Font = $fontSmall
    $chkOnlyDownload.Location = New-Object System.Drawing.Point(155, 42)
    $chkOnlyDownload.Size = New-Object System.Drawing.Size(95, 24)
    $pnlBottom.Controls.Add($chkOnlyDownload)

    $lblSelectStats = New-Object System.Windows.Forms.Label
    $lblSelectStats.Text = "Đã chọn: 0 (Tổng 0 MB)"
    $lblSelectStats.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $lblSelectStats.ForeColor = [System.Drawing.Color]::FromArgb(0, 105, 92)
    $lblSelectStats.Location = New-Object System.Drawing.Point(265, 43)
    $lblSelectStats.Size = New-Object System.Drawing.Size(250, 22)
    $pnlBottom.Controls.Add($lblSelectStats)

    $btnSelectAll = New-Object System.Windows.Forms.Button
    $btnSelectAll.Text = "Chọn tất cả"
    $btnSelectAll.Font = $fontSmall
    $btnSelectAll.Location = New-Object System.Drawing.Point(525, 39)
    $btnSelectAll.Size = New-Object System.Drawing.Size(95, 30)
    $btnSelectAll.BackColor = [System.Drawing.Color]::White
    $btnSelectAll.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnSelectAll.Cursor = [System.Windows.Forms.Cursors]::Hand
    $pnlBottom.Controls.Add($btnSelectAll)

    $btnDeselectAll = New-Object System.Windows.Forms.Button
    $btnDeselectAll.Text = "Bỏ chọn"
    $btnDeselectAll.Font = $fontSmall
    $btnDeselectAll.Location = New-Object System.Drawing.Point(628, 39)
    $btnDeselectAll.Size = New-Object System.Drawing.Size(85, 30)
    $btnDeselectAll.BackColor = [System.Drawing.Color]::White
    $btnDeselectAll.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnDeselectAll.Cursor = [System.Windows.Forms.Cursors]::Hand
    $pnlBottom.Controls.Add($btnDeselectAll)

    $btnBatchInstall = New-Object System.Windows.Forms.Button
    $btnBatchInstall.Text = "Cài đặt (0)"
    $btnBatchInstall.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $btnBatchInstall.ForeColor = [System.Drawing.Color]::White
    $btnBatchInstall.BackColor = [System.Drawing.Color]::FromArgb(0, 137, 123)
    $btnBatchInstall.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnBatchInstall.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnBatchInstall.Location = New-Object System.Drawing.Point(725, 33)
    $btnBatchInstall.Size = New-Object System.Drawing.Size(180, 42)
    $pnlBottom.Controls.Add($btnBatchInstall)

    # Hàm cập nhật số liệu thống kê lựa chọn
    $updateStats = {
        $cnt = 0
        $totMB = 0
        foreach ($a in $softwareCatalog) {
            if ($selectedMap[$a.Name]) {
                $cnt++
                $totMB += $a.MB
            }
        }
        $lblSelectStats.Text = "Đã chọn: $cnt (Tổng $($totMB) MB)"
        $actionWord = if ($chkOnlyDownload.Checked) { "Tải về" } else { "Cài đặt" }
        $btnBatchInstall.Text = "$actionWord ($cnt)"
        $btnBatchInstall.Enabled = ($cnt -gt 0)
    }

    $chkOnlyDownload.Add_CheckedChanged({ & $updateStats })

    # Hàm render danh sách thẻ phần mềm
    $renderList = {
        $pnlCards.SuspendLayout()
        $pnlCards.Controls.Clear()

        $filterText = $txtSearch.Text.Trim().ToLower()
        $filteredList = @()

        foreach ($app in $softwareCatalog) {
            # Kiểm tra Category
            $matchCat = $false
            if ($script:activeCategory -eq "Tất cả") {
                $matchCat = $true
            } elseif ($app.Category -eq $script:activeCategory -or $app.AltCategory -eq $script:activeCategory) {
                $matchCat = $true
            }

            if (-not $matchCat) { continue }

            # Kiểm tra Search filter
            if ($filterText) {
                $matchSearch = ($app.Name.ToLower().Contains($filterText) -or $app.Desc.ToLower().Contains($filterText))
                if (-not $matchSearch) { continue }
            }

            $filteredList += $app
        }

        $y = 4
        $rowIdx = 0
        foreach ($app in $filteredList) {
            $pnlRow = New-Object System.Windows.Forms.Panel
            $pnlRow.Location = New-Object System.Drawing.Point(6, $y)
            $pnlRow.Size = New-Object System.Drawing.Size(880, 44)
            $pnlRow.BackColor = if ($rowIdx % 2 -eq 0) { [System.Drawing.Color]::White } else { [System.Drawing.Color]::FromArgb(248, 250, 252) }
            $pnlRow.BorderStyle = [System.Windows.Forms.BorderStyle]::None
            $pnlCards.Controls.Add($pnlRow)

            # Checkbox
            $chkItem = New-Object System.Windows.Forms.CheckBox
            $chkItem.Location = New-Object System.Drawing.Point(10, 12)
            $chkItem.Size = New-Object System.Drawing.Size(20, 20)
            $chkItem.Checked = [bool]$selectedMap[$app.Name]
            $chkItem.Cursor = [System.Windows.Forms.Cursors]::Hand
            $thisAppName = $app.Name
            $chkItem.Add_CheckedChanged({
                param($s, $e)
                $selectedMap[$thisAppName] = $s.Checked
                & $updateStats
            }.GetNewClosure())
            $pnlRow.Controls.Add($chkItem)

            # Tên phần mềm
            $lblName = New-Object System.Windows.Forms.Label
            $lblName.Text = $app.Name
            $lblName.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
            $lblName.ForeColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
            $lblName.Location = New-Object System.Drawing.Point(36, 12)
            $lblName.Size = New-Object System.Drawing.Size(185, 22)
            $lblName.AutoEllipsis = $true
            $pnlRow.Controls.Add($lblName)

            # Dung lượng
            $lblSize = New-Object System.Windows.Forms.Label
            $lblSize.Text = "• ~$($app.Size)"
            $lblSize.Font = $fontSmall
            $lblSize.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
            $lblSize.Location = New-Object System.Drawing.Point(225, 13)
            $lblSize.Size = New-Object System.Drawing.Size(75, 20)
            $pnlRow.Controls.Add($lblSize)

            # Mô tả ngắn
            $lblDesc = New-Object System.Windows.Forms.Label
            $lblDesc.Text = $app.Desc
            $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
            $lblDesc.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
            $lblDesc.Location = New-Object System.Drawing.Point(305, 13)
            $lblDesc.Size = New-Object System.Drawing.Size(380, 20)
            $lblDesc.AutoEllipsis = $true
            $pnlRow.Controls.Add($lblDesc)

            # Kiểm tra trạng thái cài đặt
            $isInstalled = Get-SoftwareAppStatus $app $script:cachedInstalled

            # Badge trạng thái
            $lblStatus = New-Object System.Windows.Forms.Label
            $lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
            $lblStatus.Location = New-Object System.Drawing.Point(695, 10)
            $lblStatus.Size = New-Object System.Drawing.Size(75, 24)
            $lblStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
            if ($isInstalled) {
                $lblStatus.Text = "Đã cài"
                $lblStatus.BackColor = [System.Drawing.Color]::FromArgb(0, 105, 92)
                $lblStatus.ForeColor = [System.Drawing.Color]::White
            } else {
                $lblStatus.Text = "Chưa cài"
                $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
            }
            $pnlRow.Controls.Add($lblStatus)

            # Nút hành động đơn lẻ (Cài / Cài lại)
            $btnAction = New-Object System.Windows.Forms.Button
            $btnAction.Text = if ($isInstalled) { "Cài lại" } else { "Cài" }
            $btnAction.Font = $fontSmall
            $btnAction.Location = New-Object System.Drawing.Point(785, 8)
            $btnAction.Size = New-Object System.Drawing.Size(80, 28)
            $btnAction.Cursor = [System.Windows.Forms.Cursors]::Hand
            $btnAction.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
            if ($isInstalled) {
                $btnAction.BackColor = [System.Drawing.Color]::White
                $btnAction.ForeColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
            } else {
                $btnAction.BackColor = [System.Drawing.Color]::FromArgb(0, 137, 123)
                $btnAction.ForeColor = [System.Drawing.Color]::White
            }
            $targetApp = $app
            $btnAction.Add_Click({
                param($s, $e)
                $btnAction.Enabled = $false
                $btnAction.Text = "Đang cài..."
                [System.Windows.Forms.Application]::DoEvents()

                Install-CatalogSoftware $targetApp $chkOnlyDownload.Checked $chkKeepFiles.Checked $script:currentDownloadDir
                
                # Cập nhật lại cache & UI
                $script:cachedInstalled = & $getRegInstalled
                & $renderList
            }.GetNewClosure())
            $pnlRow.Controls.Add($btnAction)

            $y += 46
            $rowIdx++
        }

        $pnlCards.ResumeLayout()
        & $updateStats
    }

    # Tạo các nút chọn danh mục (Category Pills)
    $pillX = 5
    foreach ($cat in $categories) {
        $btnPill = New-Object System.Windows.Forms.Button
        $btnPill.Text = $cat.Label
        $btnPill.Font = $fontBtn
        $btnPill.Location = New-Object System.Drawing.Point($pillX, 6)
        $btnPill.Size = New-Object System.Drawing.Size(145, 34)
        $btnPill.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $btnPill.Cursor = [System.Windows.Forms.Cursors]::Hand
        $btnPill.Tag = $cat.Key

        $thisCatKey = $cat.Key
        $btnPill.Add_Click({
            param($s, $e)
            $script:activeCategory = $thisCatKey
            foreach ($p in $pillButtons) {
                if ($p.Tag -eq $script:activeCategory) {
                    $p.BackColor = [System.Drawing.Color]::FromArgb(224, 242, 241)
                    $p.ForeColor = [System.Drawing.Color]::FromArgb(0, 121, 107)
                    $p.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(0, 121, 107)
                } else {
                    $p.BackColor = [System.Drawing.Color]::White
                    $p.ForeColor = [System.Drawing.Color]::FromArgb(71, 85, 105)
                    $p.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
                }
            }
            & $renderList
        }.GetNewClosure())

        if ($cat.Key -eq $script:activeCategory) {
            $btnPill.BackColor = [System.Drawing.Color]::FromArgb(224, 242, 241)
            $btnPill.ForeColor = [System.Drawing.Color]::FromArgb(0, 121, 107)
            $btnPill.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(0, 121, 107)
        } else {
            $btnPill.BackColor = [System.Drawing.Color]::White
            $btnPill.ForeColor = [System.Drawing.Color]::FromArgb(71, 85, 105)
            $btnPill.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
        }

        $pnlPills.Controls.Add($btnPill)
        $pillButtons += $btnPill
        $pillX += 150
    }

    # Sự kiện tìm kiếm thời gian thực
    $txtSearch.Add_TextChanged({ & $renderList })

    # Sự kiện nút Làm mới
    $btnRefresh.Add_Click({
        $script:cachedInstalled = & $getRegInstalled
        & $renderList
        Write-Log "Đã làm mới danh sách kiểm tra phần mềm đã cài đặt." "CLEAN"
    })

    # Sự kiện Chọn tất cả / Bỏ chọn
    $btnSelectAll.Add_Click({
        foreach ($app in $softwareCatalog) {
            $matchCat = ($script:activeCategory -eq "Tất cả" -or $app.Category -eq $script:activeCategory -or $app.AltCategory -eq $script:activeCategory)
            if ($matchCat) { $selectedMap[$app.Name] = $true }
        }
        & $renderList
    })

    $btnDeselectAll.Add_Click({
        foreach ($app in $softwareCatalog) {
            $selectedMap[$app.Name] = $false
        }
        & $renderList
    })

    # Sự kiện Cài đặt hàng loạt (Batch Install)
    $btnBatchInstall.Add_Click({
        $itemsToInstall = @()
        foreach ($app in $softwareCatalog) {
            if ($selectedMap[$app.Name]) { $itemsToInstall += $app }
        }

        if ($itemsToInstall.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Vui lòng chọn ít nhất 1 phần mềm để cài đặt!", "Thông báo", 0, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }

        $actionText = if ($chkOnlyDownload.Checked) { "tải về" } else { "cài đặt" }
        $confirm = [System.Windows.Forms.MessageBox]::Show("Bạn có chắc chắn muốn $actionText $($itemsToInstall.Count) phần mềm đã chọn?", "Xác nhận", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        $btnBatchInstall.Enabled = $false
        $dlg.Cursor = [System.Windows.Forms.Cursors]::WaitCursor

        $idx = 1
        foreach ($item in $itemsToInstall) {
            $btnBatchInstall.Text = "Đang cài $idx/$($itemsToInstall.Count)..."
            [System.Windows.Forms.Application]::DoEvents()

            Install-CatalogSoftware $item $chkOnlyDownload.Checked $chkKeepFiles.Checked $script:currentDownloadDir
            $idx++
        }

        # Quét lại trạng thái & render lại
        $script:cachedInstalled = & $getRegInstalled
        & $renderList

        $dlg.Cursor = [System.Windows.Forms.Cursors]::Default
        $btnBatchInstall.Enabled = $true
        & $updateStats

        [System.Windows.Forms.MessageBox]::Show("Đã hoàn tất $actionText $($itemsToInstall.Count) phần mềm!", "Hoàn tất", 0, [System.Windows.Forms.MessageBoxIcon]::Information)
    })

    # Render lần đầu
    & $renderList

    $dlg.ShowDialog() | Out-Null
}

# --- THIẾT LẬP TAB CONTROL ---
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Location = New-Object System.Drawing.Point(20, 300)
$tabControl.Size = New-Object System.Drawing.Size(845, 410)
$tabControl.Font = $fontSection

# TAB 1: Quản lý & Kích hoạt Online
$tab1 = New-Object System.Windows.Forms.TabPage
$tab1.Text = "1. Nạp Key Online & Quét"
$tab1.BackColor = [System.Drawing.Color]::White

$lblKey = New-Object System.Windows.Forms.Label
$lblKey.Text = "Nhập Product Key (25 Ký tự, dạng XXXXX-XXXXX-...):"
$lblKey.Location = New-Object System.Drawing.Point(15, 20)
$lblKey.AutoSize = $true
$tab1.Controls.Add($lblKey)

$txtKey = New-Object System.Windows.Forms.TextBox
$txtKey.Location = New-Object System.Drawing.Point(15, 45)
$txtKey.Size = New-Object System.Drawing.Size(800, 28)
$txtKey.Font = $fontCode
$txtKey.CharacterCasing = 'Upper'
$tab1.Controls.Add($txtKey)

$btnWidth = 390; $btnHeight = 45
$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Text = "Quét Bản Quyền (Win & Office)"
$btnScan.Location = New-Object System.Drawing.Point(15, 90)
$btnScan.Size = New-Object System.Drawing.Size($btnWidth, $btnHeight)
$btnScan.BackColor = [System.Drawing.Color]::FromArgb(21, 101, 192); $btnScan.ForeColor = [System.Drawing.Color]::White; $btnScan.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnScan.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnScan.Add_Click({ Toggle-Buttons $false; Invoke-LicenseScan; Toggle-Buttons $true }); $tab1.Controls.Add($btnScan); $allButtons += $btnScan

$btnInstallWin = New-Object System.Windows.Forms.Button
$btnInstallWin.Text = "Nạp Key Windows (Online)"
$btnInstallWin.Location = New-Object System.Drawing.Point(15, 145)
$btnInstallWin.Size = New-Object System.Drawing.Size($btnWidth, $btnHeight)
$btnInstallWin.BackColor = [System.Drawing.Color]::FromArgb(46, 125, 50); $btnInstallWin.ForeColor = [System.Drawing.Color]::White; $btnInstallWin.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnInstallWin.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnInstallWin.Add_Click({ Toggle-Buttons $false; Install-WinKeyOnline; Toggle-Buttons $true }); $tab1.Controls.Add($btnInstallWin); $allButtons += $btnInstallWin

$btnClearWin = New-Object System.Windows.Forms.Button
$btnClearWin.Text = "Xóa Key / Crack Windows"
$btnClearWin.Location = New-Object System.Drawing.Point(15, 200)
$btnClearWin.Size = New-Object System.Drawing.Size($btnWidth, $btnHeight)
$btnClearWin.BackColor = [System.Drawing.Color]::FromArgb(198, 40, 40); $btnClearWin.ForeColor = [System.Drawing.Color]::White; $btnClearWin.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnClearWin.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnClearWin.Add_Click({ Toggle-Buttons $false; Clear-WinLicenses; Toggle-Buttons $true }); $tab1.Controls.Add($btnClearWin); $allButtons += $btnClearWin

# Cột 2
$col2 = 425

$btnScanHardware = New-Object System.Windows.Forms.Button
$btnScanHardware.Text = "Quét Cấu Hình Máy Tính"
$btnScanHardware.Location = New-Object System.Drawing.Point($col2, 90)
$btnScanHardware.Size = New-Object System.Drawing.Size($btnWidth, $btnHeight)
$btnScanHardware.BackColor = [System.Drawing.Color]::FromArgb(230, 81, 0); $btnScanHardware.ForeColor = [System.Drawing.Color]::White; $btnScanHardware.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnScanHardware.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnScanHardware.Add_Click({ Toggle-Buttons $false; Invoke-HardwareScan; Toggle-Buttons $true }); $tab1.Controls.Add($btnScanHardware); $allButtons += $btnScanHardware

$btnInstallOffice = New-Object System.Windows.Forms.Button
$btnInstallOffice.Text = "Nạp Key Office (Online)"
$btnInstallOffice.Location = New-Object System.Drawing.Point($col2, 145)
$btnInstallOffice.Size = New-Object System.Drawing.Size($btnWidth, $btnHeight)
$btnInstallOffice.BackColor = [System.Drawing.Color]::FromArgb(0, 150, 136); $btnInstallOffice.ForeColor = [System.Drawing.Color]::White; $btnInstallOffice.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnInstallOffice.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnInstallOffice.Add_Click({ Toggle-Buttons $false; Install-OfficeKeyOnline; Toggle-Buttons $true }); $tab1.Controls.Add($btnInstallOffice); $allButtons += $btnInstallOffice

$btnClearOffice = New-Object System.Windows.Forms.Button
$btnClearOffice.Text = "Xóa Bản Quyền / Crack Office"
$btnClearOffice.Location = New-Object System.Drawing.Point($col2, 200)
$btnClearOffice.Size = New-Object System.Drawing.Size($btnWidth, $btnHeight)
$btnClearOffice.BackColor = [System.Drawing.Color]::FromArgb(173, 20, 87); $btnClearOffice.ForeColor = [System.Drawing.Color]::White; $btnClearOffice.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnClearOffice.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnClearOffice.Add_Click({ Toggle-Buttons $false; Clear-OfficeLicenses; Toggle-Buttons $true }); $tab1.Controls.Add($btnClearOffice); $allButtons += $btnClearOffice


# TAB 2: Kích hoạt By Phone
$tab2 = New-Object System.Windows.Forms.TabPage
$tab2.Text = "2. Kích Hoạt By Phone"
$tab2.BackColor = [System.Drawing.Color]::White

# --- DÒNG 1: CHỌN ĐỐI TƯỢNG (TARGET SELECTOR) & CÔNG CỤ NHANH ---
$lblTarget = New-Object System.Windows.Forms.Label
$lblTarget.Text = "Đối tượng:"
$lblTarget.Location = New-Object System.Drawing.Point(15, 12)
$lblTarget.Font = $fontSection
$lblTarget.AutoSize = $true
$tab2.Controls.Add($lblTarget)

$rbTargetWin = New-Object System.Windows.Forms.RadioButton
$rbTargetWin.Text = "Windows (Hệ điều hành)"
$rbTargetWin.Location = New-Object System.Drawing.Point(95, 10)
$rbTargetWin.Font = $fontBtn
$rbTargetWin.AutoSize = $true
$rbTargetWin.Checked = $true
$rbTargetWin.Cursor = [System.Windows.Forms.Cursors]::Hand
$rbTargetWin.Add_CheckedChanged({
    if ($rbTargetWin.Checked) {
        Write-Log "Đã chọn đối tượng làm việc: Windows" "INFO"
        Update-PhoneValidationUI
    }
})
$tab2.Controls.Add($rbTargetWin)

$rbTargetOffice = New-Object System.Windows.Forms.RadioButton
$rbTargetOffice.Text = "Microsoft Office"
$rbTargetOffice.Location = New-Object System.Drawing.Point(280, 10)
$rbTargetOffice.Font = $fontBtn
$rbTargetOffice.AutoSize = $true
$rbTargetOffice.Checked = $false
$rbTargetOffice.Cursor = [System.Windows.Forms.Cursors]::Hand
$rbTargetOffice.Add_CheckedChanged({
    if ($rbTargetOffice.Checked) {
        Write-Log "Đã chọn đối tượng làm việc: Microsoft Office" "INFO"
        Update-PhoneValidationUI
    }
})
$tab2.Controls.Add($rbTargetOffice)

$btnCheckLicStatus = New-Object System.Windows.Forms.Button
$btnCheckLicStatus.Text = "Kiểm Tra Bản Quyền"
$btnCheckLicStatus.Location = New-Object System.Drawing.Point(435, 8)
$btnCheckLicStatus.Size = New-Object System.Drawing.Size(145, 28)
$btnCheckLicStatus.Font = $fontSmall
$btnCheckLicStatus.BackColor = [System.Drawing.Color]::FromArgb(25, 118, 210)
$btnCheckLicStatus.ForeColor = [System.Drawing.Color]::White
$btnCheckLicStatus.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCheckLicStatus.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnCheckLicStatus.Add_Click({ Toggle-Buttons $false; Check-TargetStatus; Toggle-Buttons $true })
$tab2.Controls.Add($btnCheckLicStatus); $allButtons += $btnCheckLicStatus

$btnQuickKey = New-Object System.Windows.Forms.Button
$btnQuickKey.Text = "Nạp Key Phone Mới"
$btnQuickKey.Location = New-Object System.Drawing.Point(590, 8)
$btnQuickKey.Size = New-Object System.Drawing.Size(140, 28)
$btnQuickKey.Font = $fontSmall
$btnQuickKey.BackColor = [System.Drawing.Color]::FromArgb(0, 150, 136)
$btnQuickKey.ForeColor = [System.Drawing.Color]::White
$btnQuickKey.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnQuickKey.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnQuickKey.Add_Click({ Show-QuickKeyDialog })
$tab2.Controls.Add($btnQuickKey); $allButtons += $btnQuickKey

$btnClearFields = New-Object System.Windows.Forms.Button
$btnClearFields.Text = "Xóa Ô"
$btnClearFields.Location = New-Object System.Drawing.Point(740, 8)
$btnClearFields.Size = New-Object System.Drawing.Size(75, 28)
$btnClearFields.Font = $fontSmall
$btnClearFields.BackColor = [System.Drawing.Color]::FromArgb(120, 144, 156)
$btnClearFields.ForeColor = [System.Drawing.Color]::White
$btnClearFields.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnClearFields.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnClearFields.Add_Click({
    $txtIID.Text = ""
    $txtCID.Text = ""
    Update-PhoneValidationUI
    Write-Log "Đã xóa trắng các ô IID và CID trên Tab 2." "INFO"
})
$tab2.Controls.Add($btnClearFields); $allButtons += $btnClearFields

# --- DÒNG 2 & 3: INSTALLATION ID (IID) ---
$lblIID = New-Object System.Windows.Forms.Label
$lblIID.Text = "1. Installation ID (IID):"
$lblIID.Location = New-Object System.Drawing.Point(15, 44)
$lblIID.Font = $fontSection
$lblIID.AutoSize = $true
$tab2.Controls.Add($lblIID)

$lblIIDCount = New-Object System.Windows.Forms.Label
$lblIIDCount.Text = "[CHƯA CÓ IID]"
$lblIIDCount.Location = New-Object System.Drawing.Point(175, 46)
$lblIIDCount.Size = New-Object System.Drawing.Size(250, 20)
$lblIIDCount.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$lblIIDCount.ForeColor = [System.Drawing.Color]::FromArgb(120, 144, 156)
$tab2.Controls.Add($lblIIDCount)

$btnGetIID = New-Object System.Windows.Forms.Button
$btnGetIID.Text = "Lấy IID (Installation ID)"
$btnGetIID.Location = New-Object System.Drawing.Point(435, 40)
$btnGetIID.Size = New-Object System.Drawing.Size(160, 26)
$btnGetIID.Font = $fontSmall
$btnGetIID.BackColor = [System.Drawing.Color]::FromArgb(0, 131, 143)
$btnGetIID.ForeColor = [System.Drawing.Color]::White
$btnGetIID.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnGetIID.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnGetIID.Add_Click({ Toggle-Buttons $false; Get-TargetIID; Toggle-Buttons $true })
$tab2.Controls.Add($btnGetIID); $allButtons += $btnGetIID

$btnCopyIID = New-Object System.Windows.Forms.Button
$btnCopyIID.Text = "Copy Số Liền"
$btnCopyIID.Location = New-Object System.Drawing.Point(603, 40)
$btnCopyIID.Size = New-Object System.Drawing.Size(102, 26)
$btnCopyIID.Font = $fontSmall
$btnCopyIID.BackColor = [System.Drawing.Color]::White
$btnCopyIID.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnCopyIID.Add_Click({
    $clean = $txtIID.Text -replace '\D', ''
    if ($clean) {
        [System.Windows.Forms.Clipboard]::SetText($clean)
        Write-Log "Đã sao chép IID (số liền) vào Clipboard: $clean" "CLEAN"
    } else { Write-Log "Ô IID đang trống!" "WARN" }
})
$tab2.Controls.Add($btnCopyIID); $allButtons += $btnCopyIID

$btnCopyIIDGrouped = New-Object System.Windows.Forms.Button
$btnCopyIIDGrouped.Text = "Copy Dạng Khối"
$btnCopyIIDGrouped.Location = New-Object System.Drawing.Point(712, 40)
$btnCopyIIDGrouped.Size = New-Object System.Drawing.Size(103, 26)
$btnCopyIIDGrouped.Font = $fontSmall
$btnCopyIIDGrouped.BackColor = [System.Drawing.Color]::White
$btnCopyIIDGrouped.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnCopyIIDGrouped.Add_Click({
    $clean = $txtIID.Text -replace '\D', ''
    if ($clean) {
        $grouped = Format-IIDGrouped $clean
        [System.Windows.Forms.Clipboard]::SetText($grouped)
        Write-Log "Đã sao chép IID (dạng khối) vào Clipboard: $grouped" "CLEAN"
    } else { Write-Log "Ô IID đang trống!" "WARN" }
})
$tab2.Controls.Add($btnCopyIIDGrouped); $allButtons += $btnCopyIIDGrouped

$txtIID = New-Object System.Windows.Forms.TextBox
$txtIID.Location = New-Object System.Drawing.Point(15, 70)
$txtIID.Size = New-Object System.Drawing.Size(800, 26)
$txtIID.Font = $fontCode
$txtIID.Add_TextChanged({
    Update-PhoneValidationUI
})
$tab2.Controls.Add($txtIID)

$lblIIDPreview = New-Object System.Windows.Forms.Label
$lblIIDPreview.Text = "(IID Dạng Khối 9 nhóm x 7 số để đọc qua điện thoại sẽ hiển thị tại đây)"
$lblIIDPreview.Location = New-Object System.Drawing.Point(15, 98)
$lblIIDPreview.Size = New-Object System.Drawing.Size(800, 22)
$lblIIDPreview.Font = New-Object System.Drawing.Font("Consolas", 9.5, [System.Drawing.FontStyle]::Bold)
$lblIIDPreview.ForeColor = [System.Drawing.Color]::FromArgb(21, 101, 192)
$lblIIDPreview.BackColor = [System.Drawing.Color]::FromArgb(240, 245, 250)
$lblIIDPreview.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$lblIIDPreview.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblIIDPreview.UseMnemonic = $false
$tab2.Controls.Add($lblIIDPreview)

# --- DÒNG 4 & 5: CONFIRMATION ID (CID) ---
$lblCID = New-Object System.Windows.Forms.Label
$lblCID.Text = "2. Confirmation ID (CID - 48 số):"
$lblCID.Location = New-Object System.Drawing.Point(15, 126)
$lblCID.Font = $fontSection
$lblCID.AutoSize = $true
$tab2.Controls.Add($lblCID)

$lblCIDCount = New-Object System.Windows.Forms.Label
$lblCIDCount.Text = "[CHƯA CÓ CID]"
$lblCIDCount.Location = New-Object System.Drawing.Point(235, 128)
$lblCIDCount.Size = New-Object System.Drawing.Size(200, 20)
$lblCIDCount.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$lblCIDCount.ForeColor = [System.Drawing.Color]::FromArgb(120, 144, 156)
$tab2.Controls.Add($lblCIDCount)

$btnPasteAndInstallCID = New-Object System.Windows.Forms.Button
$btnPasteAndInstallCID.Text = "Dán & Nạp CID (1-Click)"
$btnPasteAndInstallCID.Location = New-Object System.Drawing.Point(435, 122)
$btnPasteAndInstallCID.Size = New-Object System.Drawing.Size(160, 26)
$btnPasteAndInstallCID.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnPasteAndInstallCID.BackColor = [System.Drawing.Color]::FromArgb(46, 125, 50)
$btnPasteAndInstallCID.ForeColor = [System.Drawing.Color]::White
$btnPasteAndInstallCID.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnPasteAndInstallCID.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnPasteAndInstallCID.Add_Click({ Toggle-Buttons $false; Invoke-SmartPasteAndInstallCID; Toggle-Buttons $true })
$tab2.Controls.Add($btnPasteAndInstallCID); $allButtons += $btnPasteAndInstallCID

$btnInstallCID = New-Object System.Windows.Forms.Button
$btnInstallCID.Text = "Nạp CID"
$btnInstallCID.Location = New-Object System.Drawing.Point(603, 122)
$btnInstallCID.Size = New-Object System.Drawing.Size(80, 26)
$btnInstallCID.Font = $fontSmall
$btnInstallCID.BackColor = [System.Drawing.Color]::FromArgb(56, 142, 60)
$btnInstallCID.ForeColor = [System.Drawing.Color]::White
$btnInstallCID.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnInstallCID.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnInstallCID.Add_Click({ Toggle-Buttons $false; Install-TargetCID; Toggle-Buttons $true })
$tab2.Controls.Add($btnInstallCID); $allButtons += $btnInstallCID

$btnPasteCID = New-Object System.Windows.Forms.Button
$btnPasteCID.Text = "Dán"
$btnPasteCID.Location = New-Object System.Drawing.Point(690, 122)
$btnPasteCID.Size = New-Object System.Drawing.Size(60, 26)
$btnPasteCID.Font = $fontSmall
$btnPasteCID.BackColor = [System.Drawing.Color]::White
$btnPasteCID.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnPasteCID.Add_Click({
    if ([System.Windows.Forms.Clipboard]::ContainsText()) {
        $clip = [System.Windows.Forms.Clipboard]::GetText()
        $clean = $clip -replace '\D', ''
        if ($clean.Length -gt 48) { $clean = $clean.Substring(0, 48) }
        $txtCID.Text = $clean
        Update-PhoneValidationUI
        if ($clean.Length -eq 48) {
            Write-Log "Đã dán CID hợp lệ (48 số): $clean" "CLEAN"
        } else {
            Write-Log "Đã dán CID từ Clipboard: $clean (Cần 48 số, hiện có $($clean.Length) số)" "WARN"
        }
    }
})
$tab2.Controls.Add($btnPasteCID); $allButtons += $btnPasteCID

$btnCopyCID = New-Object System.Windows.Forms.Button
$btnCopyCID.Text = "Copy"
$btnCopyCID.Location = New-Object System.Drawing.Point(755, 122)
$btnCopyCID.Size = New-Object System.Drawing.Size(60, 26)
$btnCopyCID.Font = $fontSmall
$btnCopyCID.BackColor = [System.Drawing.Color]::White
$btnCopyCID.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnCopyCID.Add_Click({
    $clean = $txtCID.Text -replace '\D', ''
    if ($clean) {
        [System.Windows.Forms.Clipboard]::SetText($clean)
        Write-Log "Đã sao chép CID vào Clipboard: $clean" "CLEAN"
    } else { Write-Log "Ô CID đang trống!" "WARN" }
})
$tab2.Controls.Add($btnCopyCID); $allButtons += $btnCopyCID

$txtCID = New-Object System.Windows.Forms.TextBox
$txtCID.Location = New-Object System.Drawing.Point(15, 152)
$txtCID.Size = New-Object System.Drawing.Size(800, 26)
$txtCID.Font = $fontCode
$txtCID.Add_TextChanged({
    $clean = $txtCID.Text -replace '\D', ''
    if ($clean.Length -gt 48) { $clean = $clean.Substring(0, 48) }
    if ($txtCID.Text -ne $clean) {
        $pos = $txtCID.SelectionStart
        $txtCID.Text = $clean
        $txtCID.SelectionStart = [Math]::Min($pos, $txtCID.Text.Length)
    }
    Update-PhoneValidationUI
})
$tab2.Controls.Add($txtCID)

$lblCIDPreview = New-Object System.Windows.Forms.Label
$lblCIDPreview.Text = "(CID Dạng Khối 8 nhóm [A] - [H] sẽ hiển thị tại đây)"
$lblCIDPreview.Location = New-Object System.Drawing.Point(15, 180)
$lblCIDPreview.Size = New-Object System.Drawing.Size(800, 22)
$lblCIDPreview.Font = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
$lblCIDPreview.ForeColor = [System.Drawing.Color]::FromArgb(46, 125, 50)
$lblCIDPreview.BackColor = [System.Drawing.Color]::FromArgb(240, 248, 240)
$lblCIDPreview.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$lblCIDPreview.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblCIDPreview.UseMnemonic = $false
$tab2.Controls.Add($lblCIDPreview)

# --- DÒNG 6: CÁC NÚT HÀNH ĐỘNG CHÍNH ---
$btnCallAssistant = New-Object System.Windows.Forms.Button
$btnCallAssistant.Text = "Trợ Lý Hotline 1800 400 470"
$btnCallAssistant.Location = New-Object System.Drawing.Point(15, 208)
$btnCallAssistant.Size = New-Object System.Drawing.Size(200, 38)
$btnCallAssistant.Font = $fontBtn
$btnCallAssistant.BackColor = [System.Drawing.Color]::FromArgb(106, 27, 154)
$btnCallAssistant.ForeColor = [System.Drawing.Color]::White
$btnCallAssistant.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCallAssistant.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnCallAssistant.Add_Click({ Show-CallCenterAssistantDialog })
$tab2.Controls.Add($btnCallAssistant); $allButtons += $btnCallAssistant

$btnAutoGetCID = New-Object System.Windows.Forms.Button
$btnAutoGetCID.Text = "Tự Động Get CID (API)"
$btnAutoGetCID.Location = New-Object System.Drawing.Point(222, 208)
$btnAutoGetCID.Size = New-Object System.Drawing.Size(190, 38)
$btnAutoGetCID.Font = $fontBtn
$btnAutoGetCID.BackColor = [System.Drawing.Color]::FromArgb(40, 53, 147)
$btnAutoGetCID.ForeColor = [System.Drawing.Color]::White
$btnAutoGetCID.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnAutoGetCID.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnAutoGetCID.Add_Click({ Toggle-Buttons $false; Invoke-AutoGetCIDFromIID; Toggle-Buttons $true })
$tab2.Controls.Add($btnAutoGetCID); $allButtons += $btnAutoGetCID

# Context menu cho Web Get CID (5 trang đang hoạt động)
$menuWebCID = New-Object System.Windows.Forms.ContextMenuStrip
$menuWebCID.Font = $fontNormal
$menuWebCID.Items.Add("1. KhoaToanTin CIDMS (User: trogiup24h / PHO)").Add_Click({ Open-SpecificWebCID "https://khoatoantin.com/cidms" "KhoaToanTin CIDMS" })
$menuWebCID.Items.Add("2. GetCID Việt Nam (getcid.vn)").Add_Click({ Open-SpecificWebCID "https://getcid.vn" "GetCID.vn" })
$menuWebCID.Items.Add("3. GetCID Quốc Tế (getcid.info)").Add_Click({ Open-SpecificWebCID "https://getcid.info" "GetCID.info" })
$menuWebCID.Items.Add("4. KhoaToanTin Portal (khoatoantin.com)").Add_Click({ Open-SpecificWebCID "https://khoatoantin.com" "KhoaToanTin Portal" })
$menuWebCID.Items.Add("5. Microsoft Self-Service Support Web").Add_Click({ Open-SpecificWebCID "https://support.microsoft.com/en-us/help/4051701/self-service-for-mobile-portal" "Microsoft Self-Service" })

$btnOpenWebCID = New-Object System.Windows.Forms.Button
$btnOpenWebCID.Text = "Mở Web Get CID (5 Web)"
$btnOpenWebCID.Location = New-Object System.Drawing.Point(420, 208)
$btnOpenWebCID.Size = New-Object System.Drawing.Size(195, 38)
$btnOpenWebCID.Font = $fontBtn
$btnOpenWebCID.BackColor = [System.Drawing.Color]::FromArgb(230, 81, 0)
$btnOpenWebCID.ForeColor = [System.Drawing.Color]::White
$btnOpenWebCID.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnOpenWebCID.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnOpenWebCID.Add_Click({
    $clean = $txtIID.Text -replace '\D', ''
    if (-not $clean) {
        Get-TargetIID
        $clean = $txtIID.Text -replace '\D', ''
    }
    if ($clean) {
        [System.Windows.Forms.Clipboard]::SetText($clean)
        Write-Log "ĐÃ SAO CHÉP IID VÀO CLIPBOARD: $clean" "CLEAN"
    }
    $menuWebCID.Show($btnOpenWebCID, 0, $btnOpenWebCID.Height)
})
$tab2.Controls.Add($btnOpenWebCID); $allButtons += $btnOpenWebCID

$btnAuto1Click = New-Object System.Windows.Forms.Button
$btnAuto1Click.Text = "Auto 1-Click (All-in-One)"
$btnAuto1Click.Location = New-Object System.Drawing.Point(623, 208)
$btnAuto1Click.Size = New-Object System.Drawing.Size(192, 38)
$btnAuto1Click.Font = $fontBtn
$btnAuto1Click.BackColor = [System.Drawing.Color]::FromArgb(27, 94, 32)
$btnAuto1Click.ForeColor = [System.Drawing.Color]::White
$btnAuto1Click.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnAuto1Click.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnAuto1Click.Add_Click({ Toggle-Buttons $false; Invoke-1ClickFullAutoPhone; Toggle-Buttons $true })
$tab2.Controls.Add($btnAuto1Click); $allButtons += $btnAuto1Click

# --- DÒNG 7: NÚT BACKUP & THÔNG TIN HOTLINE ---
$btnSavePhone = New-Object System.Windows.Forms.Button
$btnSavePhone.Text = "Lưu Backup Key & CID Ra Desktop"
$btnSavePhone.Location = New-Object System.Drawing.Point(15, 252)
$btnSavePhone.Size = New-Object System.Drawing.Size(255, 30)
$btnSavePhone.Font = $fontSmall
$btnSavePhone.BackColor = [System.Drawing.Color]::FromArgb(69, 90, 100)
$btnSavePhone.ForeColor = [System.Drawing.Color]::White
$btnSavePhone.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnSavePhone.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnSavePhone.Add_Click({ Save-PhoneActivationBackup })
$tab2.Controls.Add($btnSavePhone); $allButtons += $btnSavePhone

$lblHotlineNotice = New-Object System.Windows.Forms.Label
$lblHotlineNotice.Text = "Hotline Miễn Phí: 1800 400 470 (24/7)  •  Bấm 1 (Tiếng Việt) -> Bấm 1 (Cá nhân)"
$lblHotlineNotice.Location = New-Object System.Drawing.Point(280, 256)
$lblHotlineNotice.Size = New-Object System.Drawing.Size(535, 22)
$lblHotlineNotice.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$lblHotlineNotice.ForeColor = [System.Drawing.Color]::FromArgb(198, 40, 40)
$lblHotlineNotice.UseMnemonic = $false
$tab2.Controls.Add($lblHotlineNotice)

# --- DÒNG 8: KHUNG HƯỚNG DẪN QUY TRÌNH (QUICK GUIDE) ---
$pnlGuide = New-Object System.Windows.Forms.Panel
$pnlGuide.Location = New-Object System.Drawing.Point(15, 288)
$pnlGuide.Size = New-Object System.Drawing.Size(800, 78)
$pnlGuide.BackColor = [System.Drawing.Color]::FromArgb(240, 244, 248)
$pnlGuide.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$tab2.Controls.Add($pnlGuide)

$lblGuideTitle = New-Object System.Windows.Forms.Label
$lblGuideTitle.Text = "HƯỚNG DẪN QUY TRÌNH KÍCH HOẠT BY PHONE (3 BƯỚC NHANH GỌN):"
$lblGuideTitle.Location = New-Object System.Drawing.Point(8, 4)
$lblGuideTitle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblGuideTitle.ForeColor = [System.Drawing.Color]::FromArgb(21, 101, 192)
$lblGuideTitle.AutoSize = $true
$pnlGuide.Controls.Add($lblGuideTitle)

$lblGuideContent = New-Object System.Windows.Forms.Label
$lblGuideContent.Text = "1. Chọn đối tượng (Windows / Office) -> Bấm 'Lấy IID' (hoặc 'Nạp Key Phone Mới' nếu máy chưa nạp Key).`r`n" +
                        "2. Bấm 'Trợ Lý Hotline 1800 400 470' để gọi tổng đài miễn phí, hoặc bấm 'Tự Động Get CID' / 'Mở Web Get CID'.`r`n" +
                        "3. Bấm 'Dán & Nạp CID (1-Click)' để kích hoạt ngay. Thành công thì bấm 'Lưu Backup' để dùng lại vĩnh viễn!"
$lblGuideContent.Location = New-Object System.Drawing.Point(8, 22)
$lblGuideContent.Size = New-Object System.Drawing.Size(782, 50)
$lblGuideContent.Font = $fontSmall
$lblGuideContent.ForeColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
$lblGuideContent.UseMnemonic = $false
$pnlGuide.Controls.Add($lblGuideContent)

# Cập nhật hiển thị trạng thái ban đầu
Update-PhoneValidationUI


# TAB 3: Sửa lỗi & Bảo mật
$tab3 = New-Object System.Windows.Forms.TabPage
$tab3.Text = "3. Sửa Lỗi & Bảo Mật"
$tab3.BackColor = [System.Drawing.Color]::White

$btnDeepScan = New-Object System.Windows.Forms.Button
$btnDeepScan.Text = "Quét Bảo Mật Sâu (Tìm Crack)"
$btnDeepScan.Location = New-Object System.Drawing.Point(15, 30)
$btnDeepScan.Size = New-Object System.Drawing.Size($btnWidth, $btnHeight)
$btnDeepScan.BackColor = [System.Drawing.Color]::FromArgb(106, 27, 154); $btnDeepScan.ForeColor = [System.Drawing.Color]::White; $btnDeepScan.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnDeepScan.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnDeepScan.Add_Click({ Toggle-Buttons $false; Invoke-DeepScan; Toggle-Buttons $true }); $tab3.Controls.Add($btnDeepScan); $allButtons += $btnDeepScan

$btnResetWU = New-Object System.Windows.Forms.Button
$btnResetWU.Text = "Sửa Lỗi Windows Update"
$btnResetWU.Location = New-Object System.Drawing.Point($col2, 30)
$btnResetWU.Size = New-Object System.Drawing.Size($btnWidth, $btnHeight)
$btnResetWU.BackColor = [System.Drawing.Color]::FromArgb(0, 137, 123); $btnResetWU.ForeColor = [System.Drawing.Color]::White; $btnResetWU.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnResetWU.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnResetWU.Add_Click({ Toggle-Buttons $false; Invoke-ResetWU; Toggle-Buttons $true }); $tab3.Controls.Add($btnResetWU); $allButtons += $btnResetWU

$btnFixHosts = New-Object System.Windows.Forms.Button
$btnFixHosts.Text = "Kiểm Tra & Sửa File Hosts"
$btnFixHosts.Location = New-Object System.Drawing.Point(15, 90)
$btnFixHosts.Size = New-Object System.Drawing.Size($btnWidth, $btnHeight)
$btnFixHosts.BackColor = [System.Drawing.Color]::FromArgb(230, 81, 0); $btnFixHosts.ForeColor = [System.Drawing.Color]::White; $btnFixHosts.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnFixHosts.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnFixHosts.Add_Click({ Toggle-Buttons $false; Invoke-FixHosts; Toggle-Buttons $true }); $tab3.Controls.Add($btnFixHosts); $allButtons += $btnFixHosts

$btnSystemRepair = New-Object System.Windows.Forms.Button
$btnSystemRepair.Text = "Phục Hồi Hệ Thống (SFC/DISM)"
$btnSystemRepair.Location = New-Object System.Drawing.Point($col2, 90)
$btnSystemRepair.Size = New-Object System.Drawing.Size($btnWidth, $btnHeight)
$btnSystemRepair.BackColor = [System.Drawing.Color]::FromArgb(25, 118, 210); $btnSystemRepair.ForeColor = [System.Drawing.Color]::White; $btnSystemRepair.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnSystemRepair.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnSystemRepair.Add_Click({ Toggle-Buttons $false; Invoke-SystemRepair; Toggle-Buttons $true }); $tab3.Controls.Add($btnSystemRepair); $allButtons += $btnSystemRepair

$btnRestartServices = New-Object System.Windows.Forms.Button
$btnRestartServices.Text = "Khởi Động Lại SPP / OSPP"
$btnRestartServices.Location = New-Object System.Drawing.Point(15, 150)
$btnRestartServices.Size = New-Object System.Drawing.Size($btnWidth, $btnHeight)
$btnRestartServices.BackColor = [System.Drawing.Color]::FromArgb(194, 24, 91); $btnRestartServices.ForeColor = [System.Drawing.Color]::White; $btnRestartServices.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnRestartServices.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnRestartServices.Add_Click({ Toggle-Buttons $false; Restart-LicensingServices; Toggle-Buttons $true }); $tab3.Controls.Add($btnRestartServices); $allButtons += $btnRestartServices

$btnRegisterLicDLLs = New-Object System.Windows.Forms.Button
$btnRegisterLicDLLs.Text = "Đăng Ký Lại Licensing DLLs"
$btnRegisterLicDLLs.Location = New-Object System.Drawing.Point($col2, 150)
$btnRegisterLicDLLs.Size = New-Object System.Drawing.Size($btnWidth, $btnHeight)
$btnRegisterLicDLLs.BackColor = [System.Drawing.Color]::FromArgb(69, 39, 160); $btnRegisterLicDLLs.ForeColor = [System.Drawing.Color]::White; $btnRegisterLicDLLs.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnRegisterLicDLLs.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnRegisterLicDLLs.Add_Click({ Toggle-Buttons $false; Invoke-RegisterLicDLLs; Toggle-Buttons $true }); $tab3.Controls.Add($btnRegisterLicDLLs); $allButtons += $btnRegisterLicDLLs

$btnForceRemoveOffice = New-Object System.Windows.Forms.Button
$btnForceRemoveOffice.Text = "Xóa Tận Gốc Office (Force Remove)"
$btnForceRemoveOffice.Location = New-Object System.Drawing.Point(15, 210)
$btnForceRemoveOffice.Size = New-Object System.Drawing.Size($btnWidth, $btnHeight)
$btnForceRemoveOffice.BackColor = [System.Drawing.Color]::FromArgb(211, 47, 47); $btnForceRemoveOffice.ForeColor = [System.Drawing.Color]::White; $btnForceRemoveOffice.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnForceRemoveOffice.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnForceRemoveOffice.Add_Click({ Toggle-Buttons $false; Invoke-ForceRemoveOffice; Toggle-Buttons $true }); $tab3.Controls.Add($btnForceRemoveOffice); $allButtons += $btnForceRemoveOffice

$btnResetNetwork = New-Object System.Windows.Forms.Button
$btnResetNetwork.Text = "Reset Network && Firewall"
$btnResetNetwork.Location = New-Object System.Drawing.Point($col2, 210)
$btnResetNetwork.Size = New-Object System.Drawing.Size($btnWidth, $btnHeight)
$btnResetNetwork.BackColor = [System.Drawing.Color]::FromArgb(55, 71, 79); $btnResetNetwork.ForeColor = [System.Drawing.Color]::White; $btnResetNetwork.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnResetNetwork.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnResetNetwork.Add_Click({ Toggle-Buttons $false; Invoke-ResetNetwork; Toggle-Buttons $true }); $tab3.Controls.Add($btnResetNetwork); $allButtons += $btnResetNetwork

$btnUninstallOffice = New-Object System.Windows.Forms.Button
$btnUninstallOffice.Text = "Gỡ Phần Mềm Office"
$btnUninstallOffice.Location = New-Object System.Drawing.Point(15, 270)
$btnUninstallOffice.Size = New-Object System.Drawing.Size($btnWidth, $btnHeight)
$btnUninstallOffice.BackColor = [System.Drawing.Color]::FromArgb(211, 47, 47); $btnUninstallOffice.ForeColor = [System.Drawing.Color]::White; $btnUninstallOffice.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnUninstallOffice.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnUninstallOffice.Add_Click({ Toggle-Buttons $false; Show-OfficeUninstaller; Toggle-Buttons $true }); $tab3.Controls.Add($btnUninstallOffice); $allButtons += $btnUninstallOffice
# TAB 4: Công cụ Bổ sung (Backup & PID)
$tab4 = New-Object System.Windows.Forms.TabPage
$tab4.Text = "4. Backup"
$tab4.BackColor = [System.Drawing.Color]::White

$lblPIDKey = New-Object System.Windows.Forms.Label
$lblPIDKey.Text = "Nhập Key cần kiểm tra (PID Checker):"
$lblPIDKey.Location = New-Object System.Drawing.Point(15, 20)
$lblPIDKey.AutoSize = $true
$tab4.Controls.Add($lblPIDKey)

$txtPIDKey = New-Object System.Windows.Forms.TextBox
$txtPIDKey.Location = New-Object System.Drawing.Point(15, 45)
$txtPIDKey.Size = New-Object System.Drawing.Size(390, 28)
$txtPIDKey.Font = $fontCode
$txtPIDKey.CharacterCasing = 'Upper'
$tab4.Controls.Add($txtPIDKey)

$btnCheckPID = New-Object System.Windows.Forms.Button
$btnCheckPID.Text = "Kiểm Tra Key (PID Checker)"
$btnCheckPID.Location = New-Object System.Drawing.Point($col2, 43)
$btnCheckPID.Size = New-Object System.Drawing.Size($btnWidth, 32)
$btnCheckPID.BackColor = [System.Drawing.Color]::FromArgb(25, 118, 210); $btnCheckPID.ForeColor = [System.Drawing.Color]::White; $btnCheckPID.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnCheckPID.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnCheckPID.Add_Click({ Toggle-Buttons $false; Invoke-PIDChecker; Toggle-Buttons $true }); $tab4.Controls.Add($btnCheckPID); $allButtons += $btnCheckPID

$chkBackupTokens = New-Object System.Windows.Forms.CheckBox
$chkBackupTokens.Text = "Bản quyền (Tokens)"
$chkBackupTokens.Checked = $true
$chkBackupTokens.Location = New-Object System.Drawing.Point(15, 90)
$chkBackupTokens.AutoSize = $true
$tab4.Controls.Add($chkBackupTokens)
$chkBackupDrivers = New-Object System.Windows.Forms.CheckBox
$chkBackupDrivers.Text = "Trình điều khiển (Drivers)"
$chkBackupDrivers.Checked = $true
$chkBackupDrivers.Location = New-Object System.Drawing.Point(200, 90)
$chkBackupDrivers.AutoSize = $true
$tab4.Controls.Add($chkBackupDrivers)
$btnBackupTokens = New-Object System.Windows.Forms.Button
$btnBackupTokens.Text = "Sao Lưu Đã Chọn"
$btnBackupTokens.Location = New-Object System.Drawing.Point(15, 120)
$btnBackupTokens.Size = New-Object System.Drawing.Size($btnWidth, $btnHeight)
$btnBackupTokens.BackColor = [System.Drawing.Color]::FromArgb(46, 125, 50); $btnBackupTokens.ForeColor = [System.Drawing.Color]::White; $btnBackupTokens.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnBackupTokens.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnBackupTokens.Add_Click({ Toggle-Buttons $false; Invoke-BackupTokens; Toggle-Buttons $true }); $tab4.Controls.Add($btnBackupTokens); $allButtons += $btnBackupTokens
$btnRestoreTokens = New-Object System.Windows.Forms.Button
$btnRestoreTokens.Text = "Phục Hồi Đã Chọn"
$btnRestoreTokens.Location = New-Object System.Drawing.Point($col2, 120)
$btnRestoreTokens.Size = New-Object System.Drawing.Size($btnWidth, $btnHeight)
$btnRestoreTokens.BackColor = [System.Drawing.Color]::FromArgb(198, 40, 40); $btnRestoreTokens.ForeColor = [System.Drawing.Color]::White; $btnRestoreTokens.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnRestoreTokens.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnRestoreTokens.Add_Click({ Toggle-Buttons $false; Invoke-RestoreTokens; Toggle-Buttons $true }); $tab4.Controls.Add($btnRestoreTokens); $allButtons += $btnRestoreTokens
# TAB 5: Cài Đặt Phần Mềm (Văn Phòng & Tiện Ích Thiết Yếu)
$tab5 = New-Object System.Windows.Forms.TabPage
$tab5.Text = "5. Phần Mềm"
$tab5.BackColor = [System.Drawing.Color]::White

# Tiêu đề & Giới thiệu
$lblArtTitle = New-Object System.Windows.Forms.Label
$lblArtTitle.Text = "TRUNG TÂM PHẦN MỀM & TIỆN ÍCH VĂN PHÒNG"
$lblArtTitle.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$lblArtTitle.ForeColor = [System.Drawing.Color]::FromArgb(26, 35, 126)
$lblArtTitle.Location = New-Object System.Drawing.Point(15, 10)
$lblArtTitle.Size = New-Object System.Drawing.Size(810, 24)
$tab5.Controls.Add($lblArtTitle)

$lblArtDesc = New-Object System.Windows.Forms.Label
$lblArtDesc.Text = "Cung cấp thư viện cài đặt nhanh các phần mềm văn phòng, trình duyệt, gõ tiếng Việt, PDF, runtimes hệ thống và hệ sinh thái ArtCraft."
$lblArtDesc.Font = $fontSmall
$lblArtDesc.ForeColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
$lblArtDesc.Location = New-Object System.Drawing.Point(15, 34)
$lblArtDesc.Size = New-Object System.Drawing.Size(810, 20)
$tab5.Controls.Add($lblArtDesc)

# --- NÚT LỚN NỔI BẬT: THƯ VIỆN PHẦN MỀM (KIỂU ANHDV BOOT) ---
$btnOpenSoftLibrary = New-Object System.Windows.Forms.Button
$btnOpenSoftLibrary.Text = "Thư Viện Phần Mềm (Chrome, Zalo, Unikey, Office, PDF, C++...)"
$btnOpenSoftLibrary.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$btnOpenSoftLibrary.Location = New-Object System.Drawing.Point(15, 58)
$btnOpenSoftLibrary.Size = New-Object System.Drawing.Size(810, 44)
$btnOpenSoftLibrary.BackColor = [System.Drawing.Color]::FromArgb(0, 137, 123)
$btnOpenSoftLibrary.ForeColor = [System.Drawing.Color]::White
$btnOpenSoftLibrary.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnOpenSoftLibrary.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnOpenSoftLibrary.Add_Click({
    Show-SoftwareLibraryDialog
})
$tab5.Controls.Add($btnOpenSoftLibrary); $allButtons += $btnOpenSoftLibrary

# Tiêu đề phụ: Bộ ứng dụng văn phòng ArtCraft
$lblArtSection = New-Object System.Windows.Forms.Label
$lblArtSection.Text = "BỘ ỨNG DỤNG VĂN PHÒNG NỘI BỘ ARTCRAFT (PURE RUST - SIÊU NHẸ - MIỄN PHÍ BẢN QUYỀN):"
$lblArtSection.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$lblArtSection.ForeColor = [System.Drawing.Color]::FromArgb(21, 101, 192)
$lblArtSection.Location = New-Object System.Drawing.Point(15, 110)
$lblArtSection.Size = New-Object System.Drawing.Size(810, 20)
$tab5.Controls.Add($lblArtSection)

# --- 1. HÀNG WORDCRAFT (THAY THẾ WORD) ---
$lblWordName = New-Object System.Windows.Forms.Label
$lblWordName.Text = "WordCraft (Thay thế Word)"
$lblWordName.Font = $fontSection
$lblWordName.ForeColor = [System.Drawing.Color]::FromArgb(24, 90, 189)
$lblWordName.Location = New-Object System.Drawing.Point(15, 136)
$lblWordName.Size = New-Object System.Drawing.Size(260, 22)
$tab5.Controls.Add($lblWordName)

$lblWordStatus = New-Object System.Windows.Forms.Label
$lblWordStatus.Text = "Đang kiểm tra..."
$lblWordStatus.Font = $fontNormal
$lblWordStatus.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
$lblWordStatus.Location = New-Object System.Drawing.Point(280, 137)
$lblWordStatus.Size = New-Object System.Drawing.Size(180, 22)
$tab5.Controls.Add($lblWordStatus)

$btnInstallWord = New-Object System.Windows.Forms.Button
$btnInstallWord.Text = "Cài Đặt"
$btnInstallWord.Font = $fontBtn
$btnInstallWord.Location = New-Object System.Drawing.Point(470, 131)
$btnInstallWord.Size = New-Object System.Drawing.Size(160, 32)
$btnInstallWord.BackColor = [System.Drawing.Color]::FromArgb(24, 90, 189)
$btnInstallWord.ForeColor = [System.Drawing.Color]::White
$btnInstallWord.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnInstallWord.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnInstallWord.Add_Click({
    Toggle-Buttons $false
    Install-ArtCraftApp -targetName "wordcraft" -displayName "WordCraft (Word)"
    Update-ArtCraftStatusUI
    Toggle-Buttons $true
})
$tab5.Controls.Add($btnInstallWord); $allButtons += $btnInstallWord

$btnRunWord = New-Object System.Windows.Forms.Button
$btnRunWord.Text = "Mở App"
$btnRunWord.Font = $fontBtn
$btnRunWord.Location = New-Object System.Drawing.Point(640, 131)
$btnRunWord.Size = New-Object System.Drawing.Size(95, 32)
$btnRunWord.BackColor = [System.Drawing.Color]::FromArgb(69, 90, 100)
$btnRunWord.ForeColor = [System.Drawing.Color]::White
$btnRunWord.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnRunWord.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnRunWord.Add_Click({ Start-ArtCraftApp -targetName "wordcraft" -displayName "WordCraft" })
$tab5.Controls.Add($btnRunWord); $allButtons += $btnRunWord

$btnUninstallWord = New-Object System.Windows.Forms.Button
$btnUninstallWord.Text = "Gỡ Bỏ"
$btnUninstallWord.Font = $fontSmall
$btnUninstallWord.Location = New-Object System.Drawing.Point(745, 131)
$btnUninstallWord.Size = New-Object System.Drawing.Size(80, 32)
$btnUninstallWord.BackColor = [System.Drawing.Color]::White
$btnUninstallWord.ForeColor = [System.Drawing.Color]::FromArgb(198, 40, 40)
$btnUninstallWord.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnUninstallWord.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnUninstallWord.Add_Click({
    Toggle-Buttons $false
    Uninstall-ArtCraftApp -targetName "wordcraft" -displayName "WordCraft"
    Toggle-Buttons $true
})
$tab5.Controls.Add($btnUninstallWord); $allButtons += $btnUninstallWord

# --- 2. HÀNG GRIDCRAFT (THAY THẾ EXCEL) ---
$lblGridName = New-Object System.Windows.Forms.Label
$lblGridName.Text = "GridCraft (Thay thế Excel)"
$lblGridName.Font = $fontSection
$lblGridName.ForeColor = [System.Drawing.Color]::FromArgb(16, 124, 65)
$lblGridName.Location = New-Object System.Drawing.Point(15, 175)
$lblGridName.Size = New-Object System.Drawing.Size(260, 22)
$tab5.Controls.Add($lblGridName)

$lblGridStatus = New-Object System.Windows.Forms.Label
$lblGridStatus.Text = "Đang kiểm tra..."
$lblGridStatus.Font = $fontNormal
$lblGridStatus.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
$lblGridStatus.Location = New-Object System.Drawing.Point(280, 176)
$lblGridStatus.Size = New-Object System.Drawing.Size(180, 22)
$tab5.Controls.Add($lblGridStatus)

$btnInstallGrid = New-Object System.Windows.Forms.Button
$btnInstallGrid.Text = "Cài Đặt"
$btnInstallGrid.Font = $fontBtn
$btnInstallGrid.Location = New-Object System.Drawing.Point(470, 170)
$btnInstallGrid.Size = New-Object System.Drawing.Size(160, 32)
$btnInstallGrid.BackColor = [System.Drawing.Color]::FromArgb(16, 124, 65)
$btnInstallGrid.ForeColor = [System.Drawing.Color]::White
$btnInstallGrid.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnInstallGrid.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnInstallGrid.Add_Click({
    Toggle-Buttons $false
    Install-ArtCraftApp -targetName "gridcraft" -displayName "GridCraft (Excel)"
    Update-ArtCraftStatusUI
    Toggle-Buttons $true
})
$tab5.Controls.Add($btnInstallGrid); $allButtons += $btnInstallGrid

$btnRunGrid = New-Object System.Windows.Forms.Button
$btnRunGrid.Text = "Mở App"
$btnRunGrid.Font = $fontBtn
$btnRunGrid.Location = New-Object System.Drawing.Point(640, 170)
$btnRunGrid.Size = New-Object System.Drawing.Size(95, 32)
$btnRunGrid.BackColor = [System.Drawing.Color]::FromArgb(69, 90, 100)
$btnRunGrid.ForeColor = [System.Drawing.Color]::White
$btnRunGrid.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnRunGrid.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnRunGrid.Add_Click({ Start-ArtCraftApp -targetName "gridcraft" -displayName "GridCraft" })
$tab5.Controls.Add($btnRunGrid); $allButtons += $btnRunGrid

$btnUninstallGrid = New-Object System.Windows.Forms.Button
$btnUninstallGrid.Text = "Gỡ Bỏ"
$btnUninstallGrid.Font = $fontSmall
$btnUninstallGrid.Location = New-Object System.Drawing.Point(745, 170)
$btnUninstallGrid.Size = New-Object System.Drawing.Size(80, 32)
$btnUninstallGrid.BackColor = [System.Drawing.Color]::White
$btnUninstallGrid.ForeColor = [System.Drawing.Color]::FromArgb(198, 40, 40)
$btnUninstallGrid.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnUninstallGrid.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnUninstallGrid.Add_Click({
    Toggle-Buttons $false
    Uninstall-ArtCraftApp -targetName "gridcraft" -displayName "GridCraft"
    Toggle-Buttons $true
})
$tab5.Controls.Add($btnUninstallGrid); $allButtons += $btnUninstallGrid

# --- 3. HÀNG DECKCRAFT (THAY THẾ POWERPOINT) ---
$lblDeckName = New-Object System.Windows.Forms.Label
$lblDeckName.Text = "DeckCraft (Thay PowerPoint)"
$lblDeckName.Font = $fontSection
$lblDeckName.ForeColor = [System.Drawing.Color]::FromArgb(196, 62, 28)
$lblDeckName.Location = New-Object System.Drawing.Point(15, 214)
$lblDeckName.Size = New-Object System.Drawing.Size(260, 22)
$tab5.Controls.Add($lblDeckName)

$lblDeckStatus = New-Object System.Windows.Forms.Label
$lblDeckStatus.Text = "Đang kiểm tra..."
$lblDeckStatus.Font = $fontNormal
$lblDeckStatus.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
$lblDeckStatus.Location = New-Object System.Drawing.Point(280, 215)
$lblDeckStatus.Size = New-Object System.Drawing.Size(180, 22)
$tab5.Controls.Add($lblDeckStatus)

$btnInstallDeck = New-Object System.Windows.Forms.Button
$btnInstallDeck.Text = "Cài Đặt"
$btnInstallDeck.Font = $fontBtn
$btnInstallDeck.Location = New-Object System.Drawing.Point(470, 209)
$btnInstallDeck.Size = New-Object System.Drawing.Size(160, 32)
$btnInstallDeck.BackColor = [System.Drawing.Color]::FromArgb(196, 62, 28)
$btnInstallDeck.ForeColor = [System.Drawing.Color]::White
$btnInstallDeck.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnInstallDeck.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnInstallDeck.Add_Click({
    Toggle-Buttons $false
    Install-ArtCraftApp -targetName "deckcraft" -displayName "DeckCraft (PowerPoint)"
    Update-ArtCraftStatusUI
    Toggle-Buttons $true
})
$tab5.Controls.Add($btnInstallDeck); $allButtons += $btnInstallDeck

$btnRunDeck = New-Object System.Windows.Forms.Button
$btnRunDeck.Text = "Mở App"
$btnRunDeck.Font = $fontBtn
$btnRunDeck.Location = New-Object System.Drawing.Point(640, 209)
$btnRunDeck.Size = New-Object System.Drawing.Size(95, 32)
$btnRunDeck.BackColor = [System.Drawing.Color]::FromArgb(69, 90, 100)
$btnRunDeck.ForeColor = [System.Drawing.Color]::White
$btnRunDeck.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnRunDeck.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnRunDeck.Add_Click({ Start-ArtCraftApp -targetName "deckcraft" -displayName "DeckCraft" })
$tab5.Controls.Add($btnRunDeck); $allButtons += $btnRunDeck

$btnUninstallDeck = New-Object System.Windows.Forms.Button
$btnUninstallDeck.Text = "Gỡ Bỏ"
$btnUninstallDeck.Font = $fontSmall
$btnUninstallDeck.Location = New-Object System.Drawing.Point(745, 209)
$btnUninstallDeck.Size = New-Object System.Drawing.Size(80, 32)
$btnUninstallDeck.BackColor = [System.Drawing.Color]::White
$btnUninstallDeck.ForeColor = [System.Drawing.Color]::FromArgb(198, 40, 40)
$btnUninstallDeck.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnUninstallDeck.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnUninstallDeck.Add_Click({
    Toggle-Buttons $false
    Uninstall-ArtCraftApp -targetName "deckcraft" -displayName "DeckCraft"
    Toggle-Buttons $true
})
$tab5.Controls.Add($btnUninstallDeck); $allButtons += $btnUninstallDeck

# --- KHỐI THAO TÁC TỔNG THỂ (DƯỚI CÙNG) ---
$pnlArtDivider = New-Object System.Windows.Forms.Panel
$pnlArtDivider.Location = New-Object System.Drawing.Point(15, 250)
$pnlArtDivider.Size = New-Object System.Drawing.Size(810, 1)
$pnlArtDivider.BackColor = [System.Drawing.Color]::FromArgb(220, 220, 220)
$tab5.Controls.Add($pnlArtDivider)

# Hàng nút 1: Cài trọn bộ Office & Mở kho ứng dụng mở rộng
$btnInstallSuite = New-Object System.Windows.Forms.Button
$btnInstallSuite.Text = "Cài Trọn Bộ Office (Word + Excel + PPT)"
$btnInstallSuite.Font = $fontBtn
$btnInstallSuite.Location = New-Object System.Drawing.Point(15, 258)
$btnInstallSuite.Size = New-Object System.Drawing.Size(395, 38)
$btnInstallSuite.BackColor = [System.Drawing.Color]::FromArgb(49, 27, 146)
$btnInstallSuite.ForeColor = [System.Drawing.Color]::White
$btnInstallSuite.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnInstallSuite.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnInstallSuite.Add_Click({
    Toggle-Buttons $false
    Install-ArtCraftSuite
    Toggle-Buttons $true
})
$tab5.Controls.Add($btnInstallSuite); $allButtons += $btnInstallSuite

$btnOpenStore = New-Object System.Windows.Forms.Button
$btnOpenStore.Text = "Kho ArtCraft 16+ Mở Rộng (Photoshop, AI, Figma...)"
$btnOpenStore.Font = $fontBtn
$btnOpenStore.Location = New-Object System.Drawing.Point(420, 258)
$btnOpenStore.Size = New-Object System.Drawing.Size(405, 38)
$btnOpenStore.BackColor = [System.Drawing.Color]::FromArgb(106, 27, 154)
$btnOpenStore.ForeColor = [System.Drawing.Color]::White
$btnOpenStore.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnOpenStore.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnOpenStore.Add_Click({
    Show-ArtCraftStoreDialog
})
$tab5.Controls.Add($btnOpenStore); $allButtons += $btnOpenStore

# Hàng nút 2: Các nút công cụ phụ trợ
$btnRefreshArtStatus = New-Object System.Windows.Forms.Button
$btnRefreshArtStatus.Text = "Quét Lại Trạng Thái"
$btnRefreshArtStatus.Font = $fontBtn
$btnRefreshArtStatus.Location = New-Object System.Drawing.Point(15, 304)
$btnRefreshArtStatus.Size = New-Object System.Drawing.Size(190, 34)
$btnRefreshArtStatus.BackColor = [System.Drawing.Color]::FromArgb(0, 137, 123)
$btnRefreshArtStatus.ForeColor = [System.Drawing.Color]::White
$btnRefreshArtStatus.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnRefreshArtStatus.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnRefreshArtStatus.Add_Click({
    Update-ArtCraftStatusUI
    Write-Log "Đã cập nhật trạng thái các ứng dụng ArtCraft Office." "CLEAN"
})
$tab5.Controls.Add($btnRefreshArtStatus); $allButtons += $btnRefreshArtStatus

$btnOpenSoftFolder = New-Object System.Windows.Forms.Button
$btnOpenSoftFolder.Text = "Mở Thư Mục Phần Mềm"
$btnOpenSoftFolder.Font = $fontBtn
$btnOpenSoftFolder.Location = New-Object System.Drawing.Point(215, 304)
$btnOpenSoftFolder.Size = New-Object System.Drawing.Size(195, 34)
$btnOpenSoftFolder.BackColor = [System.Drawing.Color]::FromArgb(69, 90, 100)
$btnOpenSoftFolder.ForeColor = [System.Drawing.Color]::White
$btnOpenSoftFolder.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnOpenSoftFolder.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnOpenSoftFolder.Add_Click({
    $dir = Join-Path $env:USERPROFILE "Downloads\BKC_Software"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.Diagnostics.Process]::Start("explorer.exe", $dir) | Out-Null
})
$tab5.Controls.Add($btnOpenSoftFolder); $allButtons += $btnOpenSoftFolder

$btnArtGitHub = New-Object System.Windows.Forms.Button
$btnArtGitHub.Text = "Trang GitHub ArtCraft (storytold)"
$btnArtGitHub.Font = $fontBtn
$btnArtGitHub.Location = New-Object System.Drawing.Point(420, 304)
$btnArtGitHub.Size = New-Object System.Drawing.Size(405, 34)
$btnArtGitHub.BackColor = [System.Drawing.Color]::FromArgb(38, 50, 56)
$btnArtGitHub.ForeColor = [System.Drawing.Color]::White
$btnArtGitHub.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnArtGitHub.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnArtGitHub.Add_Click({
    [System.Diagnostics.Process]::Start("https://github.com/storytold") | Out-Null
    Write-Log "Đã mở trang GitHub ArtCraft (storytold) trong trình duyệt." "INFO"
})
$tab5.Controls.Add($btnArtGitHub); $allButtons += $btnArtGitHub

# Khi bấm chuyển sang Tab 5 thì tự quét lại trạng thái
$tab5.Add_Enter({
    Update-ArtCraftStatusUI
})

# TAB 6: Thông Tin Tác Giả
$tab6 = New-Object System.Windows.Forms.TabPage
$tab6.Text = "6. Thông Tin"
$tab6.BackColor = [System.Drawing.Color]::White

$lblInfo = New-Object System.Windows.Forms.Label
$lblInfo.Text = "CÔNG CỤ TỐI ƯU VÀ KÍCH HOẠT BẢN QUYỀN - BKC LIC ULTIMATE EDITION`n`n" +
                "Phát triển bởi: Trần Hà (BKC)`n" +
                "Phiên bản: 3.0 Ultimate`n`n" +
                "Thông tin liên hệ:`n" +
                " - Website: lic.bachkhoapc.vn`n" +
                " - Email: bachkhoapc.vn@gmail.com`n" +
                " - Facebook: facebook.com/bachkhoapc.vn`n" +
                " - Hotline / Zalo: 0968.99.33.55`n`n" +
                "Mọi thắc mắc hoặc cần hỗ trợ, vui lòng liên hệ theo các kênh trên."
$lblInfo.Font = $fontNormal
$lblInfo.Location = New-Object System.Drawing.Point(30, 30)
$lblInfo.Size = New-Object System.Drawing.Size(400, 250)
$lblInfo.BackColor = [System.Drawing.Color]::White
$tab6.Controls.Add($lblInfo)

$lblDonate = New-Object System.Windows.Forms.Label
$lblDonate.Text = "ỦNG HỘ TÁC GIẢ (DONATE)`n" +
                  "Ngân hàng: Vietcombank (VCB)`n" +
                  "Số tài khoản: 9969699833`n" +
                  "Chủ tài khoản: TRAN THANH HA"
$lblDonate.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
$lblDonate.ForeColor = [System.Drawing.Color]::FromArgb(46, 125, 50)
$lblDonate.Location = New-Object System.Drawing.Point(430, 20)
$lblDonate.Size = New-Object System.Drawing.Size(320, 75)
$tab6.Controls.Add($lblDonate)

$pbQR = New-Object System.Windows.Forms.PictureBox
$pbQR.Location = New-Object System.Drawing.Point(430, 95)
$pbQR.Size = New-Object System.Drawing.Size(165, 165)
$pbQR.SizeMode = 'Zoom'
$pbQR.BorderStyle = 'None'
$tab6.Controls.Add($pbQR)

$tab6.Add_Enter({
    if ($pbQR.Image -eq $null) {
        try {
            $webClient = New-Object System.Net.WebClient
            $imgBytes = $webClient.DownloadData("https://img.vietqr.io/image/vcb-9969699833-qr_only.png")
            $ms = New-Object System.IO.MemoryStream($imgBytes, 0, $imgBytes.Length)
            $pbQR.Image = [System.Drawing.Image]::FromStream($ms)
        } catch { }
    }
})

# Gộp các Tab vào TabControl
$tabControl.Controls.Add($tab1)
$tabControl.Controls.Add($tab2)
$tabControl.Controls.Add($tab3)
$tabControl.Controls.Add($tab4)
$tabControl.Controls.Add($tab5)
$tabControl.Controls.Add($tab6)
$form.Controls.Add($tabControl)

# Chân trang / Footer
$lblFooter = New-Object System.Windows.Forms.Label
$lblFooter.Text = "BKC Lic - By TranHa v3.0 Ultimate • Phát triển tối ưu hóa bản quyền Windows & Microsoft Office"
$lblFooter.Font = $fontSmall
$lblFooter.ForeColor = [System.Drawing.Color]::FromArgb(120, 120, 120)
$lblFooter.Location = New-Object System.Drawing.Point(20, 715)
$lblFooter.Size = New-Object System.Drawing.Size(845, 20)
$lblFooter.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$form.Controls.Add($lblFooter)

# Tự động quét trạng thái ban đầu khi vừa mở ứng dụng
$form.Add_Shown({
    Write-Log "Chào mừng bạn đến với BKC Lic - By TranHa Ultimate Edition!" "CLEAN"
    Write-Log "Giao diện đã được chia thành các Tab, hãy chọn Tab phù hợp phía dưới." "INFO"
    Update-ArtCraftStatusUI
})

$form.ResumeLayout($false)
$form.PerformLayout()
$form.ShowDialog() | Out-Null

