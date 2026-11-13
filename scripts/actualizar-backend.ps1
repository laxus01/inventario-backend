#Requires -Version 5.1
<#
.SYNOPSIS
  Actualiza el backend de inventario en el equipo cliente.

.DESCRIPTION
  Script incluido en el paquete de actualizacion (zip). Al ejecutarlo:
    1. Pide la carpeta del backend (por defecto inventario-backend junto al zip).
    2. Respalda dist/, web/, prisma/ y node_modules/ en backups/.
    3. Copia los archivos nuevos desde payload/.
    4. Ejecuta `prisma migrate deploy` con el node_modules incluido.
    5. Reinicia el servicio InventarioAPI (NSSM o servicio de Windows).
    6. Verifica http://localhost:3000/health.

  Ejecutar con doble clic o desde PowerShell. Se auto-eleva a administrador.
#>

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# --- Auto-elevar a administrador ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
  ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  Write-Host 'Solicitando permisos de administrador...' -ForegroundColor Yellow
  Start-Process powershell -Verb RunAs -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`""
  )
  exit
}

$ExtractTo = Join-Path $env:TEMP ('inv-upd-' + [guid]::NewGuid().ToString('N').Substring(0, 8))

function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn2($msg){ Write-Host "  [AVISO] $msg" -ForegroundColor Yellow }
function Write-Err2($msg) { Write-Host "  [ERROR] $msg" -ForegroundColor Red }

try {
  # --- Localizar payload (carpeta junto al script) o el zip ---
  Write-Step 'Localizando paquete de actualizacion'
  $selfDir = Split-Path -Parent $PSCommandPath
  $payload = Join-Path $selfDir 'payload'
  if (-not (Test-Path $payload)) {
    $zip = Get-ChildItem -Path $selfDir -Filter '*.zip' |
           Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $zip) { throw "No se encontro la carpeta payload/ ni un .zip junto a este script en $selfDir" }
    Write-Ok "Zip: $($zip.Name)"
    Write-Step 'Extrayendo paquete'
    Expand-Archive -Path $zip.FullName -DestinationPath $ExtractTo -Force
    $payload = Join-Path $ExtractTo 'payload'
  }
  if (-not (Test-Path $payload)) { throw "El paquete no contiene la carpeta payload/" }
  Write-Ok "Payload: $payload"

  # --- Carpeta destino del backend ---
  Write-Step 'Carpeta del backend'
  $defaultDir = Join-Path $selfDir 'inventario-backend'
  $backend = Read-Host "Ruta del backend en este equipo [$defaultDir]"
  if ([string]::IsNullOrWhiteSpace($backend)) { $backend = $defaultDir }
  $backend = $backend.Trim('"').Trim()
  if (-not (Test-Path (Join-Path $backend 'package.json'))) {
    throw "No existe package.json en $backend . Verifica la ruta."
  }
  $backend = (Resolve-Path $backend).Path
  Write-Ok "Backend: $backend"

  # --- Respaldo ---
  Write-Step 'Respaldando version actual'
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $backupRoot = Join-Path $backend "backups\$stamp"
  foreach ($item in 'dist', 'web', 'prisma', 'node_modules') {
    $src = Join-Path $backend $item
    if (Test-Path $src) {
      $dst = Join-Path $backupRoot $item
      New-Item -ItemType Directory -Path (Split-Path $dst) -Force | Out-Null
      Copy-Item -Path $src -Destination $dst -Recurse -Force
      Write-Ok "Respaldado $item -> $backupRoot\$item"
    }
  }

  # --- Detener el servicio antes de reemplazar archivos ---
  Write-Step 'Deteniendo servicio InventarioAPI'
  $nssm = Join-Path $backend 'nssm.exe'
  $serviceStopped = $false
  if (Test-Path $nssm) {
    & $nssm stop InventarioAPI | Out-Null
    $serviceStopped = ($LASTEXITCODE -eq 0)
  }
  if (-not $serviceStopped) {
    try { Stop-Service -Name 'InventarioAPI' -Force -ErrorAction Stop; $serviceStopped = $true }
    catch { Write-Warn2 "No se pudo detener el servicio: $($_.Exception.Message)" }
  }
  if ($serviceStopped) { Write-Ok 'Servicio detenido' }
  else { Write-Warn2 'El servicio sigue activo; si la copia falla por archivos en uso, detengalo manualmente.' }

  # --- Copiar archivos nuevos (se reemplazan las carpetas; ya hay respaldo) ---
  Write-Step 'Copiando archivos nuevos'
  foreach ($item in 'dist', 'web', 'prisma', 'node_modules') {
    $src = Join-Path $payload $item
    $dst = Join-Path $backend $item
    if (Test-Path $src) {
      if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
      Copy-Item -Path $src -Destination $dst -Recurse -Force
      Write-Ok "$item/"
    }
  }
  foreach ($f in 'package.json', 'package-lock.json', 'actualizar-cliente.bat', 'instalar-servicio.bat') {
    $src = Join-Path $payload $f
    if (Test-Path $src) { Copy-Item $src (Join-Path $backend $f) -Force; Write-Ok $f }
  }
  if (-not (Test-Path (Join-Path $payload 'web'))) {
    Write-Warn2 'El paquete no incluye web/; la app web del cliente no cambia.'
  }
  if (-not (Test-Path (Join-Path $payload 'node_modules'))) {
    Write-Warn2 'El paquete no incluye node_modules/; se asume que el backend ya tiene dependencias.'
  }

  # --- Node.js ---
  Write-Step 'Buscando Node.js'
  $node = $null
  foreach ($cand in @(
      'C:\Program Files\nodejs\node.exe',
      'C:\Program Files (x86)\nodejs\node.exe',
      "$env:LOCALAPPDATA\Programs\nodejs\node.exe",
      "$env:APPDATA\nvm\current\node.exe")) {
    if (Test-Path $cand) { $node = $cand; break }
  }
  if (-not $node) { $node = (Get-Command node.exe -ErrorAction SilentlyContinue).Source }
  if (-not $node) { throw 'No se encontro node.exe. Instala Node.js 20+ o agrega node al PATH.' }
  Write-Ok "Node: $node"

  # --- Migraciones Prisma ---
  Write-Step 'Migraciones de base de datos'
  $envFile = Join-Path $backend '.env'
  if (-not (Test-Path $envFile)) { throw 'No existe .env en el backend. Configuralo antes de actualizar.' }
  $dbUrl = $null
  foreach ($line in Get-Content $envFile) {
    if ($line -match '^\s*DATABASE_URL\s*=\s*"?([^"]+)"?\s*$') { $dbUrl = $Matches[1]; break }
  }
  if (-not $dbUrl) { throw 'No se encontro DATABASE_URL en .env' }
  $env:DATABASE_URL = $dbUrl
  $env:PRISMA_HIDE_UPDATE_MESSAGE = '1'

  $migrationFailed = $false
  Push-Location $backend
  try {
    $prismaCli = Join-Path $backend 'node_modules\prisma\build\index.js'
    if (-not (Test-Path $prismaCli)) { throw "No existe $prismaCli" }
    & $node $prismaCli migrate deploy
    if ($LASTEXITCODE -ne 0) {
      $migrationFailed = $true
      Write-Err2 "prisma migrate deploy fallo (codigo $LASTEXITCODE). Se intentara arrancar el servicio igual."
    } else {
      Write-Ok 'Migraciones aplicadas'
    }
  } finally { Pop-Location }

  # --- Arrancar servicio ---
  Write-Step 'Arrancando servicio InventarioAPI'
  if (Test-Path $nssm) {
    & $nssm start InventarioAPI | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Ok 'Servicio arrancado con NSSM' }
    else { Write-Warn2 "nssm start devolvio codigo $LASTEXITCODE" }
  } else {
    try {
      Start-Service -Name 'InventarioAPI' -ErrorAction Stop
      Write-Ok 'Servicio arrancado'
    } catch {
      Write-Warn2 "No se pudo arrancar el servicio: $($_.Exception.Message)"
      Write-Warn2 'Arrancalo manualmente o ejecuta instalar-servicio.bat.'
    }
  }

  # --- Verificacion ---
  Write-Step 'Verificando API'
  $healthy = $false
  foreach ($i in 1..15) {
    try {
      $r = Invoke-RestMethod -Uri 'http://localhost:3000/health' -TimeoutSec 3
      if ($r.ok) { $healthy = $true; break }
    } catch { Start-Sleep -Seconds 2 }
  }
  if ($healthy) { Write-Ok 'API respondiendo en http://localhost:3000/health' }
  else { Write-Warn2 'La API no respondio aun. Revisa logs\api-err.log en el backend.' }

  Write-Step 'Actualizacion finalizada'
  if ($migrationFailed) {
    Write-Err2 'ATENCION: las migraciones fallaron. Revisa la salida de prisma arriba y logs\api-err.log.'
    Write-Host "  Respaldo en: $backupRoot" -ForegroundColor DarkGray
    exit 1
  }
  Write-Host "  Respaldo en: $backupRoot" -ForegroundColor DarkGray
  Write-Host '  Si algo falla, puedes restaurar dist/, web/, prisma/ y node_modules/' -ForegroundColor DarkGray
  Write-Host '  desde esa carpeta de respaldo.' -ForegroundColor DarkGray
} catch {
  Write-Err2 $_.Exception.Message
  Write-Host "`nEl respaldo quedo en: $backupRoot" -ForegroundColor DarkGray
  Write-Host 'Para restaurar, copia las carpetas de vuelta al backend.' -ForegroundColor DarkGray
  exit 1
} finally {
  if (Test-Path $ExtractTo) { Remove-Item $ExtractTo -Recurse -Force -ErrorAction SilentlyContinue }
}

Read-Host "`nPresiona Enter para cerrar"
