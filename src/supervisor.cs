using System.ComponentModel;
using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security;
using System.Threading;

namespace NtutVpn {
    public static class Supervisor {
        public static string DisplayOutput(string line) {
            // OpenConnect's Windows strftime time-zone suffix can already contain
            // replacement characters before it reaches our pipe. Rebuild only that
            // display suffix from Windows, preserving the reported local date/time.
            var match = System.Text.RegularExpressions.Regex.Match(line,
                @"^(Session authentication will expire at )([A-Za-z]{3}, \d{1,2} [A-Za-z]{3} \d{4} \d{2}:\d{2}:\d{2})(?:\s+.*)?$");
            DateTime expiry;
            if (match.Success && DateTime.TryParseExact(match.Groups[2].Value,
                "ddd, d MMM yyyy HH:mm:ss", System.Globalization.CultureInfo.InvariantCulture,
                System.Globalization.DateTimeStyles.None, out expiry)) {
                var zone = TimeZoneInfo.Local;
                string name = zone.IsDaylightSavingTime(expiry) ? zone.DaylightName : zone.StandardName;
                line = match.Groups[1].Value + match.Groups[2].Value + " " + name;
            }
            return line;
        }
        // Read without blocking the hook scripts: they may delete or rewrite the
        // file at any moment, so allow both while it is open here.
        public static string ReadShared(string path) {
            try {
                using (var stream = new System.IO.FileStream(path, System.IO.FileMode.Open, System.IO.FileAccess.Read,
                    System.IO.FileShare.ReadWrite | System.IO.FileShare.Delete))
                using (var reader = new System.IO.StreamReader(stream, System.Text.Encoding.Default, true))
                    return reader.ReadToEnd();
            } catch (System.IO.IOException) { return ""; }
            catch (UnauthorizedAccessException) { return ""; }
        }
        static readonly string[] SessionSuffixes = { "", ".started", ".cancel", ".ready", ".cleanup", ".recovering", ".error", ".command" };
        // Remove the previous session's files before starting the next one. Markers are
        // also token-checked, so a file that cannot be removed is still never trusted.
        public static void ClearSessionFiles(string stateFile) {
            foreach (string suffix in SessionSuffixes) {
                string path = stateFile + suffix;
                for (int attempt = 0; attempt < 20 && System.IO.File.Exists(path); attempt++) {
                    try { System.IO.File.Delete(path); }
                    catch (System.IO.IOException) { Thread.Sleep(100); }
                    catch (UnauthorizedAccessException) { Thread.Sleep(100); }
                }
            }
        }
        public static int Run(string exe, string hook, string routeScript, string stateFile, string user, SecureString password) {
            bool cancelled = false;
            ConsoleCancelEventHandler handler = delegate(object s, ConsoleCancelEventArgs e) {
                e.Cancel = true;
                Volatile.Write(ref cancelled, true);
            };
            Console.CancelKeyPress += handler;
            try {
                int failures = 0;
                while (failures < 3 && !Volatile.Read(ref cancelled)) {
                    // A fresh token prevents arbitrary server messages imitating hook events.
                    string token = Guid.NewGuid().ToString("N");
                    var lines = new ConcurrentQueue<string>();
                    var info = new ProcessStartInfo(exe);
                    info.UseShellExecute = false;
                    info.CreateNoWindow = false; // Share console: Ctrl+C also reaches OpenConnect.
                    info.WorkingDirectory = System.IO.Path.GetDirectoryName(exe);
                    info.EnvironmentVariables["LC_ALL"] = "C";
                    info.EnvironmentVariables["PATH"] = Environment.SystemDirectory + ";" + System.IO.Path.GetDirectoryName(exe);
                    info.EnvironmentVariables["ComSpec"] = System.IO.Path.Combine(Environment.SystemDirectory, "cmd.exe");
                    info.EnvironmentVariables.Remove("LOG2FILE");
                    info.RedirectStandardInput = true;
                    info.RedirectStandardOutput = true;
                    info.RedirectStandardError = true;
                    info.Arguments = "--protocol=gp --usergroup=gateway --user=" + user +
                        " --interface=NTUT-School-VPN-" + token.Substring(0, 12) + " --passwd-on-stdin --non-inter --reconnect-timeout=300 --script=\"" +
                        hook + "\" vpn.ntut.edu.tw";
                    info.EnvironmentVariables["NTUT_ROUTE_SCRIPT"] = routeScript;
                    info.EnvironmentVariables["NTUT_ROUTE_WORKER"] = System.IO.Path.Combine(System.IO.Path.GetDirectoryName(hook), "route-worker.js");
                    info.EnvironmentVariables["NTUT_EVENT_TOKEN"] = token;
                    info.EnvironmentVariables["NTUT_STATE_FILE"] = stateFile;
                    ClearSessionFiles(stateFile);
                    Console.WriteLine("[VPN] Starting; consecutive failures: {0}/3. Ctrl+C disconnects.", failures);
                    using (var job = new ChildJob()) using (var child = new Process()) {
                        child.StartInfo = info;
                        child.OutputDataReceived += delegate(object s, DataReceivedEventArgs e) { if(e.Data != null) lines.Enqueue(DisplayOutput(e.Data)); };
                        child.ErrorDataReceived += delegate(object s, DataReceivedEventArgs e) { if(e.Data != null) lines.Enqueue(DisplayOutput(e.Data)); };
                        bool started = false;
                        bool stable = false;
                        bool everConnected = false;
                        bool stopping = false;
                        var connected = new Stopwatch();
                        var stopWait = new Stopwatch();
                        var setupWait = new Stopwatch();
                        var exitWait = new Stopwatch();
                        bool setupFailed = false;
                        string lastState = "";
                        try {
                            child.Start(); started = true; job.Assign(child);
                            child.BeginOutputReadLine(); child.BeginErrorReadLine();
                            IntPtr ptr = Marshal.SecureStringToBSTR(password);
                            try {
                                for (int i = 0; i < password.Length; i++)
                                    child.StandardInput.Write((char)Marshal.ReadInt16(ptr, i * 2));
                                child.StandardInput.WriteLine();
                                child.StandardInput.Flush();
                            } finally {
                                Marshal.ZeroFreeBSTR(ptr);
                                child.StandardInput.Close();
                            }
                            bool exited = false;
                            while (true) {
                                string line;
                                while (lines.TryDequeue(out line)) {
                                    Console.WriteLine(line); // No raw client output is written to disk.
                                }
                                string state = ReadShared(stateFile);
                                if (state != lastState) {
                                    lastState = state;
                                    if (state.StartsWith(token + ":connected:", StringComparison.Ordinal)) {
                                        everConnected = true; connected.Restart();
                                        setupWait.Reset();
                                        Console.WriteLine("[VPN] Routing hook completed; starting stability timer.");
                                    } else if (state.StartsWith(token + ":configuring:", StringComparison.Ordinal)) {
                                        if (!setupWait.IsRunning) setupWait.Start();
                                        connected.Reset();
                                        string[] fields = state.Split(new char[] { ':' }, 4);
                                        Console.WriteLine("[VPN] Configuring routes/DNS{0}", fields.Length == 4 ? ": " + fields[3] : "...");
                                    } else if (state.StartsWith(token + ":setup-error:", StringComparison.Ordinal)) {
                                        setupFailed = true; setupWait.Reset(); connected.Reset();
                                        Console.WriteLine("[ERROR] Network configuration failed: {0}", state.Substring(token.Length + 1));
                                    } else if (state.StartsWith(token + ":recovering:", StringComparison.Ordinal) ||
                                               state.StartsWith(token + ":disconnecting:", StringComparison.Ordinal)) {
                                        connected.Reset();
                                        if (state.StartsWith(token + ":disconnecting:", StringComparison.Ordinal)) setupWait.Reset();
                                        Console.WriteLine("[VPN] Recovering or cleaning up this VPN's network configuration...");
                                    } else if (state.StartsWith(token + ":disconnected:", StringComparison.Ordinal)) {
                                        connected.Reset();
                                        Console.WriteLine("[VPN] Tunnel interrupted; OpenConnect is handling recovery.");
                                    } else if (state.StartsWith(token + ":cancelled:", StringComparison.Ordinal)) {
                                        Console.WriteLine("[VPN] Route/DNS setup skipped because this session is disconnecting.");
                                    }
                                }
                                if (connected.IsRunning && connected.Elapsed.TotalSeconds >= 60 && !stable) {
                                    failures = 0; stable = true;
                                    Console.WriteLine("[VPN] Stable for 60 seconds; failure count reset.");
                                }
                                if (setupWait.IsRunning && setupWait.Elapsed.TotalSeconds >= 120) {
                                    setupFailed = true; setupWait.Reset();
                                    Console.WriteLine("[ERROR] Route/DNS setup exceeded 120 seconds; inspect network configuration.");
                                    string lastCommand = ReadShared(stateFile + ".command");
                                    if (lastCommand.Length != 0) Console.WriteLine("[ERROR] Last routing command: " + lastCommand);
                                }
                                if (setupFailed && !child.HasExited) { child.Kill(); child.WaitForExit(); exited = true; }
                                if (exited) {
                                    bool wasStarted = ReadShared(stateFile + ".started").StartsWith(token, StringComparison.Ordinal);
                                    bool cleaned = ReadShared(stateFile + ".cleanup").StartsWith(token, StringComparison.Ordinal);
                                    if (!wasStarted || cleaned || setupFailed) break;
                                    if (!exitWait.IsRunning) exitWait.Start();
                                    if (exitWait.Elapsed.TotalSeconds >= 60) {
                                        Console.WriteLine("[WARNING] Network cleanup did not finish in 60 seconds; inspect routes/DNS."); break;
                                    }
                                    Thread.Sleep(100); continue;
                                }
                                if (child.WaitForExit(100)) { child.WaitForExit(); exited = true; continue; }
                                if (Volatile.Read(ref cancelled) && !stopping) {
                                    stopping = true; stopWait.Start();
                                    Console.WriteLine("[VPN] Waiting up to 60 seconds for OpenConnect cleanup...");
                                }
                                if (stopping && stopWait.Elapsed.TotalSeconds >= 60) {
                                    Console.WriteLine("[WARNING] Graceful exit timed out. Stopping this child only; inspect adapter/routes/DNS.");
                                    child.Kill(); child.WaitForExit(); break;
                                }
                            }
                            // Flush final decoded diagnostic lines.
                            string tail;
                            while (lines.TryDequeue(out tail)) {
                                if (!tail.StartsWith(token + ":", StringComparison.Ordinal)) Console.WriteLine(tail);
                            }
                            if (Volatile.Read(ref cancelled)) return 130;
                            if (setupFailed) return 1;
                            Console.WriteLine("[VPN] OpenConnect exited: {0}; connected event observed: {1}.", child.ExitCode, everConnected);
                            // Authentication errors, certificate failures, and hook failures are
                            // deliberately NOT replayed automatically using the saved password.
                            if (child.ExitCode != 0 && !everConnected) {
                                Console.WriteLine("[STOP] Initial connection failed. Check the error before trying again.");
                                return child.ExitCode;
                            }
                            if (!stable) failures++;
                        } finally {
                            if (started && !child.HasExited) {
                                Console.WriteLine("[WARNING] Unexpected supervisor exit. Stopping its child; network cleanup is unverified.");
                                child.Kill(); child.WaitForExit();
                            }
                        }
                    }
                    if (failures >= 3) break;
                    int delay = 5 * Math.Max(failures, 1);
                    Console.WriteLine("[VPN] Restarting in {0} seconds.", delay);
                    for (int i = 0; i < delay * 10 && !Volatile.Read(ref cancelled); i++) Thread.Sleep(100);
                }
                if (Volatile.Read(ref cancelled)) return 130;
                Console.WriteLine("[STOP] Three consecutive unstable sessions. Automatic retries stopped.");
                return 1;
            } finally { Console.CancelKeyPress -= handler; }
        }
    }
}

