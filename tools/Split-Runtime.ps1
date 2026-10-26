<# Store oversized runtime files as 32 MiB parts. Does not execute the simulator. #>
[CmdletBinding()]
param([string]$RepositoryRoot, [switch]$UpdateManifest, [switch]$Force)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = Split-Path -Parent $PSScriptRoot }
$provider = $null
$drive = $null
$root = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RepositoryRoot, [ref]$provider, [ref]$drive)
if ($provider.Name -cne 'FileSystem') { throw 'RepositoryRoot must use the FileSystem provider.' }
$root = [System.IO.Path]::GetFullPath($root).TrimEnd('\', '/')
$prefix = $root + [System.IO.Path]::DirectorySeparatorChar
$partLimit = 32MB
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Assert-RegularPath {
    param([string]$Path)
    $current = $Path
    while (-not [string]::IsNullOrEmpty($current)) {
        if (Test-Path -LiteralPath $current) {
            if (((Get-Item -LiteralPath $current -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Reparse points are not permitted: $current"
            }
        }
        $current = [System.IO.Path]::GetDirectoryName($current)
    }
}

function Get-SafePath {
    param([string]$Relative)
    if ([string]::IsNullOrWhiteSpace($Relative) -or [System.IO.Path]::IsPathRooted($Relative) -or
        $Relative.Contains('\') -or $Relative -match '[\x00-\x1f<>:"|?*]') { throw "Unsafe runtime path: $Relative" }
    foreach ($part in $Relative.Split('/')) {
        if ([string]::IsNullOrEmpty($part) -or $part -eq '.' -or $part -eq '..' -or $part.EndsWith('.') -or $part.EndsWith(' ') -or
            $part -match '^(?i:CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|CLOCK\$|COM[1-9]|LPT[1-9])(?:\.|$)') { throw "Unsafe runtime path: $Relative" }
    }
    $path = [System.IO.Path]::GetFullPath((Join-Path $root $Relative))
    if (-not $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Runtime path escapes repository.' }
    Assert-RegularPath -Path $path
    return $path
}

function Get-Sha256 {
    param([string]$Path)
    $inputStream = [System.IO.File]::OpenRead($Path)
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($algorithm.ComputeHash($inputStream)).Replace('-', '').ToLowerInvariant() }
    finally { $algorithm.Dispose(); $inputStream.Dispose() }
}

Assert-RegularPath -Path $root
if (-not [System.IO.Directory]::Exists($root)) { throw 'RepositoryRoot must be an existing directory.' }
$manifestPath = Get-SafePath -Relative 'runtime-manifest.json'
$manifest = [System.IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
if ($manifest.schema_version -ne 1) { throw 'Unsupported runtime manifest.' }
$seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$selected = @($manifest.files | Where-Object { $_.size -gt 100MB -or $null -ne $_.PSObject.Properties['parts'] })
if ($selected.Count -eq 0) { throw 'No oversized runtime files are listed.' }
$totalParts = 0
foreach ($entry in $selected) {
    if (-not $entry.runtime_path.StartsWith('_moling_probe/', [StringComparison]::Ordinal)) { throw 'Split files must be inside _moling_probe/.' }
    if (-not $seen.Add($entry.runtime_path)) { throw 'Duplicate runtime file.' }
    $sourcePath = Get-SafePath -Relative $entry.runtime_path
    if (-not [System.IO.File]::Exists($sourcePath)) { throw "Complete runtime file is missing: $($entry.runtime_path)" }
    $length = (Get-Item -LiteralPath $sourcePath).Length
    $hash = Get-Sha256 -Path $sourcePath
    if (-not $UpdateManifest -and ($length -ne $entry.size -or $hash -cne $entry.sha256)) {
        throw "Runtime file differs from the manifest: $($entry.runtime_path). Use -UpdateManifest only for an intentional binary update."
    }
    if ($length -le 0 -or [Math]::Ceiling($length / [double]$partLimit) -gt 999) { throw 'Unsupported runtime file size.' }
    $source = [System.IO.File]::Open($sourcePath, 'Open', 'Read', 'Read')
    $parts = New-Object 'System.Collections.Generic.List[object]'
    try {
        $number = 0
        $buffer = New-Object byte[] (1MB)
        while ($source.Position -lt $source.Length) {
            $number++
            $relative = '{0}.part{1:D3}' -f $entry.runtime_path, $number
            $target = Get-SafePath -Relative $relative
            if ([System.IO.Directory]::Exists($target)) { throw "Part output is a directory: $relative" }
            $temporary = $target + '.' + [Guid]::NewGuid().ToString('N') + '.assembling'
            try {
                $output = [System.IO.File]::Open($temporary, 'CreateNew', 'Write', 'None')
                try {
                    $remaining = [Math]::Min([long]$partLimit, $source.Length - $source.Position)
                    while ($remaining -gt 0) {
                        $count = $source.Read($buffer, 0, [int][Math]::Min($remaining, $buffer.Length))
                        if ($count -le 0) { throw 'Runtime input ended unexpectedly.' }
                        $output.Write($buffer, 0, $count)
                        $remaining -= $count
                    }
                }
                finally { $output.Dispose() }
                $partHash = Get-Sha256 -Path $temporary
                $partSize = (Get-Item -LiteralPath $temporary).Length
                Assert-RegularPath -Path $target
                if ([System.IO.File]::Exists($target)) {
                    if ((Get-Sha256 -Path $target) -cne $partHash) {
                        if (-not $Force) { throw "Part already exists with different content: $relative. Review it before using -Force." }
                        [System.IO.File]::Copy($temporary, $target, $true)
                    }
                }
                else { [System.IO.File]::Move($temporary, $target) }
                $parts.Add([ordered]@{ path = $relative; size = $partSize; sha256 = $partHash })
            }
            finally { if ([System.IO.File]::Exists($temporary)) { [System.IO.File]::Delete($temporary) } }
        }
    }
    finally { $source.Dispose() }
    # Detect a source change during generation before recording new metadata.
    if ((Get-Item -LiteralPath $sourcePath).Length -ne $length -or
        (Get-Sha256 -Path $sourcePath) -cne $hash) { throw 'Runtime input changed during splitting.' }
    $entry.size = $length
    $entry.sha256 = $hash
    $entry | Add-Member -NotePropertyName parts -NotePropertyValue @($parts.ToArray()) -Force
    $totalParts += $parts.Count
    Write-Output ("Split {0}: {1} parts." -f $entry.runtime_path, $parts.Count)
}
$manifestText = ($manifest | ConvertTo-Json -Depth 12).Replace("`r`n", "`n") + "`n"
$manifestTemporary = $manifestPath + '.' + [Guid]::NewGuid().ToString('N') + '.assembling'
try {
    [System.IO.File]::WriteAllText($manifestTemporary, $manifestText, $utf8)
    Assert-RegularPath -Path $manifestPath
    [System.IO.File]::Copy($manifestTemporary, $manifestPath, $true)
}
finally { if ([System.IO.File]::Exists($manifestTemporary)) { [System.IO.File]::Delete($manifestTemporary) } }
Write-Output ("Recorded {0} parts. Complete runtime files were retained. Rebuild the launcher after changing the manifest." -f $totalParts)
