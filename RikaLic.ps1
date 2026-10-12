# Requires RunAsAdministrator
param()

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

function Get-WinIID {
    $txtLog.Text = ""; Write-Log "Đang lấy Installation ID Windows..." "INFO"
    $result = Invoke-CScript "$env:SystemRoot\System32\slmgr.vbs" "/dti"
    $iid = $result | Where-Object { $_ -match "\d{20,}" } | ForEach-Object { [regex]::match($_, "\d{20,}").Value } | Select-Object -First 1
    if ($iid) { $txtIID.Text = $iid; [System.Windows.Forms.Clipboard]::SetText($iid); Write-Log "Lấy IID thành công và đã copy vào Clipboard: $iid" "CLEAN" }
    else { Write-Log "Lỗi lấy IID. Vui lòng nạp Key trước." "WARN" }
}

function Install-WinCID {
    $cleanCID = $txtCID.Text -replace '\D', ''
    if ($cleanCID.Length -eq 48) {
        $txtCID.Text = $cleanCID; Write-Log "Đang nạp CID Windows..." "INFO"
        $result = Invoke-CScript "$env:SystemRoot\System32\slmgr.vbs" "/atp $cleanCID"
        if ($result -match "successfully" -or $result -match "thành công") { Write-Log "KÍCH HOẠT WINDOWS BY PHONE THÀNH CÔNG!" "CLEAN" }
        else { Write-Log "Nạp CID thất bại:" "CRIT"; foreach ($r in $result) { Write-Log "  $r" "WARN" } }
    } else { Write-Log "CID không hợp lệ! Phải đủ 48 số." "WARN" }
}

function Get-OfficeIID {
    $txtLog.Text = ""; Write-Log "Đang lấy Installation ID Office..." "INFO"
    $ospp = Get-OsppPath
    if (!$ospp) { Write-Log "Không tìm thấy OSPP." "WARN"; return }
    $output = Invoke-CScript $ospp "/dti"
    $joined = ($output -join " "); $iid = $null
    if ($joined -match "(\d{54}|\d{48}|\d{36}|\d{20,})") { $iid = $matches[1] }
    if ($iid) { $txtIID.Text = $iid; [System.Windows.Forms.Clipboard]::SetText($iid); Write-Log "Lấy IID thành công và đã copy vào Clipboard: $iid" "CLEAN" }
    else { Write-Log "Lỗi lấy IID Office. Hãy nạp Key trước." "WARN"; foreach ($l in $output) { Write-Log "  $l" "INFO" } }
}

function Install-OfficeCID {
    $ospp = Get-OsppPath
    if (!$ospp) { Write-Log "Không tìm thấy OSPP." "WARN"; return }
    $cleanCID = $txtCID.Text -replace '\D', ''
    if ($cleanCID.Length -eq 48) {
        $txtCID.Text = $cleanCID; Write-Log "Đang nạp CID Office..." "INFO"
        $result = Invoke-CScript $ospp "/actcid:$cleanCID"
        if ($result -match "successful" -or $result -match "thành công" -or ($result -join " ") -match "successfully") { Write-Log "KÍCH HOẠT OFFICE BY PHONE THÀNH CÔNG!" "CLEAN" }
        else { Write-Log "Nạp CID thất bại:" "CRIT"; foreach ($r in $result) { Write-Log "  $r" "WARN" } }
    } else { Write-Log "CID không hợp lệ! Phải đủ 48 số." "WARN" }
}

function Invoke-AutoWinPhone {
    Get-WinIID
    $iid = $txtIID.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($iid) -or $iid.Length -ne 63) { return }
    
    Write-Log "Đang kết nối Server Get CID tự động..." "INFO"
    try {
        $response = Invoke-WebRequest -Uri "https://khoatoantin.com/api/getcid?iid=$iid" -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        $cid = $response.Content.Trim() -replace '\D', ''
        
        if ($cid.Length -eq 48) {
            $txtCID.Text = $cid
            Write-Log "=> Đã lấy CID tự động thành công: $cid" "CLEAN"
            Install-WinCID
        } else {
            Write-Log "Server trả về lỗi hoặc Key đã vượt quá giới hạn." "WARN"
            Write-Log "Hãy copy IID và tự lấy CID trên Web, sau đó nạp thủ công." "INFO"
        }
    } catch {
        Write-Log "Không thể kết nối đến Web API Get CID." "CRIT"
    }
}

