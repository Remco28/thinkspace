# Build a release and wrap it as dist\thinkspace-windows-x64.zip (run on Windows).
#   powershell -ExecutionPolicy Bypass -File tool\package_windows.ps1
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }

$release = 'build\windows\x64\runner\Release'
$out = 'dist\thinkspace-windows-x64'
if (Test-Path dist) { Remove-Item dist -Recurse -Force }
New-Item -ItemType Directory -Path $out | Out-Null
Copy-Item "$release\*" $out -Recurse

# The Visual C++ runtime, next to the program, so a clean PC needs nothing
# installed first.
foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
  $src = Join-Path $env:SystemRoot "System32\$dll"
  if (Test-Path $src) { Copy-Item $src $out }
  else { Write-Warning "$dll was not found; the zip may need the Visual C++ runtime installed" }
}

# The fonts are under the SIL Open Font License, which asks that the licence
# text travels with them.
New-Item -ItemType Directory -Path "$out\licenses" | Out-Null
Copy-Item LICENSE "$out\licenses\Thinkspace-MIT.txt"
Copy-Item assets\fonts\OFL-*.txt "$out\licenses\"
Copy-Item packaging\windows\README-Windows.txt "$out\README.txt"

Compress-Archive -Path $out -DestinationPath dist\thinkspace-windows-x64.zip
"Built dist\thinkspace-windows-x64.zip ({0:N1} MB)" -f ((Get-Item dist\thinkspace-windows-x64.zip).Length / 1MB)
