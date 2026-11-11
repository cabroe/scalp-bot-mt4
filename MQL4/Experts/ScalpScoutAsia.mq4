//+------------------------------------------------------------------+
//|                                                ScalpScoutAsia.mq4 |
//|  Opening-Range-Breakout auf USDJPY (M1) zur Tokio- und London-    |
//|  Eröffnung: zeigt Ausbrüche und Folge-Scalps zur manuellen        |
//|  Freigabe oder handelt vollautomatisch. Keine Gewinnzusage -      |
//|  Handel auf eigenes Risiko.                                       |
//+------------------------------------------------------------------+
#property copyright   "maehrsteuern"
#property version     "1.00"
#property description "ScalpScout Asia - Tokio-/London-Range-Breakout (USDJPY, M1): Signal, manuelle Freigabe, Vollautomatik, Telegram-Fernsteuerung"
#property strict

//--- Betriebsart (muss vor den Inputs definiert sein)
enum ENUM_MODUS
{
   MANUELLE_FREIGABE = 0,  // Manuelle Freigabe (Knopf im Chart)
   VOLLAUTOMATIK     = 1,  // Vollautomatik (handelt selbst)
   NUR_SIGNALE       = 2   // Nur Signale (Alert/Push, kein Trade)
};

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
//--- Betrieb
input ENUM_MODUS Modus             = MANUELLE_FREIGABE; // Betriebsart
input bool   PushAktiv             = false;   // Push-Nachricht an MT4-Mobile senden
input int    SignalGueltigSek      = 45;      // Signal gültig für (Sekunden)
input double PreisAbweichungATR    = 0.3;     // Signal verfällt, wenn Preis weiter weg ist als x * ATR(M1)
input int    Slippage              = 3;       // Max. Abweichung in Pips (bei 3/5-stelligen Kursen automatisch x10 Punkte)
input int    OrderVersuche         = 3;       // Max. Versuche bei Requote/Preisänderung

//--- Signal (Tokio-Range): Phase 1 "Tokio" (Opening-Range-Breakout)
input string RangeStart            = "03:00"; // Range Beginn (Serverzeit, HH:MM) = Tokio-Eröffnung; gilt auch für die London-Range
input string RangeEnde             = "04:00"; // Tokio-Range Ende (Serverzeit, HH:MM, muss nach Beginn liegen)
input int    ATR_H1_Periode        = 14;      // ATR-Periode (H1, letzte geschlossene Stunde) für Range-Prüfung und SL-Deckel
input double RangeMinATR           = 0.8;     // Tokio-Range gültig ab Breite x * ATR(H1)
input double RangeMaxATR           = 3.0;     // Tokio-Range gültig bis Breite x * ATR(H1)
input double AusbruchPufferPips    = 1.0;     // Ausbruch: Schluss muss um x Pips über Range-Hoch bzw. unter Range-Tief liegen
input double VolumenFaktor         = 1.3;     // Ausbruch: Tick-Volumen muss größer sein als x * Durchschnitt
input int    VolumenKerzen         = 20;      // Anzahl Kerzen (M1) für Durchschnittsvolumen (Ausbruch und Folge-Scalps)
input bool   TrendFilterAktiv      = true;    // Ausbruch: Trendfilter (Schluss über/unter EMA auf H1) verwenden
input int    EMA_H1_Periode        = 50;      // EMA-Periode (H1, letzte geschlossene Stunde) für Trendfilter

//--- London (Phase 2): Range = Asien-Session von RangeStart bis LondonStart, Einstieg ab LondonStart
input bool   LondonAktiv           = true;    // London-Phase einschalten
input string LondonStart           = "10:00"; // London: Einstiegsfenster Beginn = Ende der Asien-Range (Serverzeit, HH:MM)
input string LondonEnde            = "12:00"; // London: Einstiegsfenster Ende (Serverzeit, HH:MM)
input double LondonRangeMinATR     = 1.0;     // London-Range gültig ab Breite x * ATR(H1)
input double LondonRangeMaxATR     = 5.0;     // London-Range gültig bis Breite x * ATR(H1)

//--- Folge-Scalps (in beiden Phasen, nur in Richtung des Phasen-Ausbruchs)
input bool   FolgeTradesAktiv      = true;    // Folge-Scalps nach dem Ausbruch erlauben
input int    FolgeAusbruchKerzen   = 5;       // Folge-Signal: Schluss über Hoch (Long) bzw. unter Tief (Short) der letzten N Kerzen
input double FolgeVolumenFaktor    = 1.1;     // Folge-Signal: Tick-Volumen größer als x * Durchschnitt
input double FolgeSL_ATR           = 1.0;     // Folge-Scalp: Stop-Loss = x * ATR(M1)

//--- Ausstieg
input double SL_MaxATR             = 0.75;    // Ausbruch: Stop-Loss in der Range-Mitte, Abstand höchstens x * ATR(H1)
input double TP_CRV                = 1.5;     // Take-Profit-Abstand = x * Stop-Loss-Abstand (Ausbruch und Folge-Scalps)
input string SchlussZeit           = "13:00"; // Zeitausstieg: alle Positionen schließen (Serverzeit, HH:MM, leer = aus)
input int    ATR_Periode           = 14;      // ATR-Periode (M1): für Folge-SL, Break-even, Trailing und Preisabweichung des Signals
input bool   BE_Aktiv              = true;    // Break-even aktivieren
input double BE_ATR                = 0.8;     // Break-even ab Gewinn von x * ATR(M1)
input int    BE_PufferPunkte       = 0;       // Break-even: Puffer über/unter Einstieg (Punkte)
input bool   TrailingAktiv         = false;   // Trailing-Stop aktivieren
input double TrailingStartATR      = 1.0;     // Trailing startet ab Gewinn von x * ATR(M1)
input double TrailingATR           = 0.7;     // Trailing-Abstand = x * ATR(M1)
input double TrailingSchrittATR    = 0.1;     // SL nur nachziehen, wenn Verbesserung mind. x * ATR(M1)

//--- Risiko
input double RisikoProzent         = 1.0;     // Risiko pro Trade in % vom Equity
input double MaxLot                = 0.01;    // Harter Lot-Deckel (Live-Start)

//--- Schutzfilter
input double MaxSpreadPunkte       = 0;       // Max. Spread in Punkten (0 = automatisch aus TP-Distanz)
input double SpreadAnteilTP        = 0.25;    // Automatik: Kosten (Spread + Kommission) müssen kleiner sein als x * TP-Distanz
input double KommissionProLot      = 0.0;     // Kommission pro Lot, Hin- und Rückweg zusammen, in Kontowährung (ECN)
input string HandelStart           = "04:00"; // Tokio: Einstiegsfenster Beginn (Serverzeit, HH:MM)
input string HandelEnde            = "07:00"; // Tokio: Einstiegsfenster Ende (Serverzeit, HH:MM)
input double TagesVerlustProzent   = 3.0;     // Tagesverlust-Limit in % vom Tagesbeginn-Equity (0 = aus)
input int    MaxOffenePositionen   = 1;       // Max. offene Positionen pro Symbol
input int    MaxTradesProPhase     = 10;      // Max. Trades je Phase und Serverzeit-Tag (Ausbruch und Folge-Scalps zusammen)
input int    CooldownMinuten       = 2;       // Keine neue Eröffnung innerhalb von N Minuten nach der letzten Eröffnung/Schließung (0 = aus)
input int    PauseNachVerlusten    = 3;       // Pause nach N Verlusten in Folge (0 = aus)
input int    PauseMinuten          = 30;      // Dauer der Pause (Minuten)
input int    MagicNumber           = 26101803;// Magic Number dieses EAs (verschieden von den anderen EAs)

//--- Telegram-Fernbedienung (Freigabe per Handy)
input bool   TelegramAktiv         = false;   // Telegram-Fernbedienung einschalten
input string TelegramToken         = "";      // Bot-Token von @BotFather (nie weitergeben)
input string TelegramChatID        = "";      // deine Chat-ID (nur dieser Chat darf steuern)
input int    TelegramAbfrageSek    = 2;       // Abfrageintervall (Sekunden)
input bool   TelegramMeldeSchliessung = true; // Nachricht bei geschlossener Position mit Ergebnis
input string TagesberichtZeit      = "23:05"; // Tagesbericht per Telegram (Serverzeit HH:MM, leer = aus)
input double FernMaxLotObergrenze  = 0.05;    // Per Telegram darf MaxLot höchstens bis hierhin erhöht werden (Sicherheitsgrenze)

//+------------------------------------------------------------------+
//| Konstanten und Typen                                             |
//+------------------------------------------------------------------+
#define PRAEFIX          "SSA_"
#define EA_NAME          "ScalpScout Asia"   // Name in Journal-Meldungen
#define OBJ_KILL         "SSA_btn_kill"
#define OBJ_PNL_PRAEFIX  "SSA_pnl_"
#define OBJ_PNL_BG       "SSA_pnl_bg"
#define OBJ_PNL_OK       "SSA_pnl_btn_ok"
#define OBJ_PNL_NO       "SSA_pnl_btn_no"
#define OBJ_INFO_BG      "SSA_info_bg"
#define ORDER_KOMMENTAR  "SSA Hand"
#define INFO_ZEILEN      15
#define INFO_BREITE      540
#define INFO_MAXZEICHEN  88
#define PNL_ZEILEN       7

// Eigene Fehlercodes (unabhängig von Include-Dateien)
#define FEHLER_KEIN_FEHLER      0
#define FEHLER_PREIS_GEAENDERT  135
#define FEHLER_KEINE_KURSE      136
#define FEHLER_BROKER_BESCHAEFT 137
#define FEHLER_REQUOTE          138
#define FEHLER_KONTEXT_BELEGT   146
#define FEHLER_UNGUELTIGE_STOPS 130
#define FEHLER_NICHT_GENUG_GELD 134

struct Plan
{
   int    richtung;   // +1 Long, -1 Short
   double preis;      // Einstiegspreis (Ask/Bid)
   double sl;         // Stop-Loss (Kurs)
   double tp;         // Take-Profit (Kurs)
   double slDist;     // SL-Abstand (Preis)
   double tpDist;     // TP-Abstand (Preis)
   double lot;        // Lotgröße
   double spreadPkt;  // Spread in Punkten
   double kommPkt;    // Kommission in Punkten (0 = keine)
   double crv;        // Chance-Risiko-Verhältnis (TP/SL)
   double atr;        // ATR(M1) zur Signalzeit (für die Preisabweichung)
   int    phase;      // 0 Tokio, 1 London, -1 Hand-Trade
   int    art;        // 1 Opening-Range-Ausbruch (ORB), 2 Folge-Scalp, 0 Hand-Trade
};

struct SignalZustand
{
   bool     aktiv;    // wartet auf Freigabe
   datetime zeit;     // Erzeugungszeit (TimeLocal)
   Plan     plan;     // berechneter Plan
};

//+------------------------------------------------------------------+
//| Globale Variablen                                                |
//+------------------------------------------------------------------+
ENUM_MODUS    g_modus;               // wirksame Betriebsart
SignalZustand g_sig;                 // aktuelles Signal (Freigabe-Modus)
datetime      g_letzteKerze   = 0;   // Zeit der zuletzt ausgewerteten M1-Kerze
datetime      g_tag           = 0;   // Beginn des aktuellen Serverzeit-Tages
double        g_tagEquity     = 0.0; // Equity zu Tagesbeginn
bool          g_tagesLimit    = false; // Tagesverlust-Limit heute erreicht
bool          g_gestoppt      = false; // Kill-Switch wurde ausgelöst
int           g_startMin      = 0;   // Handelsfenster Beginn (Minuten ab 00:00)
int           g_endeMin       = 0;   // Handelsfenster Ende (Minuten ab 00:00)
int           g_histAnzahl    = -1;  // Cache: Anzahl Historieneinträge
int           g_verlustSerie  = 0;   // Verluste in Folge
datetime      g_letzterVerlust= 0;   // Schlusszeit des letzten Verlusts
string        g_hinweis       = "";  // letzter Hinweis (z. B. Lot zu klein)
datetime      g_hinweisZeit   = 0;
bool          g_ui            = true; // Oberfläche aktiv?
uint          g_uiLetzte      = 0;   // Zeitstempel letztes UI-Update
string        g_gvTag, g_gvEquity;   // Namen der globalen Variablen (Tagesstart)
int           g_orderTicket   = 0;   // Ticket der zuletzt eröffneten Order
double        g_orderPreis    = 0.0; // Einstiegspreis der zuletzt eröffneten Order

// Telegram
bool          g_tgAktiv       = false; // Telegram wirksam (Eingaben ok, kein Tester)
bool          g_tgGesperrt    = false; // WebRequest-URL nicht freigegeben (Fehler 4060)
bool          g_tgVerbunden   = false; // letzte Anfrage war erfolgreich
int           g_tgFehler      = 0;     // letzter Fehlercode (MT4-Fehler oder HTTP-Status)
bool          g_tgPause       = false; // per /stop pausiert
string        g_tgToken       = "";    // bereinigter Token
string        g_tgChat        = "";    // bereinigte Chat-ID
long          g_tgOffset      = 0;     // nächstes erwartetes update_id
datetime      g_tgLetzteAbfrage = 0;   // Zeitpunkt der letzten Abfrage (TimeLocal)
datetime      g_tgSperreBis   = 0;     // nach Netzfehler bis dahin keine Anfragen (TimeLocal)
int           g_sigId         = 0;     // ID des aktuellen Freigabe-Signals
long          g_sigMsgId      = 0;     // Telegram-message_id des aktuellen Signals (0 = keine)
string        g_tgKopf        = "";    // Kopfzeile der Signal-Nachricht (für spätere Änderungen)
int           g_tgOffen[];             // gemerkte offene eigene Tickets
int           g_tgVersuche[];          // Anzahl Suchversuche je Ticket (Historie)

// Fern-Einstellungen: Laufzeit-Werte (Start = Inputs, per Telegram änderbar, in GlobalVariables gemerkt)
double        g_risiko         = 1.0;  // Risiko pro Trade in % vom Equity
double        g_maxLot         = 0.01; // Harter Lot-Deckel
double        g_tagesLimitProz = 3.0;  // Tagesverlust-Limit in % (0 = aus); g_tagesLimit ist der Merker "erreicht"
double        g_volumenFaktor  = 1.3;  // Ausbruch: Tick-Volumen muss größer sein als x * Durchschnitt
int           g_rgStartMin     = 180;  // Range Beginn (Minuten ab 00:00, Serverzeit), gilt für Tokio und London
int           g_rgEndeMin      = 240;  // Tokio-Range Ende (Minuten ab 00:00, Serverzeit)
double        g_puffer         = 1.0;  // Ausbruchspuffer in Pips
int           g_schlussMin     = 780;  // Zeitausstieg (Minuten ab 00:00, -1 = aus)
bool          g_lonAktiv       = true; // London-Phase aktiv
int           g_lonStartMin    = 600;  // London: Einstieg Beginn = Ende der London-Range (Minuten ab 00:00)
int           g_lonEndeMin     = 720;  // London: Einstieg Ende (Minuten ab 00:00)
bool          g_folgeAktiv     = true; // Folge-Scalps aktiv
int           g_maxTrades      = 10;   // Max. Trades je Phase und Tag
int           g_cooldownMin    = 2;    // Cooldown in Minuten (0 = aus)
ENUM_MODUS    g_modusInput;            // Betriebsart laut Input (nach Tester-Regel) - Ziel von /reset
string        g_fernInfo       = "";   // Liste der aus GlobalVariables geladenen Abweichungen
long          g_cfgAutoMsg     = 0;    // Nachricht mit offener Rückfrage "Vollautomatik" (0 = keine)
datetime      g_cfgAutoBis     = 0;    // Ablauf dieser Rückfrage (TimeLocal)
long          g_cfgSchlMsg     = 0;    // Nachricht mit offener Rückfrage "Alle schließen" (0 = keine)
datetime      g_cfgSchlBis     = 0;    // Ablauf dieser Rückfrage (TimeLocal)

// Diagnose der letzten ausgewerteten M1-Kerze (für /diag und die Chart-Zeilen); Ergebnisse je Phase (0 Tokio, 1 London)
bool          g_dgGueltig      = false; // gemeinsame Werte unten sind gültig
datetime      g_dgZeit         = 0;    // Zeit der ausgewerteten Kerze
double        g_dgAtr          = 0.0;  // ATR(M1)
double        g_dgAtrH1        = 0.0;  // ATR(H1)
double        g_dgClose        = 0.0;  // Schlusskurs der ausgewerteten Kerze
double        g_dgEma          = 0.0;  // EMA(H1)
double        g_dgVolX         = 0.0;  // Volumen in Vielfachen des Durchschnitts
string        g_dgPhErg[2];            // Ergebnis je Phase ("" = Signal möglich)
int           g_dgPhArt[2];            // geprüfte Art: 0 keine, 1 Ausbruch (ORB), 2 Folge-Scalp
int           g_dgPhRicht[2];          // geprüfte Richtung +1/-1
bool          g_dgPhMoeglich[2];       // alle Bedingungen erfüllt
bool          g_dgPhFarbeOK[2];        // Kerze läuft in die geprüfte Richtung
bool          g_dgPhAusOK[2];          // Schluss jenseits der Ausbruchslinie
bool          g_dgPhVolOK[2];
bool          g_dgPhExtraOK[2];        // Ausbruch: Trendfilter, Folge: Preis auf der Ausbruchsseite der Range-Mitte
double        g_dgPhLinie[2];          // Ausbruchslinie (Range-Grenze + Puffer bzw. Hoch/Tief der letzten N Kerzen)
double        g_dgKostenIst    = 0.0;
double        g_dgKostenMax    = 0.0;
bool          g_dgKostenOK     = false;
string        g_dgFilter       = "";   // Ergebnis der Schutzfilter
string        g_dgErgebnis     = "";   // Ergebnis, wenn die Kerze gar nicht auswertbar war
int           g_dgKerzen       = 0;    // Zähler seit Start: ausgewertete Kerzen
int           g_dgSignale      = 0;    //   erkannte Signale
int           g_dgTrades       = 0;    //   eröffnete Trades
int           g_dgVerworfen    = 0;    //   nicht gehandelte Signale
string        g_dgGrund[20];           //   Gründe dafür (gekürzt)
int           g_dgGrundN[20];          //   Häufigkeit je Grund
int           g_dgGrundAnz     = 0;