namespace NtutVpn {
    internal sealed class ChildJob : IDisposable {
        IntPtr handle;
        [StructLayout(LayoutKind.Sequential)] struct BasicLimits {
            public long PerProcessUserTimeLimit, PerJobUserTimeLimit;
            public uint LimitFlags;
            public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize;
            public uint ActiveProcessLimit;
            public UIntPtr Affinity;
            public uint PriorityClass, SchedulingClass;
        }
        [StructLayout(LayoutKind.Sequential)] struct IoCounters {
            public ulong ReadOperationCount, WriteOperationCount, OtherOperationCount;
            public ulong ReadTransferCount, WriteTransferCount, OtherTransferCount;
        }
        [StructLayout(LayoutKind.Sequential)] struct ExtendedLimits {
            public BasicLimits BasicLimitInformation;
            public IoCounters IoInfo;
            public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed;
        }
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        static extern IntPtr CreateJobObject(IntPtr attributes, string name);
        [DllImport("kernel32.dll", SetLastError=true)]
        static extern bool SetInformationJobObject(IntPtr job, int infoClass, IntPtr info, uint length);
        [DllImport("kernel32.dll", SetLastError=true)]
        static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
        public ChildJob() {
            handle = CreateJobObject(IntPtr.Zero, null);
            if (handle == IntPtr.Zero) throw new Win32Exception();
            var limits = new ExtendedLimits();
            limits.BasicLimitInformation.LimitFlags = 0x2000; // KILL_ON_JOB_CLOSE, only our child tree.
            int size = Marshal.SizeOf(limits);
            IntPtr ptr = Marshal.AllocHGlobal(size);
            try {
                Marshal.StructureToPtr(limits, ptr, false);
                if (!SetInformationJobObject(handle, 9, ptr, (uint)size)) throw new Win32Exception();
            } catch { Dispose(); throw; }
            finally { Marshal.FreeHGlobal(ptr); }
        }
        public void Assign(Process process) {
            if (!AssignProcessToJobObject(handle, process.Handle)) throw new Win32Exception();
        }
        public void Dispose() {
            if (handle != IntPtr.Zero) { CloseHandle(handle); handle = IntPtr.Zero; }
        }
    }
}
