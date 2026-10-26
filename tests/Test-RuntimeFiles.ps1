<# Synthetic split-file tests. Only our test harness and --prepare-only fixture launcher run. #>
[CmdletBinding()]
param([switch]$KeepFixtures)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$testRoot = [System.IO.Path]::GetFullPath((Join-Path ([System.IO.Path]::GetTempPath()) ('omega-runtime-tests-' + [Guid]::NewGuid().ToString('N'))))
$null = [System.IO.Directory]::CreateDirectory($testRoot)
$utf8 = New-Object System.Text.UTF8Encoding($false)
$script:passed = 0
$junction = Join-Path $testRoot 'junction-root'

function Assert-RuntimeTest {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Test assertion failed: $Message" }
    $script:passed++
}

function Get-SyntheticHash {
    param([byte[]]$Bytes)
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($algorithm.ComputeHash($Bytes)).Replace('-', '').ToLowerInvariant() }
    finally { $algorithm.Dispose() }
}

function Invoke-PrepareOnly {
    param([string]$Executable)
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $Executable
    $info.Arguments = '--prepare-only'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($info)
    try {
        if (-not $process.WaitForExit(15000)) {
            $process.Kill()
            $process.WaitForExit()
            throw 'The synthetic --prepare-only launcher did not exit without interaction.'
        }
        $null = $process.StandardOutput.ReadToEnd()
        $null = $process.StandardError.ReadToEnd()
        return $process.ExitCode
    }
    finally { $process.Dispose() }
}

