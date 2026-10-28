<#
  IAVATAR_ Neural Vice - Fase 0, recon runtime (SOLA LETTURA, non modifica nulla).
  Uso:
    1) Lancia il gioco (vedi docs/RECON.md, sezione "Test manuali"), arriva in gioco.
    2) Con il gioco APERTO:  powershell -ExecutionPolicy Bypass -File .\Get-RuntimeRecon.ps1
    3) Riporta il file docs\recon\runtime-<data>.txt
  Compatibile Windows PowerShell 5.1.
#>
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$out  = Join-Path $root ("docs\recon\runtime-{0:yyyyMMdd-HHmmss}.txt" -f (Get-Date))
function W($t) { $t | Out-File -FilePath $out -Append -Encoding utf8; $t }

W "=== IAVATAR Neural Vice runtime recon $(Get-Date -Format s)"
W "`n=== Dischi"
Get-PSDrive -PSProvider FileSystem | ForEach-Object {
  W ("{0}:  libero {1:N1} GB  /  usato {2:N1} GB" -f $_.Name, ($_.Free/1GB), ($_.Used/1GB)) }

W "`n=== GPU / driver"
Get-CimInstance Win32_VideoController | ForEach-Object { W ("{0} | DriverVersion {1}" -f $_.Name, $_.DriverVersion) }
$smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
if ($smi) { W (& nvidia-smi --query-gpu=name,driver_version,compute_cap --format=csv,noheader 2>&1 | Out-String) }

W "`n=== Unreal Engine: build registrate (voce '4.0' sospetta)"
foreach ($k in 'HKCU:\Software\Epic Games\Unreal Engine\Builds','HKLM:\SOFTWARE\EpicGames\Unreal Engine') {
  if (Test-Path $k) { W "[$k]"; Get-ItemProperty $k | Out-String | ForEach-Object { W $_ }
    Get-ChildItem $k -ErrorAction SilentlyContinue | ForEach-Object { W ("  sub: {0}  InstalledDirectory={1}" -f $_.PSChildName, (Get-ItemProperty $_.PSPath).InstalledDirectory) } } }
W "`n=== Dimensione installazioni UE"
Get-ChildItem 'C:\Program Files\Epic Games' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
  $s = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
  W ("{0,-30} {1:N1} GB" -f $_.Name, ($s/1GB)) }

W "`n=== Processo del gioco e moduli grafici caricati"
$p = Get-Process -Name ViceCity -ErrorAction SilentlyContinue
if (-not $p) { W "ViceCity.exe NON in esecuzione: avvia il gioco e rilancia lo script." }
else {
  foreach ($pr in $p) {
    W ("PID {0}  Path {1}" -f $pr.Id, $pr.Path)
    try { $cl = (Get-CimInstance Win32_Process -Filter "ProcessId=$($pr.Id)").CommandLine; W "CommandLine: $cl" } catch {}
    $pr.Modules | Where-Object { $_.ModuleName -match '^(d3d11|d3d12|D3D12Core|dxgi|nvngx.*|_nvngx|nvapi64|vulkan-1|ReShade.*|socialclub.*|gfsdk.*)\.dll$' } |
      Sort-Object ModuleName | ForEach-Object { W ("  {0,-28} {1}" -f $_.ModuleName, $_.FileName) } } }

W "`n=== Log NGX piu' recenti"
$ngx = Join-Path $env:USERPROFILE 'Documents\Rockstar Games\GTA Vice City Definitive Edition\Logs\NGX'
Get-ChildItem $ngx -Recurse -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 5 | ForEach-Object {
  W "--- $($_.FullName)"
  Select-String -Path $_.FullName -Pattern 'D3D1[12]|Vulkan|DLSS|feature|version|snippet|error' -ErrorAction SilentlyContinue |
    Select-Object -First 60 | ForEach-Object { W $_.Line } }
W "`n=== Log UE in Saved\Logs"
Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Rockstar Games\GTA Vice City Definitive Edition\Saved\Logs') -File -ErrorAction SilentlyContinue |
  ForEach-Object { W "--- $($_.Name)"; Select-String $_.FullName -Pattern 'RHI|D3D1[12]|DLSS|NGX' | Select-Object -First 40 | ForEach-Object { W $_.Line } }
W "`n=== Renderer in GameUserSettings"
Select-String (Join-Path $env:USERPROFILE 'Documents\Rockstar Games\GTA Vice City Definitive Edition\Config\WindowsNoEditor\GameUserSettings.ini') -Pattern 'Renderer=\d|RTX=\d|DLSS=\d' -AllMatches |
  ForEach-Object { $_.Matches.Value } | ForEach-Object { W $_ }
W "`nReport salvato in: $out"
