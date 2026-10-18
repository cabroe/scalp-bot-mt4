# ScalpScout – MT4-Scalping-Assistent (M1)

**Kernaussage:** ScalpScout beobachtet im Ein-Minuten-Chart, ob der Kurs plötzlich kräftig und mit auffallend viel Handelsaktivität in eine Richtung ausbricht. Wenn ja, zeigt er dir einen fertigen Vorschlag (Einstieg, Stop-Loss, Take-Profit, Positionsgröße) und wartet auf deinen Klick. Auf Wunsch handelt er auch selbst oder meldet nur per Alarm und Handy-Nachricht. Eingebaute Schutzregeln begrenzen das Risiko, ersetzen aber nie dein eigenes Urteil. Gewinne sind nicht zugesagt.

Der EA ist symbolneutral (EURUSD, GBPUSD, XAUUSD, DAX/US30 und andere, auch mit Broker-Suffix). Alle Abstände werden aus der Schwankung (ATR) und den Punktwerten des jeweiligen Symbols berechnet.

## Dateien

| Datei | Zweck |
|---|---|
| `MQL4/Experts/ScalpScout.mq4` | der Expert Advisor (UTF-8 mit BOM, damit Umlaute in MetaEditor stimmen) |
| `README.md` | diese Anleitung |
| `.gitignore` | ignoriert `*.ex4` und `*.log` |

## So arbeitet er

1. Einmal pro neuer M1-Kerze wird die **zuletzt geschlossene Kerze** geprüft.
2. **Long**, wenn alles gleichzeitig stimmt:
   - Kerzenkörper größer als `ImpulsFaktor` × ATR(14),
   - Tick-Volumen größer als `VolumenFaktor` × Durchschnitt der 20 Kerzen davor,
   - Schluss über dem Hoch der vorherigen `BreakoutKerzen` Kerzen (Ausbruch),
   - Trendfilter (abschaltbar): Schluss über EMA(50).
   **Short** ist das Spiegelbild.
3. SL = `SL_ATR` × ATR, TP = `TP_ATR` × ATR (mindestens der vom Broker verlangte Mindestabstand).
4. Lot = Risiko in Geld ÷ Verlust pro Lot bei SL, auf die Lot-Schrittweite abgerundet und durch `MaxLot` gedeckelt. Ist das Lot kleiner als das Broker-Minimum, wird **nicht** gehandelt (das Risiko wird nie überschritten); der Grund steht im Info-Bereich.
5. Schutzfilter (Spread, Handelszeit, Tagesverlust, Positionslimit, Pause nach Verlustserie) gelten in allen Modi.

## Installation in MT4

1. In MT4: **Datei → Datenordner öffnen**.
2. `ScalpScout.mq4` nach `MQL4/Experts/` kopieren.
3. MetaEditor öffnen (**F4**), Datei öffnen und mit **F7** kompilieren. Es darf kein Fehler erscheinen (Datei `ScalpScout.ex4` entsteht).
4. In MT4 im Navigator mit Rechtsklick **Aktualisieren**.
5. Oben in der Symbolleiste **„Algo-Trading“ (AutoTrading)** einschalten (Knopf muss grün sein).
6. Einen **M1-Chart** des gewünschten Symbols öffnen und den EA aus dem Navigator auf den Chart ziehen.
7. Im Reiter **Allgemein** den Haken **„Live-Handel erlauben“** setzen, im Reiter **Eingaben** die Werte prüfen, **OK**.
8. Oben rechts im Chart muss neben dem EA-Namen ein lachendes Gesicht stehen. Links oben erscheint der Info-Bereich.

Tipp: Pro Symbol nur einen Chart mit dem EA und eine eigene `MagicNumber` je Chart verwenden, wenn mehrere Charts laufen. Für Push-Nachrichten unter **Extras → Optionen → Benachrichtigungen** die MetaQuotes-ID aus der MT4-App eintragen und `PushAktiv` einschalten.

## Bedienung

**Info-Bereich (links oben, immer sichtbar):** Modus, Spread aktuell/maximal, ATR, Tagesergebnis, Status des Verlustlimits, Blockadegrund (falls der Handel gerade gesperrt ist), letzter Hinweis (z. B. „Lot zu klein“).

**Signal-Fenster (nur Modus Manuelle Freigabe):** Bei einem Signal erscheint ein Fenster mit Richtung, Einstieg, SL, TP, Lot, Spread, CRV und Restzeit. Dazu Alarm, Ton und optional Push.