// Weitere Fern-Einstellungen und offene Rückfragen
bool          g_beAktiv        = true; // Break-even aktiv
bool          g_trailingAktiv  = false; // Trailing aktiv
int           g_berichtMin     = -1;   // Uhrzeit Tagesbericht (Minuten ab 00:00, -1 = aus)
datetime      g_berichtTag     = 0;    // Serverzeit-Tag, für den der Bericht schon gesendet wurde
datetime      g_berichtRetry   = 0;    // nach Sendefehler frühestens dann wieder (TimeLocal)
long          g_cfgZuMsg       = 0;    // Rückfrage "Position schließen"
datetime      g_cfgZuBis       = 0;
int           g_cfgZuTicket    = 0;
long          g_cfgHandMsg     = 0;    // Rückfrage "Hand-Trade"
datetime      g_cfgHandBis     = 0;
int           g_cfgHandRicht   = 0;
double        g_cfgHandLot     = 0.0;  // 0 = Lot aus Risiko
long          g_cfgStartMsg    = 0;    // Rückfrage "Kill-Switch-Sperre lösen"
datetime      g_cfgStartBis    = 0;

// Opening Ranges des heutigen Serverzeit-Tages (0 = Tokio, 1 = London) und Phasen-Zustand
datetime      g_rgTag          = 0;     // Tag, für den die Werte gelten
bool          g_rgDa[2];                // Range-Fenster vorbei und M1-Kerzen darin gefunden
bool          g_rgGueltig[2];           // Breite liegt zwischen Min und Max (x ATR(H1))
double        g_rgHoch[2];              // höchstes Hoch (bei laufender Range: bisher)
double        g_rgTief[2];              // tiefstes Tief
double        g_rgBreiteATR[2];         // Breite in Vielfachen von ATR(H1)
int           g_rgKerzen[2];            // Anzahl M1-Kerzen in der Range (0 = keine)
string        g_rgGrund[2];             // Zustand/Grund in Worten
string        g_rgGezKey[2];            // Stand der gezeichneten Linien (leer = nichts gezeichnet)
int           g_phRicht[2];             // Phasen-Richtung +1/-1 (0 = noch kein gültiger Ausbruch heute)
int           g_phTrades[2];            // heute eröffnete Trades der Phase (Stand letzte Kerze bzw. Eröffnung)
datetime      g_letzteAktion   = 0;     // letzte Eröffnung oder Schließung einer eigenen Position (Serverzeit)
datetime      g_schlussTag     = 0;     // Serverzeit-Tag, für den der Zeitausstieg schon lief
datetime      g_schlussRetry   = 0;     // nach Fehlern frühestens dann wieder (TimeLocal)
int           g_schlussVersuche = 0;

//+------------------------------------------------------------------+
//| Gemeinsame Funktionen aller ScalpScout-EAs                       |
//| Kern.mqh: alle drei EAs (Fehler, Lot/Kosten, Panel, Telegram)    |
//| Fern.mqh: ScalpScout + Asia (Fernsteuerung, Bericht, Diagnose)   |
//+------------------------------------------------------------------+
#include <ScalpScout/Kern.mqh>
#include <ScalpScout/Fern.mqh>

//+------------------------------------------------------------------+
//| Hilfsfunktionen: Fehler, Zahlen, Zeit                            |
//+------------------------------------------------------------------+
// Maximal erlaubte Kosten (Spread + Kommission) in Punkten, gerechnet aus der TP-Distanz des geplanten Trades.
// richtung 0 / phase -1 / art 0 = allgemeine Anzeige (aktive Phase, Ausbruchs-Regel)
double MaxSpreadAktuell(int richtung, int phase = -1, int art = 0)
{
   if(MaxSpreadPunkte > 0.0)
      return MaxSpreadPunkte;
   double sl = 0.0, tp = 0.0;
   double preis = (richtung >= 0) ? Ask : Bid;
   if(!ExitDistanzen(richtung, preis, phase, art, sl, tp))
      return 0.0;
   return SpreadAnteilTP * tp / Point;
}

//+------------------------------------------------------------------+
//| Fern-Einstellungen: Hilfsfunktionen und Speicherung              |
//+------------------------------------------------------------------+
// Die Laufzeit-Werte g_risiko, g_maxLot, g_tagesLimitProz, g_startMin/g_endeMin, g_rgStartMin/g_rgEndeMin,
// g_lonAktiv/g_lonStartMin/g_lonEndeMin, g_puffer, g_volumenFaktor, g_folgeAktiv, g_maxTrades, g_cooldownMin,
// g_schlussMin und g_modus starten mit den Inputs.
// Per Telegram geänderte Werte liegen in GlobalVariables (SSA_<konto>_<magic>_<name>)
// und überstehen einen Neustart. Im Strategietester wird nichts gespeichert oder geladen.

// Nur für den Chart (die Häkchen-Zeichen erscheinen dort als "?")
string OkText(bool ok)
{
   return ok ? "ok" : "x";
}

// Name einer globalen Variable für Fern-Einstellungen (Konto + Magic)
string FernSchluessel(string name)
{
   return "SSA_" + IntegerToString(AccountNumber()) + "_" + IntegerToString(MagicNumber) + "_" + name;
}

void FernAlleLoeschen()
{
   FernLoeschen("risiko");
   FernLoeschen("maxlot");
   FernLoeschen("limit");
   FernLoeschen("start");
   FernLoeschen("ende");
   FernLoeschen("rgstart");
   FernLoeschen("rgende");
   FernLoeschen("lonaktiv");
   FernLoeschen("lonstart");
   FernLoeschen("lonende");
   FernLoeschen("puffer");
   FernLoeschen("volumen");
   FernLoeschen("folge");
   FernLoeschen("maxtrades");
   FernLoeschen("cooldown");
   FernLoeschen("schluss");
   FernLoeschen("modus");
   FernLoeschen("be");
   FernLoeschen("trailing");
   FernLoeschen("bericht");
}

// Abweichung vom Input? (für "(fern geändert)")
bool FernRisikoAbw()   { return MathAbs(g_risiko - RisikoProzent) > 1e-9; }
bool FernMaxLotAbw()   { return MathAbs(g_maxLot - MaxLot) > 1e-9; }
bool FernLimitAbw()    { return MathAbs(g_tagesLimitProz - TagesVerlustProzent) > 1e-9; }
bool FernZeitAbw()     { return (g_startMin != ParseHHMM(HandelStart) || g_endeMin != ParseHHMM(HandelEnde)); }
bool FernRangeAbw()    { return (g_rgStartMin != ParseHHMM(RangeStart) || g_rgEndeMin != ParseHHMM(RangeEnde)); }
bool FernLondonAbw()   { return (g_lonAktiv != LondonAktiv || g_lonStartMin != ParseHHMM(LondonStart) || g_lonEndeMin != ParseHHMM(LondonEnde)); }
bool FernPufferAbw()   { return MathAbs(g_puffer - AusbruchPufferPips) > 1e-9; }
bool FernVolumenAbw()  { return MathAbs(g_volumenFaktor - VolumenFaktor) > 1e-9; }
bool FernFolgeAbw()    { return g_folgeAktiv != FolgeTradesAktiv; }
bool FernMaxTradesAbw() { return g_maxTrades != MaxTradesProPhase; }
bool FernCooldownAbw() { return g_cooldownMin != CooldownMinuten; }
bool FernSchlussAbw()  { return g_schlussMin != SchlussInputMin(); }
bool FernModusAbw()    { return g_modus != g_modusInput; }
bool FernBeAbw()       { return g_beAktiv != BE_Aktiv; }
bool FernTrailAbw()    { return g_trailingAktiv != TrailingAktiv; }

// Tagesbericht-Uhrzeit laut Input in Minuten (-1 = aus/leer)
int BerichtInputMin()
{
   string s = TagesberichtZeit;
   StringTrimLeft(s);
   StringTrimRight(s);
   return (s == "") ? -1 : ParseHHMM(s);
}
bool FernBerichtAbw()  { return g_berichtMin != BerichtInputMin(); }

// Zeitausstieg laut Input in Minuten (-1 = aus/leer)
int SchlussInputMin()
{
   string s = SchlussZeit;
   StringTrimLeft(s);
   StringTrimRight(s);
   return (s == "") ? -1 : ParseHHMM(s);
}

string SchlussText(int m)
{
   return (m >= 0) ? MinutenText(m) + " Serverzeit" : "aus";
}

string LondonText()
{
   return (g_lonAktiv ? "an" : "aus") + ", Einstieg " + MinutenText(g_lonStartMin) + "-" + MinutenText(g_lonEndeMin);
}

string FernMarke(bool abw)
{
   return abw ? " (fern geändert)" : "";
}

// Liste aller Werte, die vom Input abweichen ("" = keine)
string FernAbweichungen()
{
   string r = "";
   if(FernModusAbw())   ListeAnfuegen(r, "Modus " + ModusText());
   if(FernRisikoAbw())  ListeAnfuegen(r, "Risiko " + DoubleToString(g_risiko, 1) + " %");
   if(FernMaxLotAbw())  ListeAnfuegen(r, "MaxLot " + LotText(g_maxLot));
   if(FernLimitAbw())   ListeAnfuegen(r, "Tageslimit " + LimitText(g_tagesLimitProz));
   if(FernZeitAbw())    ListeAnfuegen(r, "Zeit " + MinutenText(g_startMin) + "-" + MinutenText(g_endeMin));
   if(FernRangeAbw())   ListeAnfuegen(r, "Range " + MinutenText(g_rgStartMin) + "-" + MinutenText(g_rgEndeMin));
   if(FernLondonAbw())  ListeAnfuegen(r, "London " + LondonText());
   if(FernPufferAbw())  ListeAnfuegen(r, "Puffer " + DoubleToString(g_puffer, 1) + " Pips");
   if(FernVolumenAbw()) ListeAnfuegen(r, "Volumen " + DoubleToString(g_volumenFaktor, 2));
   if(FernFolgeAbw())   ListeAnfuegen(r, "Folge " + (g_folgeAktiv ? "an" : "aus"));
   if(FernMaxTradesAbw()) ListeAnfuegen(r, "MaxTrades " + IntegerToString(g_maxTrades));
   if(FernCooldownAbw()) ListeAnfuegen(r, "Cooldown " + IntegerToString(g_cooldownMin) + " min");
   if(FernSchlussAbw()) ListeAnfuegen(r, "Schluss " + SchlussText(g_schlussMin));
   if(FernBeAbw())      ListeAnfuegen(r, "Break-even " + (g_beAktiv ? "an" : "aus"));
   if(FernTrailAbw())   ListeAnfuegen(r, "Trailing " + (g_trailingAktiv ? "an" : "aus"));
   if(FernBerichtAbw()) ListeAnfuegen(r, "Bericht " + BerichtZeitText(g_berichtMin));
   return r;
}

// Alle wirksamen Werte in einer Zeile (für /reset)
string WerteText()
{
   return "Modus " + ModusText() + ", Risiko " + DoubleToString(g_risiko, 1) + " %, MaxLot " + LotText(g_maxLot)
          + ", Tageslimit " + LimitText(g_tagesLimitProz) + ", Zeit " + MinutenText(g_startMin) + "-"
          + MinutenText(g_endeMin) + ", Range " + MinutenText(g_rgStartMin) + "-" + MinutenText(g_rgEndeMin)
          + ", London " + LondonText() + ", Puffer " + DoubleToString(g_puffer, 1) + " Pips, Volumen "
          + DoubleToString(g_volumenFaktor, 2) + ", Folge " + (g_folgeAktiv ? "an" : "aus")
          + ", MaxTrades " + IntegerToString(g_maxTrades) + ", Cooldown " + IntegerToString(g_cooldownMin)
          + " min, Schluss " + SchlussText(g_schlussMin)
          + ", Break-even " + (g_beAktiv ? "an" : "aus") + ", Trailing " + (g_trailingAktiv ? "an" : "aus")
          + ", Bericht " + BerichtZeitText(g_berichtMin);
}

// Werte aus den Inputs setzen (Start und /reset); Modus nach Tester-Regel steht in g_modusInput
void FernInputsUebernehmen()
{
   g_risiko         = RisikoProzent;
   g_maxLot         = MaxLot;
   g_tagesLimitProz = TagesVerlustProzent;
   g_startMin       = ParseHHMM(HandelStart);
   g_endeMin        = ParseHHMM(HandelEnde);
   g_rgStartMin     = ParseHHMM(RangeStart);
   g_rgEndeMin      = ParseHHMM(RangeEnde);
   g_lonAktiv       = LondonAktiv;
   g_lonStartMin    = ParseHHMM(LondonStart);
   g_lonEndeMin     = ParseHHMM(LondonEnde);
   g_puffer         = AusbruchPufferPips;
   g_volumenFaktor  = VolumenFaktor;
   g_folgeAktiv     = FolgeTradesAktiv;
   g_maxTrades      = MaxTradesProPhase;
   g_cooldownMin    = CooldownMinuten;
   g_schlussMin     = SchlussInputMin();
   g_beAktiv        = BE_Aktiv;
   g_trailingAktiv  = TrailingAktiv;
   g_berichtMin     = BerichtInputMin();
   g_modus          = g_modusInput;
}

// Gespeicherte Fern-Einstellungen laden (nur live). Ungültige Werte werden ignoriert -> Input gilt.
void FernLaden()
{
   g_fernInfo = "";
   if(IsTesting())
      return;
   double v = 0.0, v2 = 0.0;

   if(FernLesen("risiko", v))
   {
      if(v >= 0.1 - 1e-9 && v <= 25.0 + 1e-9) g_risiko = v;
      else Print("ScalpScout Asia: gespeicherter Wert 'risiko' ungültig - Input gilt.");
   }
   if(FernLesen("maxlot", v))
   {
      if(v >= MinLotWert() - 1e-9 && v <= MaxLotGrenze() + 1e-9) g_maxLot = LotAbrunden(v);
      else Print("ScalpScout Asia: gespeicherter Wert 'maxlot' ungültig - Input gilt.");
   }
   if(FernLesen("limit", v))
   {
      if(v < 1e-9 || (v >= 1.0 - 1e-9 && v <= 100.0 + 1e-9)) g_tagesLimitProz = (v < 1e-9) ? 0.0 : v;
      else Print("ScalpScout Asia: gespeicherter Wert 'limit' ungültig - Input gilt.");
   }
   if(FernLesen("start", v) && FernLesen("ende", v2))
   {
      if(v >= 0 && v <= 1439 && v2 >= 0 && v2 <= 1439)
      {
         g_startMin = (int)MathRound(v);
         g_endeMin  = (int)MathRound(v2);
      }
      else Print("ScalpScout Asia: gespeichertes Handelsfenster ungültig - Input gilt.");
   }
   if(FernLesen("rgstart", v) && FernLesen("rgende", v2))
   {
      if(v >= 0 && v <= 1439 && v2 >= 0 && v2 <= 1439 && v < v2)
      {
         g_rgStartMin = (int)MathRound(v);
         g_rgEndeMin  = (int)MathRound(v2);
      }
      else Print("ScalpScout Asia: gespeicherte Range ungültig - Input gilt.");
   }
   if(FernLesen("lonstart", v) && FernLesen("lonende", v2))
   {
      if(v > g_rgStartMin && v <= 1439 && v2 > v && v2 <= 1439)
      {
         g_lonStartMin = (int)MathRound(v);
         g_lonEndeMin  = (int)MathRound(v2);
      }
      else Print("ScalpScout Asia: gespeichertes London-Fenster ungültig - Input gilt.");
   }
   if(FernLesen("lonaktiv", v))
      g_lonAktiv = (v > 0.5);
   if(FernLesen("puffer", v))
   {
      if(v >= 0.0 - 1e-9 && v <= 10.0 + 1e-9) g_puffer = v;
      else Print("ScalpScout Asia: gespeicherter Wert 'puffer' ungültig - Input gilt.");
   }
   if(FernLesen("volumen", v))
   {
      if(v >= 0.8 - 1e-9 && v <= 4.0 + 1e-9) g_volumenFaktor = v;
      else Print("ScalpScout Asia: gespeicherter Wert 'volumen' ungültig - Input gilt.");
   }
   if(FernLesen("folge", v))
      g_folgeAktiv = (v > 0.5);
   if(FernLesen("maxtrades", v))
   {
      if(v >= 1.0 - 1e-9 && v <= 50.0 + 1e-9) g_maxTrades = (int)MathRound(v);
      else Print("ScalpScout Asia: gespeicherter Wert 'maxtrades' ungültig - Input gilt.");
   }
   if(FernLesen("cooldown", v))
   {
      if(v >= 0.0 - 1e-9 && v <= 30.0 + 1e-9) g_cooldownMin = (int)MathRound(v);
      else Print("ScalpScout Asia: gespeicherter Wert 'cooldown' ungültig - Input gilt.");
   }
   if(FernLesen("schluss", v))
   {
      if(v >= -1.0 - 1e-9 && v <= 1439.0 + 1e-9) g_schlussMin = (int)MathRound(v);
      else Print("ScalpScout Asia: gespeicherter Wert 'schluss' ungültig - Input gilt.");
   }
   if(FernLesen("be", v))
      g_beAktiv = (v > 0.5);
   if(FernLesen("trailing", v))
      g_trailingAktiv = (v > 0.5);
   if(FernLesen("bericht", v))
   {
      if(v >= -1.0 - 1e-9 && v <= 1439.0 + 1e-9) g_berichtMin = (int)MathRound(v);
      else Print("ScalpScout Asia: gespeicherter Wert 'bericht' ungültig - Input gilt.");
   }
   if(FernLesen("berichttag", v))        // kein Einstellwert: Tag des zuletzt gesendeten Berichts
      g_berichtTag = (datetime)(long)v;
   if(FernLesen("schlusstag", v))        // kein Einstellwert: Tag, für den der Zeitausstieg schon lief
      g_schlussTag = (datetime)(long)v;
   // Vollautomatik wird nie gespeichert: nach einem Neustart gilt dann der Input
   if(FernLesen("modus", v))
   {
      if(MathAbs(v - (double)MANUELLE_FREIGABE) < 0.5)      g_modus = MANUELLE_FREIGABE;
      else if(MathAbs(v - (double)NUR_SIGNALE) < 0.5)       g_modus = NUR_SIGNALE;
      else Print("ScalpScout Asia: gespeicherter Wert 'modus' ungültig - Input gilt.");
   }

   g_fernInfo = FernAbweichungen();
   if(g_fernInfo != "")
      Print("ScalpScout Asia: Fern-Einstellungen aktiv: ", g_fernInfo);
}

