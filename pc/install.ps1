# Installs (or updates) Foyer for PC for this Windows user.
# Run "Install Foyer.cmd" next to this file; it calls this.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$dest = Join-Path $env:LOCALAPPDATA 'Programs\Foyer'

Write-Host ''
Write-Host '  Foyer for PC' -ForegroundColor White
Write-Host '  ------------'

# close a running Foyer so its files can be replaced (your settings are kept)
Get-Process foyer -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600

New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item -Recurse -Force (Join-Path $here 'app\*') $dest
$exe = Join-Path $dest 'foyer.exe'

# Start menu and desktop shortcuts
$shell = New-Object -ComObject WScript.Shell
foreach ($dir in @([Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('Desktop'))) {
  Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $dir 'Foyer.lnk')  # the old name
  $lnk = $shell.CreateShortcut((Join-Path $dir 'Foyer TV.lnk'))
  $lnk.TargetPath = $exe
  $lnk.WorkingDirectory = $dest
  $lnk.IconLocation = "$exe,0"
  $lnk.Save()
}

# start with Windows (Foyer's own setting can turn this off later)
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'Foyer' -Value "`"$exe`"" -PropertyType String -Force | Out-Null

Write-Host "  Installed in $dest"
Write-Host '  Foyer starts by itself when you sign in to Windows.'
Write-Host ''
Start-Process $exe
