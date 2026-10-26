using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Security.Cryptography;

namespace FFXIVOmegaSim
{
    // Only the two packaged binary files have parts. Editable scripts and settings are untouched.
    internal static class RuntimeFiles
    {
        private const int MaximumPartSize = 32 * 1024 * 1024;

        [DataContract]
        private sealed class Manifest
        {
            [DataMember(Name = "schema_version", IsRequired = true)] public int SchemaVersion { get; set; }
            [DataMember(Name = "files", IsRequired = true)] public List<RuntimeFile> Files { get; set; }
        }

        [DataContract]
        private sealed class RuntimeFile
        {
            [DataMember(Name = "runtime_path")] public string Path { get; set; }
            [DataMember(Name = "size")] public long Size { get; set; }
            [DataMember(Name = "sha256")] public string Sha256 { get; set; }
            [DataMember(Name = "parts")] public List<Part> Parts { get; set; }
        }

        [DataContract]
        private sealed class Part
        {
            [DataMember(Name = "path")] public string Path { get; set; }
            [DataMember(Name = "size")] public long Size { get; set; }
            [DataMember(Name = "sha256")] public string Sha256 { get; set; }
        }

        internal static void Ensure(string root)
        {
            using (Stream manifest = Assembly.GetExecutingAssembly().GetManifestResourceStream("RuntimeManifest"))
            {
                if (manifest == null)
                    throw new InvalidDataException("The launcher runtime manifest is missing.");
                Ensure(root, manifest);
            }
        }

        // The caller owns the input stream. This overload also permits small, synthetic fixtures.
        internal static void Ensure(string root, Stream manifest)
        {
            if (String.IsNullOrWhiteSpace(root) || !System.IO.Path.IsPathRooted(root))
                throw new ArgumentException("An absolute simulator directory is required.", "root");
            string pathRoot = System.IO.Path.GetPathRoot(root);
            if (pathRoot.Length <= 1 || pathRoot.EndsWith(":"))
                throw new ArgumentException("An absolute simulator directory is required.", "root");
            string rootPath = System.IO.Path.GetFullPath(root);
            AssertRegularPath(rootPath);
            if (!Directory.Exists(rootPath))
                throw new DirectoryNotFoundException("The simulator directory is missing: " + rootPath);
            if (manifest == null) throw new ArgumentNullException("manifest");

            Manifest data = new DataContractJsonSerializer(typeof(Manifest)).ReadObject(manifest) as Manifest;
            if (data == null || data.SchemaVersion != 1 || data.Files == null)
                throw new InvalidDataException("Unsupported runtime manifest.");

            // Validate all split-file records before creating any output.
            HashSet<string> paths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (RuntimeFile file in data.Files)
            {
                if (file == null) throw new InvalidDataException("Invalid runtime file record.");
                if (file.Parts == null) continue;
                string targetPath = ResolvePath(rootPath, file.Path);
                if (!paths.Add(targetPath)) throw new InvalidDataException("Duplicate runtime path: " + file.Path);
                ValidateHash(file.Sha256);
                if (file.Size <= 0 || file.Parts.Count == 0 || file.Parts.Count > 999)
                    throw new InvalidDataException("Invalid split-file size or part count: " + file.Path);
                long totalSize = 0;
                for (int index = 0; index < file.Parts.Count; index++)
                {
                    Part part = file.Parts[index];
                    string expected = file.Path + ".part" + (index + 1).ToString("D3", CultureInfo.InvariantCulture);
                    if (part == null || !String.Equals(part.Path, expected, StringComparison.Ordinal))
                        throw new InvalidDataException("Runtime parts must be in consecutive order: " + file.Path);
                    string partPath = ResolvePath(rootPath, part.Path);
                    if (!paths.Add(partPath)) throw new InvalidDataException("Duplicate runtime part: " + part.Path);
                    ValidateHash(part.Sha256);
                    if (part.Size <= 0 || part.Size > MaximumPartSize)
                        throw new InvalidDataException("Invalid runtime part size: " + part.Path);
                    totalSize = checked(totalSize + part.Size);
                }
                if (totalSize != file.Size)
                    throw new InvalidDataException("Runtime part sizes do not match the complete file: " + file.Path);
            }

            foreach (RuntimeFile file in data.Files)
            {
                if (file.Parts != null) EnsureFile(rootPath, file);
            }
        }