| Knopf | Wirkung |
|---|---|
| **[+] Ausführen** (grün) | Holt aktuelle Preise, setzt SL/TP neu relativ zum aktuellen Preis, prüft alle Filter erneut und sendet die Order (bei Requote bis zu `OrderVersuche` Versuche). |
| **[–] Verwerfen** (rot) | Schließt das Fenster, es wird nichts gehandelt. |
| **ALLES SCHLIESSEN** | Fragt per Bestätigungsfenster nach und schließt dann alle Positionen mit eigener `MagicNumber` auf diesem Symbol. Danach sind neue Trades gesperrt, bis der EA neu gestartet wird (Chart: EA entfernen und neu aufziehen oder Eingaben ändern). |

Das Signal verfällt nach `SignalGueltigSek` Sekunden oder wenn sich der Preis mehr als `PreisAbweichungATR` × ATR vom Signalpreis entfernt hat.

**Modi:**
- `MANUELLE_FREIGABE` (Standard): Vorschlag mit Knöpfen, du entscheidest.
- `VOLLAUTOMATIK`: Der EA eröffnet direkt. Alle Filter gelten.
- `NUR_SIGNALE`: Nur Alarm/Push, kein Trade.

Im **Strategietester** wird `MANUELLE_FREIGABE` automatisch wie `VOLLAUTOMATIK` behandelt (steht im Journal), sonst könnte kein Backtest laufen.

## Inputs

„Punkte“ sind die kleinste Preisstufe des Symbols (`Point`). Bei 5-stelligen Forex-Kursen sind 10 Punkte = 1 Pip.

| Input | Standard | Bedeutung |
|---|---|---|
| `Modus` | MANUELLE_FREIGABE | Betriebsart (siehe oben) |
| `PushAktiv` | false | Push-Nachricht an MT4-Mobile bei Signal |
| `SignalGueltigSek` | 45 | Gültigkeit eines Signals in Sekunden |
| `PreisAbweichungATR` | 0.3 | Signal verfällt, wenn Preis weiter als x × ATR weg ist |
| `Slippage` | 3 | Erlaubte Abweichung in Pips; bei 3/5-stelligen Kursen automatisch ×10 in Punkte (bei Indizes/Gold prüfen) |
| `OrderVersuche` | 3 | Maximale Versuche bei Requote / Preisänderung |
| `ATR_Periode` | 14 | ATR-Periode auf M1 |
| `ImpulsFaktor` | 1.8 | Körper der Kerze > x × ATR |
| `VolumenFaktor` | 1.5 | Tick-Volumen > x × Durchschnitt |
| `VolumenKerzen` | 20 | Kerzen für das Durchschnittsvolumen (ohne Signalkerze) |
| `BreakoutKerzen` | 10 | Ausbruch über Hoch/Tief der letzten N Kerzen |
| `TrendFilterAktiv` | true | Trendfilter an/aus |
| `EMA_Periode` | 50 | EMA-Periode des Trendfilters |
| `SL_ATR` | 1.0 | Stop-Loss in Vielfachen der ATR |
| `TP_ATR` | 1.5 | Take-Profit in Vielfachen der ATR |
| `BE_Aktiv` | true | Break-even an/aus |
| `BE_ATR` | 0.8 | Break-even ab Gewinn von x × ATR |
| `BE_PufferPunkte` | 0 | Puffer über/unter dem Einstieg beim Break-even |
| `TrailingAktiv` | false | Trailing-Stop an/aus |
| `TrailingStartATR` | 1.0 | Trailing beginnt ab Gewinn von x × ATR |
| `TrailingATR` | 0.7 | Abstand des Trailing-Stops in × ATR |
| `TrailingSchrittATR` | 0.1 | SL wird nur nachgezogen, wenn er sich um mind. x × ATR verbessert |
| `RisikoProzent` | 1.0 | Risiko pro Trade in % vom Equity |
| `MaxLot` | 0.01 | Harter Lot-Deckel für den Live-Start |
| `MaxSpreadPunkte` | 0 | Max. Spread in Punkten; 0 = automatisch |
| `SpreadAnteilTP` | 0.25 | Automatik: Spread muss kleiner sein als dieser Anteil der TP-Distanz |
| `HandelStart` | 08:00 | Beginn Handelsfenster (Serverzeit, HH:MM) |
| `HandelEnde` | 20:00 | Ende Handelsfenster (Serverzeit); Fenster über Mitternacht ist möglich |
| `TagesVerlustProzent` | 3.0 | Verlustlimit je Tag vom Tagesbeginn-Equity; danach keine neuen Trades bis zum nächsten Tag (0 = aus) |
| `MaxOffenePositionen` | 1 | Max. offene Positionen pro Symbol |
| `PauseNachVerlusten` | 3 | Pause nach N Verlusten in Folge (0 = aus) |
| `PauseMinuten` | 30 | Länge der Pause |
| `MagicNumber` | 26101801 | Kennung der EA-Trades |

