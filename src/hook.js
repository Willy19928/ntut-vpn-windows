// Return promptly to OpenConnect; routing is completed by the supervised worker.
var shell = new ActiveXObject("WScript.Shell"), env = shell.Environment("Process");
var fso = new ActiveXObject("Scripting.FileSystemObject");
var token = env("NTUT_EVENT_TOKEN"), state = env("NTUT_STATE_FILE"), reason = env("reason");
var worker = env("NTUT_ROUTE_WORKER");
if (!/^[a-f0-9]{32}$/.test(token) || !state || !worker || /["\r\n]/.test(worker)) WScript.Quit(2);
function write(path, value) { var f = fso.CreateTextFile(path, true, false); f.Write(value); f.Close(); }
function report(value) { write(state, token + ":" + value + ":" + new Date().getTime()); }
if (reason == "pre-init") {
    var suffixes = ["", ".started", ".cancel", ".ready", ".cleanup", ".recovering", ".error", ".command"];
    for (var i = 0; i < suffixes.length; i++) if (fso.FileExists(state + suffixes[i])) fso.DeleteFile(state + suffixes[i], true);
    var lock = state + ".lock";
    if (fso.FolderExists(lock)) {
        var folder = fso.GetFolder(lock);
        if (folder.Files.Count != 0 || folder.SubFolders.Count != 0) WScript.Quit(3);
        fso.DeleteFolder(lock, false);
    }
    WScript.Quit(0);
}
if (reason == "attempt-reconnect") { write(state + ".recovering", token); report("recovering"); WScript.Quit(0); }
if (reason == "reconnect") {
    if (fso.FileExists(state + ".recovering")) fso.DeleteFile(state + ".recovering", true);
    if (fso.FileExists(state + ".ready")) report("connected");
    WScript.Quit(0);
}
if (reason == "connect") { write(state + ".started", token); report("configuring"); }
else if (reason == "disconnect") { write(state + ".cancel", token); report("disconnecting"); }
else WScript.Quit(0);
var cscript = shell.ExpandEnvironmentStrings("%SystemRoot%\\System32\\cscript.exe");
shell.Run('"' + cscript + '" //Nologo //E:JScript "' + worker + '"', 0, false);
WScript.Quit(0);
