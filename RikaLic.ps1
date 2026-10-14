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
    }
    return $clean
}

function Get-WinIID {
    $txtLog.Text = ""; Write-Log "Đang lấy Installation ID Windows..." "INFO"
    $result = Invoke-CScript "$env:SystemRoot\System32\slmgr.vbs" "/dti"
    $iid = $result | Where-Object { $_ -match "\d{20,}" } | ForEach-Object { [regex]::match($_, "\d{20,}").Value } | Select-Object -First 1
    if ($iid) {
        $txtIID.Text = $iid
        [System.Windows.Forms.Clipboard]::SetText($iid)
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
    $clean = $txtIID.Text.Trim() -replace '\D', ''
    if ($clean) {
        [System.Windows.Forms.Clipboard]::SetText($clean)
        Write-Log "ĐÃ SAO CHÉP IID VÀO CLIPBOARD: $clean" "CLEAN"
    }
    Write-Log "Đang mở trang web Get CID: $name ($url)..." "INFO"
    Write-Log "HƯỚNG DẪN: Nhấn Ctrl+V để dán IID vào trang web để lấy mã CID." "CLEAN"
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
        @{ Name = "KhoaToanTin (CIDMS API)"; Url = "https://khoatoantin.com/ajax/cidms_api?iids=$iid&username=trogiup24h&password=PHO" },
        @{ Name = "GetCID.info API"; Url = "https://getcid.info/api/cid?iid=$iid" },
        @{ Name = "GetCID.win API"; Url = "https://getcid.win/api?iid=$iid" }
    )
    
    $cid = $null
    foreach ($ep in $endpoints) {
        try {
            Write-Log "Thử máy chủ: $($ep.Name)..." "INFO"
            $res = Invoke-RestMethod -Uri $ep.Url -Method Get -TimeoutSec 15 -ErrorAction Stop
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
        Write-Log "CID (48 số): $cid" "CLEAN"
        $grouped = Format-CIDGrouped $cid
        Write-Log "Dạng khối: $grouped" "INFO"
        return $true
    } else {
        Write-Log "Các Web API tự động hiện tại đang quá tải hoặc yêu cầu captcha." "WARN"
        Write-Log "-> ĐÃ TỰ ĐỘNG SAO CHÉP IID VÀO CLIPBOARD: $iid" "CLEAN"
        Write-Log "GỢI Ý: Bấm nút '🌐 Mở Web Get CID' để mở trang web lấy CID và ấn Ctrl+V!" "INFO"
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
        Open-SpecificWebCID "https://khoatoantin.com/cid" "KhoaToanTin.com"
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
   - Office : ospp.vbs /actcid:`$cid
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

# --- DÒNG 1: CHỌN ĐỐI TƯỢNG (TARGET SELECTOR) ---
$lblTarget = New-Object System.Windows.Forms.Label
$lblTarget.Text = "Đối tượng kích hoạt:"
$lblTarget.Location = New-Object System.Drawing.Point(15, 12)
$lblTarget.Font = $fontSection
$lblTarget.AutoSize = $true
$tab2.Controls.Add($lblTarget)

$rbTargetWin = New-Object System.Windows.Forms.RadioButton
$rbTargetWin.Text = "Windows (Hệ điều hành)"
$rbTargetWin.Location = New-Object System.Drawing.Point(185, 10)
$rbTargetWin.Font = $fontBtn
$rbTargetWin.AutoSize = $true
$rbTargetWin.Checked = $true
$rbTargetWin.Cursor = [System.Windows.Forms.Cursors]::Hand
$rbTargetWin.Add_CheckedChanged({
    if ($rbTargetWin.Checked) { Write-Log "Đã chọn đối tượng làm việc: Windows" "INFO" }
})
$tab2.Controls.Add($rbTargetWin)

$rbTargetOffice = New-Object System.Windows.Forms.RadioButton
$rbTargetOffice.Text = "Microsoft Office"
$rbTargetOffice.Location = New-Object System.Drawing.Point(380, 10)
$rbTargetOffice.Font = $fontBtn
$rbTargetOffice.AutoSize = $true
$rbTargetOffice.Checked = $false
$rbTargetOffice.Cursor = [System.Windows.Forms.Cursors]::Hand
$rbTargetOffice.Add_CheckedChanged({
    if ($rbTargetOffice.Checked) { Write-Log "Đã chọn đối tượng làm việc: Microsoft Office" "INFO" }
})
$tab2.Controls.Add($rbTargetOffice)

$btnCheckLicStatus = New-Object System.Windows.Forms.Button
$btnCheckLicStatus.Text = "Kiểm Tra Bản Quyền"
$btnCheckLicStatus.Location = New-Object System.Drawing.Point(610, 8)
$btnCheckLicStatus.Size = New-Object System.Drawing.Size(205, 28)
$btnCheckLicStatus.Font = $fontSmall
$btnCheckLicStatus.BackColor = [System.Drawing.Color]::FromArgb(25, 118, 210)
$btnCheckLicStatus.ForeColor = [System.Drawing.Color]::White
$btnCheckLicStatus.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCheckLicStatus.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnCheckLicStatus.Add_Click({ Toggle-Buttons $false; Check-TargetStatus; Toggle-Buttons $true })
$tab2.Controls.Add($btnCheckLicStatus); $allButtons += $btnCheckLicStatus

# --- DÒNG 2: INSTALLATION ID (IID) ---
$lblIID = New-Object System.Windows.Forms.Label
$lblIID.Text = "Installation ID (IID - Bước 2):"
$lblIID.Location = New-Object System.Drawing.Point(15, 42)
$lblIID.Font = $fontSection
$lblIID.AutoSize = $true
$tab2.Controls.Add($lblIID)

$btnCopyIID = New-Object System.Windows.Forms.Button
$btnCopyIID.Text = "Copy IID"
$btnCopyIID.Location = New-Object System.Drawing.Point(235, 40)
$btnCopyIID.Size = New-Object System.Drawing.Size(85, 24)
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
$btnCopyIIDGrouped.Text = "Copy Dạng Khối (7 số)"
$btnCopyIIDGrouped.Location = New-Object System.Drawing.Point(325, 40)
$btnCopyIIDGrouped.Size = New-Object System.Drawing.Size(160, 24)
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
$txtIID.Location = New-Object System.Drawing.Point(15, 68)
$txtIID.Size = New-Object System.Drawing.Size(585, 28)
$txtIID.Font = $fontCode
$tab2.Controls.Add($txtIID)

$btnGetIID = New-Object System.Windows.Forms.Button
$btnGetIID.Text = "Lấy IID (Installation ID)"
$btnGetIID.Location = New-Object System.Drawing.Point(610, 66)
$btnGetIID.Size = New-Object System.Drawing.Size(205, 30)
$btnGetIID.Font = $fontBtn
$btnGetIID.BackColor = [System.Drawing.Color]::FromArgb(0, 131, 143)
$btnGetIID.ForeColor = [System.Drawing.Color]::White
$btnGetIID.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnGetIID.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnGetIID.Add_Click({ Toggle-Buttons $false; Get-TargetIID; Toggle-Buttons $true })
$tab2.Controls.Add($btnGetIID); $allButtons += $btnGetIID

# --- DÒNG 3: CONFIRMATION ID (CID) ---
$lblCID = New-Object System.Windows.Forms.Label
$lblCID.Text = "Confirmation ID (CID - Bước 3 - 48 số):"
$lblCID.Location = New-Object System.Drawing.Point(15, 102)
$lblCID.Font = $fontSection
$lblCID.AutoSize = $true
$tab2.Controls.Add($lblCID)

$btnPasteCID = New-Object System.Windows.Forms.Button
$btnPasteCID.Text = "Dán CID (Paste)"
$btnPasteCID.Location = New-Object System.Drawing.Point(295, 100)
$btnPasteCID.Size = New-Object System.Drawing.Size(105, 24)
$btnPasteCID.Font = $fontSmall
$btnPasteCID.BackColor = [System.Drawing.Color]::White
$btnPasteCID.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnPasteCID.Add_Click({
    if ([System.Windows.Forms.Clipboard]::ContainsText()) {
        $clip = [System.Windows.Forms.Clipboard]::GetText()
        $clean = $clip -replace '\D', ''
        if ($clean.Length -gt 48) { $clean = $clean.Substring(0, 48) }
        $txtCID.Text = $clean
        if ($clean.Length -eq 48) {
            Write-Log "Đã dán CID hợp lệ (48 số): $clean" "CLEAN"
            $grouped = Format-CIDGrouped $clean
            Write-Log "Dạng khối: $grouped" "INFO"
        } else {
            Write-Log "Đã dán CID từ Clipboard: $clean (Lưu ý: CID cần đủ 48 số, hiện có $($clean.Length) số)" "WARN"
        }
    }
})
$tab2.Controls.Add($btnPasteCID); $allButtons += $btnPasteCID

$btnCopyCID = New-Object System.Windows.Forms.Button
$btnCopyCID.Text = "Copy CID"
$btnCopyCID.Location = New-Object System.Drawing.Point(405, 100)
$btnCopyCID.Size = New-Object System.Drawing.Size(85, 24)
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
$txtCID.Location = New-Object System.Drawing.Point(15, 128)
$txtCID.Size = New-Object System.Drawing.Size(585, 28)
$txtCID.Font = $fontCode
$txtCID.Add_TextChanged({
    $clean = $txtCID.Text -replace '\D', ''
    if ($clean.Length -gt 48) { $clean = $clean.Substring(0, 48) }
    if ($txtCID.Text -ne $clean) {
        $pos = $txtCID.SelectionStart
        $txtCID.Text = $clean
        $txtCID.SelectionStart = [Math]::Min($pos, $txtCID.Text.Length)
    }
})
$tab2.Controls.Add($txtCID)

$btnInstallCID = New-Object System.Windows.Forms.Button
$btnInstallCID.Text = "Nạp CID (Kích Hoạt)"
$btnInstallCID.Location = New-Object System.Drawing.Point(610, 126)
$btnInstallCID.Size = New-Object System.Drawing.Size(205, 30)
$btnInstallCID.Font = $fontBtn
$btnInstallCID.BackColor = [System.Drawing.Color]::FromArgb(46, 125, 50)
$btnInstallCID.ForeColor = [System.Drawing.Color]::White
$btnInstallCID.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnInstallCID.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnInstallCID.Add_Click({ Toggle-Buttons $false; Install-TargetCID; Toggle-Buttons $true })
$tab2.Controls.Add($btnInstallCID); $allButtons += $btnInstallCID

# --- DÒNG 4: CÁC NÚT HÀNH ĐỘNG GET CID & 1-CLICK ---
$btnAutoGetCID = New-Object System.Windows.Forms.Button
$btnAutoGetCID.Text = "⚡ Tự Động Get CID (API)"
$btnAutoGetCID.Location = New-Object System.Drawing.Point(15, 168)
$btnAutoGetCID.Size = New-Object System.Drawing.Size(255, 40)
$btnAutoGetCID.Font = $fontBtn
$btnAutoGetCID.BackColor = [System.Drawing.Color]::FromArgb(40, 53, 147)
$btnAutoGetCID.ForeColor = [System.Drawing.Color]::White
$btnAutoGetCID.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnAutoGetCID.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnAutoGetCID.Add_Click({ Toggle-Buttons $false; Invoke-AutoGetCIDFromIID; Toggle-Buttons $true })
$tab2.Controls.Add($btnAutoGetCID); $allButtons += $btnAutoGetCID

# Context menu cho Web Get CID
$menuWebCID = New-Object System.Windows.Forms.ContextMenuStrip
$menuWebCID.Font = $fontNormal
$menuWebCID.Items.Add("1. KhoaToanTin.com (CIDMS)").Add_Click({ Open-SpecificWebCID "https://khoatoantin.com/cid" "KhoaToanTin.com" })
$menuWebCID.Items.Add("2. TroGiup24h.com (Trợ Giúp 24h)").Add_Click({ Open-SpecificWebCID "https://trogiup24h.com/getcid" "TroGiup24h.com" })
$menuWebCID.Items.Add("3. GetCID.win (Tự động Quốc Tế)").Add_Click({ Open-SpecificWebCID "https://getcid.win" "GetCID.win" })
$menuWebCID.Items.Add("4. GetCID.info").Add_Click({ Open-SpecificWebCID "https://getcid.info" "GetCID.info" })
$menuWebCID.Items.Add("5. MSKeys.org").Add_Click({ Open-SpecificWebCID "https://mskeys.org/getcid" "MSKeys.org" })

$btnOpenWebCID = New-Object System.Windows.Forms.Button
$btnOpenWebCID.Text = "🌐 Mở Web Get CID (Trợ Giúp)"
$btnOpenWebCID.Location = New-Object System.Drawing.Point(285, 168)
$btnOpenWebCID.Size = New-Object System.Drawing.Size(255, 40)
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
$btnAuto1Click.Text = "🚀 Auto 1-Click (All-in-One)"
$btnAuto1Click.Location = New-Object System.Drawing.Point(555, 168)
$btnAuto1Click.Size = New-Object System.Drawing.Size(260, 40)
$btnAuto1Click.Font = $fontBtn
$btnAuto1Click.BackColor = [System.Drawing.Color]::FromArgb(27, 94, 32)
$btnAuto1Click.ForeColor = [System.Drawing.Color]::White
$btnAuto1Click.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnAuto1Click.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnAuto1Click.Add_Click({ Toggle-Buttons $false; Invoke-1ClickFullAutoPhone; Toggle-Buttons $true })
$tab2.Controls.Add($btnAuto1Click); $allButtons += $btnAuto1Click

# --- DÒNG 5: CÁC NÚT TIỆN ÍCH MỞ RỘNG ---
$btnSavePhone = New-Object System.Windows.Forms.Button
$btnSavePhone.Text = "💾 Lưu Key & CID Ra Desktop"
$btnSavePhone.Location = New-Object System.Drawing.Point(15, 216)
$btnSavePhone.Size = New-Object System.Drawing.Size(255, 36)
$btnSavePhone.Font = $fontBtn
$btnSavePhone.BackColor = [System.Drawing.Color]::FromArgb(69, 90, 100)
$btnSavePhone.ForeColor = [System.Drawing.Color]::White
$btnSavePhone.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnSavePhone.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnSavePhone.Add_Click({ Save-PhoneActivationBackup })
$tab2.Controls.Add($btnSavePhone); $allButtons += $btnSavePhone

$btnClearFields = New-Object System.Windows.Forms.Button
$btnClearFields.Text = "🧹 Xóa Trắng Ô Nhập (Reset)"
$btnClearFields.Location = New-Object System.Drawing.Point(285, 216)
$btnClearFields.Size = New-Object System.Drawing.Size(255, 36)
$btnClearFields.Font = $fontBtn
$btnClearFields.BackColor = [System.Drawing.Color]::FromArgb(120, 144, 156)
$btnClearFields.ForeColor = [System.Drawing.Color]::White
$btnClearFields.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnClearFields.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnClearFields.Add_Click({
    $txtIID.Text = ""
    $txtCID.Text = ""
    Write-Log "Đã xóa trắng các ô IID và CID trên Tab 2." "INFO"
})
$tab2.Controls.Add($btnClearFields); $allButtons += $btnClearFields

$btnQuickKey = New-Object System.Windows.Forms.Button
$btnQuickKey.Text = "🔑 Nạp Key Phone Mới"
$btnQuickKey.Location = New-Object System.Drawing.Point(555, 216)
$btnQuickKey.Size = New-Object System.Drawing.Size(260, 36)
$btnQuickKey.Font = $fontBtn
$btnQuickKey.BackColor = [System.Drawing.Color]::FromArgb(0, 150, 136)
$btnQuickKey.ForeColor = [System.Drawing.Color]::White
$btnQuickKey.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnQuickKey.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnQuickKey.Add_Click({ Show-QuickKeyDialog })
$tab2.Controls.Add($btnQuickKey); $allButtons += $btnQuickKey

# --- KHUNG HƯỚNG DẪN QUY TRÌNH (QUICK GUIDE) ---
$pnlGuide = New-Object System.Windows.Forms.Panel
$pnlGuide.Location = New-Object System.Drawing.Point(15, 260)
$pnlGuide.Size = New-Object System.Drawing.Size(800, 95)
$pnlGuide.BackColor = [System.Drawing.Color]::FromArgb(240, 244, 248)
$pnlGuide.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$tab2.Controls.Add($pnlGuide)

$lblGuideTitle = New-Object System.Windows.Forms.Label
$lblGuideTitle.Text = "💡 HƯỚNG DẪN QUY TRÌNH KÍCH HOẠT BY PHONE (3 BƯỚC):"
$lblGuideTitle.Location = New-Object System.Drawing.Point(10, 8)
$lblGuideTitle.Font = $fontBtn
$lblGuideTitle.ForeColor = [System.Drawing.Color]::FromArgb(21, 101, 192)
$lblGuideTitle.AutoSize = $true
$pnlGuide.Controls.Add($lblGuideTitle)

$lblGuideContent = New-Object System.Windows.Forms.Label
$lblGuideContent.Text = "• Bước 1: Chọn đối tượng (Windows/Office) -> Bấm 'Lấy IID' (hoặc 'Nạp Key Phone Mới' nếu chưa nạp Key).`r`n" +
                        "• Bước 2: Bấm '⚡ Tự Động Get CID' hoặc '🌐 Mở Web Get CID' (IID sẽ tự copy, chỉ cần ấn Ctrl+V trên trang web).`r`n" +
                        "• Bước 3: Sau khi nhận 48 số CID -> Bấm 'Nạp CID (Kích Hoạt)' và bấm '💾 Lưu Key & CID' ra Desktop để tái sử dụng."
$lblGuideContent.Location = New-Object System.Drawing.Point(10, 32)
$lblGuideContent.Size = New-Object System.Drawing.Size(775, 55)
$lblGuideContent.Font = $fontSmall
$lblGuideContent.ForeColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
$pnlGuide.Controls.Add($lblGuideContent)



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
# TAB 5: Thông Tin Tác Giả
$tab5 = New-Object System.Windows.Forms.TabPage
$tab5.Text = "5. Thông Tin"
$tab5.BackColor = [System.Drawing.Color]::White

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
$tab5.Controls.Add($lblInfo)

$lblDonate = New-Object System.Windows.Forms.Label
$lblDonate.Text = "ỦNG HỘ TÁC GIẢ (DONATE)`n" +
                  "Ngân hàng: Vietcombank (VCB)`n" +
                  "Số tài khoản: 9969699833`n" +
                  "Chủ tài khoản: TRAN THANH HA"
$lblDonate.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
$lblDonate.ForeColor = [System.Drawing.Color]::FromArgb(46, 125, 50)
$lblDonate.Location = New-Object System.Drawing.Point(430, 20)
$lblDonate.Size = New-Object System.Drawing.Size(320, 75)
$tab5.Controls.Add($lblDonate)

$pbQR = New-Object System.Windows.Forms.PictureBox
$pbQR.Location = New-Object System.Drawing.Point(430, 95)
$pbQR.Size = New-Object System.Drawing.Size(165, 165)
$pbQR.SizeMode = 'Zoom'
$pbQR.BorderStyle = 'None'
$tab5.Controls.Add($pbQR)

$tab5.Add_Enter({
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
})

$form.ResumeLayout($false)
$form.PerformLayout()
$form.ShowDialog() | Out-Null



