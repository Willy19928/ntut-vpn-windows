// Return promptly to OpenConnect; routing is completed by the supervised worker.
var shell = new ActiveXObject("WScript.Shell"), env = shell.Environment("Process");
var fso = new ActiveXObject("Scripting.FileSystemObject");
var token = env("NTUT_EVENT_TOKEN"), state = env("NTUT_STATE_FILE"), reason = env("reason");
var worker = env("NTUT_ROUTE_WORKER");
if (!/^[a-f0-9]{32}$/.test(token) || !state || !worker || /["\r\n]/.test(worker)) WScript.Quit(2);
// State files can be briefly open in another process (the supervisor polling,
// a security scanner), so file operations retry instead of aborting the hook.
function retry(action) {
    for (var i = 0; ; i++) {
        try { action(); return true; }
        catch (e) { if (i >= 10) return false; WScript.Sleep(100); }
    }
}
function write(path, value) { return retry(function () { var f = fso.CreateTextFile(path, true, false); f.Write(value); f.Close(); }); }
function remove(path) { return retry(function () { if (fso.FileExists(path)) fso.DeleteFile(path, true); }); }
// Marker files only count for this session; a leftover from an earlier session is ignored.
function owned(path) {
    try {
        if (!fso.FileExists(path)) return false;
        var f = fso.OpenTextFile(path, 1, false, 0), value = f.AtEndOfStream ? "" : f.ReadAll(); f.Close();
        return value.indexOf(token) == 0;
    } catch (e) { return false; }
}
function report(value) { write(state, token + ":" + value + ":" + new Date().getTime()); }
if (reason == "pre-init") {
    var suffixes = ["", ".started", ".cancel", ".ready", ".cleanup", ".recovering", ".error", ".command"];
    for (var i = 0; i < suffixes.length; i++) remove(state + suffixes[i]);
    var lock = state + ".lock";
    if (fso.FolderExists(lock)) {
        var folder = fso.GetFolder(lock);
        if (folder.Files.Count != 0 || folder.SubFolders.Count != 0) WScript.Quit(3);
        retry(function () { if (fso.FolderExists(lock)) fso.DeleteFolder(lock, false); });
    }
    WScript.Quit(0);
}
if (reason == "attempt-reconnect") { write(state + ".recovering", token); report("recovering"); WScript.Quit(0); }
if (reason == "reconnect") {
    remove(state + ".recovering");
    if (owned(state + ".ready")) report("connected");
    WScript.Quit(0);
}
if (reason == "connect") { write(state + ".started", token); report("configuring"); }
else if (reason == "disconnect") { write(state + ".cancel", token); report("disconnecting"); }
else WScript.Quit(0);
var cscript = shell.ExpandEnvironmentStrings("%SystemRoot%\\System32\\cscript.exe");
shell.Run('"' + cscript + '" //Nologo //E:JScript "' + worker + '"', 0, false);
WScript.Quit(0);