//+------------------------------------------------------------------+
//| Diagnose der letzten ausgewerteten M1-Kerze                      |
//+------------------------------------------------------------------+
void DiagZuruecksetzen()
{
   g_dgGueltig        = false;
   for(int q = 0; q < 2; q++)
   {
      g_dgPhMoeglich[q] = false;
      g_dgPhArt[q]      = 0;
      g_dgPhErg[q]      = "";
   }
   g_dgZeit           = 0;
   g_dgErgebnis       = "";
   g_dgFilter         = "";
   g_dgKerzen         = 0;
   g_dgSignale        = 0;
   g_dgTrades         = 0;
   g_dgVerworfen      = 0;
   g_dgGrundAnz       = 0;
}

// Wertet die zuletzt geschlossene M1-Kerze für beide Phasen aus (Range, Fenster, Trade-Limit, Ausbruch bzw. Folge-Scalp,
// Volumen, Trend) ohne vorzeitigen Abbruch und merkt die Werte für /diag und die Chart-Zeilen. Daraus entscheidet auch
// SignalErkennen (eine Quelle für die Regeln). Rechnet nebenbei die Ranges neu (RangeAktualisieren).
void DiagKerze()
{
   g_dgGueltig  = false;
   g_dgFilter   = "";
   g_dgErgebnis = "";
   for(int q = 0; q < 2; q++)
   {
      g_dgPhArt[q]      = 0;
      g_dgPhMoeglich[q] = false;
      g_dgPhErg[q]      = "";
      g_dgPhRicht[q]    = (g_phRicht[q] != 0) ? g_phRicht[q] : 1;
      g_dgPhFarbeOK[q]  = false;
      g_dgPhAusOK[q]    = false;
      g_dgPhVolOK[q]    = false;
      g_dgPhExtraOK[q]  = false;
      g_dgPhLinie[q]    = 0.0;
   }
   g_dgZeit = iTime(Symbol(), PERIOD_M1, 1);

   RangeAktualisieren();

   int mindestens = MathMax(MathMax(ATR_Periode, VolumenKerzen), FolgeAusbruchKerzen) + 5;
   if(iBars(Symbol(), PERIOD_M1) < mindestens)
   {
      g_dgErgebnis = "kein Signal: zu wenig M1-Kerzen im Chart (" + IntegerToString(mindestens) + " nötig)";
      return;
   }
   int mindestensH1 = MathMax(ATR_H1_Periode, EMA_H1_Periode * 2) + 5;
   if(iBars(Symbol(), PERIOD_H1) < mindestensH1)
   {
      g_dgErgebnis = "kein Signal: zu wenig H1-Kerzen (" + IntegerToString(mindestensH1) + " nötig)";
      return;
   }
   double atr   = AktuelleATR();
   double atrH1 = AtrH1();
   double ema   = EmaH1();
   if(atr <= 0.0 || atrH1 <= 0.0 || (TrendFilterAktiv && ema <= 0.0))
   {
      g_dgErgebnis = "kein Signal: ATR/EMA nicht verfügbar";
      return;
   }
   g_dgAtr   = atr;
   g_dgAtrH1 = atrH1;
   g_dgEma   = ema;

   double o1 = iOpen(Symbol(), PERIOD_M1, 1);
   double c1 = iClose(Symbol(), PERIOD_M1, 1);
   g_dgClose = c1;

   // Volumen: Kerze 1 gegen Durchschnitt der Kerzen davor (Shift 2 .. VolumenKerzen+1)
   double summe = 0.0;
   for(int i = 2; i <= VolumenKerzen + 1; i++)
      summe += (double)iVolume(Symbol(), PERIOD_M1, i);
   double schnitt = (VolumenKerzen > 0) ? summe / VolumenKerzen : 0.0;
   double vol1    = (double)iVolume(Symbol(), PERIOD_M1, 1);
   g_dgVolX = (schnitt > 0.0) ? vol1 / schnitt : 0.0;

   for(int p = 0; p < 2; p++)
      DiagPhase(p, o1, c1, ema);

   g_dgKostenIst = SpreadPunkte() + KommissionPunkte();
   g_dgKostenMax = MaxSpreadAktuell(0);
   g_dgKostenOK  = (g_dgKostenIst <= g_dgKostenMax);

   string grund = "";
   g_dgFilter  = HandelErlaubt(grund, 0) ? "alle frei" : grund;
   g_dgGueltig = true;
}

// Bewertet die Kerze für eine Phase: vor der ersten Richtung als Opening-Range-Ausbruch (ORB), danach als Folge-Scalp
void DiagPhase(int p, double o1, double c1, double ema)
{
   if(!PhAktiv(p))
   {
      g_dgPhErg[p] = "kein Signal: Phase aus";
      return;
   }
   if(!g_rgGueltig[p])
   {
      g_dgPhErg[p] = "kein Signal: Range " + g_rgGrund[p];
      return;
   }
   if(g_dgZeit < g_rgTag + PhRangeEnde(p) * 60)
   {
      g_dgPhErg[p] = "kein Signal: Kerze gehört noch zur Range";
      return;
   }
   if(!PhaseFensterOK(p))
   {
      g_dgPhErg[p] = "kein Signal: außerhalb Einstiegsfenster " + MinutenText(PhEntryStart(p)) + "-" + MinutenText(PhEntryEnde(p));
      return;
   }
   if(SchlussErreicht())
   {
      g_dgPhErg[p] = "kein Signal: Schlusszeit erreicht";
      return;
   }
   if(g_phTrades[p] >= g_maxTrades)
   {
      g_dgPhErg[p] = "kein Signal: Trade-Limit der Phase erreicht (" + IntegerToString(g_phTrades[p]) + "/"
                     + IntegerToString(g_maxTrades) + ")";
      return;
   }

   double mitte  = (g_rgHoch[p] + g_rgTief[p]) / 2.0;
   bool   farbeL = (c1 > o1);
   bool   farbeS = (c1 < o1);

   if(g_phRicht[p] == 0)
   {
      // Opening-Range-Ausbruch: beide Richtungen prüfen, die nähere zeigen
      g_dgPhArt[p] = 1;
      double puffer = g_puffer * PipGroesse();
      bool ausL = (c1 > g_rgHoch[p] + puffer);
      bool ausS = (c1 < g_rgTief[p] - puffer);
      bool trL  = (!TrendFilterAktiv || c1 > ema);
      bool trS  = (!TrendFilterAktiv || c1 < ema);
      int  pktL = (farbeL ? 1 : 0) + (ausL ? 1 : 0) + (trL ? 1 : 0);
      int  pktS = (farbeS ? 1 : 0) + (ausS ? 1 : 0) + (trS ? 1 : 0);
      int  r    = 1;
      if(pktS > pktL || (pktS == pktL && farbeS))
         r = -1;
      g_dgPhRicht[p]   = r;
      g_dgPhFarbeOK[p] = (r > 0) ? farbeL : farbeS;
      g_dgPhAusOK[p]   = (r > 0) ? ausL : ausS;
      g_dgPhExtraOK[p] = (r > 0) ? trL : trS;
      g_dgPhVolOK[p]   = (g_dgVolX > g_volumenFaktor);
      g_dgPhLinie[p]   = (r > 0) ? g_rgHoch[p] + puffer : g_rgTief[p] - puffer;
      string txtO = (r > 0) ? "LONG" : "SHORT";
      g_dgPhMoeglich[p] = (g_dgPhFarbeOK[p] && g_dgPhAusOK[p] && g_dgPhVolOK[p] && g_dgPhExtraOK[p]);
      if(!g_dgPhFarbeOK[p])
         g_dgPhErg[p] = "kein Signal: Kerze läuft nicht in Richtung " + txtO;
      else if(!g_dgPhAusOK[p])
         g_dgPhErg[p] = "kein Signal: kein Ausbruch über Range + Puffer (" + txtO + ")";
      else if(!g_dgPhVolOK[p])
         g_dgPhErg[p] = "kein Signal: Volumen zu klein";
      else if(!g_dgPhExtraOK[p])
         g_dgPhErg[p] = "kein Signal: Trendfilter/EMA(H1) (" + txtO + ")";
      return;
   }

   // Folge-Scalp in Phasen-Richtung
   g_dgPhArt[p] = 2;
   int rf = g_phRicht[p];
   g_dgPhRicht[p] = rf;
   string txtF = (rf > 0) ? "LONG" : "SHORT";
   if(!g_folgeAktiv)
   {
      g_dgPhErg[p] = "kein Signal: Folge-Scalps aus (Phasen-Richtung " + txtF + ")";
      return;
   }
   int    ih    = iHighest(Symbol(), PERIOD_M1, MODE_HIGH, FolgeAusbruchKerzen, 2);
   int    il    = iLowest(Symbol(), PERIOD_M1, MODE_LOW, FolgeAusbruchKerzen, 2);
   double linie = 0.0;
   bool   ausF  = false;
   if(rf > 0 && ih >= 0)
   {
      linie = iHigh(Symbol(), PERIOD_M1, ih);
      ausF  = (c1 > linie);
   }
   if(rf < 0 && il >= 0)
   {
      linie = iLow(Symbol(), PERIOD_M1, il);
      ausF  = (c1 < linie);
   }
   g_dgPhLinie[p]   = linie;
   g_dgPhFarbeOK[p] = (rf > 0) ? farbeL : farbeS;
   g_dgPhAusOK[p]   = ausF;
   g_dgPhVolOK[p]   = (g_dgVolX > FolgeVolumenFaktor);
   g_dgPhExtraOK[p] = (rf > 0) ? (c1 > mitte) : (c1 < mitte);
   g_dgPhMoeglich[p] = (g_dgPhFarbeOK[p] && g_dgPhAusOK[p] && g_dgPhVolOK[p] && g_dgPhExtraOK[p]);
   if(!g_dgPhFarbeOK[p])
      g_dgPhErg[p] = "kein Folge-Signal: Kerze läuft nicht in Richtung " + txtF;
   else if(!g_dgPhAusOK[p])
      g_dgPhErg[p] = "kein Folge-Signal: kein Ausbruch über die letzten " + IntegerToString(FolgeAusbruchKerzen) + " Kerzen (" + txtF + ")";
   else if(!g_dgPhVolOK[p])
      g_dgPhErg[p] = "kein Folge-Signal: Volumen zu klein";
   else if(!g_dgPhExtraOK[p])
      g_dgPhErg[p] = "kein Folge-Signal: Preis nicht auf der Ausbruchsseite der Range-Mitte (" + txtF + ")";
}

// Phase, die jetzt im Einstiegsfenster ist (Tokio vor London); -1 = keine
int AktivePhase()
{
   for(int p = 0; p < 2; p++)
   {
      if(PhaseFensterOK(p))
         return p;
   }
   return -1;
}

// Phase für die Anzeige: die aktive, sonst die nächste heute noch anstehende, sonst die letzte
int AnzeigePhase()
{
   int ap = AktivePhase();
   if(ap >= 0)
      return ap;
   int jetzt = MinutenJetzt();
   for(int p = 0; p < 2; p++)
   {
      if(PhAktiv(p) && jetzt < PhEntryEnde(p))
         return p;
   }
   return g_lonAktiv ? 1 : 0;
}

string RichtungText(int r)
{
   if(r > 0)
      return "Long";
   if(r < 0)
      return "Short";
   return "noch keine";
}

// Ergebnis der Kerzen-Auswertung für eine Phase
string DiagErgebnisText(int p)
{
   if(!g_dgGueltig)
      return g_dgErgebnis;
   return (g_dgPhErg[p] == "") ? "Signal möglich" : g_dgPhErg[p];
}

// Chart-Zeile "Kerze London Folge Short: Close 150.312 | Ausbr ok | Vol 1.6/1.1 ok | Mitte ok"
string DiagInfoText(color &clr)
{
   clr = clrSilver;
   if(!g_dgGueltig)
      return (g_dgZeit == 0) ? "Letzte Kerze: noch nicht ausgewertet" : "Letzte Kerze: " + g_dgErgebnis;
   int p = AnzeigePhase();
   if(g_dgPhArt[p] == 0)
      return "Letzte Kerze: " + g_dgPhErg[p];
   clr = g_dgPhMoeglich[p] ? clrLime : clrSilver;
   bool folge = (g_dgPhArt[p] == 2);
   return "Kerze " + PhaseName(p) + (folge ? " Folge " : " ORB ") + ((g_dgPhRicht[p] > 0) ? "Long" : "Short")
          + ": Close " + DoubleToString(g_dgClose, Digits)
          + " | Ausbr " + OkText(g_dgPhAusOK[p])
          + " | Vol " + DoubleToString(g_dgVolX, 1) + "/" + DoubleToString(folge ? FolgeVolumenFaktor : g_volumenFaktor, 1)
          + " " + OkText(g_dgPhVolOK[p])
          + (folge ? " | Mitte " : " | Trend ") + OkText(g_dgPhExtraOK[p]);
}

//+------------------------------------------------------------------+
//| Phasen (Tokio/London), Ranges, ATR(H1), EMA(H1), Cooldown        |
//+------------------------------------------------------------------+
string PhaseName(int p)
{
   return (p == 1) ? "London" : "Tokio";
}

// London ist optional, Tokio immer aktiv
bool PhAktiv(int p)
{
   return (p == 0 || g_lonAktiv);
}

int PhRangeStart(int p)
{
   return g_rgStartMin;
}

// Tokio: RangeEnde; London: Beginn des London-Einstiegsfensters
int PhRangeEnde(int p)
{
   return (p == 0) ? g_rgEndeMin : g_lonStartMin;
}

int PhEntryStart(int p)
{
   return (p == 0) ? g_startMin : g_lonStartMin;
}

int PhEntryEnde(int p)
{
   return (p == 0) ? g_endeMin : g_lonEndeMin;
}

double PhRangeMin(int p)
{
   return (p == 0) ? RangeMinATR : LondonRangeMinATR;
}

double PhRangeMax(int p)
{
   return (p == 0) ? RangeMaxATR : LondonRangeMaxATR;
}

// Pips -> Preis (bei 3-/5-stelligen Kursen 1 Pip = 10 Punkte)
double PipGroesse()
{
   int faktor = (Digits == 3 || Digits == 5) ? 10 : 1;
   return faktor * Point;
}

// ATR der letzten geschlossenen H1-Kerze
double AtrH1()
{
   return iATR(Symbol(), PERIOD_H1, ATR_H1_Periode, 1);
}

// EMA der letzten geschlossenen H1-Kerze
double EmaH1()
{
   return iMA(Symbol(), PERIOD_H1, EMA_H1_Periode, 0, MODE_EMA, PRICE_CLOSE, 1);
}

// Beginn des aktuellen Serverzeit-Tages
datetime TagBeginn()
{
   return (datetime)((long)TimeCurrent() / 86400 * 86400);
}

int MinutenJetzt()
{
   datetime t = TimeCurrent();
   return TimeHour(t) * 60 + TimeMinute(t);
}

// Liegt die Serverzeit im Fenster [s, e)? Gleiche Zeiten = durchgehend, s > e = über Mitternacht
bool InFenster(int s, int e)
{
   if(s == e)
      return true;
   int jetzt = MinutenJetzt();
   if(s < e)
      return (jetzt >= s && jetzt < e);
   return (jetzt >= s || jetzt < e);
}

