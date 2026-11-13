param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+([+-][0-9A-Za-z.-]+)?$')]
    [string]$Version,
    [string]$FrontendPath
)

$ErrorActionPreference = 'Stop'
$backendPath = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($FrontendPath)) {
    $FrontendPath = Join-Path $backendPath '..\inventario'
}
$frontendPath = (Resolve-Path $FrontendPath).Path
$updaterProject = Join-Path $backendPath 'tools\Updater\InventarioUpdater.csproj'
$artifactsPath = Join-Path $backendPath 'artifacts'
$releasePath = Join-Path $artifactsPath "Inventario-Actualizar-$Version.exe"

if (Test-Path $releasePath) {
    throw "Ya existe el archivo de salida: $releasePath"
}
if (-not (Test-Path (Join-Path $frontendPath 'package.json'))) {
    throw "No se encontró package.json del frontend en: $frontendPath"
}
if (-not (Test-Path $updaterProject)) {
    throw "No se encontró el proyecto del actualizador: $updaterProject"
}

New-Item -ItemType Directory -Path $artifactsPath -Force | Out-Null
$workPath = Join-Path $artifactsPath "build-$([guid]::NewGuid().ToString('N'))"
$payloadPath = Join-Path $workPath 'payload'
$publishPath = Join-Path $workPath 'publish'
$payloadZip = Join-Path $workPath 'update.zip'

function Invoke-NpmBuild {
    param(
        [string]$WorkingDirectory,
        [string[]]$Arguments
    )

    Push-Location $WorkingDirectory
    try {
        & npm.cmd @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Falló npm en $WorkingDirectory con código $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}

try {
    Write-Host 'Compilando backend...'
    Invoke-NpmBuild -WorkingDirectory $backendPath -Arguments @('run', 'build')

    Write-Host 'Compilando aplicación web de producción...'
    Invoke-NpmBuild -WorkingDirectory $frontendPath -Arguments @('run', 'build', '--', '--configuration', 'production')

    $backendDist = Join-Path $backendPath 'dist'
    $frontendBuild = Join-Path $frontendPath 'www'
    if (-not (Test-Path (Join-Path $backendDist 'server.js'))) {
        throw "No se generó el backend compilado en $backendDist"
    }
    if (-not (Test-Path (Join-Path $frontendBuild 'index.html'))) {
        throw "No se generó la aplicación web en $frontendBuild"
    }

    New-Item -ItemType Directory -Path $payloadPath | Out-Null
    $payloadBackend = Join-Path $payloadPath 'inventario-backend'
    $payloadFrontend = Join-Path $payloadPath 'inventario'
    $payloadDist = Join-Path $payloadBackend 'dist'
    $payloadWeb = Join-Path $payloadFrontend 'www'
    New-Item -ItemType Directory -Path $payloadBackend | Out-Null
    New-Item -ItemType Directory -Path $payloadFrontend | Out-Null
    New-Item -ItemType Directory -Path $payloadDist | Out-Null
    New-Item -ItemType Directory -Path $payloadWeb | Out-Null
    Copy-Item -Path (Join-Path $backendDist '*') -Destination $payloadDist -Recurse
    Copy-Item -Path (Join-Path $frontendBuild '*') -Destination $payloadWeb -Recurse
    $manifest = @{
        version = $Version
        builtAtUtc = [DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json
    [System.IO.File]::WriteAllText(
        (Join-Path $payloadPath 'release.json'),
        $manifest,
        [System.Text.UTF8Encoding]::new($false)
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $payloadPath,
        $payloadZip,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false
    )

    Write-Host 'Publicando actualizador autónomo para Windows x64...'
    & dotnet publish $updaterProject `
        --configuration Release `
        --runtime win-x64 `
        --self-contained true `
        "-p:Version=$Version" `
        "-p:UpdatePayload=$payloadZip" `
        '-p:PublishSingleFile=true' `
        '-p:IncludeNativeLibrariesForSelfExtract=true' `
        '-p:EnableCompressionInSingleFile=true' `
        --output $publishPath
    if ($LASTEXITCODE -ne 0) {
        throw "Falló dotnet publish con código $LASTEXITCODE."
    }

    $publishedExe = Join-Path $publishPath 'InventarioUpdater.exe'
    if (-not (Test-Path $publishedExe)) {
        throw "No se encontró el ejecutable publicado en $publishedExe"
    }

    & $publishedExe --verify
    if ($LASTEXITCODE -ne 0) {
        throw 'El ejecutable generado no superó la validación del paquete incluido.'
    }

    Copy-Item -Path $publishedExe -Destination $releasePath
    Write-Host ''
    Write-Host "Actualizador generado: $releasePath"
    Write-Host 'Entrega únicamente ese .exe al equipo cliente.'
}
finally {
    if (Test-Path $workPath) {
        Remove-Item -LiteralPath $workPath -Recurse -Force
    }
}