try {
    $harnessPath = Join-Path $testRoot 'RuntimeFilesTests.cs'
    $harness = @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using FFXIVOmegaSim;

internal static class RuntimeFilesTests
{
    private const string Target = "_moling_probe/MPTestingCPP/Binaries/Win64/MPTestingCPP.exe";
    private static string suiteRoot;
    private static int checks;

    private sealed class Chunk
    {
        public string Path;
        public byte[] Bytes;
        public long Size;
        public string Hash;
    }

    private sealed class Record
    {
        public string Path;
        public long Size;
        public string Hash;
        public List<Chunk> Parts;
    }

    private sealed class Fixture
    {
        public string Root;
        public Record File;
        public byte[] Complete;
        public string Output { get { return Local(Root, File.Path); } }
    }

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
        checks++;
    }

    private static string Hash(byte[] bytes)
    {
        using (SHA256 algorithm = SHA256.Create())
            return BitConverter.ToString(algorithm.ComputeHash(bytes)).Replace("-", "").ToLowerInvariant();
    }

    private static string Local(string root, string relative)
    {
        return Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar));
    }

    private static void Write(string path, byte[] bytes)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path));
        File.WriteAllBytes(path, bytes);
    }

    private static byte[] Join(byte[] first, byte[] second)
    {
        byte[] result = new byte[first.Length + second.Length];
        Buffer.BlockCopy(first, 0, result, 0, first.Length);
        Buffer.BlockCopy(second, 0, result, first.Length, second.Length);
        return result;
    }

    private static Fixture CreateAt(string root)
    {
        byte[] first = Encoding.UTF8.GetBytes("Original first synthetic chunk. ");
        byte[] second = Encoding.UTF8.GetBytes("Original second synthetic chunk; never executable.");
        Fixture fixture = new Fixture {
            Root = root,
            Complete = Join(first, second),
            File = new Record { Path = Target, Parts = new List<Chunk>() }
        };
        fixture.File.Size = fixture.Complete.Length;
        fixture.File.Hash = Hash(fixture.Complete);
        byte[][] pieces = { first, second };
        for (int index = 0; index < pieces.Length; index++)
        {
            Chunk chunk = new Chunk {
                Path = Target + ".part" + (index + 1).ToString("D3", CultureInfo.InvariantCulture),
                Bytes = pieces[index], Size = pieces[index].Length, Hash = Hash(pieces[index])
            };
            fixture.File.Parts.Add(chunk);
            Write(Local(root, chunk.Path), chunk.Bytes);
        }
        return fixture;
    }

    private static Fixture Create(string name)
    {
        return CreateAt(Path.Combine(suiteRoot, name));
    }

    private static string Quote(string value)
    {
        StringBuilder json = new StringBuilder("\"");
        foreach (char character in value)
        {
            if (character == '\\' || character == '"') json.Append('\\').Append(character);
            else if (character < 32) json.Append("\\u").Append(((int)character).ToString("x4", CultureInfo.InvariantCulture));
            else json.Append(character);
        }
        return json.Append('"').ToString();
    }

    private static byte[] Manifest(params Record[] records)
    {
        StringBuilder json = new StringBuilder("{\"schema_version\":1,\"files\":[");
        for (int index = 0; index < records.Length; index++)
        {
            if (index != 0) json.Append(',');
            Record file = records[index];
            json.Append("{\"runtime_path\":").Append(Quote(file.Path))
                .Append(",\"size\":").Append(file.Size.ToString(CultureInfo.InvariantCulture))
                .Append(",\"sha256\":").Append(Quote(file.Hash));
            if (file.Parts != null)
            {
                json.Append(",\"parts\":[");
                for (int partIndex = 0; partIndex < file.Parts.Count; partIndex++)
                {
                    if (partIndex != 0) json.Append(',');
                    Chunk part = file.Parts[partIndex];
                    json.Append("{\"path\":").Append(Quote(part.Path))
                        .Append(",\"size\":").Append(part.Size.ToString(CultureInfo.InvariantCulture))
                        .Append(",\"sha256\":").Append(Quote(part.Hash)).Append('}');
                }
                json.Append(']');
            }
            json.Append('}');
        }
        return Encoding.UTF8.GetBytes(json.Append("]}").ToString());
    }

    private static void Ensure(Fixture fixture, params Record[] records)
    {
        using (MemoryStream manifest = new MemoryStream(Manifest(records)))
            RuntimeFiles.Ensure(fixture.Root, manifest);
    }

    private static HashSet<string> Inventory(string root)
    {
        return new HashSet<string>(Directory.GetFiles(root, "*", SearchOption.AllDirectories), StringComparer.OrdinalIgnoreCase);
    }

    private static void Failure(Fixture fixture, string label, Type expected, params Record[] records)
    {
        HashSet<string> before = Inventory(fixture.Root);
        Exception error = null;
        try { Ensure(fixture, records); }
        catch (Exception caught) { error = caught; }
        Check(error != null && (expected == null || expected.IsInstanceOfType(error)), label + " must fail with the expected error.");
        Check(before.SetEquals(Inventory(fixture.Root)), label + " must leave no partial output or temporary file.");
    }

    private static void InvalidPath(string name, string value)
    {
        Fixture fixture = Create(name);
        fixture.File.Path = value;
        for (int index = 0; index < fixture.File.Parts.Count; index++)
            fixture.File.Parts[index].Path = value + ".part" + (index + 1).ToString("D3", CultureInfo.InvariantCulture);
        Failure(fixture, name, typeof(InvalidDataException), fixture.File);
    }

    private static int Main(string[] args)
    {
        try
        {
            suiteRoot = Path.GetFullPath(args[0]);
            Fixture success = Create("successful concatenation with spaces \u6D4B\u8BD5");
            Ensure(success, success.File);
            Check(Hash(File.ReadAllBytes(success.Output)) == success.File.Hash, "Complete output has the original synthetic payload SHA256.");
            Check(File.ReadAllBytes(success.Output).Length == success.Complete.Length, "Complete output has the expected length.");
            Check(Inventory(success.Root).Count == 3, "Successful restoration leaves only the original parts and completed output.");
            foreach (Chunk part in success.File.Parts)
                Check(Hash(File.ReadAllBytes(Local(success.Root, part.Path))) == part.Hash, "Restoration preserves each source part.");

            Fixture reuse = Create("reuse without parts");
            Write(reuse.Output, reuse.Complete);
            foreach (Chunk part in reuse.File.Parts) File.Delete(Local(reuse.Root, part.Path));
            Ensure(reuse, reuse.File);
            Check(Hash(File.ReadAllBytes(reuse.Output)) == reuse.File.Hash, "Matching complete target is reused without parts.");
            Check(Inventory(reuse.Root).Count == 1, "Reusing a complete target creates no files.");
            using (MemoryStream owned = new MemoryStream(Manifest(reuse.File)))
            {
                RuntimeFiles.Ensure(reuse.Root, owned);
                Check(owned.CanRead, "The caller retains ownership of the manifest stream.");
            }

            Fixture changed = Create("modified target is protected");
            byte[] changedBytes = (byte[])changed.Complete.Clone();
            changedBytes[0] ^= 1;
            Write(changed.Output, changedBytes);
            Failure(changed, "Modified complete target", typeof(InvalidDataException), changed.File);
            Check(Hash(File.ReadAllBytes(changed.Output)) == Hash(changedBytes), "Existing developer changes are not overwritten.");

            Fixture missing = Create("missing part");
            File.Delete(Local(missing.Root, missing.File.Parts[1].Path));
            Failure(missing, "Missing part", typeof(FileNotFoundException), missing.File);
            Check(!File.Exists(missing.Output), "Missing parts never produce a completed output.");

            Fixture badHash = Create("part hash mismatch");
            byte[] corrupt = (byte[])badHash.File.Parts[0].Bytes.Clone();
            corrupt[0] ^= 1;
            Write(Local(badHash.Root, badHash.File.Parts[0].Path), corrupt);
            Failure(badHash, "Corrupt equal-length part", typeof(InvalidDataException), badHash.File);
            Check(!File.Exists(badHash.Output), "A corrupt part never becomes a completed output.");

            Fixture badSize = Create("part size mismatch");
            Write(Local(badSize.Root, badSize.File.Parts[0].Path), Join(badSize.File.Parts[0].Bytes, new byte[] { 42 }));
            Failure(badSize, "Wrong-sized part", typeof(InvalidDataException), badSize.File);

            Fixture finalHash = Create("complete hash mismatch");
            finalHash.File.Hash = new string('0', 64);
            Failure(finalHash, "Wrong complete-file checksum", typeof(InvalidDataException), finalHash.File);
            Check(!File.Exists(finalHash.Output), "A wrong complete hash leaves no completed output.");

            Fixture totalSize = Create("metadata total mismatch");
            totalSize.File.Size++;
            Failure(totalSize, "Inconsistent part-size total", typeof(InvalidDataException), totalSize.File);

            Fixture duplicate = Create("duplicate target records");
            Failure(duplicate, "Duplicate target records", typeof(InvalidDataException), duplicate.File, duplicate.File);
            Check(!File.Exists(duplicate.Output), "All metadata is validated before any target is written.");

            Fixture duplicateParts = Create("duplicate part record");
            Chunk first = duplicateParts.File.Parts[0];
            duplicateParts.File.Parts[1] = first;
            duplicateParts.File.Size = first.Size * 2;
            duplicateParts.File.Hash = Hash(Join(first.Bytes, first.Bytes));
            Failure(duplicateParts, "Repeated part path even with a matching aggregate checksum", typeof(InvalidDataException), duplicateParts.File);

            Fixture reversed = Create("reordered parts");
            Chunk saved = reversed.File.Parts[0];
            reversed.File.Parts[0] = reversed.File.Parts[1];
            reversed.File.Parts[1] = saved;
            reversed.File.Hash = Hash(Join(reversed.File.Parts[0].Bytes, reversed.File.Parts[1].Bytes));
            Failure(reversed, "Reordered numbered parts even with a matching aggregate checksum", typeof(InvalidDataException), reversed.File);

            Fixture gap = Create("part number gap");
            string oldPart = Local(gap.Root, gap.File.Parts[1].Path);
            gap.File.Parts[1].Path = Target + ".part003";
            File.Move(oldPart, Local(gap.Root, gap.File.Parts[1].Path));
            Failure(gap, "A gap in part numbering", typeof(InvalidDataException), gap.File);

            string outside = Path.Combine(suiteRoot, "outside-sentinel.bin");
            Fixture traversal = Create("parent path traversal");
            Write(outside, traversal.Complete);
            traversal.File.Path = "../outside-sentinel.bin";
            for (int index = 0; index < traversal.File.Parts.Count; index++)
                traversal.File.Parts[index].Path = traversal.File.Path + ".part" + (index + 1).ToString("D3", CultureInfo.InvariantCulture);
            Failure(traversal, "Parent path traversal to an existing matching target", typeof(InvalidDataException), traversal.File);
            Check(Hash(File.ReadAllBytes(outside)) == Hash(traversal.Complete), "Traversal leaves the external sentinel unchanged.");
            InvalidPath("absolute target path", outside.Replace('\\', '/'));
            InvalidPath("backslash target path", Target.Replace('/', '\\'));
            InvalidPath("reserved Windows filename", "_moling_probe/NUL/runtime.bin");
            InvalidPath("trailing dot filename", "_moling_probe/runtime.bin.");

            Fixture escapedPart = Create("part traversal");
            escapedPart.File.Parts[0].Path = "../outside-sentinel.bin";
            Failure(escapedPart, "A part path outside the target sequence", typeof(InvalidDataException), escapedPart.File);

            Fixture directoryTarget = Create("directory occupies target");
            Directory.CreateDirectory(directoryTarget.Output);
            Failure(directoryTarget, "Directory in place of a complete file", typeof(IOException), directoryTarget.File);
            Check(Directory.Exists(directoryTarget.Output), "A target directory is preserved.");

            Fixture directoryPart = Create("directory occupies part");
            string firstPart = Local(directoryPart.Root, directoryPart.File.Parts[0].Path);
            File.Delete(firstPart);
            Directory.CreateDirectory(firstPart);
            Failure(directoryPart, "Directory in place of a part", null, directoryPart.File);
            Check(Directory.Exists(firstPart), "A part directory is preserved.");

            Fixture editable = Create("editable Lua is untouched");
            string luaPath = "_moling_probe/MPTestingCPP/Binaries/Win64/ue4ss/Mods/OriginalFixture/Scripts/config.lua";
            byte[] userLua = Encoding.UTF8.GetBytes("return { user_edit = true }\n");
            Write(Local(editable.Root, luaPath), userLua);
            Record unchunked = new Record { Path = luaPath, Size = 3, Hash = Hash(new byte[] { 1, 2, 3 }) };
            Ensure(editable, editable.File, unchunked);
            Check(Hash(File.ReadAllBytes(Local(editable.Root, luaPath))) == Hash(userLua), "Restoration does not validate or overwrite editable unchunked Lua.");

            Fixture linked = CreateAt(Path.GetFullPath(args[2]));
            HashSet<string> linkedBefore = Inventory(linked.Root);
            Exception linkError = null;
            try
            {
                using (MemoryStream manifest = new MemoryStream(Manifest(linked.File)))
                    RuntimeFiles.Ensure(Path.GetFullPath(args[1]), manifest);
            }
            catch (IOException caught) { linkError = caught; }
            Check(linkError != null, "A junction root is refused.");
            Check(linkedBefore.SetEquals(Inventory(linked.Root)), "Rejecting a junction root does not write into its target.");
            Check(!File.Exists(linked.Output), "A reparse-point target receives no completed file.");

            Fixture rootArgument = Create("invalid root arguments");
            foreach (string badRoot in new string[] { "relative", "C:drive-relative", "\\drive-dependent", " " })
            {
                Exception rootError = null;
                try
                {
                    using (MemoryStream manifest = new MemoryStream(Manifest(rootArgument.File)))
                        RuntimeFiles.Ensure(badRoot, manifest);
                }
                catch (ArgumentException caught) { rootError = caught; }
                Check(rootError != null, "A non-absolute root is refused: " + badRoot);
            }
            Console.WriteLine("Runtime restoration harness checks passed: " + checks + ". Only original synthetic data was used.");
            return 0;
        }
        catch (Exception error)
        {
            Console.Error.WriteLine(error);
            return 1;
        }
    }
}
'@
    [System.IO.File]::WriteAllText($harnessPath, $harness, $utf8)
    $windowsDirectory = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Windows)
    $compiler = Join-Path $windowsDirectory 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
    if (-not [System.IO.File]::Exists($compiler)) { $compiler = Join-Path $windowsDirectory 'Microsoft.NET/Framework/v4.0.30319/csc.exe' }
    $harnessExe = Join-Path $testRoot 'RuntimeFilesTests.exe'
    $compilerArguments = @('/nologo', '/target:exe', '/main:RuntimeFilesTests', '/codepage:65001',
        '/reference:System.Runtime.Serialization.dll', ('/out:' + $harnessExe),
        (Join-Path $repositoryRoot 'launcher/RuntimeFiles.cs'), $harnessPath)
    $compilerOutput = @(& $compiler @compilerArguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw ("Runtime harness compilation failed.`n" + ($compilerOutput -join "`n")) }

    $junctionTarget = Join-Path $testRoot 'junction-target'
    $null = [System.IO.Directory]::CreateDirectory($junctionTarget)
    $null = New-Item -ItemType Junction -Path $junction -Target $junctionTarget
    & $harnessExe $testRoot $junction $junctionTarget
    if ($LASTEXITCODE -ne 0) { throw 'Runtime restoration harness failed.' }

    # Build the real launcher sources with an embedded, original synthetic manifest.
    # A literal-text .exe is deliberately not executable; --prepare-only must never launch it.
    $prepareRoot = Join-Path $testRoot 'prepare-only launcher fixture'
    $sourceRoot = Join-Path $prepareRoot 'launcher'
    $null = [System.IO.Directory]::CreateDirectory($sourceRoot)
    foreach ($name in @('Program.cs', 'RuntimeFiles.cs', 'AssemblyInfo.cs', 'app.manifest')) {
        [System.IO.File]::Copy((Join-Path $repositoryRoot ('launcher/' + $name)), (Join-Path $sourceRoot $name))
    }
    $fakeBootstrap = Join-Path $prepareRoot '_moling_probe/MPTestingCPP.exe'
    $null = [System.IO.Directory]::CreateDirectory((Split-Path -Parent $fakeBootstrap))
    $fakeBytes = $utf8.GetBytes('Original synthetic placeholder; this is not a PE executable.')
    [System.IO.File]::WriteAllBytes($fakeBootstrap, $fakeBytes)
    Assert-RuntimeTest -Condition (-not ($fakeBytes[0] -eq 0x4D -and $fakeBytes[1] -eq 0x5A)) -Message 'The simulator stand-in is literal non-PE data.'
    $targetRelative = '_moling_probe/MPTestingCPP/Binaries/Win64/MPTestingCPP.exe'
    $targetPath = Join-Path $prepareRoot $targetRelative
    $null = [System.IO.Directory]::CreateDirectory((Split-Path -Parent $targetPath))
    $first = $utf8.GetBytes('Original prepare-only fixture first half. ')
    $second = $utf8.GetBytes('Original prepare-only fixture second half.')
    [byte[]]$complete = $first + $second
    $parts = @()
    $pieces = @($first, $second)
    for ($index = 0; $index -lt $pieces.Count; $index++) {
        $relative = $targetRelative + '.part' + ($index + 1).ToString('D3')
        [System.IO.File]::WriteAllBytes((Join-Path $prepareRoot $relative), $pieces[$index])
        $parts += [ordered]@{ path = $relative; size = $pieces[$index].Length; sha256 = (Get-SyntheticHash -Bytes $pieces[$index]) }
    }
    $manifest = [ordered]@{
        schema_version = 1
        files = @(
            [ordered]@{ runtime_path = '_moling_probe/MPTestingCPP.exe'; size = $fakeBytes.Length; sha256 = (Get-SyntheticHash -Bytes $fakeBytes) },
            [ordered]@{ runtime_path = $targetRelative; size = $complete.Length; sha256 = (Get-SyntheticHash -Bytes $complete); parts = $parts }
        )
    }
    [System.IO.File]::WriteAllText((Join-Path $prepareRoot 'runtime-manifest.json'), ($manifest | ConvertTo-Json -Depth 8), $utf8)
    $null = & (Join-Path $repositoryRoot 'tools/Build-Launcher.ps1') -RepositoryRoot $prepareRoot
    $prepareExe = Join-Path $prepareRoot 'FFXIV-Omega-Sim.exe'
    Assert-RuntimeTest -Condition ((Invoke-PrepareOnly -Executable $prepareExe) -eq 0) -Message 'The real fixture launcher exits successfully with --prepare-only despite a non-executable simulator.'
    Assert-RuntimeTest -Condition ((Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash.ToLowerInvariant() -eq (Get-SyntheticHash -Bytes $complete)) -Message 'The embedded synthetic manifest restores the expected complete file.'
    Assert-RuntimeTest -Condition ((Get-FileHash -LiteralPath $fakeBootstrap -Algorithm SHA256).Hash.ToLowerInvariant() -eq (Get-SyntheticHash -Bytes $fakeBytes)) -Message 'Prepare-only preserves the literal simulator stand-in.'
    foreach ($part in $parts) { [System.IO.File]::Delete((Join-Path $prepareRoot $part.path)) }
    Assert-RuntimeTest -Condition ((Invoke-PrepareOnly -Executable $prepareExe) -eq 0) -Message 'Prepare-only reuses a valid complete file without its parts.'
    $modified = $utf8.GetBytes('Original synthetic developer change; do not overwrite.')
    [System.IO.File]::WriteAllBytes($targetPath, $modified)
    Assert-RuntimeTest -Condition ((Invoke-PrepareOnly -Executable $prepareExe) -eq 1) -Message 'Prepare-only returns an error for modified complete files without a dialog.'
    Assert-RuntimeTest -Condition ((Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash.ToLowerInvariant() -eq (Get-SyntheticHash -Bytes $modified)) -Message 'Prepare-only preserves developer-modified complete content.'
    Assert-RuntimeTest -Condition (@(Get-ChildItem -LiteralPath $prepareRoot -Recurse -File -Filter '*.assembling').Count -eq 0) -Message 'Prepare-only leaves no temporary reconstruction files.'
    Write-Output ("Prepare-only launcher checks passed: {0}. No simulator or third-party executable was run." -f $script:passed)
}
finally {
    # Remove only the junction itself before any recursive cleanup.
    if ([System.IO.Directory]::Exists($junction)) { [System.IO.Directory]::Delete($junction) }
    if ($KeepFixtures) { Write-Output "Kept fixtures: $testRoot" }
    else {
        $resolved = [System.IO.Path]::GetFullPath($testRoot)
        $tempParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        if (-not $resolved.StartsWith($tempParent, [StringComparison]::OrdinalIgnoreCase) -or
            [System.IO.Path]::GetFileName($resolved) -notmatch '^omega-runtime-tests-[0-9a-f]{32}$') {
            throw "Refusing to clean unexpected runtime test path: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