## Backtest (Strategietester)

1. **Ansicht → Strategietester** (Strg+R).
2. Expert Advisor: `ScalpScout`, Symbol wählen, Zeitraum **M1**.
3. Modell: **„Jeder Tick“** (für Scalping nötig; Kontrollpunkte/Eröffnungskurse sind zu grob).
4. Zeitraum und „Spread“ setzen. Für realistische Ergebnisse den **typischen Live-Spread des Brokers fest eintragen** (nicht „Aktuell“ mit Nachtspreads). Wenn möglich, Tick-Daten hoher Qualität verwenden.
5. Eingaben prüfen. Im Tester wird der Freigabe-Modus automatisch zur Vollautomatik. Hinweis: Tick-Volumen im Tester entsteht aus erzeugten Ticks und ist nur eine Näherung der Live-Aktivität.
6. Mit „Visualisierung“ kannst du Einstiege auf dem Chart nachvollziehen.
7. Ergebnisse nie als Prognose lesen. Erst auf Demokonto vorwärts testen (siehe Fahrplan).

## Risiko-Hinweise

- **CFD- und Forex-Handel mit Hebel kann zum Verlust des gesamten eingesetzten Kapitals führen.** Handle nur mit Geld, dessen Verlust du verkraftest.
- **Der Spread frisst Scalping-Gewinne.** Bei kleinen Zielen ist der Spread ein großer Teil des möglichen Gewinns; dazu kommen Kommission, Slippage und Requotes. Deshalb sperrt der EA bei zu hohem Spread. Der Backtest ist zu optimistisch, wenn er mit zu niedrigem Spread rechnet.
- **Kontobedingungen des Brokers prüfen:** Manche Broker verbieten oder begrenzen Scalping, Expert Advisors, Mindesthaltedauer von Positionen oder Handel kurz vor/nach News. Das muss vor dem Live-Einsatz mit den AGB geklärt sein.
- **Keine Gewinnzusage.** Vergangene Ergebnisse sagen nichts über künftige aus. Das hier ist ein technisches Werkzeug, keine Anlageberatung.
- Der EA braucht einen laufenden Rechner/VPS, Internet und eingeschaltetes Algo-Trading. Bei Verbindungsabbruch laufen offene Positionen nur mit ihrem SL/TP weiter.
- Der Tagesverlust wird am Equity gemessen und schließt offene Gewinne/Verluste ein. Einzahlungen und Auszahlungen am selben Tag verfälschen die Zahl.

## Annahmen und offene Punkte

- Broker, bei denen SL/TP nicht schon beim Öffnen mitgegeben werden dürfen (manche ECN/STP-Konten, Fehler 130), werden noch nicht unterstützt (Öffnen, danach per OrderModify setzen).
- Slippage ist als Pips-Input mit Faktor 10 bei 3/5 Digits gelöst; bei Indizes und Gold ggf. anpassen.
- Der Spread-Grenzwert gilt auch im Modus `NUR_SIGNALE`; ebenso alle anderen Filter.
- Nach „ALLES SCHLIESSEN“ ist der Handel bis zum EA-Neustart gesperrt.
- Verlustserie: Wird aus der Konto-Historie gelesen; die Historie muss in MT4 (Reiter „Kontohistorie“, Zeitraum „Gesamte Historie“) verfügbar sein.
- Der Code wurde ohne Compiler geschrieben und von Hand geprüft. Bitte einmal in MetaEditor kompilieren und Warnungen/Fehler zurückmelden.

## Fahrplan nächste Schritte

1. In MetaEditor kompilieren (F7), Fehler/Warnungen beheben.
2. Backtest mit „Jeder Tick“ auf EURUSD und XAUUSD, mit realistischem Spread; Parameter nicht überoptimieren.
3. **Demokonto**, Modus `NUR_SIGNALE`, mindestens 2 Wochen: Passen Signale zum Marktgefühl? Wie oft blockiert der Spreadfilter?
4. Demokonto mit `MANUELLE_FREIGABE`, Push aktivieren, Journal auswerten (Trefferquote, CRV, Spread-Kosten).
5. Broker-Bedingungen zu Scalping/EAs schriftlich klären.
6. Live-Start mit `MaxLot` 0.01, niedrigem Risiko und aktivem Tageslimit; erst nach stabilen Ergebnissen langsam steigern.
7. Später: Newsfilter, Handelsfenster je Markt (DAX vs. US30), Teil-Schließung, Statistik-Export.
