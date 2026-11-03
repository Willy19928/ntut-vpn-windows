// Local changes: validate an existing route before accepting a failed duplicate add,
// and keep only the first routing error in private, temporary diagnostic state.
function ntutMatchingRoute(cmd, table, tunnelIP, tunnelIndex) {
    var add = /^route\s+add\s+(\d+\.\d+\.\d+\.\d+)\s+mask\s+(\d+\.\d+\.\d+\.\d+)\s+(\d+\.\d+\.\d+\.\d+)(.*)$/i.exec(cmd);
    if (!add || /\smetric\s/i.test(add[4])) return false;
    var wantedIf = /\sif\s+(\d+)(?:\s|$)/i.exec(add[4]);
    if (wantedIf && wantedIf[1] != tunnelIndex) return false;
    var rows = table.split(/\r?\n/);
    for (var i = 0; i < rows.length; i++) {
        var row = /^\s*(\d+\.\d+\.\d+\.\d+)\s+(\d+\.\d+\.\d+\.\d+)\s+(.+?)\s+(\d+\.\d+\.\d+\.\d+)\s+(\d+)\s*$/.exec(rows[i]);
        if (!row || row[1] != add[1] || row[2] != add[2]) continue;
        if (wantedIf && row[4] != tunnelIP) continue;
        if (row[3] == add[3]) return true;
        if (add[3] == row[4] && !/^\d+\.\d+\.\d+\.\d+$/.test(row[3])) return true;
    }
    return false;
}
function ntutTemporaryDiagnostic(suffix, value, firstOnly) {
    var state = env("NTUT_STATE_FILE");
    if (!state) return;
    try {
        var fso = new ActiveXObject("Scripting.FileSystemObject");
        var path = state + suffix;
        if (firstOnly && fso.FileExists(path)) return;
        var file = fso.CreateTextFile(path, true, true);
        file.Write(value); file.Close();
    } catch (ignored) { }
}
function ntutExistingRouteMatches(cmd) {
    if (!/^route\s+add\s/i.test(cmd)) return false;
    try {
        var query = ws.Exec(comspec + ' /C "route print -4" 2>&1');
        query.StdIn.Close();
        var table = query.StdOut.ReadAll();
        if (query.ExitCode != 0) return false;
        return ntutMatchingRoute(cmd, table, env("INTERNAL_IP4_ADDRESS"), env("TUNIDX"));
    } catch (ignored) { return false; }
}
