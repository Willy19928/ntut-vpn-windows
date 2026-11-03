// Serialize routing work outside OpenConnect's 10-second callback deadline.
var shell = new ActiveXObject("WScript.Shell"), env = shell.Environment("Process");
var fso = new ActiveXObject("Scripting.FileSystemObject");
var token = env("NTUT_EVENT_TOKEN"), state = env("NTUT_STATE_FILE");
var route = env("NTUT_ROUTE_SCRIPT"), reason = env("reason"), lock = state + ".lock";
if (!/^[a-f0-9]{32}$/.test(token) || !state || !route || /["\r\n]/.test(route)) WScript.Quit(2);
function write(path, value) { var f = fso.CreateTextFile(path, true, true); f.Write(value); f.Close(); }
function report(value, detail) { write(state, token + ":" + value + ":" + new Date().getTime() + ":" + (detail || "")); }
var cscript = shell.ExpandEnvironmentStrings("%SystemRoot%\\System32\\cscript.exe");
var command = '"' + cscript + '" //Nologo //E:JScript "' + route + '"';
var acquired = false, start = new Date().getTime(), result = 1;
try {
    while (!acquired && new Date().getTime() - start < 120000) {
        try { fso.CreateFolder(lock); acquired = true; }
        catch (e) { WScript.Sleep(100); }
    }
    if (!acquired) throw new Error("Route worker lock timed out.");
    if (reason == "connect" && fso.FileExists(state + ".cancel")) {
        report("cancelled"); result = 0;
    } else {
        report(reason == "disconnect" ? "disconnecting" : "configuring");
        result = shell.Run(command, 0, true);
        if (reason == "disconnect") {
            if (fso.FileExists(state + ".ready")) fso.DeleteFile(state + ".ready", true);
            write(state + ".cleanup", String(result)); report("disconnected", String(result));
        } else if (result == 0 && !fso.FileExists(state + ".cancel")) {
            write(state + ".ready", token);
            report(fso.FileExists(state + ".recovering") ? "recovering" : "connected");
        } else if (fso.FileExists(state + ".cancel")) {
            report("cancelled");
        } else {
            var errorDetail = "";
            if (fso.FileExists(state + ".error")) {
                var errorFile = fso.OpenTextFile(state + ".error", 1, false, -1);
                errorDetail = errorFile.ReadAll().substring(0, 2400); errorFile.Close();
            }
            env("reason") = "disconnect";
            var cleanupResult = shell.Run(command, 0, true);
            write(state + ".cleanup", String(cleanupResult));
            report("setup-error", "route exit=" + result + "; cleanup exit=" + cleanupResult + "\r\n" + errorDetail);
        }
    }
} catch (error) {
    report("setup-error", error.message || String(error)); result = 1;
} finally {
    if (acquired && fso.FolderExists(lock)) fso.DeleteFolder(lock, false);
}
WScript.Quit(result);