bool PhaseFensterOK(int p)
{
   return (PhAktiv(p) && InFenster(PhEntryStart(p), PhEntryEnde(p)));
}

bool SchlussErreicht()
{
   return (g_schlussMin >= 0 && MinutenJetzt() >= g_schlussMin);
}

// Verbleibende Cooldown-Sekunden nach der letzten Eröffnung/Schließung (0 = frei)
int CooldownRest()
{
   if(g_cooldownMin <= 0 || g_letzteAktion <= 0)
      return 0;
   int rest = (int)(g_letzteAktion + g_cooldownMin * 60 - TimeCurrent());
   return (rest > 0) ? rest : 0;
}

string CooldownText()
{
   int rest = CooldownRest();
   return (rest > 0) ? "Cooldown noch " + IntegerToString(rest) + " s" : "Cooldown frei";
}

// Kommentar der Order: Phase und Art, daran werden die Trades je Phase gezählt
string OrderKommentar(int phase, int art)
{
   if(phase < 0 || art == 0)
      return ORDER_KOMMENTAR;
   return "SSA " + PhaseName(phase) + ((art == 2) ? " Folge" : " ORB");
}

// Die gerade selektierte Order (eigene, Symbol + Magic) in Phasen-Zähler, Phasen-Richtung und Cooldown-Zeit einrechnen
void TradeZaehlen(datetime tag0)
{
   if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber || OrderType() > OP_SELL)
      return;
   datetime ot = OrderOpenTime();
   datetime ct = OrderCloseTime();
   if(ot > g_letzteAktion)
      g_letzteAktion = ot;
   if(ct > g_letzteAktion)
      g_letzteAktion = ct;
   if(ot < tag0)
      return;
   string kom = OrderComment();
   for(int p = 0; p < 2; p++)
   {
      if(StringFind(kom, "SSA " + PhaseName(p)) >= 0)
      {
         g_phTrades[p]++;
         if(g_phRicht[p] == 0 && StringFind(kom, "ORB") >= 0)
            g_phRicht[p] = (OrderType() == OP_BUY) ? 1 : -1;
      }
   }
}

// Trades je Phase heute (offene Orders + Historie, nach Order-Kommentar) und letzte Eröffnung/Schließung neu zählen
void HeuteTradesAktualisieren()
{
   g_phTrades[0]  = 0;
   g_phTrades[1]  = 0;
   g_letzteAktion = 0;
   datetime tag0 = TagBeginn();
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         TradeZaehlen(tag0);
   }
   for(int k = OrdersHistoryTotal() - 1; k >= 0; k--)
   {
      if(OrderSelect(k, SELECT_BY_POS, MODE_HISTORY))
         TradeZaehlen(tag0);
   }
}

// SL- und TP-Abstand (Preis) für einen Einstieg zum Preis 'preis'.
//  Ausbruch (art 1) und Hand-Trade: SL = Range-Mitte der Phase, Abstand höchstens SL_MaxATR * ATR(H1);
//    ohne passende Range-Mitte (keine Range, Mitte auf der falschen Seite) gilt der Deckel.
//  Folge-Scalp (art 2): SL = FolgeSL_ATR * ATR(M1).
//  Dazu Mindestabstand des Brokers (StopLevel + Spread beim SL). TP = TP_CRV * SL-Abstand, mindestens StopLevel.
//  phase -1 = aktive Phase. false, wenn der nötige ATR fehlt.
bool ExitDistanzen(int richtung, double preis, int phase, int art, double &slDist, double &tpDist)
{
   slDist = 0.0;
   tpDist = 0.0;
   double d = 0.0;
   if(art == 2)
   {
      double atrM1 = AktuelleATR();
      if(atrM1 <= 0.0)
         return false;
      d = FolgeSL_ATR * atrM1;
   }
   else
   {
      double atrH1 = AtrH1();
      if(atrH1 <= 0.0)
         return false;
      double deckel = SL_MaxATR * atrH1;
      d = deckel;
      int ph = (phase >= 0) ? phase : AktivePhase();
      if(ph >= 0 && g_rgDa[ph] && g_rgHoch[ph] > g_rgTief[ph])
      {
         double mitte = (g_rgHoch[ph] + g_rgTief[ph]) / 2.0;
         int    rr    = richtung;
         if(rr == 0)
            rr = (preis >= mitte) ? 1 : -1;
         double dm = (rr > 0) ? preis - mitte : mitte - preis;
         if(dm > 0.0)
            d = MathMin(dm, deckel);
      }
   }
   double spread  = Ask - Bid;
   double stopLvl = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   slDist = MathMax(d, stopLvl + spread);
   tpDist = MathMax(TP_CRV * slDist, stopLvl);
   return true;
}

// Range der Phase p aus den M1-Kerzen berechnen (Kerzen mit Öffnungszeit in [Range-Beginn, Range-Ende) des heutigen
// Serverzeit-Tages). Funktioniert auch, wenn der EA erst nach Range-Ende angehängt wurde (liest die Historie).
void RangeBerechnen(int p)
{
   datetime tag0 = TagBeginn();
   g_rgTag          = tag0;
   g_rgDa[p]        = false;
   g_rgGueltig[p]   = false;
   g_rgHoch[p]      = 0.0;
   g_rgTief[p]      = 0.0;
   g_rgKerzen[p]    = 0;
   g_rgBreiteATR[p] = 0.0;
   if(!PhAktiv(p))
   {
      g_rgGrund[p] = "aus";
      return;
   }
   int      rs = PhRangeStart(p);
   int      re = PhRangeEnde(p);
   datetime t0 = tag0 + rs * 60;
   datetime t1 = tag0 + re * 60;
   int jetzt = MinutenJetzt();
   if(jetzt < rs)
   {
      g_rgGrund[p] = "noch nicht begonnen";
      return;
   }
   bool vorbei = (jetzt >= re);
   if(vorbei && iTime(Symbol(), PERIOD_M1, 0) < t1)
   {
      g_rgGrund[p] = "unvollständig (Kerze nach Range-Ende fehlt noch)";
      return;
   }
   int nBars = iBars(Symbol(), PERIOD_M1);
   if(nBars <= 0)
   {
      g_rgGrund[p] = "ohne M1-Historie";
      return;
   }
   if(iTime(Symbol(), PERIOD_M1, nBars - 1) > t0)
   {
      g_rgGrund[p] = "ohne M1-Historie bis Range-Beginn";
      return;
   }
   int sEnde  = iBarShift(Symbol(), PERIOD_M1, t1 - 60, false);   // Kerze bei/vor der letzten Range-Minute
   int sStart = iBarShift(Symbol(), PERIOD_M1, t0, false);        // Kerze bei/vor Range-Beginn
   if(sEnde < 0 || sStart < 0)
   {
      g_rgGrund[p] = "ohne M1-Kerzen im Fenster";
      return;
   }
   if(iTime(Symbol(), PERIOD_M1, sEnde) >= t1)
      sEnde++;
   if(iTime(Symbol(), PERIOD_M1, sStart) < t0)
      sStart--;                                                   // erste Kerze innerhalb der Range
   if(sEnde < 1)
      sEnde = 1;                                                  // die laufende Kerze (Shift 0) nie mitrechnen
   int anz = sStart - sEnde + 1;
   if(anz < 1 || iTime(Symbol(), PERIOD_M1, sEnde) < t0 || iTime(Symbol(), PERIOD_M1, sEnde) >= t1
      || iTime(Symbol(), PERIOD_M1, sStart) < t0 || iTime(Symbol(), PERIOD_M1, sStart) >= t1)
   {
      g_rgGrund[p] = "ohne M1-Kerzen im Fenster";
      return;
   }
   int hi = iHighest(Symbol(), PERIOD_M1, MODE_HIGH, anz, sEnde);
   int lo = iLowest(Symbol(), PERIOD_M1, MODE_LOW, anz, sEnde);
   if(hi < 0 || lo < 0)
   {
      g_rgGrund[p] = "ohne M1-Kerzen im Fenster";
      return;
   }
   g_rgHoch[p]   = iHigh(Symbol(), PERIOD_M1, hi);
   g_rgTief[p]   = iLow(Symbol(), PERIOD_M1, lo);
   g_rgKerzen[p] = anz;
   if(!vorbei)
   {
      g_rgGrund[p] = "läuft";      // Zwischenstand, noch nicht für Signale
      return;
   }
   g_rgDa[p] = true;
   double atr = AtrH1();
   if(atr <= 0.0)
   {
      g_rgGrund[p] = "ohne ATR(H1)";
      return;
   }
   g_rgBreiteATR[p] = (g_rgHoch[p] - g_rgTief[p]) / atr;
   g_rgGueltig[p]   = (g_rgBreiteATR[p] >= PhRangeMin(p) - 1e-9 && g_rgBreiteATR[p] <= PhRangeMax(p) + 1e-9);
   g_rgGrund[p]     = g_rgGueltig[p] ? "gültig"
                      : "ungültig: Breite " + DoubleToString(g_rgBreiteATR[p], 2) + " x ATR(H1), erlaubt "
                        + DoubleToString(PhRangeMin(p), 2) + "-" + DoubleToString(PhRangeMax(p), 2);
}

// Beide Ranges neu berechnen und im Chart nachziehen
void RangeAktualisieren()
{
   RangeBerechnen(0);
   RangeBerechnen(1);
   RangeZeichnen();
}

// Neuer Tag: alles zurücksetzen, Linien entfernen
void RangeZuruecksetzen()
{
   g_rgTag = 0;
   for(int p = 0; p < 2; p++)
   {
      g_rgDa[p]        = false;
      g_rgGueltig[p]   = false;
      g_rgHoch[p]      = 0.0;
      g_rgTief[p]      = 0.0;
      g_rgBreiteATR[p] = 0.0;
      g_rgKerzen[p]    = 0;
      g_rgGrund[p]     = "noch nicht berechnet";
   }
   RangeZeichnen();
}

void RangeLinieSetzen(string name, datetime t0, datetime t1, double preis, color clr, int breite, string text)
{
   ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_TREND, 0, t0, preis, t1, preis))
      return;
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, breite);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

// Range-Hoch/-Tief beider Phasen als waagerechte Linien (Tokio gold, London blau, ungültig grau); nur bei Änderung neu gezeichnet
void RangeZeichnen()
{
   if(!g_ui)
      return;
   for(int p = 0; p < 2; p++)
   {
      string nHi = PRAEFIX + "rg" + IntegerToString(p) + "_hi";
      string nLo = PRAEFIX + "rg" + IntegerToString(p) + "_lo";
      if(g_rgKerzen[p] <= 0)
      {
         if(g_rgGezKey[p] != "")
         {
            ObjectDelete(0, nHi);
            ObjectDelete(0, nLo);
            g_rgGezKey[p] = "";
            ChartRedraw(0);
         }
         continue;
      }
      string key = IntegerToString((long)g_rgTag) + "|" + DoubleToString(g_rgHoch[p], Digits) + "|"
                   + DoubleToString(g_rgTief[p], Digits) + "|" + (g_rgDa[p] ? "1" : "0") + (g_rgGueltig[p] ? "1" : "0");
      if(key == g_rgGezKey[p])
         continue;
      color clr = clrSilver;
      if(g_rgDa[p])
         clr = g_rgGueltig[p] ? ((p == 0) ? clrGold : clrDodgerBlue) : clrDimGray;
      datetime t0 = g_rgTag + PhRangeStart(p) * 60;
      datetime t1 = g_rgTag + 86400;
      RangeLinieSetzen(nHi, t0, t1, g_rgHoch[p], clr, (p == 0) ? 2 : 1, PhaseName(p) + " Range-Hoch");
      RangeLinieSetzen(nLo, t0, t1, g_rgTief[p], clr, (p == 0) ? 2 : 1, PhaseName(p) + " Range-Tief");
      g_rgGezKey[p] = key;
      ChartRedraw(0);
   }
}

// "Hoch x | Tief y | z Pips = w x ATR(H1) ok" (telegram = true: Häkchen und "×")
string RangeWerte(int p, bool telegram)
{
   string s = "Hoch " + DoubleToString(g_rgHoch[p], Digits) + " | Tief " + DoubleToString(g_rgTief[p], Digits)
              + " | " + DoubleToString((g_rgHoch[p] - g_rgTief[p]) / PipGroesse(), 1) + " Pips";
   if(!g_rgDa[p])
      return s + " (läuft)";
   return s + " = " + DoubleToString(g_rgBreiteATR[p], 2) + (telegram ? "×" : " x ") + "ATR(H1) "
          + (telegram ? HaekchenText(g_rgGueltig[p]) : OkText(g_rgGueltig[p]));
}

// Aktueller Zustand einer Phase in Worten (ohne Phasennamen)
string PhaseText(int p)
{
   if(!PhAktiv(p))
      return "aus";
   int jetzt = MinutenJetzt();
   string rg = MinutenText(PhRangeStart(p)) + "-" + MinutenText(PhRangeEnde(p));
   if(jetzt < PhRangeStart(p))
      return "wartet auf Range " + rg;
   if(jetzt < PhRangeEnde(p))
      return "Range läuft (" + rg + ")";
   if(!g_rgDa[p])
      return "Range fehlt (" + g_rgGrund[p] + ")";
   if(!g_rgGueltig[p])
      return "Range " + g_rgGrund[p];
   string fenster = MinutenText(PhEntryStart(p)) + "-" + MinutenText(PhEntryEnde(p));
   if(!InFenster(PhEntryStart(p), PhEntryEnde(p)))
   {
      if(jetzt >= PhEntryEnde(p) && PhEntryStart(p) < PhEntryEnde(p))
         return "Einstiegsfenster vorbei (" + fenster + ")";
      return "Einstiegsfenster noch zu (" + fenster + ")";
   }
   if(SchlussErreicht())
      return "Schlusszeit erreicht";
   if(g_phTrades[p] >= g_maxTrades)
      return "Trade-Limit erreicht (" + IntegerToString(g_phTrades[p]) + "/" + IntegerToString(g_maxTrades) + ")";
   if(g_phRicht[p] == 0)
      return "bereit für Ausbruch (Opening Range)";
   if(g_folgeAktiv)
      return "bereit für Folge-Scalps " + RichtungText(g_phRicht[p]);
   return "Richtung " + RichtungText(g_phRicht[p]) + ", Folge-Scalps aus";
}

// "Tokio: Long 3/10 | London: noch keine 0/10 | Cooldown frei"
string PhasenZeile()
{
   string s = "";
   for(int p = 0; p < 2; p++)
   {
      if(p > 0)
         s += " | ";
      s += PhaseName(p) + ": ";
      if(!PhAktiv(p))
         s += "aus";
      else
         s += RichtungText(g_phRicht[p]) + " " + IntegerToString(g_phTrades[p]) + "/" + IntegerToString(g_maxTrades);
   }
   return s + " | " + CooldownText();
}

// Zeitausstieg: ab SchlussZeit (Serverzeit) einmal pro Tag alle eigenen Positionen auf diesem Symbol schließen.
// Im Gegensatz zum Kill-Switch bleibt der Handel erlaubt (neue Einstiege blockt HandelErlaubt ab der Schlusszeit).
void SchlussTagSetzen(datetime tag)
{
   g_schlussTag = tag;
   FernSpeichern("schlusstag", (double)tag);
}

void ZeitausstiegPruefen()
{
   if(g_schlussMin < 0 || !SchlussErreicht())
      return;
   datetime heute = TagBeginn();
   if(g_schlussTag == heute || TimeLocal() < g_schlussRetry)
      return;

   int tickets[];
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber || OrderType() > OP_SELL)
         continue;
      ArrayResize(tickets, n + 1);
      tickets[n] = OrderTicket();
      n++;
   }
   int    geschlossen = 0;
   int    fehler      = 0;
   string letzterFehler = "";
   for(int k = 0; k < n; k++)
   {
      string fe = "";
      if(PositionSchliessen(tickets[k], fe))
         geschlossen++;
      else
      {
         fehler++;
         letzterFehler = fe;
      }
   }
   if(fehler > 0 && g_schlussVersuche < 5)
   {
      g_schlussVersuche++;
      g_schlussRetry = TimeLocal() + 15;
      HinweisSetzen("Zeitausstieg " + MinutenText(g_schlussMin) + ": " + IntegerToString(fehler)
                    + " Position(en) nicht geschlossen (" + letzterFehler + "), neuer Versuch");
      return;
   }
   SchlussTagSetzen(heute);
   g_schlussVersuche = 0;
   if(n == 0)
      return;
   string text = "Zeitausstieg " + MinutenText(g_schlussMin) + ": " + IntegerToString(geschlossen) + " Position(en) geschlossen"
                 + ((fehler > 0) ? ", " + IntegerToString(fehler) + " Fehler (" + letzterFehler + ")" : "");
   HinweisSetzen(text);
   TgNachrichtSenden("⏰ " + HtmlEscape(text), "");
}

