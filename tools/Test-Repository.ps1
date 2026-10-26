<# Static checkout checks. Does not compile, load or execute the simulator. #>
[CmdletBinding()]
param([string]$RepositoryRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepositoryRoot {
    param([string]$Path)
    $provider = $null
    $drive = $null
    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path, [ref]$provider, [ref]$drive)
    if ($null -eq $provider -or $provider.Name -cne 'FileSystem') { throw 'RepositoryRoot must use the FileSystem provider.' }
    $full = [System.IO.Path]::GetFullPath($resolved)
    $volume = [System.IO.Path]::GetPathRoot($full)
    if ($full.Length -gt $volume.Length) { return $full.TrimEnd([char[]]@('\', '/')) }
    return $full
}

function Assert-NoReparsePoint {
    param([string]$Path)
    $current = $Path
    while (-not [string]::IsNullOrEmpty($current)) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse points are not permitted: $current" }
        }
        $parent = [System.IO.Path]::GetDirectoryName($current)
        if ($parent -eq $current) { break }
        $current = $parent
    }
}

function Get-RepositoryPath {
    param([string]$Relative)
    if ([string]::IsNullOrWhiteSpace($Relative) -or [System.IO.Path]::IsPathRooted($Relative) -or
        $Relative.Contains('\') -or $Relative -match '[\x00-\x1f<>:"|?*]') { throw "Unsafe manifest path: $Relative" }
    foreach ($part in $Relative.Split('/')) {
        if ([string]::IsNullOrEmpty($part) -or $part -eq '.' -or $part -eq '..' -or $part.EndsWith('.') -or $part.EndsWith(' ') -or
            $part -match '^(?i:CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|CLOCK\$|COM[1-9]|LPT[1-9])(?:\.|$)') { throw "Unsafe manifest path: $Relative" }
    }
    $path = [System.IO.Path]::GetFullPath((Join-Path $root $Relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)))
    $prefix = $root.TrimEnd([char[]]@('\', '/')) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Manifest path escapes repository: $Relative" }
    Assert-NoReparsePoint -Path $path
    return $path
}

function Assert-RealFile {
    param([string]$Relative)
    $path = Get-RepositoryPath -Relative $Relative
    if (-not [System.IO.File]::Exists($path)) { throw "Required file is missing: $Relative" }
    $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $buffer = New-Object byte[] 128
        $count = $stream.Read($buffer, 0, $buffer.Length)
        $firstBytes = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $count)
        if ($firstBytes.StartsWith('version https://git-lfs.github.com/spec/v1', [StringComparison]::Ordinal)) {
            throw "Required file contains a Git LFS pointer instead of its content: $Relative"
        }
    }
    finally { $stream.Dispose() }
    return $path
}

function Assert-WindowsGuiExecutable {
    param([string]$Relative)
    $path = Assert-RealFile -Relative $Relative
    $stream = [System.IO.File]::OpenRead($path)
    $reader = New-Object System.IO.BinaryReader($stream)
    try {
        if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5A4D) { throw "Launcher is not a PE executable: $Relative" }
        $stream.Position = 0x3C
        $peOffset = $reader.ReadInt32()
        if ($peOffset -lt 64 -or $peOffset -gt ($stream.Length - 94)) { throw "Launcher has an invalid PE header: $Relative" }
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) { throw "Launcher has an invalid PE signature: $Relative" }
        $stream.Position = $peOffset + 20
        $optionalSize = $reader.ReadUInt16()
        if ($optionalSize -lt 70 -or ($peOffset + 24 + $optionalSize) -gt $stream.Length) { throw "Launcher has an invalid optional header: $Relative" }
        $stream.Position = $peOffset + 24
        $magic = $reader.ReadUInt16()
        if ($magic -ne 0x10B -and $magic -ne 0x20B) { throw "Launcher has an unsupported PE optional header: $Relative" }
        $stream.Position = $peOffset + 24 + 68
        if ($reader.ReadUInt16() -ne 2) { throw "Launcher must use the Windows GUI subsystem: $Relative" }
    }
    finally { $reader.Dispose(); $stream.Dispose() }
}

function Assert-PartitionedRuntimeFile {
    param($Entry)
    $parts = @($Entry.parts)
    $chunkSize = [long]33554432
    $expectedSize = [long]$Entry.size
    if ($expectedSize -le 0 -or $Entry.sha256 -cnotmatch '^[0-9a-f]{64}$' -or $parts.Count -eq 0) {
        throw "Invalid partitioned runtime entry: $($Entry.runtime_path)"
    }
    $expectedCount = [int][Math]::Ceiling($expectedSize / [double]$chunkSize)
    if ($parts.Count -ne $expectedCount) { throw "Unexpected runtime part count: $($Entry.runtime_path)" }
    $wholeHasher = [System.Security.Cryptography.SHA256]::Create()
    $buffer = New-Object byte[] (1024 * 1024)
    $totalSize = [long]0
    try {
        for ($index = 0; $index -lt $parts.Count; $index++) {
            $part = $parts[$index]
            $expectedPath = $Entry.runtime_path + '.part' + ($index + 1).ToString('000')
            $expectedPartSize = [Math]::Min($chunkSize, $expectedSize - $totalSize)
            if ($part.path -cne $expectedPath -or [long]$part.size -ne $expectedPartSize -or
                $part.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw "Invalid runtime part metadata: $expectedPath" }
            $partPath = Assert-RealFile -Relative $part.path
            $stream = [System.IO.File]::OpenRead($partPath)
            $partHasher = [System.Security.Cryptography.SHA256]::Create()
            try {
                if ($stream.Length -ne $expectedPartSize) { throw "Runtime part has an unexpected size: $($part.path)" }
                while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    $null = $partHasher.TransformBlock($buffer, 0, $read, $buffer, 0)
                    $null = $wholeHasher.TransformBlock($buffer, 0, $read, $buffer, 0)
                }
                $null = $partHasher.TransformFinalBlock((New-Object byte[] 0), 0, 0)
                $partHash = [BitConverter]::ToString($partHasher.Hash).Replace('-', '').ToLowerInvariant()
                if ($partHash -cne $part.sha256) { throw "Runtime part SHA-256 differs from the manifest: $($part.path)" }
                $totalSize += $stream.Length
            }
            finally { $partHasher.Dispose(); $stream.Dispose() }
        }
        $null = $wholeHasher.TransformFinalBlock((New-Object byte[] 0), 0, 0)
        $wholeHash = [BitConverter]::ToString($wholeHasher.Hash).Replace('-', '').ToLowerInvariant()
        if ($totalSize -ne $expectedSize -or $wholeHash -cne $Entry.sha256) {
            throw "Combined runtime parts differ from the original file: $($Entry.runtime_path)"
        }
    }
    finally { $wholeHasher.Dispose() }
    return $parts.Count
}

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = Split-Path -Parent $PSScriptRoot }
$root = Resolve-RepositoryRoot -Path $RepositoryRoot
Assert-NoReparsePoint -Path $root
if (-not [System.IO.Directory]::Exists($root)) { throw 'RepositoryRoot must be an existing directory.' }
foreach ($relative in @('launcher/Program.cs', 'launcher/RuntimeFiles.cs', 'launcher/app.manifest', 'tools/Build-Launcher.ps1', 'tools/Split-Runtime.ps1')) {
    $null = Assert-RealFile -Relative $relative
}
foreach ($relative in @('Start-Simulator.cmd', 'tools/Build-Release.ps1', 'tests/Test-BuildRelease.ps1', 'tools/Assemble-Runtime.ps1', 'tests/Test-AssembleRuntime.ps1')) {
    if (Test-Path -LiteralPath (Get-RepositoryPath -Relative $relative)) { throw "Obsolete launch or packaging workflow remains: $relative" }
}
Assert-WindowsGuiExecutable -Relative 'FFXIV-Omega-Sim.exe'

