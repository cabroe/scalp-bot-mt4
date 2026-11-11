#!/bin/bash
# Kompiliert die EAs unter Wine mit MetaEditor (MT4 in ~/.wine-mt4) und zeigt Fehler/Warnungen.
# Aufruf: ./kompilieren.sh [EA.mq4 ...]   (ohne Argument: alle EAs in MQL4/Experts)
export WINEPREFIX=$HOME/.wine-mt4 WINEDEBUG=-all
ME="$WINEPREFIX/drive_c/Program Files (x86)/MetaTrader 4/metaeditor.exe"
cd "$(dirname "$0")/MQL4/Experts" || exit 1
rc=0
for f in ${@:-*.mq4}; do
  b=${f%.mq4}
  rm -f "$b.ex4" "$b.log"
  wine "$ME" /compile:"Z:$(pwd)/$f" /include:"Z:$(dirname "$(pwd)")" /log:"Z:$(pwd)/$b.log" >/dev/null 2>&1
  iconv -f UTF-16LE -t UTF-8 "$b.log" 2>/dev/null | tr -d '\r' > "$b.txt"; mv "$b.txt" "$b.log"
  echo "=== $f: $(grep -E 'Result|result' "$b.log" | tail -1)  ex4: $([ -f "$b.ex4" ] && echo ja || echo NEIN)"
  grep -E ' : (error|warning) ' "$b.log" | sed -E 's#^.*Experts\\##' | head -${MAXZ:-40}
  [ -f "$b.ex4" ] || rc=1
done
exit $rc