//+------------------------------------------------------------------+
//| Tages- und Verlustverwaltung                                     |
//+------------------------------------------------------------------+
// Neuen Serverzeit-Tag erkennen und Tagesstart-Equity setzen
void TagPruefen()
{
   datetime heute = (datetime)((long)TimeCurrent() / 86400 * 86400);
   if(heute != g_tag)
   {
      g_tag        = heute;
      g_tagEquity  = AccountEquity();
      g_tagesLimit = false;
      g_phRicht[0]  = 0;
      g_phRicht[1]  = 0;
      g_phTrades[0] = 0;
      g_phTrades[1] = 0;
      g_schlussVersuche = 0;
      RangeZuruecksetzen();
      TagSpeichern();
      Print("ScalpScout Asia: neuer Handelstag, Start-Equity ", DoubleToString(g_tagEquity, 2));
   }
   // Tageslimit einrasten (gilt bis zum nächsten Tag)
   if(!g_tagesLimit && g_tagesLimitProz > 0.0 && g_tagEquity > 0.0)
   {
      double verlustProz = (g_tagEquity - AccountEquity()) / g_tagEquity * 100.0;
      if(verlustProz >= g_tagesLimitProz)
      {
         g_tagesLimit = true;
         Print("ScalpScout Asia: Tagesverlust-Limit erreicht (", DoubleToString(verlustProz, 2),
               " %). Keine neuen Trades bis zum nächsten Tag.");
      }
   }
}

// Liegt die Serverzeit in einem der Einstiegsfenster (Tokio oder London)?
bool ZeitfensterOK()
{
   return (PhaseFensterOK(0) || PhaseFensterOK(1));
}

