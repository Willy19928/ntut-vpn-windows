// Serialize routing work outside OpenConnect's 10-second callback deadline.
var shell = new ActiveXObject("WScript.Shell"), env = shell.Environment("Process");
var fso = new ActiveXObject("Scripting.FileSystemObject");
var token = env("NTUT_EVENT_TOKEN"), state = env("NTUT_STATE_FILE");
var route = env("NTUT_ROUTE_SCRIPT"), reason = env("reason"), lock = state + ".lock";
if (!/^[a-f0-9]{32}$/.test(token) || !state || !route || /["\r\n]/.test(route)) WScript.Quit(2);
// State files can be briefly open in another process, so file operations retry.
function retry(action) {
    for (var i = 0; ; i++) {
        try { action(); return; }
        catch (e) { if (i >= 50) throw e; WScript.Sleep(100); }
    }
}
function writeText(path, value, unicode) { retry(function () { var f = fso.CreateTextFile(path, true, unicode); f.Write(value); f.Close(); }); }
function remove(path) { retry(function () { if (fso.FileExists(path)) fso.DeleteFile(path, true); }); }
// Marker files start with the session token; a leftover from an earlier session is ignored.
function owned(path) {
    try {
        if (!fso.FileExists(path)) return false;
        var f = fso.OpenTextFile(path, 1, false, 0), value = f.AtEndOfStream ? "" : f.ReadAll(); f.Close();
        return value.indexOf(token) == 0;
    } catch (e) { return false; }
}
function report(value, detail) { writeText(state, token + ":" + value + ":" + new Date().getTime() + ":" + (detail || ""), true); }
var cscript = shell.ExpandEnvironmentStrings("%SystemRoot%\\System32\\cscript.exe");
var command = '"' + cscript + '" //Nologo //E:JScript "' + route + '"';
var acquired = false, start = new Date().getTime(), result = 1;
try {
    while (!acquired && new Date().getTime() - start < 120000) {
        try { fso.CreateFolder(lock); acquired = true; }
        catch (e) { WScript.Sleep(100); }
    }
    if (!acquired) throw new Error("Route worker lock timed out.");
    if (reason == "connect" && owned(state + ".cancel")) {
        report("cancelled"); result = 0;
    } else {
        report(reason == "disconnect" ? "disconnecting" : "configuring");
        result = shell.Run(command, 0, true);
        if (reason == "disconnect") {
            remove(state + ".ready");
            writeText(state + ".cleanup", token + ":" + result, false); report("disconnected", String(result));
        } else if (result == 0 && !owned(state + ".cancel")) {
            writeText(state + ".ready", token, false);
            report(owned(state + ".recovering") ? "recovering" : "connected");
        } else if (owned(state + ".cancel")) {
            report("cancelled");
        } else {
            var errorDetail = "";
            if (fso.FileExists(state + ".error")) {
                var errorFile = fso.OpenTextFile(state + ".error", 1, false, -1);
                errorDetail = errorFile.ReadAll().substring(0, 2400); errorFile.Close();
            }
            env("reason") = "disconnect";
            var cleanupResult = shell.Run(command, 0, true);
            writeText(state + ".cleanup", token + ":" + cleanupResult, false);
            report("setup-error", "route exit=" + result + "; cleanup exit=" + cleanupResult + "\r\n" + errorDetail);
        }
    }
} catch (error) {
    try { report("setup-error", error.message || String(error)); } catch (ignored) { }
    result = 1;
} finally {
    if (acquired && fso.FolderExists(lock)) fso.DeleteFolder(lock, false);
}
WScript.Quit(result);
