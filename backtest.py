#!/usr/bin/env python3
"""Strategietester-Lauf unter Wine (MT4 portable in ~/.wine-mt4) für einen EA.

Aufruf:
  ./backtest.py EA SYMBOL VON BIS SPREAD [NAME=WERT ...] [--name BERICHT]
Beispiel:
  ./backtest.py ScalpScoutAsia USDJPY 2026.08.01 2026.10.31 12 FolgeTradesAktiv=false --name Asia_ohneFolge

Die .set-Datei wird aus den input-Standardwerten des EAs erzeugt, einzelne Werte lassen sich
mit NAME=WERT überschreiben. MT4 muss vorher beendet sein (der Tester startet es selbst und
schließt es danach). Der Bericht landet in tester-berichte/<Name>.htm, eine Kurzfassung auf stdout.
"""
import html, os, pathlib, re, shutil, subprocess, sys, time

REPO = pathlib.Path(__file__).resolve().parent
PREFIX = pathlib.Path.home() / ".wine-mt4"
MT4 = PREFIX / "drive_c/Program Files (x86)/MetaTrader 4"
ENUMS = {"MANUELLE_FREIGABE": 0, "VOLLAUTOMATIK": 1, "NUR_SIGNALE": 2,
         "EINSTIEG_SOFORT": 0, "EINSTIEG_RETEST": 1}


def set_datei(ea, ueberschreiben):
    quelle = (REPO / "MQL4/Experts" / (ea + ".mq4")).read_text(encoding="utf-8-sig")
    werte = {}
    for m in re.finditer(r'^input\s+(\w+)\s+(\w+)\s*=\s*([^;]*);', quelle, re.M):
        typ, name, wert = m.groups()
        wert = wert.strip()
        if typ == "string":
            wert = wert.strip('"')
        elif typ == "bool":
            wert = "1" if wert == "true" else "0"
        elif wert in ENUMS:
            wert = str(ENUMS[wert])
        werte[name] = (typ, wert)
    for kv in ueberschreiben:
        name, wert = kv.split("=", 1)
        if name not in werte:
            sys.exit("Unbekannter Input: " + name)
        typ = werte[name][0]
        if typ == "bool":
            wert = "1" if wert.lower() in ("1", "true") else "0"
        elif wert in ENUMS:
            wert = str(ENUMS[wert])
        werte[name] = (typ, wert)
    return "".join("%s=%s\r\n" % (n, w) for n, (t, w) in werte.items())


def kurzfassung(pfad):
    """Kennzahlen-Block des (deutschen oder englischen) MT4-Berichts als Text, Zeile je Tabellenzeile."""
    t = pfad.read_text(encoding="cp1252", errors="replace")
    t = re.sub(r"</t[dh]>", " | ", t)
    t = re.sub(r"</tr>", "\n", t)
    t = html.unescape(re.sub(r"<[^>]+>", "", t))
    zeilen = [re.sub(r"(\s*\|\s*)+$", "", re.sub(r"\s+", " ", z)).strip(" |") for z in t.split("\n")]
    aus, an = [], False
    for z in zeilen:
        if z.startswith(("Getestete Kerzen", "Bars in test")):
            an = True
        if z.startswith(("Nr. |", "# |")):
            break
        if an and z:
            aus.append(z)
    return "\n".join(aus)


def main():
    args = sys.argv[1:]
    name = None
    if "--name" in args:
        i = args.index("--name")
        name = args[i + 1]
        del args[i:i + 2]
    if len(args) < 5:
        sys.exit(__doc__)
    ea, symbol, von, bis, spread = args[:5]
    name = name or "%s_%s" % (ea, symbol)
    name = name.replace(".", "p")   # MT4 hängt sonst kein .htm an (Punkt gilt als Endung)

    for f in ("Experts/%s.ex4" % ea,):
        if not (REPO / "MQL4" / f).exists():
            sys.exit("Fehlt: MQL4/%s - erst ./kompilieren.sh" % f)
    shutil.copy2(REPO / "MQL4/Experts" / (ea + ".ex4"), MT4 / "MQL4/Experts")

    (MT4 / "tester" / (name + ".set")).write_text(set_datei(ea, args[5:]), encoding="cp1252", newline="")
    ini = ("[Tester]\r\nTestExpert=%s\r\nTestExpertParameters=%s.set\r\nTestSymbol=%s\r\nTestPeriod=M1\r\n"
           "TestModel=0\r\nTestSpread=%s\r\nTestOptimization=false\r\nTestDateEnable=true\r\n"
           "TestFromDate=%s\r\nTestToDate=%s\r\nTestReport=tester\\%s\r\nTestReplaceReport=true\r\n"
           "TestShutdownTerminal=true\r\nTestVisualEnable=false\r\n") % (ea, name, symbol, spread, von, bis, name)
    (MT4 / "tester" / (name + ".ini")).write_text(ini, encoding="cp1252", newline="")

    bericht = MT4 / "tester" / (name + ".htm")
    if bericht.exists():
        bericht.unlink()
    env = dict(os.environ, WINEPREFIX=str(PREFIX), WINEDEBUG="-all")
    start = time.time()
    subprocess.run(["wine", "terminal.exe", "/portable", "tester\\%s.ini" % name], cwd=MT4, env=env,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if not bericht.exists():
        sys.exit("Kein Bericht entstanden (%s). Tester-Log: %s" % (bericht, MT4 / "tester/logs"))
    ziel = REPO / "tester-berichte"
    ziel.mkdir(exist_ok=True)
    shutil.copy2(bericht, ziel / bericht.name)
    for gif in (MT4 / "tester").glob(name + "*.gif"):
        shutil.copy2(gif, ziel / gif.name)
    print("=== %s (%s, %s-%s, Spread %s, %.0f s)" % (name, symbol, von, bis, spread, time.time() - start))
    print(kurzfassung(bericht))


if __name__ == "__main__":
    main()