// Prüft alle Schutzfilter. true = Handel erlaubt, sonst Grund in 'grund'
// manuell = Hand-Trade per Telegram: Zeitfenster und Spread-Limit werden ignoriert
bool HandelErlaubt(string &grund, int richtung = 0, bool manuell = false, int phase = -1, int art = 0)
{
   grund = "";
   VerlustSerieAktualisieren();

   if(g_gestoppt)
   {
      grund = "Gestoppt (Kill-Switch) - per Telegram /start oder EA neu starten";
      return false;
   }
   if(g_tgPause)
   {
      grund = "Pausiert per Telegram (/start hebt auf)";
      return false;
   }
   if((g_modus != NUR_SIGNALE || manuell) && !IsTesting() && (!IsTradeAllowed() || !IsExpertEnabled()))
   {
      grund = "Algo-Trading/AutoTrading ist aus";
      return false;
   }
   if(!manuell && !ZeitfensterOK())
   {
      grund = "Außerhalb Handelszeit (Tokio " + MinutenText(g_startMin) + "-" + MinutenText(g_endeMin)
              + (g_lonAktiv ? ", London " + MinutenText(g_lonStartMin) + "-" + MinutenText(g_lonEndeMin) : "") + ")";
      return false;
   }
   if(!manuell && SchlussErreicht())
   {
      grund = "Nach Schlusszeit (" + MinutenText(g_schlussMin) + ")";
      return false;
   }
   if(g_tagesLimit)
   {
      grund = "Tagesverlust-Limit erreicht";
      return false;
   }
   if(PauseNachVerlusten > 0 && g_verlustSerie >= PauseNachVerlusten && g_letzterVerlust > 0)
   {
      datetime ende = g_letzterVerlust + PauseMinuten * 60;
      if(TimeCurrent() < ende)
      {
         grund = "Pause nach " + IntegerToString(g_verlustSerie) + " Verlusten (noch "
                 + IntegerToString((int)((ende - TimeCurrent()) / 60) + 1) + " min)";
         return false;
      }
   }
   if(ZaehlePositionen() >= MaxOffenePositionen)
   {
      grund = "Max. offene Positionen erreicht";
      return false;
   }
   if(!manuell && CooldownRest() > 0)
   {
      grund = "Cooldown nach letztem Trade (noch " + IntegerToString(CooldownRest()) + " s)";
      return false;
   }
   double maxSp  = MaxSpreadAktuell(richtung, phase, art);
   double sp     = SpreadPunkte();
   double ko     = KommissionPunkte();
   double kosten = sp + ko;
   if(!manuell && MaxSpreadPunkte <= 0.0 && maxSp <= 0.0)
   {
      grund = "ATR nicht verfügbar";
      return false;
   }
   if(!manuell && kosten > maxSp)
   {
      grund = "Kosten zu hoch (" + KostenText(sp, ko) + " > " + DoubleToString(maxSp, 1) + " Pkt)";
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Plan berechnen: Preise, SL/TP, Lot                               |
//+------------------------------------------------------------------+
// lotVorgabe > 0: feste Lotgröße statt Risiko-Berechnung (Hand-Trade, Deckel = FernMaxLotObergrenze)
bool BerechnePlan(int richtung, double atr, Plan &p, string &grund, double lotVorgabe = 0.0, int phase = -1, int art = 0)
{
   grund = "";
   RefreshRates();

   if(atr <= 0.0)
   {
      grund = "ATR(M1) nicht verfügbar";
      return false;
   }

   p.richtung  = richtung;
   p.atr       = atr;
   p.phase     = phase;
   p.art       = art;
   p.preis     = (richtung > 0) ? Ask : Bid;
   p.spreadPkt = SpreadPunkte();
   p.kommPkt   = KommissionPunkte();

   double slDist = 0.0;
   double tpDist = 0.0;
   if(!ExitDistanzen(richtung, p.preis, phase, art, slDist, tpDist))
   {
      grund = (art == 2) ? "ATR(M1) nicht verfügbar" : "ATR(H1) nicht verfügbar";
      return false;
   }

   if(richtung > 0)
   {
      p.sl = NormalizeDouble(p.preis - slDist, Digits);
      p.tp = NormalizeDouble(p.preis + tpDist, Digits);
   }
   else
   {
      p.sl = NormalizeDouble(p.preis + slDist, Digits);
      p.tp = NormalizeDouble(p.preis - tpDist, Digits);
   }
   p.slDist = MathAbs(p.preis - p.sl);
   p.tpDist = MathAbs(p.preis - p.tp);
   if(p.slDist <= 0.0)
   {
      grund = "SL-Abstand ungültig";
      return false;
   }
   p.crv = p.tpDist / p.slDist;

   // Lotgröße aus Risiko
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double minLot    = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLotBr  = MarketInfo(Symbol(), MODE_MAXLOT);
   if(tickSize <= 0.0 || tickValue <= 0.0 || minLot <= 0.0)
   {
      grund = "Symbol-Daten (TickValue/TickSize/MinLot) fehlen";
      return false;
   }
   double risikoGeld   = AccountEquity() * g_risiko / 100.0;
   double verlustProLot = p.slDist / tickSize * tickValue + KommissionProLot;   // SL-Verlust + Kommission
   if(verlustProLot <= 0.0)
   {
      grund = "Verlust pro Lot ungültig";
      return false;
   }
   double lotRoh = (lotVorgabe > 0.0) ? lotVorgabe : risikoGeld / verlustProLot;
   double lot    = LotAbrunden(lotRoh);

   if(lot < minLot - 1e-9)
   {
      grund = "Lot " + DoubleToString(lotRoh, 4) + " < MinLot " + DoubleToString(minLot, 2)
              + ": Risiko " + DoubleToString(g_risiko, 1) + " % zu klein, kein Trade";
      return false;
   }
   if(lotVorgabe <= 0.0 && lot > g_maxLot)
      lot = LotAbrunden(g_maxLot);
   if(lotVorgabe > 0.0 && lot > FernMaxLotObergrenze)
      lot = LotAbrunden(FernMaxLotObergrenze);
   if(maxLotBr > 0.0 && lot > maxLotBr)
      lot = LotAbrunden(maxLotBr);
   if(lot < minLot - 1e-9)
   {
      grund = "MaxLot-Deckel (" + DoubleToString(g_maxLot, 2) + ") < MinLot " + DoubleToString(minLot, 2)
              + ", kein Trade";
      return false;
   }
   p.lot = lot;

   // Margin prüfen
   ResetLastError();
   double fm  = AccountFreeMarginCheck(Symbol(), (richtung > 0) ? OP_BUY : OP_SELL, p.lot);
   int    err = GetLastError();
   if(fm <= 0.0 || err == FEHLER_NICHT_GENUG_GELD)
   {
      if(err != 0)
         LogFehler("AccountFreeMarginCheck", err);
      grund = "Nicht genug freie Margin für " + DoubleToString(p.lot, 2) + " Lot";
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Order senden (mit Retry bei Requote)                             |
//+------------------------------------------------------------------+
bool OrderOeffnen(int richtung, double atr, string &grund, double lotVorgabe = 0.0, int phase = -1, int art = 0)
{
   int   cmd  = (richtung > 0) ? OP_BUY : OP_SELL;
   color clr  = (richtung > 0) ? clrLime : clrRed;
   int   slip = SlippagePunkte();
   int   max  = MathMax(1, OrderVersuche);

   for(int v = 1; v <= max; v++)
   {
      // Handelskontext abwarten (max. ca. 3 s)
      if(!IsTesting())
      {
         int warte = 0;
         while(IsTradeContextBusy() && warte < 60)
         {
            Sleep(50);
            warte++;
         }
      }

      // Bei jedem Versuch frische Preise, SL/TP relativ zum aktuellen Preis
      Plan p;
      if(!BerechnePlan(richtung, atr, p, grund, lotVorgabe, phase, art))
         return false;

      ResetLastError();
      int ticket = OrderSend(Symbol(), cmd, p.lot, p.preis, slip, p.sl, p.tp,
                             OrderKommentar(phase, art), MagicNumber, 0, clr);
      if(ticket > 0)
      {
         Print("ScalpScout Asia: Order eröffnet #", ticket, " ", (richtung > 0 ? "BUY " : "SELL "),
               DoubleToString(p.lot, 2), " ", Symbol(), " @", DoubleToString(p.preis, Digits),
               " SL ", DoubleToString(p.sl, Digits), " TP ", DoubleToString(p.tp, Digits),
               " (Versuch ", v, ")");
         g_orderTicket = ticket;
         g_dgTrades++;
         g_letzteAktion = TimeCurrent();
         if(phase >= 0)
            g_phTrades[phase]++;
         g_orderPreis  = p.preis;
         if(OrderSelect(ticket, SELECT_BY_TICKET))
            g_orderPreis = OrderOpenPrice();
         return true;
      }

      int err = GetLastError();
      LogFehler("OrderSend (Versuch " + IntegerToString(v) + "/" + IntegerToString(max) + ")", err);
      grund = "OrderSend: " + FehlerText(err) + " (" + IntegerToString(err) + ")";

      bool wiederholen = (err == FEHLER_REQUOTE || err == FEHLER_PREIS_GEAENDERT ||
                          err == FEHLER_KEINE_KURSE || err == FEHLER_BROKER_BESCHAEFT ||
                          err == FEHLER_KONTEXT_BELEGT);
      if(!wiederholen)
         return false;
      if(!IsTesting())
         Sleep(200);
   }
   return false;
}

//+------------------------------------------------------------------+
//| Kill-Switch: alle eigenen Positionen auf diesem Symbol schließen |
//+------------------------------------------------------------------+
// Rückgabe über geschlossen/fehler; die Bestätigung (MessageBox bzw. Telegram-Knopf) liegt beim Aufrufer
void AlleSchliessen(int &geschlossen, int &fehler)
{
   geschlossen = 0;
   fehler = 0;
   int slip = SlippagePunkte();
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber || OrderType() > OP_SELL)
         continue;
      int    ticket = OrderTicket();
      int    typ    = OrderType();
      double lots   = OrderLots();
      bool   ok     = false;
      for(int v = 1; v <= 3 && !ok; v++)
      {
         RefreshRates();
         double preis = (typ == OP_BUY) ? Bid : Ask;
         ResetLastError();
         ok = OrderClose(ticket, lots, preis, slip, clrOrange);
         if(!ok)
         {
            LogFehler("OrderClose #" + IntegerToString(ticket) + " (Versuch " + IntegerToString(v) + ")",
                      GetLastError());
            if(!IsTesting())
               Sleep(200);
         }
         // für nächsten Versuch Order neu selektieren
         if(!ok && !OrderSelect(ticket, SELECT_BY_TICKET))
            break;
      }
      if(ok) geschlossen++; else fehler++;
   }
   g_gestoppt = true;
   SignalVerwerfen("Kill-Switch", "🛑 verworfen (Kill-Switch)");
   PanelLoeschen();
   g_sig.aktiv = false;
   HinweisSetzen("Kill-Switch: " + IntegerToString(geschlossen) + " Position(en) geschlossen, "
                 + IntegerToString(fehler) + " Fehler. Neue Trades gesperrt.");
   Alert("ScalpScout Asia ", Symbol(), ": Kill-Switch - ", geschlossen, " geschlossen, ", fehler, " Fehler");
}

//+------------------------------------------------------------------+
//| Info-Bereich oben links                                          |
//+------------------------------------------------------------------+
void UiAktualisieren()
{
   if(!g_ui)
      return;
   double atr    = AktuelleATR();
   double atrH1  = AtrH1();
   double maxSp  = MaxSpreadAktuell(0);
   double sp     = SpreadPunkte();
   double ko     = KommissionPunkte();
   double diff   = AccountEquity() - g_tagEquity;
   double proz   = (g_tagEquity > 0.0) ? diff / g_tagEquity * 100.0 : 0.0;
   string grund  = "";
   bool   frei   = HandelErlaubt(grund, 0);

   InfoZeile(0, "ScalpScout Asia | " + Symbol() + " | Magic " + IntegerToString(MagicNumber), clrWhite);
   InfoZeile(1, "Modus: " + ModusText() + (IsTesting() ? " (Tester)" : "") + " | Risiko "
                + DoubleToString(g_risiko, 1) + " % | MaxLot " + LotText(g_maxLot),
             (FernModusAbw() || FernRisikoAbw() || FernMaxLotAbw()) ? clrGold : clrWhite);
   InfoZeile(2, "Kosten: " + KostenText(sp, ko) + " / max " + DoubleToString(maxSp, 1) + " Pkt",
             (sp + ko > maxSp) ? clrOrangeRed : clrLime);
   InfoZeile(3, "ATR(H1, " + IntegerToString(ATR_H1_Periode) + "): " + DoubleToString(atrH1, Digits)
                + " (" + DoubleToString(atrH1 / PipGroesse(), 1) + " Pips) | ATR(M1): " + DoubleToString(atr, Digits), clrWhite);
   InfoZeile(4, "Serverzeit: " + TimeToString(TimeCurrent(), TIME_MINUTES)
                + " (Tokio " + MinutenText(g_startMin) + "-" + MinutenText(g_endeMin)
                + (g_lonAktiv ? ", London " + MinutenText(g_lonStartMin) + "-" + MinutenText(g_lonEndeMin) : "")
                + ((g_schlussMin >= 0) ? ", Schluss " + MinutenText(g_schlussMin) : "") + ")",
             ZeitfensterOK() ? clrLime : clrOrange);
   InfoZeile(5, "Tagesergebnis: " + DoubleToString(diff, 2) + " " + AccountCurrency()
                + " (" + DoubleToString(proz, 2) + " %)", (diff >= 0.0) ? clrLime : clrOrangeRed);
   InfoZeile(6, g_tagesLimit ? "Verlustlimit: ERREICHT (" + LimitText(g_tagesLimitProz) + ")"
                             : "Verlustlimit: ok (max " + LimitText(g_tagesLimitProz) + ")",
             g_tagesLimit ? clrOrangeRed : clrLime);
   InfoZeile(7, frei ? "Status: bereit" : "Blockiert: " + grund, frei ? clrLime : clrOrange);
   color tgFarbe = clrSilver;
   string tgText = TgInfoText(tgFarbe);
   InfoZeile(8, tgText, tgFarbe);
   for(int p = 0; p < 2; p++)
   {
      color  rgFarbe = clrSilver;
      string rgText  = "Range " + PhaseName(p) + " " + MinutenText(PhRangeStart(p)) + "-" + MinutenText(PhRangeEnde(p)) + ": ";
      if(!PhAktiv(p))
         rgText += "aus";
      else if(g_rgKerzen[p] > 0)
      {
         rgText += RangeWerte(p, false);
         if(g_rgDa[p])
            rgFarbe = g_rgGueltig[p] ? clrLime : clrOrangeRed;
      }
      else
         rgText += g_rgGrund[p];
      InfoZeile(9 + p, rgText, rgFarbe);
   }
   int    ap    = AnzeigePhase();
   string phase = PhaseText(ap);
   InfoZeile(11, "Phase " + PhaseName(ap) + ": " + phase,
             (StringFind(phase, "bereit") == 0) ? clrLime : clrSilver);
   InfoZeile(12, "Richtung/Trades: " + PhasenZeile(), (CooldownRest() > 0) ? clrOrange : clrWhite);
   color dgFarbe = clrSilver;
   string dgText = DiagInfoText(dgFarbe);
   InfoZeile(13, dgText, dgFarbe);
   string h = (g_hinweis == "") ? "Hinweis: -" :
              "Hinweis (" + TimeToString(g_hinweisZeit, TIME_MINUTES) + "): " + g_hinweis;
   InfoZeile(14, h, (g_hinweis == "") ? clrSilver : clrGold);
}

//+------------------------------------------------------------------+
//| Signal-Panel (Freigabe-Modus)                                    |
//+------------------------------------------------------------------+
string PanelZeileText(int i)
{
   Plan p = g_sig.plan;
   switch(i)
   {
      case 0: return "SIGNAL" + ((p.phase >= 0) ? " " + PhaseName(p.phase) + ((p.art == 2) ? " Folge" : " ORB") : "")
                     + ": " + (p.richtung > 0 ? "LONG (Kauf)" : "SHORT (Verkauf)");
      case 1: return "Einstieg ca.: " + DoubleToString(p.preis, Digits);
      case 2: return "Stop-Loss: " + DoubleToString(p.sl, Digits) + "  (" + DoubleToString(p.slDist / Point, 0) + " Pkt)";
      case 3: return "Take-Profit: " + DoubleToString(p.tp, Digits) + "  (" + DoubleToString(p.tpDist / Point, 0) + " Pkt)";
      case 4: return "Lot: " + DoubleToString(p.lot, LotStellen(MarketInfo(Symbol(), MODE_LOTSTEP)))
                     + "  | Risiko " + DoubleToString(g_risiko, 1) + " %";
      case 5: return "Kosten: " + KostenText(p.spreadPkt, p.kommPkt) + " Pkt | CRV 1:" + DoubleToString(p.crv, 2);
      case 6:
      {
         int rest = SignalGueltigSek - (int)(TimeLocal() - g_sig.zeit);
         if(rest < 0) rest = 0;
         return "Gültig noch: " + IntegerToString(rest) + " s";
      }
   }
   return "";
}

// Klick auf "Ausführen" bzw. Telegram "JA". true = Order eröffnet.
// ergebnis: bei Erfolg "#Ticket @Preis", sonst der Grund.
// perTelegram: true = der Aufrufer (Telegram) ändert die Nachricht selbst.
bool SignalAusfuehren(bool perTelegram, string &ergebnis)
{
   ergebnis = "";
   if(!g_sig.aktiv)
   {
      ergebnis = "kein aktives Signal";
      return false;
   }
   SignalPruefen();
   if(!g_sig.aktiv)
   {
      ergebnis = "Signal abgelaufen";
      return false;
   }

   int    richtung = g_sig.plan.richtung;
   double atr      = g_sig.plan.atr;
   int    phase    = g_sig.plan.phase;
   int    art      = g_sig.plan.art;
   long   msgId    = g_sigMsgId;
   string kopf     = g_tgKopf;
   g_sig.aktiv = false;      // gegen Doppelklick
   PanelLoeschen();

   string grund = "";
   bool   ok    = false;
   if(!HandelErlaubt(grund, richtung, false, phase, art))
   {
      HinweisSetzen("Nicht ausgeführt: " + grund);
      DiagVerworfen(grund);
      ergebnis = grund;
   }
   else if(!OrderOeffnen(richtung, atr, grund, 0.0, phase, art))
   {
      HinweisSetzen("Order fehlgeschlagen: " + grund);
      DiagVerworfen(grund);
      ergebnis = grund;
   }
   else
   {
      HinweisSetzen("Order ausgeführt (" + (richtung > 0 ? "LONG" : "SHORT") + ")");
      ergebnis = "#" + IntegerToString(g_orderTicket) + " @" + DoubleToString(g_orderPreis, Digits);
      ok = true;
   }

   if(!perTelegram && msgId > 0)
      TgNachrichtBearbeiten(msgId, kopf + "\n" + (ok ? "✅ am PC ausgeführt: " + ergebnis
                                                   : "⚠️ am PC nicht ausgeführt: " + HtmlEscape(ergebnis)));
   return ok;
}

//+------------------------------------------------------------------+
//| Telegram-Fernbedienung (WebRequest, nur Timer und Ereignisse)    |
//+------------------------------------------------------------------+
// Telegram ist komplett aus bei !TelegramAktiv, leerem Token/Chat-ID oder im Tester.
// Fehler führen nie zum Absturz: Anfragen schlagen still fehl, der Handel läuft weiter.

// Nachricht senden; Rückgabe message_id (0 = nicht gesendet). tastatur = reply_markup-JSON oder "".
long TgNachrichtSenden(string html, string tastatur)
{
   if(!TgBereit())
      return 0;
   string body = "{\"chat_id\":\"" + JsonEscape(g_tgChat) + "\",\"text\":\"" + JsonEscape("[Asia] " + html)
                 + "\",\"parse_mode\":\"HTML\"";
   if(tastatur != "")
      body += ",\"reply_markup\":" + tastatur;
   body += "}";
   string antwort = "";
   if(!TgAnfrage("sendMessage", body, antwort))
      return 0;
   long id = 0;
   int p = StringFind(antwort, "\"message_id\":");
   if(p >= 0)
      JsonZahl(antwort, "message_id", p, id);
   return id;
}

// Text einer gesendeten Nachricht ändern und die Knöpfe entfernen
bool TgNachrichtBearbeiten(long msgId, string html)
{
   if(msgId <= 0 || !TgBereit())
      return false;
   string body = "{\"chat_id\":\"" + JsonEscape(g_tgChat) + "\",\"message_id\":" + IntegerToString(msgId)
                 + ",\"text\":\"" + JsonEscape("[Asia] " + html) + "\",\"parse_mode\":\"HTML\""
                 + ",\"reply_markup\":{\"inline_keyboard\":[]}}";
   string antwort = "";
   return TgAnfrage("editMessageText", body, antwort);
}

string TgSignalKopf(Plan &p)
{
   string art = (p.phase >= 0) ? " (" + PhaseName(p.phase) + ((p.art == 2) ? " Folge" : " ORB") + ")" : "";
   return "<b>" + HtmlEscape(Symbol()) + "</b>  " + ((p.richtung > 0) ? "🟢 KAUF" : "🔴 VERKAUF") + art;
}

// Zeile mit der Range der Phase des Signals (leer bei Hand-Trades)
string TgRangeZeile(Plan &p)
{
   if(p.phase < 0 || g_rgKerzen[p.phase] <= 0)
      return "";
   return "Range " + PhaseName(p.phase) + ": " + RangeWerte(p.phase, true) + "\n";
}

string TgSignalText(Plan &p)
{
   int ls = LotStellen(MarketInfo(Symbol(), MODE_LOTSTEP));
   return TgSignalKopf(p) + "\n"
        + "Einstieg: " + DoubleToString(p.preis, Digits) + "\n"
        + TgRangeZeile(p)
        + "SL: " + DoubleToString(p.sl, Digits) + " (" + DoubleToString(p.slDist / Point, 0) + " Pkt)\n"
        + "TP: " + DoubleToString(p.tp, Digits) + " (" + DoubleToString(p.tpDist / Point, 0) + " Pkt)\n"
        + "Lot: " + DoubleToString(p.lot, ls) + "\n"
        + "Kosten: " + KostenText(p.spreadPkt, p.kommPkt) + " Pkt\n"
        + "CRV 1:" + DoubleToString(p.crv, 2);
}

string TgStatusText()
{
   double sp    = SpreadPunkte();
   double ko    = KommissionPunkte();
   double maxSp = MaxSpreadAktuell(0);
   double diff  = AccountEquity() - g_tagEquity;
   double proz  = (g_tagEquity > 0.0) ? diff / g_tagEquity * 100.0 : 0.0;
   string grund = "";
   bool   frei  = HandelErlaubt(grund, 0);
   string status = frei ? "Status: bereit" : "Blockiert: " + HtmlEscape(grund);
   return "<b>ScalpScout Asia " + HtmlEscape(Symbol()) + "</b> (Magic " + IntegerToString(MagicNumber) + ")\n"
        + "Modus: " + ModusText() + FernMarke(FernModusAbw()) + "\n"
        + "Risiko: " + DoubleToString(g_risiko, 1) + " %" + FernMarke(FernRisikoAbw()) + "\n"
        + "MaxLot: " + LotText(g_maxLot) + FernMarke(FernMaxLotAbw()) + " (Obergrenze " + LotText(FernMaxLotObergrenze) + ")\n"
        + "Tageslimit: " + LimitText(g_tagesLimitProz) + FernMarke(FernLimitAbw()) + "\n"
        + "Tokio: Range " + MinutenText(g_rgStartMin) + "-" + MinutenText(g_rgEndeMin) + FernMarke(FernRangeAbw())
        + ", Einstieg " + MinutenText(g_startMin) + "-" + MinutenText(g_endeMin) + " Serverzeit" + FernMarke(FernZeitAbw()) + "\n"
        + "London: " + LondonText() + " (Range " + MinutenText(g_rgStartMin) + "-" + MinutenText(g_lonStartMin) + ")"
        + FernMarke(FernLondonAbw()) + "\n"
        + "Zeitausstieg: " + SchlussText(g_schlussMin) + FernMarke(FernSchlussAbw()) + "\n"
        + "Signal: Ausbruchspuffer " + DoubleToString(g_puffer, 1) + " Pips" + FernMarke(FernPufferAbw()) + "\n"
        + "Signal: Volumen &gt; " + DoubleToString(g_volumenFaktor, 2) + "×Ø" + FernMarke(FernVolumenAbw()) + "\n"
        + "Signal: Range-Breite Tokio " + DoubleToString(RangeMinATR, 2) + "-" + DoubleToString(RangeMaxATR, 2)
        + ", London " + DoubleToString(LondonRangeMinATR, 2) + "-" + DoubleToString(LondonRangeMaxATR, 2)
        + " ×ATR(H1), Trendfilter " + (TrendFilterAktiv ? "an (EMA " + IntegerToString(EMA_H1_Periode) + " H1)" : "aus") + "\n"
        + "Folge-Scalps: " + (g_folgeAktiv ? "an" : "aus") + FernMarke(FernFolgeAbw()) + " (Ausbruch über "
        + IntegerToString(FolgeAusbruchKerzen) + " Kerzen, Volumen &gt; " + DoubleToString(FolgeVolumenFaktor, 2)
        + "×Ø, SL " + DoubleToString(FolgeSL_ATR, 2) + "×ATR M1)\n"
        + "Limits: max. " + IntegerToString(g_maxTrades) + " Trades je Phase" + FernMarke(FernMaxTradesAbw())
        + ", Cooldown " + IntegerToString(g_cooldownMin) + " min" + FernMarke(FernCooldownAbw())
        + ", max. offene Positionen " + IntegerToString(MaxOffenePositionen) + "\n"
        + "Ausstieg: Ausbruch-SL Range-Mitte (max. " + DoubleToString(SL_MaxATR, 2) + "×ATR H1), TP " + DoubleToString(TP_CRV, 2)
        + "×SL\n"
        + "Break-even: " + (g_beAktiv ? "an" : "aus") + FernMarke(FernBeAbw()) + ", Trailing: "
        + (g_trailingAktiv ? "an" : "aus") + FernMarke(FernTrailAbw()) + "\n"
        + "Tagesbericht: " + BerichtZeitText(g_berichtMin) + FernMarke(FernBerichtAbw()) + "\n"
        + "Konto: Kontostand " + DoubleToString(AccountBalance(), 2) + ", Equity " + DoubleToString(AccountEquity(), 2)
        + ", freie Margin " + DoubleToString(AccountFreeMargin(), 2) + " " + AccountCurrency() + "\n"
        + "Kosten: " + KostenText(sp, ko) + " / max " + DoubleToString(maxSp, 1) + " Pkt\n"
        + "Phasen: " + HtmlEscape(PhasenZeile()) + "\n"
        + "Tokio jetzt: " + HtmlEscape(PhaseText(0)) + "\n"
        + "London jetzt: " + HtmlEscape(PhaseText(1)) + "\n"
        + "Tagesergebnis: " + DoubleToString(diff, 2) + " " + AccountCurrency() + " (" + DoubleToString(proz, 2) + " %)\n"
        + "Offene Positionen: " + IntegerToString(ZaehlePositionen()) + " ("
        + DoubleToString(OffenerGewinn(), 2) + " " + AccountCurrency() + ")\n"
        + status;
}


// Befehlsübersicht mit aktuellen Werten
string TgHilfeText()
{
   return "<b>ScalpScout Asia Befehle</b> (" + HtmlEscape(Symbol()) + ", Magic " + IntegerToString(MagicNumber) + ")\n"
        + "/status - Zustand, Konto und alle Einstellungen\n"
        + "/diag - Auswertung der letzten Kerze und Zähler seit Start\n"
        + "/modus manuell|signale|auto - Betriebsart, jetzt: " + ModusText()
        + " (auto nur nach Bestätigung per Knopf)\n"
        + "/risiko X - Risiko je Trade in % (0.1-25), jetzt " + DoubleToString(g_risiko, 1) + "\n"
        + "/maxlot X - Lot-Deckel (" + LotText(MinLotWert()) + " bis " + LotText(MaxLotGrenze()) + "), jetzt "
        + LotText(g_maxLot) + "\n"
        + "/limit X|aus - Tagesverlust-Limit in % (1-100), jetzt " + LimitText(g_tagesLimitProz) + "\n"
        + "/zeit HH:MM-HH:MM - Tokio-Einstiegsfenster in Serverzeit (London: /london), jetzt " + MinutenText(g_startMin) + "-"
        + MinutenText(g_endeMin) + "\n"
        + "/range HH:MM-HH:MM - Tokio-Range in Serverzeit (Beginn gilt auch für London), jetzt " + MinutenText(g_rgStartMin)
        + "-" + MinutenText(g_rgEndeMin) + "\n"
        + "/london HH:MM-HH:MM|aus|an - London-Einstiegsfenster (die Range endet bei dessen Beginn), jetzt " + LondonText() + "\n"
        + "/puffer X - Ausbruchspuffer in Pips (0-10), jetzt " + DoubleToString(g_puffer, 1) + "\n"
        + "/volumen X - Volumen-Faktor für den Ausbruch (0.8-4.0), jetzt " + DoubleToString(g_volumenFaktor, 2) + "\n"
        + "/folge an|aus - Folge-Scalps in Phasen-Richtung, jetzt " + (g_folgeAktiv ? "an" : "aus") + "\n"
        + "/maxtrades N - max. Trades je Phase (1-50), jetzt " + IntegerToString(g_maxTrades) + "\n"
        + "/cooldown N - Pause in Minuten nach der letzten Eröffnung/Schließung (0-30), jetzt " + IntegerToString(g_cooldownMin) + "\n"
        + "/schluss HH:MM|aus - Zeitausstieg (alle Positionen schließen), jetzt " + SchlussText(g_schlussMin) + "\n"
        + "/be an|aus - Break-even, jetzt " + (g_beAktiv ? "an" : "aus") + "\n"
        + "/trailing an|aus - Trailing-Stop, jetzt " + (g_trailingAktiv ? "an" : "aus") + "\n"
        + "/bericht [HH:MM|aus] - Tagesbericht sofort bzw. Uhrzeit setzen, jetzt " + BerichtZeitText(g_berichtMin) + "\n"
        + "/kauf [lot] und /verkauf [lot] - Hand-Trade mit Vorschau und Bestätigung (30 s)\n"
        + "/zu ticket - eine Position schließen (mit Bestätigung)\n"
        + "/sl ticket preis|be und /tp ticket preis - Stop-Loss bzw. Take-Profit ändern\n"
        + "/positionen - offene Positionen\n"
        + "/heute - heute geschlossene Trades\n"
        + "/schliessen - alle Positionen schließen (mit Bestätigung)\n"
        + "/stop und /start - Signale pausieren bzw. freigeben (/start löst auch die Kill-Switch-Sperre, mit Bestätigung)\n"
        + "/reset - Fern-Einstellungen löschen, Inputs gelten wieder\n"
        + "Dezimaltrenner: Komma oder Punkt.";
}

// Ergebnis der letzten Kerzen-Auswertung und Zähler seit Start
string TgDiagText()
{
   string s = "<b>Diagnose " + HtmlEscape(Symbol()) + "</b>\n"
              + "Serverzeit " + TimeToString(TimeCurrent(), TIME_MINUTES) + " | " + HtmlEscape(PhasenZeile()) + "\n";
   if(g_dgZeit == 0)
      s += "Noch keine Kerze ausgewertet - die erste Auswertung kommt mit der nächsten neuen M1-Kerze.\n";
   for(int p = 0; p < 2; p++)
   {
      s += "\n<b>" + PhaseName(p) + "</b>: " + HtmlEscape(PhaseText(p)) + "\n"
         + "Range " + MinutenText(PhRangeStart(p)) + "-" + MinutenText(PhRangeEnde(p)) + ": "
         + ((g_rgKerzen[p] > 0) ? RangeWerte(p, true) : "keine (" + HtmlEscape(g_rgGrund[p]) + ")") + "\n"
         + "Einstieg " + MinutenText(PhEntryStart(p)) + "-" + MinutenText(PhEntryEnde(p))
         + ", Phasen-Richtung: " + RichtungText(g_phRicht[p]) + ", Trades " + IntegerToString(g_phTrades[p]) + "/"
         + IntegerToString(g_maxTrades) + "\n";
      if(g_dgZeit == 0)
         continue;
      if(!g_dgGueltig || g_dgPhArt[p] == 0)
      {
         s += "Letzte Kerze: " + HtmlEscape(DiagErgebnisText(p)) + "\n";
         continue;
      }
      bool   folge = (g_dgPhArt[p] == 2);
      string rt    = (g_dgPhRicht[p] > 0) ? "LONG" : "SHORT";
      s += "Letzte Kerze " + TimeToString(g_dgZeit, TIME_DATE | TIME_MINUTES) + " (Serverzeit), geprüft als "
         + (folge ? "Folge-Scalp " : "Opening-Range-Ausbruch ") + rt + "\n"
         + "Schluss " + DoubleToString(g_dgClose, Digits) + " / Linie " + DoubleToString(g_dgPhLinie[p], Digits) + ": "
         + HaekchenText(g_dgPhAusOK[p]) + "\n"
         + "Kerze in Richtung " + rt + ": " + HaekchenText(g_dgPhFarbeOK[p]) + "\n"
         + "Volumen: " + DoubleToString(g_dgVolX, 2) + "×Ø (Soll &gt; "
         + DoubleToString(folge ? FolgeVolumenFaktor : g_volumenFaktor, 2) + ") " + HaekchenText(g_dgPhVolOK[p]) + "\n";
      if(folge)
         s += "Preis auf der Ausbruchsseite der Range-Mitte: " + HaekchenText(g_dgPhExtraOK[p]) + "\n";
      else
         s += "Trend/EMA(H1): " + (TrendFilterAktiv ? HaekchenText(g_dgPhExtraOK[p]) : "✓ (Filter aus)") + "\n";
      s += "<b>Ergebnis: " + HtmlEscape(DiagErgebnisText(p)) + "</b>\n";
   }
   if(g_dgGueltig)
      s += "\nKosten: " + DoubleToString(g_dgKostenIst, 1) + " / max " + DoubleToString(g_dgKostenMax, 1) + " Pkt "
         + HaekchenText(g_dgKostenOK) + "\n"
         + "Filter: " + HtmlEscape(g_dgFilter) + "\n";
   else if(g_dgZeit != 0)
      s += "\n" + HtmlEscape(g_dgErgebnis) + "\n";
   s += "Seit Start: " + IntegerToString(g_dgKerzen) + " Kerzen, " + IntegerToString(g_dgSignale) + " Signale, "
      + IntegerToString(g_dgTrades) + " Trades, " + IntegerToString(g_dgVerworfen) + " verworfen";
   int best = -1;
   for(int i = 0; i < g_dgGrundAnz; i++)
   {
      if(best < 0 || g_dgGrundN[i] > g_dgGrundN[best])
         best = i;
   }
   if(best >= 0)
      s += "\nHäufigster Grund: " + HtmlEscape(g_dgGrund[best]) + " (" + IntegerToString(g_dgGrundN[best]) + "×)";
   return s;
}

// Einstellbefehle /risiko /maxlot /limit /zeit /range /london /puffer /volumen /folge /maxtrades /cooldown /schluss. true = Befehl erkannt.
bool TgEinstellung(string cmd, string arg)
{
   double w = 0.0;
   string alt;

   if(cmd == "/risiko")
   {
      if(!TgBereichOK(cmd, arg, 0.1, 25.0, 1, " %", w))
         return true;
      w   = NormalizeDouble(w, 2);
      alt = DoubleToString(g_risiko, 1) + " %";
      g_risiko = w;
      FernSpeichern("risiko", g_risiko);
      TgGeaendert("Risiko", alt, DoubleToString(g_risiko, 1) + " %");
      return true;
   }
   if(cmd == "/maxlot")
   {
      double mn = MinLotWert();
      double mx = MaxLotGrenze();
      if(mx < mn - 1e-9)
      {
         TgNachrichtSenden("⚠️ /maxlot: Obergrenze (" + LotText(mx) + ") liegt unter MinLot (" + LotText(mn)
                           + ") - nicht änderbar.", "");
         return true;
      }
      if(!TgBereichOK(cmd, arg, mn, mx, LotStellenAktuell(), " Lot", w))
         return true;
      double l = LotAbrunden(w);
      if(l < mn - 1e-9)
         l = mn;
      alt = LotText(g_maxLot) + " Lot";
      g_maxLot = l;
      FernSpeichern("maxlot", g_maxLot);
      TgGeaendert("MaxLot", alt, LotText(g_maxLot) + " Lot");
      return true;
   }
   if(cmd == "/limit")
   {
      if(arg == "aus" || arg == "off" || arg == "0")
         w = 0.0;
      else if(!TgBereichOK(cmd, arg, 1.0, 100.0, 0, " % (oder 'aus')", w))
         return true;
      w   = NormalizeDouble(w, 2);
      alt = LimitText(g_tagesLimitProz);
      g_tagesLimitProz = w;
      FernSpeichern("limit", g_tagesLimitProz);
      g_tagesLimit = false;       // mit neuem Limit neu bewerten (rastet bei Überschreitung sofort wieder ein)
      TagPruefen();
      TgGeaendert("Tageslimit", alt, LimitText(g_tagesLimitProz)
                  + (g_tagesLimit ? " (heute schon erreicht - Sperre bleibt)" : ""));
      return true;
   }
   if(cmd == "/zeit")
   {
      int sp = StringFind(arg, "-");
      int a = -1, b = -1;
      if(sp > 0)
      {
         a = ZeitLesen(StringSubstr(arg, 0, sp));
         b = ZeitLesen(StringSubstr(arg, sp + 1));
      }
      if(a < 0 || b < 0)
      {
         TgNachrichtSenden("⚠️ /zeit: Format HH:MM-HH:MM erwartet (Serverzeit), z. B. /zeit 08:00-20:00. "
                           + "Gleiche Start- und Endzeit = durchgehend.", "");
         return true;
      }
      alt = MinutenText(g_startMin) + "-" + MinutenText(g_endeMin);
      g_startMin = a;
      g_endeMin  = b;
      FernSpeichern("start", a);
      FernSpeichern("ende", b);
      TgGeaendert("Handelsfenster", alt, MinutenText(a) + "-" + MinutenText(b) + " Serverzeit");
      return true;
   }
   if(cmd == "/range")
   {
      int sp = StringFind(arg, "-");
      int a = -1, b = -1;
      if(sp > 0)
      {
         a = ZeitLesen(StringSubstr(arg, 0, sp));
         b = ZeitLesen(StringSubstr(arg, sp + 1));
      }
      if(a < 0 || b < 0 || a >= b)
      {
         TgNachrichtSenden("⚠️ /range: Format HH:MM-HH:MM erwartet (Serverzeit, Beginn vor Ende), z. B. /range 03:00-04:00.", "");
         return true;
      }
      if(g_schlussMin >= 0 && b >= g_schlussMin)
      {
         TgNachrichtSenden("⚠️ /range: das Range-Ende muss vor der Schlusszeit (" + MinutenText(g_schlussMin)
                           + ") liegen - erst /schluss anpassen.", "");
         return true;
      }
      if(g_lonAktiv && a >= g_lonStartMin)
      {
         TgNachrichtSenden("⚠️ /range: der Range-Beginn muss vor dem London-Einstieg (" + MinutenText(g_lonStartMin)
                           + ") liegen - erst /london anpassen.", "");
         return true;
      }
      alt = MinutenText(g_rgStartMin) + "-" + MinutenText(g_rgEndeMin);
      g_rgStartMin = a;
      g_rgEndeMin  = b;
      FernSpeichern("rgstart", a);
      FernSpeichern("rgende", b);
      RangeAktualisieren();
      TgGeaendert("Range", alt, MinutenText(a) + "-" + MinutenText(b) + " Serverzeit");
      return true;
   }
   if(cmd == "/puffer")
   {
      if(!TgBereichOK(cmd, arg, 0.0, 10.0, 1, " Pips", w))
         return true;
      w   = NormalizeDouble(w, 1);
      alt = DoubleToString(g_puffer, 1) + " Pips";
      g_puffer = w;
      FernSpeichern("puffer", g_puffer);
      TgGeaendert("Ausbruchspuffer", alt, DoubleToString(g_puffer, 1) + " Pips");
      return true;
   }
   if(cmd == "/london")
   {
      if(arg == "aus" || arg == "off")
      {
         alt = g_lonAktiv ? "an" : "aus";
         g_lonAktiv = false;
         FernSpeichern("lonaktiv", 0.0);
         RangeAktualisieren();
         TgGeaendert("London-Phase", alt, "aus");
         return true;
      }
      if(arg == "an" || arg == "ein" || arg == "on")
      {
         if(g_lonStartMin <= g_rgStartMin || g_lonEndeMin <= g_lonStartMin)
         {
            TgNachrichtSenden("⚠️ /london: das Fenster " + MinutenText(g_lonStartMin) + "-" + MinutenText(g_lonEndeMin)
                              + " passt nicht zur Range - erst /london HH:MM-HH:MM setzen.", "");
            return true;
         }
         alt = g_lonAktiv ? "an" : "aus";
         g_lonAktiv = true;
         FernSpeichern("lonaktiv", 1.0);
         RangeAktualisieren();
         TgGeaendert("London-Phase", alt, "an (" + LondonText() + ")");
         return true;
      }
      int sp = StringFind(arg, "-");
      int a = -1, b = -1;
      if(sp > 0)
      {
         a = ZeitLesen(StringSubstr(arg, 0, sp));
         b = ZeitLesen(StringSubstr(arg, sp + 1));
      }
      if(a < 0 || b < 0 || a <= g_rgStartMin || b <= a)
      {
         TgNachrichtSenden("⚠️ /london: Format HH:MM-HH:MM erwartet (Serverzeit, Einstiegsfenster; Beginn nach dem Range-Beginn "
                           + MinutenText(g_rgStartMin) + ", Ende nach dem Beginn), z. B. /london 10:00-12:00. Außerdem /london aus|an.", "");
         return true;
      }
      alt = MinutenText(g_lonStartMin) + "-" + MinutenText(g_lonEndeMin);
      g_lonStartMin = a;
      g_lonEndeMin  = b;
      FernSpeichern("lonstart", a);
      FernSpeichern("lonende", b);
      RangeAktualisieren();
      TgGeaendert("London-Einstieg", alt, MinutenText(a) + "-" + MinutenText(b) + " Serverzeit (Range " + MinutenText(g_rgStartMin)
                  + "-" + MinutenText(a) + ")");
      return true;
   }
   if(cmd == "/folge")
   {
      bool an;
      if(arg == "an" || arg == "ein" || arg == "on" || arg == "1")
         an = true;
      else if(arg == "aus" || arg == "off" || arg == "0")
         an = false;
      else
      {
         TgNachrichtSenden("⚠️ /folge: an oder aus erwartet. Aktuell: " + (g_folgeAktiv ? "an" : "aus") + ".", "");
         return true;
      }
      alt = g_folgeAktiv ? "an" : "aus";
      g_folgeAktiv = an;
      FernSpeichern("folge", an ? 1.0 : 0.0);
      TgGeaendert("Folge-Scalps", alt, an ? "an" : "aus");
      return true;
   }
   if(cmd == "/maxtrades")
   {
      if(!TgBereichOK(cmd, arg, 1.0, 50.0, 0, " Trades je Phase (ganze Zahl)", w))
         return true;
      if(MathAbs(w - MathRound(w)) > 1e-9)
      {
         TgNachrichtSenden("⚠️ /maxtrades: ganze Zahl von 1 bis 50 erwartet.", "");
         return true;
      }
      alt = IntegerToString(g_maxTrades);
      g_maxTrades = (int)MathRound(w);
      FernSpeichern("maxtrades", g_maxTrades);
      TgGeaendert("Max. Trades je Phase", alt, IntegerToString(g_maxTrades));
      return true;
   }
   if(cmd == "/cooldown")
   {
      if(!TgBereichOK(cmd, arg, 0.0, 30.0, 0, " Minuten (ganze Zahl)", w))
         return true;
      if(MathAbs(w - MathRound(w)) > 1e-9)
      {
         TgNachrichtSenden("⚠️ /cooldown: ganze Zahl von 0 bis 30 (Minuten) erwartet.", "");
         return true;
      }
      alt = IntegerToString(g_cooldownMin) + " min";
      g_cooldownMin = (int)MathRound(w);
      FernSpeichern("cooldown", g_cooldownMin);
      TgGeaendert("Cooldown", alt, IntegerToString(g_cooldownMin) + " min");
      return true;
   }
   if(cmd == "/volumen")
   {
      if(!TgBereichOK(cmd, arg, 0.8, 4.0, 1, " (×Durchschnitt)", w))
         return true;
      w   = NormalizeDouble(w, 2);
      alt = DoubleToString(g_volumenFaktor, 2) + "×Ø";
      g_volumenFaktor = w;
      FernSpeichern("volumen", g_volumenFaktor);
      TgGeaendert("Volumen-Faktor", alt, DoubleToString(g_volumenFaktor, 2) + "×Ø");
      return true;
   }
   if(cmd == "/schluss")
   {
      int m = -1;
      if(arg != "aus" && arg != "off")
      {
         m = ZeitLesen(arg);
         if(m < 0)
         {
            TgNachrichtSenden("⚠️ /schluss: HH:MM (Serverzeit) oder aus erwartet, z. B. /schluss 13:00.", "");
            return true;
         }
         if(m <= g_rgEndeMin)
         {
            TgNachrichtSenden("⚠️ /schluss: die Schlusszeit muss nach dem Range-Ende (" + MinutenText(g_rgEndeMin) + ") liegen.", "");
            return true;
         }
      }
      alt = SchlussText(g_schlussMin);
      g_schlussMin = m;
      FernSpeichern("schluss", (double)m);
      if(m >= 0)      // heute schon nach der neuen Zeit: nicht nachträglich ausführen, erst morgen
         SchlussTagSetzen((MinutenJetzt() >= m) ? TagBeginn() : (datetime)0);
      TgGeaendert("Schlusszeit", alt, SchlussText(g_schlussMin));
      return true;
   }
   return false;
}

// /reset: Fern-Einstellungen löschen, Inputs gelten wieder
void TgReset()
{
   string abw = FernAbweichungen();
   FernAlleLoeschen();
   ENUM_MODUS alt = g_modus;
   FernInputsUebernehmen();
   RangeAktualisieren();
   if(g_schlussMin >= 0 && MinutenJetzt() >= g_schlussMin)
      SchlussTagSetzen(TagBeginn());   // heute nicht nachträglich ausführen
   if(g_berichtMin >= 0 && TimeHour(TimeCurrent()) * 60 + TimeMinute(TimeCurrent()) >= g_berichtMin)
      g_berichtTag = (datetime)((long)TimeCurrent() / 86400 * 86400);   // heute nicht nachträglich senden
   if(alt != g_modus && g_modus != MANUELLE_FREIGABE && g_sig.aktiv)
      SignalVerwerfen("Reset", "⌛ verworfen (Reset)");
   g_tagesLimit = false;        // mit dem Input-Limit neu bewerten
   TagPruefen();
   g_fernInfo = "";
   HinweisSetzen("Fern-Einstellungen zurückgesetzt");
   Print("ScalpScout Asia Fern: Reset, Inputs aktiv (", WerteText(), ")");
   TgNachrichtSenden("♻️ Fern-Einstellungen gelöscht, die Inputs gelten wieder.\n"
                     + ((abw == "") ? "Es gab keine Fern-Änderungen.\n" : "Zurückgesetzt wurden: " + HtmlEscape(abw) + "\n")
                     + "Jetzt aktiv: " + HtmlEscape(WerteText()), "");
   UiAktualisieren();
}

//+------------------------------------------------------------------+
//| Fernsteuerung Teil 2: Einzelpositionen, Hand-Trades, Bericht     |
//+------------------------------------------------------------------+
// Eine Position schließen (3 Versuche), ohne MessageBox und ohne Sperre neuer Trades
bool PositionSchliessen(int ticket, string &fehler)
{
   fehler = "";
   if(!EigenePositionWaehlen(ticket))
   {
      fehler = "Ticket nicht (mehr) offen";
      return false;
   }
   int    typ   = OrderType();
   double lots  = OrderLots();
   int    slip  = SlippagePunkte();
   int    err   = 0;
   for(int v = 1; v <= 3; v++)
   {
      RefreshRates();
      double preis = (typ == OP_BUY) ? Bid : Ask;
      ResetLastError();
      if(OrderClose(ticket, lots, preis, slip, clrOrange))
      {
         Print("ScalpScout Asia: Position #", ticket, " geschlossen");
         return true;
      }
      err = GetLastError();
      LogFehler("OrderClose #" + IntegerToString(ticket) + " (Versuch " + IntegerToString(v) + ")", err);
      if(!IsTesting())
         Sleep(200);
      if(!OrderSelect(ticket, SELECT_BY_TICKET) || OrderCloseTime() > 0)
         break;
   }
   fehler = FehlerText(err) + " (" + IntegerToString(err) + ")";
   return false;
}

// /kauf [lot] und /verkauf [lot]: Vorschau mit Knöpfen (30 s), Ausführung erst nach ✅
void TgHandTradeAnfrage(int richtung, string arg)
{
   string cmd = (richtung > 0) ? "/kauf" : "/verkauf";
   double lot = 0.0;                      // 0 = Lot aus Risiko %
   if(arg != "")
   {
      double mn = MinLotWert(), mx = MaxLotGrenze();
      if(mx < mn - 1e-9)
      {
         TgNachrichtSenden("⚠️ " + cmd + ": Obergrenze (" + LotText(mx) + ") liegt unter MinLot (" + LotText(mn) + ").", "");
         return;
      }
      if(!TgBereichOK(cmd, arg, mn, mx, LotStellenAktuell(), " Lot", lot))
         return;
      lot = LotAbrunden(lot);
      if(lot < mn - 1e-9)
         lot = mn;
   }
   RefreshRates();
   double atr = AktuelleATR();
   string grund = "";
   if(!HandelErlaubt(grund, richtung, true))
   {
      TgNachrichtSenden("⚠️ " + cmd + " nicht möglich: " + HtmlEscape(grund), "");
      return;
   }
   Plan p;
   if(!BerechnePlan(richtung, atr, p, grund, lot))
   {
      TgNachrichtSenden("⚠️ " + cmd + " nicht möglich: " + HtmlEscape(grund), "");
      return;
   }
   double maxSp = MaxSpreadAktuell(richtung);
   string kosten = "Kosten: " + KostenText(p.spreadPkt, p.kommPkt) + " Pkt (Limit " + DoubleToString(maxSp, 1) + ")"
                   + ((p.spreadPkt + p.kommPkt > maxSp) ? " - über dem Limit, wird bei Hand-Trades ignoriert" : "");
   if(g_cfgHandMsg > 0)
      TgNachrichtBearbeiten(g_cfgHandMsg, "⌛ ersetzt durch neue Anfrage.");
   g_cfgHandRicht = richtung;
   g_cfgHandLot   = lot;
   g_cfgHandMsg = TgNachrichtSenden("⚠️ <b>Hand-Trade " + HtmlEscape(Symbol()) + " " + ((richtung > 0) ? "🟢 KAUF" : "🔴 VERKAUF")
                                    + "</b>\nEinstieg ca.: " + DoubleToString(p.preis, Digits) + "\n"
                                    + "SL: " + DoubleToString(p.sl, Digits) + " (" + DoubleToString(p.slDist / Point, 0) + " Pkt)\n"
                                    + "TP: " + DoubleToString(p.tp, Digits) + " (" + DoubleToString(p.tpDist / Point, 0) + " Pkt)\n"
                                    + "Lot: " + LotText(p.lot) + ((lot > 0.0) ? " (vorgegeben)" : " (Risiko " + DoubleToString(g_risiko, 1) + " %)") + "\n"
                                    + kosten + "\nBestätigung gilt 30 Sekunden.",
                                    TgTastaturCfg("✅ Ausführen", "cfg_hand_ja", "❌ Abbrechen", "cfg_hand_nein"));
   g_cfgHandBis = TimeLocal() + 30;
}

// Hand-Trade nach Bestätigung: Filter (ohne Zeitfenster/Spread) erneut prüfen, Order senden
string TgHandAusfuehren()
{
   RefreshRates();
   double atr = AktuelleATR();
   string grund = "";
   int r = g_cfgHandRicht;
   if(!HandelErlaubt(grund, r, true))
   {
      DiagVerworfen(grund);
      return "⚠️ Nicht ausgeführt: " + HtmlEscape(grund);
   }
   if(!OrderOeffnen(r, atr, grund, g_cfgHandLot))
   {
      DiagVerworfen(grund);
      return "⚠️ Order fehlgeschlagen: " + HtmlEscape(grund);
   }
   HinweisSetzen("Hand-Trade " + (r > 0 ? "KAUF" : "VERKAUF") + " #" + IntegerToString(g_orderTicket));
   return "✅ Ausgeführt: " + (r > 0 ? "BUY" : "SELL") + " #" + IntegerToString(g_orderTicket) + " @"
          + DoubleToString(g_orderPreis, Digits);
}

//+------------------------------------------------------------------+
//| Signal-Logik auf geschlossener M1-Kerze (Shift 1)                |
//+------------------------------------------------------------------+
// Rückgabe: +1 Long, -1 Short, 0 kein Signal. Phase (0 Tokio, 1 London) und Art (1 Ausbruch, 2 Folge-Scalp) kommen
// aus der Auswertung in DiagKerze (eine Quelle für die Regeln); atr = ATR(M1) für Plan und Preisabweichung.
int SignalErkennen(int &phase, int &art, double &atr)
{
   phase = -1;
   art   = 0;
   atr   = 0.0;
   if(!g_dgGueltig)
      return 0;
   for(int p = 0; p < 2; p++)
   {
      if(g_dgPhMoeglich[p])
      {
         phase = p;
         art   = g_dgPhArt[p];
         atr   = g_dgAtr;
         return g_dgPhRicht[p];
      }
   }
   return 0;
}

void NeueKerzeAuswerten()
{
   HeuteTradesAktualisieren();   // Trades je Phase, Phasen-Richtung und Cooldown-Zeit aus Orders/Historie
   DiagKerze();                  // wertet die Kerze aus (Ranges, Bedingungen) und merkt die Werte für /diag und Chart
   g_dgKerzen++;

   double atr   = 0.0;
   int    phase = -1;
   int    art   = 0;
   int    sig   = SignalErkennen(phase, art, atr);
   if(sig == 0)
      return;

   string txt = (sig > 0) ? "LONG" : "SHORT";
   string pn  = PhaseName(phase) + ((art == 2) ? " Folge" : " ORB");
   string grund;
   g_dgSignale++;
   if(art == 1)
      g_phRicht[phase] = sig;    // Phasen-Richtung steht ab dem ersten gültigen Ausbruch fest (auch wenn er abgelehnt wird)
   g_dgPhRicht[phase] = sig;

   if(!HandelErlaubt(grund, sig, false, phase, art))
   {
      g_dgPhErg[phase] = "Signal " + pn + " " + txt + " erkannt, aber blockiert: " + grund;
      DiagVerworfen(grund);
      HinweisSetzen("Signal " + pn + " " + txt + " blockiert: " + grund);
      return;
   }

   Plan p;
   if(!BerechnePlan(sig, atr, p, grund, 0.0, phase, art))
   {
      g_dgPhErg[phase] = "Signal " + pn + " " + txt + " erkannt, aber ohne Trade: " + grund;
      DiagVerworfen(grund);
      HinweisSetzen("Signal " + pn + " " + txt + " ohne Trade: " + grund);
      return;
   }
   g_dgPhErg[phase] = "Signal " + pn + " " + txt;

   string meldung = "ScalpScout Asia " + Symbol() + " " + pn + " " + txt + " @" + DoubleToString(p.preis, Digits)
                    + " SL " + DoubleToString(p.sl, Digits) + " TP " + DoubleToString(p.tp, Digits)
                    + " Lot " + DoubleToString(p.lot, 2) + " " + KostenText(p.spreadPkt, p.kommPkt)
                    + " CRV 1:" + DoubleToString(p.crv, 2);

   switch(g_modus)
   {
      case NUR_SIGNALE:
         Melden(meldung + " (nur Signal)");
         HinweisSetzen("Signal " + pn + " " + txt + " gemeldet (kein Trade)");
         TgNachrichtSenden(TgSignalText(p) + "\nnur Signal, kein Trade", "");
         break;

      case VOLLAUTOMATIK:
         if(OrderOeffnen(sig, atr, grund, 0.0, phase, art))
         {
            Melden(meldung + " - ausgeführt");
            HinweisSetzen("Auto-Trade " + pn + " " + txt + " eröffnet");
            TgNachrichtSenden(TgSignalText(p) + "\n✅ automatisch ausgeführt: #" + IntegerToString(g_orderTicket)
                              + " @" + DoubleToString(g_orderPreis, Digits), "");
         }
         else
         {
            g_dgPhErg[phase] = "Signal " + pn + " " + txt + " erkannt, Order fehlgeschlagen: " + grund;
            DiagVerworfen(grund);
            HinweisSetzen("Auto-Trade " + pn + " " + txt + " fehlgeschlagen: " + grund);
         }
         break;

      case MANUELLE_FREIGABE:
         if(g_sig.aktiv)
            SignalVerwerfen("durch neues Signal ersetzt", "⌛ ersetzt durch neues Signal");
         g_sig.aktiv = true;
         g_sig.zeit  = TimeLocal();
         g_sig.plan  = p;
         g_sigId     = TgNeueSignalId();
         g_sigMsgId  = 0;
         g_tgKopf    = TgSignalKopf(p);
         PanelZeigen();
         Melden(meldung + " - Freigabe im Chart nötig (" + IntegerToString(SignalGueltigSek) + " s)");
         g_sigMsgId  = TgNachrichtSenden(TgSignalText(p) + "\n⏱ gültig " + IntegerToString(SignalGueltigSek) + " s",
                                         TgTastatur(g_sigId));
         break;
   }
}

//+------------------------------------------------------------------+
//| Expert-Funktionen                                                |
//+------------------------------------------------------------------+
int OnInit()
{
   // Eingaben prüfen
   g_startMin = ParseHHMM(HandelStart);
   g_endeMin  = ParseHHMM(HandelEnde);
   if(g_startMin < 0 || g_endeMin < 0)
   {
      Alert("ScalpScout Asia: HandelStart/HandelEnde müssen das Format HH:MM haben (z. B. 04:00).");
      return INIT_PARAMETERS_INCORRECT;
   }
   int rgS = ParseHHMM(RangeStart);
   int rgE = ParseHHMM(RangeEnde);
   if(rgS < 0 || rgE < 0 || rgS >= rgE)
   {
      Alert("ScalpScout Asia: RangeStart/RangeEnde müssen das Format HH:MM haben, RangeStart muss vor RangeEnde liegen (z. B. 03:00 und 04:00).");
      return INIT_PARAMETERS_INCORRECT;
   }
   int lonS = ParseHHMM(LondonStart);
   int lonE = ParseHHMM(LondonEnde);
   if(lonS < 0 || lonE < 0 || (LondonAktiv && (lonS <= rgS || lonE <= lonS)))
   {
      Alert("ScalpScout Asia: LondonStart/LondonEnde müssen das Format HH:MM haben, LondonStart muss nach RangeStart und LondonEnde nach LondonStart liegen (z. B. 10:00 und 12:00).");
      return INIT_PARAMETERS_INCORRECT;
   }
   string sz = SchlussZeit;
   StringTrimLeft(sz);
   StringTrimRight(sz);
   if(sz != "" && (ParseHHMM(sz) < 0 || ParseHHMM(sz) <= rgE))
   {
      Alert("ScalpScout Asia: SchlussZeit muss das Format HH:MM haben, nach RangeEnde liegen oder leer sein.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(sz != "" && LondonAktiv && ParseHHMM(sz) <= lonE)
      Print("ScalpScout Asia WARNUNG: SchlussZeit liegt nicht nach LondonEnde - die London-Phase wird verkürzt.");
   if(ATR_Periode < 1 || ATR_H1_Periode < 1 || EMA_H1_Periode < 1 || VolumenKerzen < 1 || FolgeAusbruchKerzen < 1 ||
      VolumenFaktor <= 0.0 || FolgeVolumenFaktor <= 0.0 || FolgeSL_ATR <= 0.0 ||
      RangeMinATR <= 0.0 || RangeMaxATR <= RangeMinATR || LondonRangeMinATR <= 0.0 || LondonRangeMaxATR <= LondonRangeMinATR ||
      AusbruchPufferPips < 0.0 || SL_MaxATR <= 0.0 || TP_CRV <= 0.0 || MaxTradesProPhase < 1 || CooldownMinuten < 0 ||
      RisikoProzent <= 0.0 || MaxLot <= 0.0 || FernMaxLotObergrenze <= 0.0 || MaxOffenePositionen < 1 || SignalGueltigSek < 1 ||
      KommissionProLot < 0.0)
   {
      Alert("ScalpScout Asia: Ungültige Eingabewerte (Perioden, Faktoren, SL_MaxATR, TP_CRV, Risiko, MaxLot müssen > 0 sein, Range-Max > Range-Min, MaxTradesProPhase >= 1, Puffer/Cooldown/Kommission nicht negativ).");
      return INIT_PARAMETERS_INCORRECT;
   }

   string bz = TagesberichtZeit;
   StringTrimLeft(bz);
   StringTrimRight(bz);
   if(bz != "" && ParseHHMM(bz) < 0)
   {
      Alert("ScalpScout Asia: TagesberichtZeit muss das Format HH:MM haben oder leer sein.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(Period() != PERIOD_M1)
      Print("ScalpScout Asia WARNUNG: EA ist für den M1-Chart gedacht (aktuell: ", Period(), " Min.). Auswertung läuft trotzdem auf M1.");
   if(StringFind(Symbol(), "JPY") < 0)
      Print("ScalpScout Asia WARNUNG: EA ist für USDJPY (Tokio-/London-Eröffnung) gedacht, aktuell: ", Symbol(), ".");

   // Wirksame Betriebsart
   g_modus = Modus;
   if(IsTesting() && Modus == MANUELLE_FREIGABE)
   {
      g_modus = VOLLAUTOMATIK;
      Print("ScalpScout Asia: Strategietester erkannt - Modus MANUELLE_FREIGABE wird wie VOLLAUTOMATIK behandelt.");
   }
   g_modusInput = g_modus;
   g_ui = (!IsTesting() || IsVisualMode());

   // Laufzeit-Werte: erst aus den Inputs, dann (live) die per Telegram gespeicherten Änderungen
   g_berichtTag   = 0;
   g_berichtRetry = 0;
   g_schlussTag   = 0;
   g_schlussRetry = 0;
   g_schlussVersuche = 0;
   g_letzteAktion = 0;
   for(int q = 0; q < 2; q++)
   {
      g_phRicht[q]  = 0;
      g_phTrades[q] = 0;
      g_rgGezKey[q] = "";
   }
   RangeZuruecksetzen();
   FernInputsUebernehmen();
   FernLaden();
   DiagZuruecksetzen();

   g_sig.aktiv = false;
   g_gestoppt  = false;
   g_hinweis   = "";
   g_histAnzahl = -1;
   g_sigId     = 0;
   g_sigMsgId  = 0;
   g_tgKopf    = "";
   g_tgPause   = false;

   // Tagesstart (live aus globalen Variablen wiederherstellen)
   g_gvTag    = "SSA_" + IntegerToString(AccountNumber()) + "_" + IntegerToString(MagicNumber) + "_tag";
   g_gvEquity = "SSA_" + IntegerToString(AccountNumber()) + "_" + IntegerToString(MagicNumber) + "_eq";
   datetime heute = (datetime)((long)TimeCurrent() / 86400 * 86400);
   g_tag = 0;
   g_tagEquity = AccountEquity();
   if(!IsTesting() && GlobalVariableCheck(g_gvTag) && GlobalVariableCheck(g_gvEquity) &&
      (datetime)GlobalVariableGet(g_gvTag) == heute)
   {
      g_tag       = heute;
      g_tagEquity = GlobalVariableGet(g_gvEquity);
   }
   TagPruefen();
   RangeAktualisieren();          // Ranges aus der M1-Historie (auch wenn der EA nach Range-Ende angehängt wird)
   HeuteTradesAktualisieren();    // Trades je Phase und Phasen-Richtung aus Orders/Historie

   // Telegram (nur live, nur mit Token und Chat-ID)
   TelegramStarten();

   // Erst die nächste neue Kerze auswerten (keine alte Kerze beim Anhängen)
   g_letzteKerze = iTime(Symbol(), PERIOD_M1, 0);

   if(g_ui)
   {
      InfoAufbauen();
      UiAktualisieren();
   }
   if(!IsTesting())
      EventSetTimer(1);

   Print("ScalpScout Asia gestartet: ", Symbol(), ", Modus ", ModusText(), ", MaxLot ", DoubleToString(g_maxLot, 2),
         ", Risiko ", DoubleToString(g_risiko, 1), " %, Digits ", Digits, ", Point ", DoubleToString(Point, Digits));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, PRAEFIX);
   g_rgGezKey[0] = "";
   g_rgGezKey[1] = "";
   Comment("");
   ChartRedraw(0);
   Print("ScalpScout Asia beendet (Grund ", reason, ").");
}

void OnTick()
{
   TagPruefen();
   ZeitausstiegPruefen();
   PositionenVerwalten();
   SignalPruefen();

   datetime kerze = iTime(Symbol(), PERIOD_M1, 0);
   if(kerze != g_letzteKerze && kerze > 0)
   {
      g_letzteKerze = kerze;
      NeueKerzeAuswerten();
   }

   if(g_ui)
   {
      uint jetzt = GetTickCount();
      if(jetzt - g_uiLetzte >= 500)
      {
         g_uiLetzte = jetzt;
         UiAktualisieren();
      }
   }
}

// Läuft jede Sekunde (live): Signalablauf auch ohne neue Ticks erkennen
void OnTimer()
{
   TagPruefen();
   ZeitausstiegPruefen();
   SignalPruefen();
   TgAbfragen();
   TgCfgAblaufPruefen();
   TagesberichtPruefen();
   TgSchliessungenPruefen();
   UiAktualisieren();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   if(sparam == OBJ_PNL_OK)
   {
      ObjectSetInteger(0, OBJ_PNL_OK, OBJPROP_STATE, false);
      string ergebnis = "";
      SignalAusfuehren(false, ergebnis);
      UiAktualisieren();
   }
   else if(sparam == OBJ_PNL_NO)
   {
      ObjectSetInteger(0, OBJ_PNL_NO, OBJPROP_STATE, false);
      SignalVerwerfen("vom Nutzer verworfen", "❌ am PC verworfen");
      HinweisSetzen("Signal verworfen");
      UiAktualisieren();
   }
   else if(sparam == OBJ_KILL)
   {
      ObjectSetInteger(0, OBJ_KILL, OBJPROP_STATE, false);
      int antwort = MessageBox("Alle Positionen von ScalpScout Asia (Magic " + IntegerToString(MagicNumber)
                               + ") auf " + Symbol() + " jetzt schließen?\n\nDanach sind neue Trades gesperrt, bis der EA neu gestartet wird.",
                               "ScalpScout Asia - ALLES SCHLIESSEN", MB_YESNO | MB_ICONWARNING);
      if(antwort == IDYES)
      {
         int geschlossen = 0, fehler = 0;
         AlleSchliessen(geschlossen, fehler);
      }
      UiAktualisieren();
   }
}
//+------------------------------------------------------------------+