        private static void EnsureFile(string root, RuntimeFile file)
        {
            string target = ResolvePath(root, file.Path);
            AssertRegularPath(target);
            if (Directory.Exists(target))
                throw new IOException("A directory occupies the runtime file path: " + file.Path);
            if (File.Exists(target))
            {
                VerifyFile(target, file.Size, file.Sha256);
                return;
            }

            string temporary = target + "." + Guid.NewGuid().ToString("N") + ".assembling";
            bool ownsTemporary = false;
            try
            {
                AssertRegularPath(temporary);
                using (FileStream output = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                {
                    ownsTemporary = true;
                    using (SHA256 completeHash = SHA256.Create())
                    {
                        long completeSize = 0;
                        byte[] buffer = new byte[1024 * 1024];
                        foreach (Part part in file.Parts)
                        {
                            string partPath = ResolvePath(root, part.Path);
                            AssertRegularPath(partPath);
                            using (FileStream input = new FileStream(partPath, FileMode.Open, FileAccess.Read, FileShare.Read))
                            using (SHA256 partHash = SHA256.Create())
                            {
                                if (input.Length != part.Size)
                                    throw new InvalidDataException("Runtime part size does not match: " + part.Path);
                                long partSize = 0;
                                int count;
                                while ((count = input.Read(buffer, 0, buffer.Length)) != 0)
                                {
                                    partSize = checked(partSize + count);
                                    if (partSize > part.Size)
                                        throw new InvalidDataException("Runtime part changed while reading: " + part.Path);
                                    output.Write(buffer, 0, count);
                                    partHash.TransformBlock(buffer, 0, count, buffer, 0);
                                    completeHash.TransformBlock(buffer, 0, count, buffer, 0);
                                }
                                partHash.TransformFinalBlock(new byte[0], 0, 0);
                                if (partSize != part.Size || !HashMatches(partHash.Hash, part.Sha256))
                                    throw new InvalidDataException("Runtime part checksum does not match: " + part.Path);
                                completeSize = checked(completeSize + partSize);
                            }
                        }
                        completeHash.TransformFinalBlock(new byte[0], 0, 0);
                        if (completeSize != file.Size || !HashMatches(completeHash.Hash, file.Sha256))
                            throw new InvalidDataException("Runtime file checksum does not match: " + file.Path);
                    }
                    output.Flush(true);
                }

                AssertRegularPath(target);
                try
                {
                    // File.Move never replaces an existing file, including one created by another launcher.
                    File.Move(temporary, target);
                    ownsTemporary = false;
                }
                catch (IOException)
                {
                    if (!File.Exists(target)) throw;
                    VerifyFile(target, file.Size, file.Sha256);
                }
            }
            finally
            {
                if (ownsTemporary && File.Exists(temporary)) File.Delete(temporary);
            }
        }

        private static void VerifyFile(string path, long expectedSize, string expectedHash)
        {
            AssertRegularPath(path);
            using (FileStream input = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
            using (SHA256 hash = SHA256.Create())
            {
                if (input.Length != expectedSize || !HashMatches(hash.ComputeHash(input), expectedHash))
                    throw new InvalidDataException("An existing runtime file differs from the packaged version and was preserved: " + path);
            }
        }

        private static void ValidateHash(string hash)
        {
            if (hash == null || hash.Length != 64) throw new InvalidDataException("Invalid SHA-256 in runtime manifest.");
            foreach (char character in hash)
            {
                if (!((character >= '0' && character <= '9') || (character >= 'a' && character <= 'f') ||
                      (character >= 'A' && character <= 'F')))
                    throw new InvalidDataException("Invalid SHA-256 in runtime manifest.");
            }
        }

        private static bool HashMatches(byte[] actual, string expected)
        {
            return String.Equals(BitConverter.ToString(actual).Replace("-", ""), expected, StringComparison.OrdinalIgnoreCase);
        }

        private static string ResolvePath(string root, string relative)
        {
            if (String.IsNullOrWhiteSpace(relative) || System.IO.Path.IsPathRooted(relative) || relative.IndexOf('\\') >= 0)
                throw new InvalidDataException("Runtime paths must be relative and use forward slashes.");
            string[] components = relative.Split('/');
            foreach (string component in components)
            {
                if (component.Length == 0 || component == "." || component == ".." ||
                    component.EndsWith(".") || component.EndsWith(" ") || component.IndexOfAny(System.IO.Path.GetInvalidFileNameChars()) >= 0)
                    throw new InvalidDataException("Unsafe runtime path: " + relative);
                string name = component.Split('.')[0].ToUpperInvariant();
                if (component.Equals(".git", StringComparison.OrdinalIgnoreCase) ||
                    name == "CON" || name == "PRN" || name == "AUX" || name == "NUL" ||
                    name == "CONIN$" || name == "CONOUT$" || name == "CLOCK$" ||
                    (name.Length == 4 && (name.StartsWith("COM") || name.StartsWith("LPT")) && name[3] >= '1' && name[3] <= '9'))
                    throw new InvalidDataException("Unsafe runtime path: " + relative);
            }
            string prefix = root.TrimEnd(System.IO.Path.DirectorySeparatorChar, System.IO.Path.AltDirectorySeparatorChar) + System.IO.Path.DirectorySeparatorChar;
            string path = System.IO.Path.GetFullPath(System.IO.Path.Combine(prefix, relative.Replace('/', System.IO.Path.DirectorySeparatorChar)));
            if (!path.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Runtime path leaves the simulator directory: " + relative);
            AssertRegularPath(path);
            return path;
        }

        private static void AssertRegularPath(string path)
        {
            string current = System.IO.Path.GetFullPath(path);
            while (!String.IsNullOrEmpty(current))
            {
                try
                {
                    FileAttributes attributes = File.GetAttributes(current);
                    if ((attributes & FileAttributes.ReparsePoint) != 0)
                        throw new IOException("Reparse points are not accepted for runtime paths: " + current);
                }
                catch (FileNotFoundException) { }
                catch (DirectoryNotFoundException) { }
                current = System.IO.Path.GetDirectoryName(current);
            }
        }
    }
}