function Invoke-AutoOfficePhone {
    Get-OfficeIID
    $iid = $txtIID.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($iid) -or $iid.Length -ne 63) { return }
    
    Write-Log "Đang kết nối Server Get CID tự động..." "INFO"
    try {
        $response = Invoke-WebRequest -Uri "https://khoatoantin.com/api/getcid?iid=$iid" -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        $cid = $response.Content.Trim() -replace '\D', ''
        
        if ($cid.Length -eq 48) {
            $txtCID.Text = $cid
            Write-Log "=> Đã lấy CID tự động thành công: $cid" "CLEAN"
            Install-OfficeCID
        } else {
            Write-Log "Server trả về lỗi hoặc Key đã vượt quá giới hạn." "WARN"
            Write-Log "Hãy copy IID và tự lấy CID trên Web, sau đó nạp thủ công." "INFO"
        }
    } catch {
        Write-Log "Không thể kết nối đến Web API Get CID." "CRIT"
    }
}

function Invoke-AutoGetCID {
    $iid = $txtIID.Text.Trim()
    if (-not ($iid -match "^\d{63}$")) {
        Write-Log "IID không hợp lệ! Vui lòng Lấy IID trước (phải đủ 63 số)." "WARN"
        return
    }
    
    $txtLog.Text = ""
    Write-Log "Đang gửi yêu cầu lấy CID tự động lên máy chủ..." "INFO"
    Write-Log "Vui lòng đợi vài giây (tối đa 30s)..." "INFO"
    [System.Windows.Forms.Application]::DoEvents()
    
    try {
        # API Demo: Có thể thay thế bằng endpoint thực tế
        $apiUrl = "https://getcid.info/api/cid?iid=$iid"
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get -TimeoutSec 30 -ErrorAction Stop
        
        $cid = $null
        if ($response.cid) { $cid = $response.cid }
        elseif ($response -match "\d{48}") { $cid = $matches[0] }
        
        if ($cid -match "^\d{48}$") {
            $txtCID.Text = $cid
            Write-Log "Lấy CID tự động THÀNH CÔNG: $cid" "CLEAN"
            Write-Log "Bây giờ bạn có thể bấm Nạp CID!" "INFO"
        } else {
            Write-Log "Máy chủ không trả về CID hợp lệ hoặc IID đã bị block." "WARN"
            Write-Log "Dữ liệu trả về: $response" "INFO"
        }
    } catch {
        Write-Log "Lỗi kết nối hoặc Web API tạm thời ngưng hoạt động." "CRIT"
        Write-Log $_.Exception.Message "WARN"
        Write-Log "Vui lòng lấy CID thủ công qua Web/Call." "INFO"
    }
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

        Write-Log "Ổ đĩa vật lý:" "CLEAN"
        try {
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

$lblIID = New-Object System.Windows.Forms.Label
$lblIID.Text = "Installation ID (IID):"
$lblIID.Location = New-Object System.Drawing.Point(15, 20)
$lblIID.AutoSize = $true
$tab2.Controls.Add($lblIID)

$txtIID = New-Object System.Windows.Forms.TextBox
$txtIID.Location = New-Object System.Drawing.Point(15, 45)
$txtIID.Size = New-Object System.Drawing.Size(390, 28)
$txtIID.Font = $fontCode; $txtIID.ReadOnly = $true
$tab2.Controls.Add($txtIID)

$lblCID = New-Object System.Windows.Forms.Label
$lblCID.Text = "Confirmation ID (CID):"
$lblCID.Location = New-Object System.Drawing.Point($col2, 20)
$lblCID.AutoSize = $true
$tab2.Controls.Add($lblCID)

$txtCID = New-Object System.Windows.Forms.TextBox
$txtCID.Location = New-Object System.Drawing.Point($col2, 45)
$txtCID.Size = New-Object System.Drawing.Size(390, 28)
$txtCID.Font = $fontCode
$txtCID.Add_TextChanged({
    $clean = $txtCID.Text -replace '\D', ''
    if ($clean.Length -gt 48) { $clean = $clean.Substring(0, 48) }
    if ($txtCID.Text -ne $clean) { $pos = $txtCID.SelectionStart; $txtCID.Text = $clean; $txtCID.SelectionStart = [Math]::Min($pos, $txtCID.Text.Length) }
})
$tab2.Controls.Add($txtCID)

$btnAutoWinPhone = New-Object System.Windows.Forms.Button
$btnAutoWinPhone.Text = "Auto Active Windows (1-Click)"
$btnAutoWinPhone.Location = New-Object System.Drawing.Point(15, 90)
$btnAutoWinPhone.Size = New-Object System.Drawing.Size($btnWidth, $btnHeight)
$btnAutoWinPhone.BackColor = [System.Drawing.Color]::FromArgb(46, 125, 50); $btnAutoWinPhone.ForeColor = [System.Drawing.Color]::White; $btnAutoWinPhone.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnAutoWinPhone.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnAutoWinPhone.Add_Click({ Toggle-Buttons $false; Invoke-AutoWinPhone; Toggle-Buttons $true }); $tab2.Controls.Add($btnAutoWinPhone); $allButtons += $btnAutoWinPhone

$btnAutoOfficePhone = New-Object System.Windows.Forms.Button
$btnAutoOfficePhone.Text = "Auto Active Office (1-Click)"
$btnAutoOfficePhone.Location = New-Object System.Drawing.Point($col2, 90)
$btnAutoOfficePhone.Size = New-Object System.Drawing.Size($btnWidth, $btnHeight)
$btnAutoOfficePhone.BackColor = [System.Drawing.Color]::FromArgb(46, 125, 50); $btnAutoOfficePhone.ForeColor = [System.Drawing.Color]::White; $btnAutoOfficePhone.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnAutoOfficePhone.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnAutoOfficePhone.Add_Click({ Toggle-Buttons $false; Invoke-AutoOfficePhone; Toggle-Buttons $true }); $tab2.Controls.Add($btnAutoOfficePhone); $allButtons += $btnAutoOfficePhone

$btnGetWinIID = New-Object System.Windows.Forms.Button
$btnGetWinIID.Text = "Lấy IID Windows (Thủ công)"
$btnGetWinIID.Location = New-Object System.Drawing.Point(15, 145)
$btnGetWinIID.Size = New-Object System.Drawing.Size($btnWidth, $btnHeight)
$btnGetWinIID.BackColor = [System.Drawing.Color]::FromArgb(0, 131, 143); $btnGetWinIID.ForeColor = [System.Drawing.Color]::White; $btnGetWinIID.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnGetWinIID.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnGetWinIID.Add_Click({ Toggle-Buttons $false; Get-WinIID; Toggle-Buttons $true }); $tab2.Controls.Add($btnGetWinIID); $allButtons += $btnGetWinIID

$btnGetOfficeIID = New-Object System.Windows.Forms.Button
$btnGetOfficeIID.Text = "Lấy IID Office (Thủ công)"
$btnGetOfficeIID.Location = New-Object System.Drawing.Point($col2, 145)
$btnGetOfficeIID.Size = New-Object System.Drawing.Size($btnWidth, $btnHeight)
$btnGetOfficeIID.BackColor = [System.Drawing.Color]::FromArgb(55, 71, 79); $btnGetOfficeIID.ForeColor = [System.Drawing.Color]::White; $btnGetOfficeIID.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnGetOfficeIID.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnGetOfficeIID.Add_Click({ Toggle-Buttons $false; Get-OfficeIID; Toggle-Buttons $true }); $tab2.Controls.Add($btnGetOfficeIID); $allButtons += $btnGetOfficeIID

$btnInstallWinCID = New-Object System.Windows.Forms.Button
$btnInstallWinCID.Text = "Nạp CID Windows (Thủ công)"
$btnInstallWinCID.Location = New-Object System.Drawing.Point(15, 200)
$btnInstallWinCID.Size = New-Object System.Drawing.Size($btnWidth, $btnHeight)
$btnInstallWinCID.BackColor = [System.Drawing.Color]::FromArgb(0, 131, 143); $btnInstallWinCID.ForeColor = [System.Drawing.Color]::White; $btnInstallWinCID.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnInstallWinCID.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnInstallWinCID.Add_Click({ Toggle-Buttons $false; Install-WinCID; Toggle-Buttons $true }); $tab2.Controls.Add($btnInstallWinCID); $allButtons += $btnInstallWinCID

$btnInstallOfficeCID = New-Object System.Windows.Forms.Button
$btnInstallOfficeCID.Text = "Nạp CID Office (Thủ công)"
$btnInstallOfficeCID.Location = New-Object System.Drawing.Point($col2, 200)
$btnInstallOfficeCID.Size = New-Object System.Drawing.Size($btnWidth, $btnHeight)
$btnInstallOfficeCID.BackColor = [System.Drawing.Color]::FromArgb(55, 71, 79); $btnInstallOfficeCID.ForeColor = [System.Drawing.Color]::White; $btnInstallOfficeCID.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnInstallOfficeCID.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnInstallOfficeCID.Add_Click({ Toggle-Buttons $false; Install-OfficeCID; Toggle-Buttons $true }); $tab2.Controls.Add($btnInstallOfficeCID); $allButtons += $btnInstallOfficeCID



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
$btnRestoreTokens.Add_Click({ Toggle-Buttons $false; Invoke-RestoreTokens; Toggle-Buttons $true }); 
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



