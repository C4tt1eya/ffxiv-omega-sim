using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

namespace FFXIVOmegaSim
{
    internal static class Program
    {
        internal const string SimulatorArguments = "-windowed -ResX=1280 -ResY=720";

        // Kept separate from Main so tests can inspect the command without starting it.
        internal static ProcessStartInfo BuildStartInfo(string launcherDirectory)
        {
            if (String.IsNullOrWhiteSpace(launcherDirectory))
                throw new ArgumentException("The launcher directory is required.", "launcherDirectory");
            string pathRoot = Path.GetPathRoot(launcherDirectory);
            if (!Path.IsPathRooted(launcherDirectory) || pathRoot.Length <= 1 || pathRoot.EndsWith(":"))
                throw new ArgumentException("The launcher directory must be absolute.", "launcherDirectory");

            string runtimeDirectory = Path.Combine(Path.GetFullPath(launcherDirectory), "_moling_probe");
            string executable = Path.Combine(runtimeDirectory, "MPTestingCPP.exe");
            if (!File.Exists(executable))
                throw new FileNotFoundException("Simulator executable is missing.", executable);

            return new ProcessStartInfo
            {
                FileName = executable,
                WorkingDirectory = runtimeDirectory,
                Arguments = SimulatorArguments,
                UseShellExecute = false
            };
        }

        [STAThread]
        private static int Main(string[] args)
        {
            Application.EnableVisualStyles();
            bool prepareOnly = Array.Exists(args, delegate(string argument) { return argument == "--prepare-only"; });
            try
            {
                if (args.Length != 0 && !(prepareOnly && args.Length == 1))
                    throw new ArgumentException("Unknown launcher argument.");
                Cursor.Current = Cursors.WaitCursor;
                RuntimeFiles.Ensure(AppDomain.CurrentDomain.BaseDirectory);
                Cursor.Current = Cursors.Default;
                if (prepareOnly) return 0;
                ProcessStartInfo startInfo = BuildStartInfo(AppDomain.CurrentDomain.BaseDirectory);
                using (Process simulator = Process.Start(startInfo))
                {
                    if (simulator == null)
                        throw new InvalidOperationException("Windows did not return a simulator process.");
                }
                return 0;
            }
            catch (Exception error)
            {
                if (prepareOnly)
                {
                    Console.Error.WriteLine(error.Message);
                    return 1;
                }
                Cursor.Current = Cursors.Default;
                MessageBox.Show(
                    "无法启动模拟器。请完整解压下载的文件后重试。\n" +
                    "Unable to start the simulator. Extract all downloaded files and try again.\n\n" + error.Message,
                    "FFXIV Omega Simulator", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
            finally
            {
                Cursor.Current = Cursors.Default;
            }
        }
    }
}
