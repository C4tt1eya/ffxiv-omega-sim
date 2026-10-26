<# Original synthetic launcher tests. Only the test harness runs, never the simulator or launcher entry point. #>
[CmdletBinding()]
param([switch]$KeepFixtures)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$buildTool = Join-Path $repositoryRoot 'tools/Build-Launcher.ps1'
$testRoot = [System.IO.Path]::GetFullPath((Join-Path ([System.IO.Path]::GetTempPath()) ('omega-launcher-tests-' + [Guid]::NewGuid().ToString('N'))))
$null = [System.IO.Directory]::CreateDirectory($testRoot)
$utf8 = New-Object System.Text.UTF8Encoding($false)
$script:passed = 0

function Assert-LauncherTest {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Test assertion failed: $Message" }
    $script:passed++
}

function Assert-LauncherBuildFails {
    param([string]$Root, [switch]$Force)
    $failed = $false
    try { $null = & $buildTool -RepositoryRoot $Root -Force:$Force }
    catch { $failed = $true }
    Assert-LauncherTest -Condition $failed -Message 'Unsafe or invalid builds must fail.'
}

function New-LauncherFixture {
    param([string]$Name)
    $root = Join-Path $testRoot $Name
    $source = Join-Path $root 'launcher'
    $null = [System.IO.Directory]::CreateDirectory($source)
    foreach ($name in @('Program.cs', 'RuntimeFiles.cs', 'AssemblyInfo.cs', 'app.manifest')) {
        [System.IO.File]::Copy((Join-Path $repositoryRoot ('launcher/' + $name)), (Join-Path $source $name))
    }
    [System.IO.File]::WriteAllText((Join-Path $root 'runtime-manifest.json'), '{"schema_version":1,"files":[]}', $utf8)
    return $root
}

