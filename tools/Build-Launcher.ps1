<# Compile the small, readable Windows launcher. No simulator process is started. #>
[CmdletBinding()]
param([string]$RepositoryRoot, [switch]$Force)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = Split-Path -Parent $PSScriptRoot }
$rootProvider = $null
$rootDrive = $null
$root = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
    $RepositoryRoot, [ref]$rootProvider, [ref]$rootDrive)
if ($rootProvider.Name -ne 'FileSystem') { throw 'RepositoryRoot must use the FileSystem provider.' }
$root = [System.IO.Path]::GetFullPath($root)

function Assert-LauncherRegularPath {
    param([string]$Path)
    $candidate = [System.IO.Path]::GetFullPath($Path)
    while (-not [string]::IsNullOrEmpty($candidate)) {
        if (Test-Path -LiteralPath $candidate) {
            $item = Get-Item -LiteralPath $candidate -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Reparse points are not accepted for launcher build paths: $candidate"
            }
        }
        $candidate = [System.IO.Path]::GetDirectoryName($candidate)
    }
}

function Assert-LauncherGeneratedOutput {
    param([string]$Path)
    $metadata = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
    if ($metadata.ProductName -ne 'FFXIV Omega Simulator' -or
        $metadata.FileDescription -ne 'FFXIV Omega Simulator' -or
        $metadata.Comments -ne 'Maintenance launcher for the upstream simulator; not the original simulator implementation.') {
        throw 'Existing output is not a recognized maintenance launcher. Review and remove it manually before building.'
    }
}

if (-not [System.IO.Directory]::Exists($root)) { throw "Repository directory is missing: $root" }
Assert-LauncherRegularPath -Path $root
$sourceDirectory = Join-Path $root 'launcher'
$sourcePaths = @((Join-Path $sourceDirectory 'Program.cs'), (Join-Path $sourceDirectory 'RuntimeFiles.cs'), (Join-Path $sourceDirectory 'AssemblyInfo.cs'))
$manifestPath = Join-Path $sourceDirectory 'app.manifest'
$runtimeManifestPath = Join-Path $root 'runtime-manifest.json'
foreach ($path in @($sourcePaths) + @($manifestPath, $runtimeManifestPath)) {
    Assert-LauncherRegularPath -Path $path
    if (-not [System.IO.File]::Exists($path)) { throw "Launcher source is missing: $path" }
}
$outputPath = Join-Path $root 'FFXIV-Omega-Sim.exe'
Assert-LauncherRegularPath -Path $outputPath
if ([System.IO.Directory]::Exists($outputPath)) { throw "Launcher output is a directory: $outputPath" }
if ([System.IO.File]::Exists($outputPath) -and -not $Force) {
    throw 'FFXIV-Omega-Sim.exe already exists. Use -Force to replace only this generated launcher.'
}
if ([System.IO.File]::Exists($outputPath)) { Assert-LauncherGeneratedOutput -Path $outputPath }

$windowsDirectory = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Windows)
$compilerCandidates = @(
    (Join-Path $windowsDirectory 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'),
    (Join-Path $windowsDirectory 'Microsoft.NET/Framework/v4.0.30319/csc.exe')
)
$compiler = @($compilerCandidates | Where-Object { [System.IO.File]::Exists($_) } | Select-Object -First 1)
if ($compiler.Count -ne 1) { throw 'The Windows .NET Framework C# compiler was not found.' }

# Compile separately so source or compiler errors preserve the previous launcher.
$temporaryOutput = Join-Path $root ('.FFXIV-Omega-Sim.' + [Guid]::NewGuid().ToString('N') + '.tmp.exe')
try {
    $compilerArguments = @(
        '/nologo', '/target:winexe', '/platform:anycpu', '/optimize+', '/debug-', '/codepage:65001',
        '/reference:System.Windows.Forms.dll', '/reference:System.Runtime.Serialization.dll',
        ('/win32manifest:' + $manifestPath), ('/resource:' + $runtimeManifestPath + ',RuntimeManifest'),
        ('/out:' + $temporaryOutput)
    ) + $sourcePaths
    $compilerOutput = @(& $compiler[0] @compilerArguments 2>&1)
    if ($LASTEXITCODE -ne 0 -or -not [System.IO.File]::Exists($temporaryOutput)) {
        throw ("Launcher compilation failed. Existing output was preserved.`n" + ($compilerOutput -join "`n"))
    }
    Assert-LauncherRegularPath -Path $outputPath
    if ([System.IO.Directory]::Exists($outputPath)) { throw "Launcher output is a directory: $outputPath" }
    if ([System.IO.File]::Exists($outputPath)) {
        if (-not $Force) { throw 'Launcher appeared during compilation. Use -Force to replace it.' }
        Assert-LauncherGeneratedOutput -Path $outputPath
        [System.IO.File]::Copy($temporaryOutput, $outputPath, $true)
    }
    else { [System.IO.File]::Move($temporaryOutput, $outputPath) }
    Write-Output "Built launcher: $outputPath"
    Write-Output 'The simulator was not started.'
}
finally {
    if ([System.IO.File]::Exists($temporaryOutput)) { [System.IO.File]::Delete($temporaryOutput) }
}
