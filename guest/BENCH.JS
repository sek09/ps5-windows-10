// CPU benchmark: integer loop + pi digits (spigot). Writes the result to C:\bench.txt
function now() { return new Date().getTime(); }
var t0 = now(), s = 0;
for (var i = 0; i < 3000000; i++) { s = (s + i * 7) % 1000003; }
var t1 = now();
// Rabinowitz-Wagon spigot, 600 digits
var n = 600, len = Math.floor(10 * n / 3) + 1, a = [], out = "", nines = 0, pre = 0;
for (var j = 0; j < len; j++) a[j] = 2;
for (var k = 0; k < n; k++) {
  var q = 0;
  for (var j = len; j > 0; j--) { var x = 10 * a[j - 1] + q * j; a[j - 1] = x % (2 * j - 1); q = Math.floor(x / (2 * j - 1)); }
  a[0] = q % 10; q = Math.floor(q / 10);
  if (q == 9) nines++; else if (q == 10) { out += (pre + 1); for (var m = 0; m < nines; m++) out += "0"; pre = 0; nines = 0; }
  else { out += pre; pre = q; for (var m = 0; m < nines; m++) out += "9"; nines = 0; }
}
var t2 = now();
var r = "loop_ms=" + (t1 - t0) + " pi_ms=" + (t2 - t1) + " check=" + s + " pi=" + out.substr(1, 12);
try { var fso = new ActiveXObject("Scripting.FileSystemObject"); var f = fso.CreateTextFile("C:\bench.txt", true); f.WriteLine(r); f.Close(); } catch (e) {}
try { var com = new ActiveXObject("Scripting.FileSystemObject").CreateTextFile("COM1", true); com.WriteLine("BENCH " + r); com.Close(); } catch (e) {}
new ActiveXObject("WScript.Shell").Popup(r, 25, "BENCH", 64);
