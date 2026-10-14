// Responsiveness benchmark: program launch times, alone and next to a CPU hog.
// The result goes to COM1 as "BENCH2 ..." (the Linux side reads serial.txt in the VM folder).
var sh = new ActiveXObject("WScript.Shell");
function now() { return new Date().getTime(); }
function spawn(n) {                 // n x "cmd /c exit", waiting for each one
  var t = now();
  for (var i = 0; i < n; i++) sh.Run("cmd /c exit", 0, true);
  return now() - t;
}
function notepad() {                // start Notepad, wait for its window, close it
  var t = now(), ok = false, p = sh.Exec("notepad.exe");
  while (now() - t < 30000) {
    if (sh.AppActivate(p.ProcessID)) { ok = true; break; }
    WScript.Sleep(10);
  }
  var dt = now() - t;
  p.Terminate();
  WScript.Sleep(500);
  return ok ? dt : -1;
}
var s1 = spawn(10), n1 = notepad(), n2 = notepad(), n3 = notepad();
var hog = sh.Exec("wscript.exe D:\\HOG.JS");
WScript.Sleep(2000);
var s2 = spawn(10), m1 = notepad(), m2 = notepad(), m3 = notepad();
try { hog.Terminate(); } catch (e) {}
var r = "spawn10_ms=" + s1 + " notepad_ms=" + n1 + "," + n2 + "," + n3 +
        " hog_spawn10_ms=" + s2 + " hog_notepad_ms=" + m1 + "," + m2 + "," + m3;
try { var com = new ActiveXObject("Scripting.FileSystemObject").CreateTextFile("COM1", true); com.WriteLine("BENCH2 " + r); com.Close(); } catch (e) {}
sh.Popup(r, 25, "BENCH2", 64);