try {
    $relativeFixture = New-LauncherFixture -Name 'relative working directory'
    $differentProcessDirectory = Join-Path $testRoot 'different process cwd'
    $null = [System.IO.Directory]::CreateDirectory($differentProcessDirectory)
    $savedLocation = Get-Location
    $savedProcessDirectory = [System.Environment]::CurrentDirectory
    try {
        Set-Location -LiteralPath $relativeFixture
        [System.Environment]::CurrentDirectory = $differentProcessDirectory
        Assert-LauncherTest -Condition ((Get-Location).Path -ne [System.Environment]::CurrentDirectory) -Message 'Fixture separates PowerShell location from process cwd.'
        $null = & $buildTool -RepositoryRoot '.'
        Assert-LauncherTest -Condition ([System.IO.File]::Exists((Join-Path $relativeFixture 'FFXIV-Omega-Sim.exe'))) -Message 'Relative RepositoryRoot resolves against PowerShell location.'
        Assert-LauncherTest -Condition (-not [System.IO.File]::Exists((Join-Path $differentProcessDirectory 'FFXIV-Omega-Sim.exe'))) -Message 'Relative builds do not write into the unrelated process cwd.'
    }
    finally {
        Set-Location -LiteralPath $savedLocation.Path
        [System.Environment]::CurrentDirectory = $savedProcessDirectory
    }
    $providerRejected = $false
    try { $null = & $buildTool -RepositoryRoot 'Env:PATH' }
    catch { $providerRejected = $_.Exception.Message -match 'FileSystem provider' }
    Assert-LauncherTest -Condition $providerRejected -Message 'Non-FileSystem RepositoryRoot values are explicitly rejected.'

    $fixture = New-LauncherFixture -Name ('repository with spaces ' + [char]0x6D4B + [char]0x8BD5)
    $null = & $buildTool -RepositoryRoot $fixture
    $builtExe = Join-Path $fixture 'FFXIV-Omega-Sim.exe'
    Assert-LauncherTest -Condition ([System.IO.File]::Exists($builtExe)) -Message 'Build creates the root launcher.'
    $initialHash = (Get-FileHash -LiteralPath $builtExe -Algorithm SHA256).Hash
    Assert-LauncherBuildFails -Root $fixture
    Assert-LauncherTest -Condition ((Get-FileHash -LiteralPath $builtExe -Algorithm SHA256).Hash -eq $initialHash) -Message 'Default build preserves existing output.'
    $null = & $buildTool -RepositoryRoot $fixture -Force
    Assert-LauncherTest -Condition ([System.IO.File]::Exists($builtExe)) -Message 'Force rebuild replaces the root launcher.'
    $preFailureHash = (Get-FileHash -LiteralPath $builtExe -Algorithm SHA256).Hash
    $originalProgram = [System.IO.File]::ReadAllText((Join-Path $fixture 'launcher/Program.cs'))
    [System.IO.File]::WriteAllText((Join-Path $fixture 'launcher/Program.cs'), 'deliberately invalid original test fixture', $utf8)
    Assert-LauncherBuildFails -Root $fixture -Force
    Assert-LauncherTest -Condition ((Get-FileHash -LiteralPath $builtExe -Algorithm SHA256).Hash -eq $preFailureHash) -Message 'Failed compilation preserves the previous launcher.'
    Assert-LauncherTest -Condition (@(Get-ChildItem -LiteralPath $fixture -Filter '.FFXIV-Omega-Sim.*.tmp.exe' -Force).Count -eq 0) -Message 'Failed builds leave no temporary executable.'
    [System.IO.File]::WriteAllText((Join-Path $fixture 'launcher/Program.cs'), $originalProgram, $utf8)

    $directoryFixture = New-LauncherFixture -Name 'output-is-directory'
    $null = [System.IO.Directory]::CreateDirectory((Join-Path $directoryFixture 'FFXIV-Omega-Sim.exe'))
    Assert-LauncherBuildFails -Root $directoryFixture -Force
    $missingFixture = New-LauncherFixture -Name 'missing-manifest'
    [System.IO.File]::Delete((Join-Path $missingFixture 'launcher/app.manifest'))
    Assert-LauncherBuildFails -Root $missingFixture
    $fileRoot = Join-Path $testRoot 'not-a-directory'
    [System.IO.File]::WriteAllText($fileRoot, 'Original test fixture.', $utf8)
    Assert-LauncherBuildFails -Root $fileRoot
    $unknownOutputFixture = New-LauncherFixture -Name 'unknown-output'
    $unknownOutput = Join-Path $unknownOutputFixture 'FFXIV-Omega-Sim.exe'
    [System.IO.File]::WriteAllText($unknownOutput, 'Original unrelated synthetic executable placeholder.', $utf8)
    Assert-LauncherBuildFails -Root $unknownOutputFixture -Force
    Assert-LauncherTest -Condition ([System.IO.File]::ReadAllText($unknownOutput) -eq 'Original unrelated synthetic executable placeholder.') -Message 'Force refuses to overwrite an unrelated file at the output path.'

    $junctionRoot = Join-Path $testRoot 'junction-source'
    $null = [System.IO.Directory]::CreateDirectory($junctionRoot)
    $junction = Join-Path $junctionRoot 'launcher'
    try {
        $null = New-Item -ItemType Junction -Path $junction -Target (Join-Path $fixture 'launcher')
        Assert-LauncherBuildFails -Root $junctionRoot
        Assert-LauncherTest -Condition ([System.IO.File]::Exists((Join-Path $fixture 'launcher/Program.cs'))) -Message 'Rejected junction build preserves the source target.'
    }
    finally {
        # Remove the junction itself, without traversing or deleting its target.
        if ([System.IO.Directory]::Exists($junction)) { [System.IO.Directory]::Delete($junction) }
    }

    $harnessPath = Join-Path $testRoot 'LauncherTests.cs'
    $harness = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Xml;
using FFXIVOmegaSim;

internal static class LauncherTests
{
    private static int count;
    private static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
        count++;
    }

    // LOAD_LIBRARY_AS_DATAFILE maps resources only and never executes the PE entry point.
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr LoadLibraryEx(string file, IntPtr reserved, uint flags);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr FindResource(IntPtr module, IntPtr name, IntPtr type);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint SizeofResource(IntPtr module, IntPtr resource);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr LoadResource(IntPtr module, IntPtr resource);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr LockResource(IntPtr resource);
    [DllImport("kernel32.dll")]
    private static extern bool FreeLibrary(IntPtr module);

    private static string ReadManifest(string executable)
    {
        IntPtr module = LoadLibraryEx(executable, IntPtr.Zero, 0x00000002);
        if (module == IntPtr.Zero) throw new Exception("Cannot map executable resources as data.");
        try
        {
            IntPtr resource = FindResource(module, new IntPtr(1), new IntPtr(24));
            if (resource == IntPtr.Zero) throw new Exception("Embedded application manifest is missing.");
            uint size = SizeofResource(module, resource);
            IntPtr data = LockResource(LoadResource(module, resource));
            if (data == IntPtr.Zero || size == 0) throw new Exception("Embedded manifest is empty.");
            byte[] bytes = new byte[size];
            Marshal.Copy(data, bytes, 0, bytes.Length);
            return Encoding.UTF8.GetString(bytes).TrimStart('\uFEFF').TrimEnd('\0');
        }
        finally { FreeLibrary(module); }
    }

    private static int Main(string[] args)
    {
        try
        {
            string testRoot = Path.GetFullPath(args[0]);
            string executable = Path.GetFullPath(args[1]);
            string launcherRoot = Path.Combine(testRoot, "launcher with spaces \u6D4B\u8BD5");
            string runtime = Path.Combine(launcherRoot, "_moling_probe");
            Directory.CreateDirectory(runtime);
            string target = Path.Combine(runtime, "MPTestingCPP.exe");
            File.WriteAllText(target, "Original synthetic placeholder. Never execute.");
            string otherDirectory = Path.Combine(testRoot, "unrelated cwd");
            Directory.CreateDirectory(otherDirectory);
            Environment.CurrentDirectory = otherDirectory;

            ProcessStartInfo info = Program.BuildStartInfo(launcherRoot);
            Check(info.FileName == target, "Target is the sibling simulator's absolute path.");
            Check(Path.IsPathRooted(info.FileName), "Target path is rooted.");
            Check(info.WorkingDirectory == runtime, "Working directory is _moling_probe, independent of caller cwd.");
            Check(info.Arguments == "-windowed -ResX=1280 -ResY=720", "Upstream flags remain unchanged.");
            Check(!info.UseShellExecute, "No command shell or file association is used.");
            Check(info.Verb == String.Empty, "No elevation verb is requested.");
            Check(!info.RedirectStandardInput && !info.RedirectStandardOutput && !info.RedirectStandardError,
                "Launcher does not hold the child alive through redirected streams.");
            Check(Program.BuildStartInfo(launcherRoot + Path.DirectorySeparatorChar).FileName == target,
                "A trailing directory separator is handled.");
            bool rejected = false;
            try { Program.BuildStartInfo("relative folder"); }
            catch (ArgumentException) { rejected = true; }
            Check(rejected, "Relative launcher directories are rejected.");
            rejected = false;
            try { Program.BuildStartInfo("C:drive-relative"); }
            catch (ArgumentException) { rejected = true; }
            Check(rejected, "Drive-relative launcher directories are rejected.");
            rejected = false;
            try { Program.BuildStartInfo("\\drive-dependent"); }
            catch (ArgumentException) { rejected = true; }
            Check(rejected, "Drive-dependent launcher directories are rejected.");
            rejected = false;
            try { Program.BuildStartInfo(" "); }
            catch (ArgumentException) { rejected = true; }
            Check(rejected, "Empty launcher directories are rejected.");
            File.Delete(target);
            rejected = false;
            try { Program.BuildStartInfo(launcherRoot); }
            catch (FileNotFoundException error) { rejected = error.FileName == target; }
            Check(rejected, "Missing targets are rejected with the expected path.");
            Directory.CreateDirectory(target);
            rejected = false;
            try { Program.BuildStartInfo(launcherRoot); }
            catch (FileNotFoundException) { rejected = true; }
            Check(rejected, "A directory cannot substitute for the target executable.");

            using (BinaryReader reader = new BinaryReader(File.OpenRead(executable)))
            {
                Check(reader.ReadUInt16() == 0x5A4D, "Launcher has a DOS PE header.");
                reader.BaseStream.Position = 0x3C;
                int peOffset = reader.ReadInt32();
                reader.BaseStream.Position = peOffset;
                Check(reader.ReadUInt32() == 0x00004550, "Launcher has a valid PE signature.");
                reader.BaseStream.Position = peOffset + 24 + 68;
                Check(reader.ReadUInt16() == 2, "PE subsystem is Windows GUI, without a console.");
            }
            XmlDocument manifest = new XmlDocument();
            manifest.XmlResolver = null;
            manifest.LoadXml(ReadManifest(executable));
            XmlNode level = manifest.SelectSingleNode("//*[local-name()='requestedExecutionLevel']");
            Check(level != null && level.Attributes["level"].Value == "asInvoker", "Embedded manifest does not request elevation.");
            Check(level.Attributes["uiAccess"].Value == "false", "Embedded manifest does not request UI access privileges.");
            FileVersionInfo version = FileVersionInfo.GetVersionInfo(executable);
            Check(version.ProductName == "FFXIV Omega Simulator", "Product name is the simulator maintenance name.");
            Check(version.FileDescription == "FFXIV Omega Simulator", "Executable title is correct.");
            Check(version.FileVersion == "0.1.0.0", "File version matches the maintained launcher release.");
            Check(version.ProductVersion == "0.1.0-alpha.1", "Product version identifies the alpha release.");
            Check(version.Comments.Contains("not the original simulator implementation"), "Metadata preserves original authorship distinction.");
            Console.WriteLine("Launcher harness checks passed: " + count + ". Simulator and launcher entry point were not executed.");
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
    $harnessExe = Join-Path $testRoot 'LauncherTests.exe'
    $compilerArguments = @('/nologo', '/target:exe', '/main:LauncherTests', '/codepage:65001', '/reference:System.Windows.Forms.dll',
        '/reference:System.Runtime.Serialization.dll', ('/out:' + $harnessExe),
        (Join-Path $repositoryRoot 'launcher/Program.cs'), (Join-Path $repositoryRoot 'launcher/RuntimeFiles.cs'), $harnessPath)
    $compilerOutput = @(& $compiler @compilerArguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw ("Test harness compilation failed.`n" + ($compilerOutput -join "`n")) }
    & $harnessExe $testRoot $builtExe
    if ($LASTEXITCODE -ne 0) { throw 'Launcher test harness failed.' }
    Write-Output ("Launcher build checks passed: {0}. The actual simulator was not executed." -f $script:passed)
}
finally {
    if ($KeepFixtures) { Write-Output "Kept fixtures: $testRoot" }
    else {
        $resolved = [System.IO.Path]::GetFullPath($testRoot)
        $tempParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        if (-not $resolved.StartsWith($tempParent, [StringComparison]::OrdinalIgnoreCase) -or
            [System.IO.Path]::GetFileName($resolved) -notmatch '^omega-launcher-tests-[0-9a-f]{32}$') {
            throw "Refusing to clean unexpected test path: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