$manifestPath = Assert-RealFile -Relative 'runtime-manifest.json'
$manifest = [System.IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json -ErrorAction Stop
if ($manifest.schema_version -ne 1 -or $null -eq $manifest.files -or @($manifest.files).Count -eq 0) { throw 'Invalid runtime manifest.' }
$runtimePaths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$listedLua = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$maintainedCount = 0
$partitionedCount = 0
$partCount = 0
foreach ($entry in $manifest.files) {
    $null = Get-RepositoryPath -Relative $entry.runtime_path
    if (-not $runtimePaths.Add($entry.runtime_path)) { throw "Duplicate runtime manifest path: $($entry.runtime_path)" }
    if ([System.IO.Path]::GetExtension($entry.runtime_path) -ieq '.cmd') { throw "Runtime manifest must not include a CMD launcher: $($entry.runtime_path)" }
    if ($null -ne $entry.PSObject.Properties['parts']) {
        $partCount += Assert-PartitionedRuntimeFile -Entry $entry
        $partitionedCount++
    }
    else {
        if ([long]$entry.size -gt (100 * 1024 * 1024)) { throw "Oversized runtime file must be supplied as parts: $($entry.runtime_path)" }
        $null = Assert-RealFile -Relative $entry.runtime_path
    }
    if ($null -eq $entry.PSObject.Properties['repository_path']) { continue }
    if ($entry.repository_path -cne $entry.runtime_path) { throw "Maintained file must use its actual runtime path: $($entry.runtime_path)" }
    if ([System.IO.Path]::GetExtension($entry.runtime_path) -ieq '.lua') { $null = $listedLua.Add($entry.runtime_path) }
    $maintainedCount++
}
if ($listedLua.Count -eq 0) { throw 'Runtime manifest must identify the maintained Lua sources.' }
$scriptsRelative = '_moling_probe/MPTestingCPP/Binaries/Win64/ue4ss/Mods/MolingDelta/Scripts'
$luaFiles = @(Get-ChildItem -LiteralPath (Get-RepositoryPath -Relative $scriptsRelative) -Filter '*.lua' -File -Recurse -Force)
if ($luaFiles.Count -ne $listedLua.Count) { throw 'Working Lua file set differs from the manifest.' }
foreach ($file in $luaFiles) {
    Assert-NoReparsePoint -Path $file.FullName
    $relative = $file.FullName.Substring($root.Length + 1).Replace('\', '/')
    if (-not $listedLua.Contains($relative)) { throw "Unlisted Lua source: $relative" }
}
foreach ($relative in @(($scriptsRelative + '/config.lua'), ($scriptsRelative + '/omega/config.lua'))) {
    $text = [System.IO.File]::ReadAllText((Get-RepositoryPath -Relative $relative))
    $withoutLineComments = $text -replace '(?m)--[^\r\n]*', ''
    if ($withoutLineComments -notmatch '\bverification_script\s*=\s*false\b' -or
        $withoutLineComments -match '\bverification_script\s*=\s*true\b') { throw "Verification harness must remain disabled: $relative" }
}
$modsRelative = '_moling_probe/MPTestingCPP/Binaries/Win64/ue4ss/Mods/mods.txt'
$modsLines = @([System.IO.File]::ReadAllLines((Get-RepositoryPath -Relative $modsRelative)) | Where-Object { $_ -notmatch '^\s*(?:[;#]|$)' })
if ($modsLines.Count -ne 1 -or $modsLines[0] -notmatch '^\s*MolingDelta\s*:\s*1\s*$') { throw 'mods.txt must contain the expected MolingDelta : 1 entry.' }
$syntaxCount = 0
foreach ($directory in @('tools', 'tests')) {
    foreach ($script in @(Get-ChildItem -LiteralPath (Get-RepositoryPath -Relative $directory) -Filter '*.ps1' -File -Recurse)) {
        Assert-NoReparsePoint -Path $script.FullName
        $tokens = $null
        $parseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$parseErrors)
        if (@($parseErrors).Count -ne 0) { throw "PowerShell syntax error in $($script.Name): $($parseErrors[0].Message)" }
        $syntaxCount++
    }
}
$readmePath = Assert-RealFile -Relative 'README.md'
if ([System.IO.File]::ReadAllText($readmePath) -match '\u672c\u8f6e|\u9996\u8f6e|\u672c\u6b21|\u672c\u5730\u5ba1\u9605') { throw 'README.md contains review-session wording.' }
Write-Output ("Repository checks passed: {0} runtime entries, {1} partitioned files in {2} verified parts, {3} maintained files, {4} maintained Lua files, {5} PowerShell scripts; root launcher is Windows GUI; verification harness disabled; mods.txt enables MolingDelta." -f $runtimePaths.Count, $partitionedCount, $partCount, $maintainedCount, $listedLua.Count, $syntaxCount)
Write-Output 'Runtime parts match both their individual and combined SHA-256 hashes. Editable source and configuration hashes, compilation and simulator execution were not tested.'
