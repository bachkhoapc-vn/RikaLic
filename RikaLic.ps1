# =========================================================================
# BKC Lic Ultimate Edition - By TranHa v3.0
# =========================================================================

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


