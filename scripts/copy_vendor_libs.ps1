param([string]$OutputDir)

if (-not $OutputDir) {
    $OutputDir = "build/"
}

$odinRoot = (odin root).Trim()
$files = Get-ChildItem -Filter *.odin -Recurse
$pkgs = @()

foreach ($f in $files) {
    $content = Get-Content $f.FullName -Raw
    $foundMatches = [regex]::Matches($content, 'vendor:([a-zA-Z0-9_]+)')
    foreach ($m in $foundMatches) {
        $pkgs += $m.Groups[1].Value
    }
}
$pkgs = $pkgs | Sort-Object -Unique

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Force $OutputDir | Out-Null
}

foreach ($pkg in $pkgs) {
    $vendorPath = Join-Path $odinRoot "vendor\$pkg"
    if (Test-Path $vendorPath) {
        Write-Host "=> Checking vendor package: $pkg at $vendorPath"
        $dlls = Get-ChildItem -Path $vendorPath -Filter *.dll -Recurse
        foreach ($dll in $dlls) {
            $destPath = Join-Path $OutputDir $dll.Name
            if (-not (Test-Path $destPath)) {
                Copy-Item -Path $dll.FullName -Destination $OutputDir -Force
                Write-Host "Copied $($dll.Name) to $OutputDir"
            }
        }
    }
}
