//+------------------------------------------------------------------+
//|                                                  ScalpScout.mq4  |
//|  Scalping-Assistent für M1: erkennt Volatilitäts-/Liquiditäts-   |
//|  schübe, zeigt Signale zur manuellen Freigabe oder handelt       |
//|  vollautomatisch. Keine Gewinnzusage - Handel auf eigenes Risiko.|
//+------------------------------------------------------------------+
#property copyright   "maehrsteuern"
#property version     "1.10"
#property description "ScalpScout - M1-Scalping-Assistent (Signal, manuelle Freigabe, Vollautomatik, Telegram)"
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
input double PreisAbweichungATR    = 0.3;     // Signal verfällt, wenn Preis weiter weg ist als x * ATR
input int    Slippage              = 3;       // Max. Abweichung in Pips (bei 3/5-stelligen Kursen automatisch x10 Punkte)
input int    OrderVersuche         = 3;       // Max. Versuche bei Requote/Preisänderung

//--- Signal
input int    ATR_Periode           = 14;      // ATR-Periode (M1)
input double ImpulsFaktor          = 1.8;     // Kerzenkörper muss größer sein als x * ATR
input double VolumenFaktor         = 1.5;     // Tick-Volumen muss größer sein als x * Durchschnitt
input int    VolumenKerzen         = 20;      // Anzahl Kerzen für Durchschnittsvolumen
input int    BreakoutKerzen        = 10;      // Ausbruch über Hoch/Tief der letzten N Kerzen
input bool   TrendFilterAktiv      = true;    // Trendfilter (Schluss über/unter EMA) verwenden
input int    EMA_Periode           = 50;      // EMA-Periode (M1) für Trendfilter

//--- Ausstieg
input double SL_ATR                = 1.0;     // Stop-Loss = x * ATR
input double TP_ATR                = 1.5;     // Take-Profit = x * ATR
input bool   BE_Aktiv              = true;    // Break-even aktivieren
input double BE_ATR                = 0.8;     // Break-even ab Gewinn von x * ATR
input int    BE_PufferPunkte       = 0;       // Break-even: Puffer über/unter Einstieg (Punkte)
input bool   TrailingAktiv         = false;   // Trailing-Stop aktivieren
input double TrailingStartATR      = 1.0;     // Trailing startet ab Gewinn von x * ATR
input double TrailingATR           = 0.7;     // Trailing-Abstand = x * ATR
input double TrailingSchrittATR    = 0.1;     // SL nur nachziehen, wenn Verbesserung mind. x * ATR

//--- Risiko
input double RisikoProzent         = 1.0;     // Risiko pro Trade in % vom Equity
input double MaxLot                = 0.01;    // Harter Lot-Deckel (Live-Start)

//--- Schutzfilter
input double MaxSpreadPunkte       = 0;       // Max. Spread in Punkten (0 = automatisch aus TP-Distanz)
input double SpreadAnteilTP        = 0.25;    // Automatik: Kosten (Spread + Kommission) müssen kleiner sein als x * TP-Distanz
input double KommissionProLot      = 0.0;     // Kommission pro Lot, Hin- und Rückweg zusammen, in Kontowährung (ECN)
input string HandelStart           = "08:00"; // Handelsfenster Beginn (Serverzeit, HH:MM)
input string HandelEnde            = "20:00"; // Handelsfenster Ende (Serverzeit, HH:MM)
input double TagesVerlustProzent   = 3.0;     // Tagesverlust-Limit in % vom Tagesbeginn-Equity (0 = aus)
input int    MaxOffenePositionen   = 1;       // Max. offene Positionen pro Symbol
input int    PauseNachVerlusten    = 3;       // Pause nach N Verlusten in Folge (0 = aus)
input int    PauseMinuten          = 30;      // Dauer der Pause (Minuten)
input int    MagicNumber           = 26101801;// Magic Number dieses EAs

//--- Telegram-Fernbedienung (Freigabe per Handy)
input bool   TelegramAktiv         = false;   // Telegram-Fernbedienung einschalten
input string TelegramToken         = "";      // Bot-Token von @BotFather (nie weitergeben)
input string TelegramChatID        = "";      // deine Chat-ID (nur dieser Chat darf steuern)
input int    TelegramAbfrageSek    = 2;       // Abfrageintervall (Sekunden)
input bool   TelegramMeldeSchliessung = true; // Nachricht bei geschlossener Position mit Ergebnis

//+------------------------------------------------------------------+
//| Konstanten und Typen                                             |
//+------------------------------------------------------------------+
#define PRAEFIX          "SSC_"
#define OBJ_KILL         "SSC_btn_kill"
#define OBJ_PNL_PRAEFIX  "SSC_pnl_"
#define OBJ_PNL_BG       "SSC_pnl_bg"
#define OBJ_PNL_OK       "SSC_pnl_btn_ok"
#define OBJ_PNL_NO       "SSC_pnl_btn_no"
#define OBJ_INFO_BG      "SSC_info_bg"
#define ORDER_KOMMENTAR  "ScalpScout"
#define INFO_ZEILEN      10
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
   double atr;        // verwendeter ATR-Wert
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

//+------------------------------------------------------------------+
//| Hilfsfunktionen: Fehler, Zahlen, Zeit                            |
//+------------------------------------------------------------------+
string FehlerText(int err)
{
   switch(err)
   {
      case 0:   return "kein Fehler";
      case 2:   return "allgemeiner Fehler";
      case 3:   return "ungültige Parameter";
      case 4:   return "Handelsserver beschäftigt";
      case 6:   return "keine Verbindung zum Server";
      case 8:   return "zu häufige Anfragen";
      case 64:  return "Konto gesperrt";
      case 65:  return "ungültige Kontonummer";
      case 128: return "Handels-Timeout";
      case 129: return "ungültiger Preis";
      case 130: return "ungültige Stops (SL/TP zu nah oder falsch)";
      case 131: return "ungültiges Volumen";
      case 132: return "Markt geschlossen";
      case 133: return "Handel nicht erlaubt";
      case 134: return "nicht genug Geld/Margin";
      case 135: return "Preis hat sich geändert";
      case 136: return "keine Kurse";
      case 137: return "Broker beschäftigt";
      case 138: return "Requote";
      case 139: return "Order gesperrt";
      case 141: return "zu viele Anfragen";
      case 145: return "Änderung nicht erlaubt (zu nah am Markt)";
      case 146: return "Handelskontext beschäftigt";
      case 148: return "zu viele offene Orders";
      case 4060: return "Funktion nicht erlaubt (WebRequest-URL in den Optionen freigeben)";
      case 4108: return "ungültige Ticketnummer";
      case 4109: return "Handel im Terminal nicht erlaubt (AutoTrading/Algo-Trading aus)";
      case 4110: return "Kaufen nicht erlaubt";
      case 4111: return "Verkaufen nicht erlaubt";
   }
   return "unbekannter Fehler";
}

// Fehlercode ins Journal schreiben
void LogFehler(string kontext, int err)
{
   Print("ScalpScout FEHLER bei ", kontext, ": Code ", err, " (", FehlerText(err), ")");
}

// Minuten seit 00:00 aus "HH:MM"; -1 bei ungültiger Eingabe
int ParseHHMM(string s)
{
   if(StringLen(s) != 5 || StringGetCharacter(s, 2) != ':')
      return -1;
   int h = (int)StringToInteger(StringSubstr(s, 0, 2));
   int m = (int)StringToInteger(StringSubstr(s, 3, 2));
   if(h < 0 || h > 23 || m < 0 || m > 59)
      return -1;
   return h * 60 + m;
}

// Anzahl Nachkommastellen der Lot-Schrittweite
int LotStellen(double step)
{
   int d = 0;
   while(d < 8 && MathAbs(step * MathPow(10, d) - MathRound(step * MathPow(10, d))) > 1e-9)
      d++;
   return d;
}

// Lot auf Schrittweite abrunden
double LotAbrunden(double lot)
{
   double step = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(step <= 0.0)
      step = 0.01;
   double l = MathFloor(lot / step + 1e-8) * step;
   return NormalizeDouble(l, LotStellen(step));
}

// Slippage in Punkten (bei 3-/5-stelligen Kursen Pips x 10)
int SlippagePunkte()
{
   int faktor = (Digits == 3 || Digits == 5) ? 10 : 1;
   return Slippage * faktor;
}

// Aktueller ATR (geschlossene M1-Kerze)
double AktuelleATR()
{
   return iATR(Symbol(), PERIOD_M1, ATR_Periode, 1);
}

// Maximal erlaubte Kosten (Spread + Kommission) in Punkten
double MaxSpreadAktuell(double atr)
{
   if(MaxSpreadPunkte > 0.0)
      return MaxSpreadPunkte;
   double stopLvl = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   double tpDist  = MathMax(TP_ATR * atr, stopLvl);
   return SpreadAnteilTP * tpDist / Point;
}

double SpreadPunkte()
{
   return (Ask - Bid) / Point;
}

// Kommission (Hin- und Rückweg) in Punkten; 0 bei keiner Kommission oder ungültigen Symboldaten
double KommissionPunkte()
{
   if(KommissionProLot <= 0.0)
      return 0.0;
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0 || Point <= 0.0)
      return 0.0;
   double geldProPunkt = tickValue / tickSize * Point;   // Geld pro Punkt und Lot
   if(geldProPunkt <= 0.0)
      return 0.0;
   return KommissionProLot / geldProPunkt;
}

// Text "Spread a" bzw. "Spread a + Komm. b" (Kommission nur wenn > 0)
string KostenText(double sp, double ko)
{
   return "Spread " + DoubleToString(sp, 1) + ((ko > 0.0) ? " + Komm. " + DoubleToString(ko, 1) : "");
}

// Text für Info-Zeilen kürzen
string Kuerzen(string s, int maxLen)
{
   if(StringLen(s) <= maxLen)
      return s;
   return StringSubstr(s, 0, maxLen - 3) + "...";
}

void HinweisSetzen(string text)
{
   g_hinweis     = text;
   g_hinweisZeit = TimeCurrent();
   Print("ScalpScout Hinweis: ", text);
}

//+------------------------------------------------------------------+
//| Tages- und Verlustverwaltung                                     |
//+------------------------------------------------------------------+
void TagSpeichern()
{
   if(IsTesting())
      return;
   GlobalVariableSet(g_gvTag, (double)g_tag);
   GlobalVariableSet(g_gvEquity, g_tagEquity);
}

// Neuen Serverzeit-Tag erkennen und Tagesstart-Equity setzen
void TagPruefen()
{
   datetime heute = (datetime)((long)TimeCurrent() / 86400 * 86400);
   if(heute != g_tag)
   {
      g_tag        = heute;
      g_tagEquity  = AccountEquity();
      g_tagesLimit = false;
      TagSpeichern();
      Print("ScalpScout: neuer Handelstag, Start-Equity ", DoubleToString(g_tagEquity, 2));
   }
   // Tageslimit einrasten (gilt bis zum nächsten Tag)
   if(!g_tagesLimit && TagesVerlustProzent > 0.0 && g_tagEquity > 0.0)
   {
      double verlustProz = (g_tagEquity - AccountEquity()) / g_tagEquity * 100.0;
      if(verlustProz >= TagesVerlustProzent)
      {
         g_tagesLimit = true;
         Print("ScalpScout: Tagesverlust-Limit erreicht (", DoubleToString(verlustProz, 2),
               " %). Keine neuen Trades bis zum nächsten Tag.");
      }
   }
}

// Verluste in Folge aus der Kontohistorie ermitteln (nur bei neuer Historie)
void VerlustSerieAktualisieren()
{
   int n = OrdersHistoryTotal();
   if(n == g_histAnzahl)
      return;
   g_histAnzahl     = n;
   g_verlustSerie   = 0;
   g_letzterVerlust = 0;
   if(PauseNachVerlusten <= 0)
      return;

   datetime vorher = TimeCurrent() + 86400;
   for(int k = 0; k < PauseNachVerlusten; k++)
   {
      datetime bestZeit   = 0;
      double   bestProfit = 0.0;
      bool     gefunden   = false;
      for(int i = 0; i < n; i++)
      {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
            continue;
         if(OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol())
            continue;
         if(OrderType() > OP_SELL)
            continue;
         datetime ct = OrderCloseTime();
         if(ct > 0 && ct < vorher && ct > bestZeit)
         {
            bestZeit   = ct;
            bestProfit = OrderProfit() + OrderSwap() + OrderCommission();
            gefunden   = true;
         }
      }
      if(!gefunden)
         break;
      if(bestProfit < 0.0)
      {
         g_verlustSerie++;
         if(g_verlustSerie == 1)
            g_letzterVerlust = bestZeit;
      }
      else
         break;
      vorher = bestZeit;
   }
}

int ZaehlePositionen()
{
   int z = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber && OrderType() <= OP_SELL)
         z++;
   }
   return z;
}

bool ZeitfensterOK()
{
   if(g_startMin == g_endeMin)
      return true;
   datetime t = TimeCurrent();
   int jetzt = TimeHour(t) * 60 + TimeMinute(t);
   if(g_startMin < g_endeMin)
      return (jetzt >= g_startMin && jetzt < g_endeMin);
   return (jetzt >= g_startMin || jetzt < g_endeMin);   // Fenster über Mitternacht
}

// Prüft alle Schutzfilter. true = Handel erlaubt, sonst Grund in 'grund'
bool HandelErlaubt(string &grund, double atr)
{
   grund = "";
   VerlustSerieAktualisieren();

   if(g_gestoppt)
   {
      grund = "Gestoppt (Kill-Switch) - EA neu starten";
      return false;
   }
   if(g_tgPause)
   {
      grund = "Pausiert per Telegram (/start hebt auf)";
      return false;
   }
   if(g_modus != NUR_SIGNALE && !IsTesting() && (!IsTradeAllowed() || !IsExpertEnabled()))
   {
      grund = "Algo-Trading/AutoTrading ist aus";
      return false;
   }
   if(!ZeitfensterOK())
   {
      grund = "Außerhalb Handelszeit (" + HandelStart + "-" + HandelEnde + ")";
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
   double maxSp  = MaxSpreadAktuell(atr);
   double sp     = SpreadPunkte();
   double ko     = KommissionPunkte();
   double kosten = sp + ko;
   if(kosten > maxSp)
   {
      grund = "Kosten zu hoch (" + KostenText(sp, ko) + " > " + DoubleToString(maxSp, 1) + " Pkt)";
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Plan berechnen: Preise, SL/TP, Lot                               |
//+------------------------------------------------------------------+
bool BerechnePlan(int richtung, double atr, Plan &p, string &grund)
{
   grund = "";
   RefreshRates();

   if(atr <= 0.0)
   {
      grund = "ATR nicht verfügbar";
      return false;
   }

   p.richtung  = richtung;
   p.atr       = atr;
   p.preis     = (richtung > 0) ? Ask : Bid;
   p.spreadPkt = SpreadPunkte();
   p.kommPkt   = KommissionPunkte();

   double spread  = Ask - Bid;
   double stopLvl = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

   // Mindestabstände: SL wird vom Gegenkurs gemessen -> StopLevel + Spread
   double slDist = MathMax(SL_ATR * atr, stopLvl + spread);
   double tpDist = MathMax(TP_ATR * atr, stopLvl);

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
   double risikoGeld   = AccountEquity() * RisikoProzent / 100.0;
   double verlustProLot = p.slDist / tickSize * tickValue + KommissionProLot;   // SL-Verlust + Kommission
   if(verlustProLot <= 0.0)
   {
      grund = "Verlust pro Lot ungültig";
      return false;
   }
   double lotRoh = risikoGeld / verlustProLot;
   double lot    = LotAbrunden(lotRoh);

   if(lot < minLot - 1e-9)
   {
      grund = "Lot " + DoubleToString(lotRoh, 4) + " < MinLot " + DoubleToString(minLot, 2)
              + ": Risiko " + DoubleToString(RisikoProzent, 1) + " % zu klein, kein Trade";
      return false;
   }
   if(lot > MaxLot)
      lot = LotAbrunden(MaxLot);
   if(maxLotBr > 0.0 && lot > maxLotBr)
      lot = LotAbrunden(maxLotBr);
   if(lot < minLot - 1e-9)
   {
      grund = "MaxLot-Deckel (" + DoubleToString(MaxLot, 2) + ") < MinLot " + DoubleToString(minLot, 2)
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
bool OrderOeffnen(int richtung, double atr, string &grund)
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
      if(!BerechnePlan(richtung, atr, p, grund))
         return false;

      ResetLastError();
      int ticket = OrderSend(Symbol(), cmd, p.lot, p.preis, slip, p.sl, p.tp,
                             ORDER_KOMMENTAR, MagicNumber, 0, clr);
      if(ticket > 0)
      {
         Print("ScalpScout: Order eröffnet #", ticket, " ", (richtung > 0 ? "BUY " : "SELL "),
               DoubleToString(p.lot, 2), " ", Symbol(), " @", DoubleToString(p.preis, Digits),
               " SL ", DoubleToString(p.sl, Digits), " TP ", DoubleToString(p.tp, Digits),
               " (Versuch ", v, ")");
         g_orderTicket = ticket;
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
//| Positionen verwalten: Break-even und Trailing                    |
//+------------------------------------------------------------------+
void PositionenVerwalten()
{
   if(!BE_Aktiv && !TrailingAktiv)
      return;
   double atr = AktuelleATR();
   if(atr <= 0.0)
      return;
   double stopLvl = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber)
         continue;
      int typ = OrderType();
      if(typ > OP_SELL)
         continue;

      double offen = OrderOpenPrice();
      double sl    = OrderStopLoss();
      double neu   = sl;
      bool   aendern = false;

      if(typ == OP_BUY)
      {
         double gewinn = Bid - offen;
         if(BE_Aktiv && gewinn >= BE_ATR * atr)
         {
            double be = NormalizeDouble(offen + BE_PufferPunkte * Point, Digits);
            if(sl == 0.0 || be > sl + Point / 2.0)
               neu = be;
         }
         if(TrailingAktiv && gewinn >= TrailingStartATR * atr)
         {
            double t = NormalizeDouble(Bid - TrailingATR * atr, Digits);
            if(neu == 0.0 || t > neu + TrailingSchrittATR * atr)
               neu = t;
         }
         neu = NormalizeDouble(neu, Digits);
         aendern = (neu > 0.0 && (sl == 0.0 || neu > sl + Point / 2.0) && neu <= Bid - stopLvl);
      }
      else
      {
         double gewinn = offen - Ask;
         if(BE_Aktiv && gewinn >= BE_ATR * atr)
         {
            double be = NormalizeDouble(offen - BE_PufferPunkte * Point, Digits);
            if(sl == 0.0 || be < sl - Point / 2.0)
               neu = be;
         }
         if(TrailingAktiv && gewinn >= TrailingStartATR * atr)
         {
            double t = NormalizeDouble(Ask + TrailingATR * atr, Digits);
            if(neu == 0.0 || t < neu - TrailingSchrittATR * atr)
               neu = t;
         }
         neu = NormalizeDouble(neu, Digits);
         aendern = (neu > 0.0 && (sl == 0.0 || neu < sl - Point / 2.0) && neu >= Ask + stopLvl);
      }

      if(aendern)
      {
         ResetLastError();
         if(!OrderModify(OrderTicket(), offen, neu, OrderTakeProfit(), 0, clrDodgerBlue))
         {
            int err = GetLastError();
            if(err != 1)   // 1 = keine Änderung, harmlos
               LogFehler("OrderModify #" + IntegerToString(OrderTicket()), err);
         }
         else
            Print("ScalpScout: SL #", OrderTicket(), " nachgezogen auf ", DoubleToString(neu, Digits));
      }
   }
}

//+------------------------------------------------------------------+
//| Kill-Switch: alle eigenen Positionen auf diesem Symbol schließen |
//+------------------------------------------------------------------+
void AlleSchliessen()
{
   int geschlossen = 0, fehler = 0;
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
   Alert("ScalpScout ", Symbol(), ": Kill-Switch - ", geschlossen, " geschlossen, ", fehler, " Fehler");
}

//+------------------------------------------------------------------+
//| Oberfläche: Objekt-Helfer                                        |
//+------------------------------------------------------------------+
void LabelSetzen(string name, int x, int y, string text, color clr, int groesse = 9)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, groesse);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void RechteckSetzen(string name, int x, int y, int b, int h, color bg, color rand)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, b);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, rand);
}

void KnopfSetzen(string name, int x, int y, int b, int h, string text, color bg, color fg)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, b);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, fg);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

string ModusText()
{
   switch(g_modus)
   {
      case MANUELLE_FREIGABE: return "Manuelle Freigabe";
      case VOLLAUTOMATIK:     return "Vollautomatik";
      case NUR_SIGNALE:       return "Nur Signale";
   }
   return "?";
}

//+------------------------------------------------------------------+
//| Info-Bereich oben links                                          |
//+------------------------------------------------------------------+
void InfoAufbauen()
{
   if(!g_ui)
      return;
   // Dunkler Hintergrund zuerst, damit Labels und Knopf darüber liegen
   RechteckSetzen(OBJ_INFO_BG, 4, 24, INFO_BREITE, INFO_ZEILEN * 15 + 40, C'20,20,20', clrGray);
   for(int i = 0; i < INFO_ZEILEN; i++)
      LabelSetzen(PRAEFIX + "info_" + IntegerToString(i), 10, 30 + i * 15, "", clrWhite);
   KnopfSetzen(OBJ_KILL, 10, 30 + INFO_ZEILEN * 15 + 6, 200, 22, "ALLES SCHLIESSEN", clrFireBrick, clrWhite);
}

void InfoZeile(int i, string text, color clr)
{
   LabelSetzen(PRAEFIX + "info_" + IntegerToString(i), 10, 30 + i * 15, Kuerzen(text, INFO_MAXZEICHEN), clr);
}

void UiAktualisieren()
{
   if(!g_ui)
      return;
   double atr    = AktuelleATR();
   double maxSp  = MaxSpreadAktuell(atr);
   double sp     = SpreadPunkte();
   double ko     = KommissionPunkte();
   double diff   = AccountEquity() - g_tagEquity;
   double proz   = (g_tagEquity > 0.0) ? diff / g_tagEquity * 100.0 : 0.0;
   string grund  = "";
   bool   frei   = HandelErlaubt(grund, atr);

   InfoZeile(0, "ScalpScout | " + Symbol() + " | Magic " + IntegerToString(MagicNumber), clrWhite);
   InfoZeile(1, "Modus: " + ModusText() + (IsTesting() ? " (Tester)" : ""), clrWhite);
   InfoZeile(2, "Kosten: " + KostenText(sp, ko) + " / max " + DoubleToString(maxSp, 1) + " Pkt",
             (sp + ko > maxSp) ? clrOrangeRed : clrLime);
   InfoZeile(3, "ATR(" + IntegerToString(ATR_Periode) + ", M1): " + DoubleToString(atr, Digits)
                + " (" + DoubleToString(atr / Point, 0) + " Pkt)", clrWhite);
   InfoZeile(4, "Serverzeit: " + TimeToString(TimeCurrent(), TIME_MINUTES)
                + " (Handel " + HandelStart + "-" + HandelEnde + ")",
             ZeitfensterOK() ? clrLime : clrOrange);
   InfoZeile(5, "Tagesergebnis: " + DoubleToString(diff, 2) + " " + AccountCurrency()
                + " (" + DoubleToString(proz, 2) + " %)", (diff >= 0.0) ? clrLime : clrOrangeRed);
   InfoZeile(6, g_tagesLimit ? "Verlustlimit: ERREICHT (" + DoubleToString(TagesVerlustProzent, 1) + " %)"
                             : "Verlustlimit: ok (max " + DoubleToString(TagesVerlustProzent, 1) + " %)",
             g_tagesLimit ? clrOrangeRed : clrLime);
   InfoZeile(7, frei ? "Status: bereit" : "Blockiert: " + grund, frei ? clrLime : clrOrange);
   color tgFarbe = clrSilver;
   string tgText = TgInfoText(tgFarbe);
   InfoZeile(8, tgText, tgFarbe);
   string h = (g_hinweis == "") ? "Hinweis: -" :
              "Hinweis (" + TimeToString(g_hinweisZeit, TIME_MINUTES) + "): " + g_hinweis;
   InfoZeile(9, h, (g_hinweis == "") ? clrSilver : clrGold);
}

//+------------------------------------------------------------------+
//| Signal-Panel (Freigabe-Modus)                                    |
//+------------------------------------------------------------------+
void PanelLoeschen()
{
   ObjectsDeleteAll(0, OBJ_PNL_PRAEFIX);
   ChartRedraw(0);
}

string PanelZeileText(int i)
{
   Plan p = g_sig.plan;
   switch(i)
   {
      case 0: return "SIGNAL: " + (p.richtung > 0 ? "LONG (Kauf)" : "SHORT (Verkauf)") + "  " + Symbol();
      case 1: return "Einstieg ca.: " + DoubleToString(p.preis, Digits);
      case 2: return "Stop-Loss: " + DoubleToString(p.sl, Digits) + "  (" + DoubleToString(p.slDist / Point, 0) + " Pkt)";
      case 3: return "Take-Profit: " + DoubleToString(p.tp, Digits) + "  (" + DoubleToString(p.tpDist / Point, 0) + " Pkt)";
      case 4: return "Lot: " + DoubleToString(p.lot, LotStellen(MarketInfo(Symbol(), MODE_LOTSTEP)))
                     + "  | Risiko " + DoubleToString(RisikoProzent, 1) + " %";
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

void PanelZeigen()
{
   if(!g_ui)
      return;
   PanelLoeschen();
   int x = 10;
   int y = 30 + INFO_ZEILEN * 15 + 40;
   color titel = (g_sig.plan.richtung > 0) ? clrLime : clrOrangeRed;
   RechteckSetzen(OBJ_PNL_BG, x, y, 340, 190, C'22,28,40', clrDimGray);
   for(int i = 0; i < PNL_ZEILEN; i++)
      LabelSetzen(OBJ_PNL_PRAEFIX + "z" + IntegerToString(i), x + 10, y + 8 + i * 18,
                  PanelZeileText(i), (i == 0) ? titel : clrWhite, (i == 0) ? 10 : 9);
   KnopfSetzen(OBJ_PNL_OK, x + 10,  y + 190 - 38, 150, 28, "[+] Ausführen", clrForestGreen, clrWhite);
   KnopfSetzen(OBJ_PNL_NO, x + 180, y + 190 - 38, 150, 28, "[–] Verwerfen", clrFireBrick, clrWhite);
   ChartRedraw(0);
}

void PanelAktualisieren()
{
   if(!g_ui || !g_sig.aktiv)
      return;
   for(int i = 0; i < PNL_ZEILEN; i++)
      ObjectSetString(0, OBJ_PNL_PRAEFIX + "z" + IntegerToString(i), OBJPROP_TEXT, PanelZeileText(i));
}

// tgText: Statuszeile für die Telegram-Nachricht (leer = Nachricht nicht ändern)
void SignalVerwerfen(string grund, string tgText = "")
{
   bool war = g_sig.aktiv;
   if(war)
      Print("ScalpScout: Signal verworfen - ", grund);
   g_sig.aktiv = false;
   PanelLoeschen();
   if(war && tgText != "" && g_sigMsgId > 0)
      TgNachrichtBearbeiten(g_sigMsgId, g_tgKopf + "\n" + tgText);
}

// Ablauf und Preisabstand des offenen Signals prüfen
void SignalPruefen()
{
   if(!g_sig.aktiv)
      return;
   if(TimeLocal() - g_sig.zeit > SignalGueltigSek)
   {
      SignalVerwerfen("abgelaufen", "⌛ abgelaufen");
      HinweisSetzen("Signal abgelaufen (" + IntegerToString(SignalGueltigSek) + " s)");
      return;
   }
   RefreshRates();
   double aktuell = (g_sig.plan.richtung > 0) ? Ask : Bid;
   if(MathAbs(aktuell - g_sig.plan.preis) > PreisAbweichungATR * g_sig.plan.atr)
   {
      SignalVerwerfen("Preis zu weit vom Signal entfernt", "⌛ verworfen: Preis zu weit vom Signal entfernt");
      HinweisSetzen("Signal verworfen: Preis zu weit weg");
      return;
   }
   PanelAktualisieren();
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
   long   msgId    = g_sigMsgId;
   string kopf     = g_tgKopf;
   g_sig.aktiv = false;      // gegen Doppelklick
   PanelLoeschen();

   string grund = "";
   bool   ok    = false;
   if(!HandelErlaubt(grund, atr))
   {
      HinweisSetzen("Nicht ausgeführt: " + grund);
      ergebnis = grund;
   }
   else if(!OrderOeffnen(richtung, atr, grund))
   {
      HinweisSetzen("Order fehlgeschlagen: " + grund);
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
//| Benachrichtigung                                                 |
//+------------------------------------------------------------------+
void Melden(string text)
{
   Print("ScalpScout: ", text);
   if(IsTesting())
      return;
   Alert(text);
   PlaySound("alert.wav");
   if(PushAktiv)
   {
      if(!SendNotification(text))
         LogFehler("SendNotification", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Telegram-Fernbedienung (WebRequest, nur Timer und Ereignisse)    |
//+------------------------------------------------------------------+
// Telegram ist komplett aus bei !TelegramAktiv, leerem Token/Chat-ID oder im Tester.
// Fehler führen nie zum Absturz: Anfragen schlagen still fehl, der Handel läuft weiter.

bool TgBereit()
{
   return (g_tgAktiv && !g_tgGesperrt && TimeLocal() >= g_tgSperreBis);
}

// Text für JSON-Strings: \ " und Zeilenumbruch maskieren, Nicht-ASCII als \uXXXX (Emoji = Surrogatpaar)
string JsonEscape(string s)
{
   string z = "0123456789abcdef";
   string r = "";
   int n = StringLen(s);
   for(int i = 0; i < n; i++)
   {
      int c = (int)StringGetCharacter(s, i);
      if(c == 92)
         r += "\\\\";
      else if(c == 34)
         r += "\\\"";
      else if(c == 10)
         r += "\\n";
      else if(c == 13)
         r += "\\r";
      else if(c == 9)
         r += "\\t";
      else if(c < 32 || c > 126)
         r += "\\u" + StringSubstr(z, (c >> 12) & 15, 1) + StringSubstr(z, (c >> 8) & 15, 1)
                    + StringSubstr(z, (c >> 4) & 15, 1) + StringSubstr(z, c & 15, 1);
      else
         r += StringSubstr(s, i, 1);
   }
   return r;
}

// Sonderzeichen für Telegram parse_mode HTML maskieren
string HtmlEscape(string s)
{
   StringReplace(s, "&", "&amp;");
   StringReplace(s, "<", "&lt;");
   StringReplace(s, ">", "&gt;");
   return s;
}

int HexZiffer(int c)
{
   if(c >= 48 && c <= 57)  return c - 48;        // 0-9
   if(c >= 97 && c <= 102) return c - 97 + 10;   // a-f
   if(c >= 65 && c <= 70)  return c - 65 + 10;   // A-F
   return 0;
}

// Ganzzahl zu "key": ab Position 'von' lesen (einfaches JSON-Parsing ohne Include)
bool JsonZahl(string s, string key, int von, long &wert)
{
   string k = "\"" + key + "\":";
   int p = StringFind(s, k, von);
   if(p < 0)
      return false;
   p += StringLen(k);
   int n = StringLen(s);
   while(p < n && StringGetCharacter(s, p) == 32)
      p++;
   string z = "";
   while(p < n)
   {
      int c = (int)StringGetCharacter(s, p);
      if((c >= 48 && c <= 57) || (z == "" && c == 45))
      {
         z += StringSubstr(s, p, 1);
         p++;
      }
      else
         break;
   }
   if(z == "" || z == "-")
      return false;
   wert = StringToInteger(z);
   return true;
}

// Text zu "key":"..." ab Position 'von' lesen, Escapes (\" \\ \n \uXXXX) auflösen
bool JsonText(string s, string key, int von, string &wert)
{
   string k = "\"" + key + "\":\"";
   int p = StringFind(s, k, von);
   if(p < 0)
      return false;
   p += StringLen(k);
   int n = StringLen(s);
   string r = "";
   while(p < n)
   {
      int c = (int)StringGetCharacter(s, p);
      if(c == 34)
      {
         wert = r;
         return true;
      }
      if(c == 92 && p + 1 < n)
      {
         int e = (int)StringGetCharacter(s, p + 1);
         p += 2;
         if(e == 110)       r += "\n";          // \n
         else if(e == 114)  r += "\r";          // \r
         else if(e == 116)  r += "\t";          // \t
         else if(e == 117 && p + 4 <= n)        // \uXXXX
         {
            int v = 0;
            for(int h = 0; h < 4; h++)
               v = v * 16 + HexZiffer((int)StringGetCharacter(s, p + h));
            r += ShortToString((ushort)v);
            p += 4;
         }
         else
            r += StringSubstr(s, p - 1, 1);      // \" \\ \/
         continue;
      }
      r += StringSubstr(s, p, 1);
      p++;
   }
   return false;
}

// Eine Anfrage an die Bot-API (POST, JSON). true nur bei "ok":true.
bool TgAnfrage(string methode, string jsonBody, string &antwort)
{
   antwort = "";
   if(!g_tgAktiv || g_tgGesperrt)
      return false;

   string url  = "https://api.telegram.org/bot" + g_tgToken + "/" + methode;
   string kopf = "Content-Type: application/json\r\n";
   string kopfAntwort = "";
   char   daten[];
   char   ergebnis[];

   StringToCharArray(jsonBody, daten, 0, -1, CP_UTF8);
   int groesse = ArraySize(daten);
   if(groesse > 0 && daten[groesse - 1] == 0)
      ArrayResize(daten, groesse - 1);      // abschließende Null entfernen

   ResetLastError();
   int code = WebRequest("POST", url, kopf, 5000, daten, ergebnis, kopfAntwort);
   if(code == -1)
   {
      int err = GetLastError();
      g_tgVerbunden = false;
      g_tgFehler    = err;
      if(err == 4060)
      {
         g_tgGesperrt = true;
         Print("ScalpScout Telegram FEHLER 4060: URL nicht erlaubt. In MT4 Extras > Optionen > Expert Advisors ",
               "'WebRequest für folgende URLs erlauben' https://api.telegram.org eintragen, dann EA neu starten.");
      }
      else
      {
         g_tgSperreBis = TimeLocal() + 10;   // kurze Pause bei Netzproblemen
         LogFehler("Telegram " + methode, err);
      }
      return false;
   }

   antwort = CharArrayToString(ergebnis, 0, WHOLE_ARRAY, CP_UTF8);
   if(code >= 500 || code == 0)
      g_tgSperreBis = TimeLocal() + 10;
   else if(code == 401 || code == 404 || code == 409 || code == 429)
      g_tgSperreBis = TimeLocal() + 30;   // Token falsch / Webhook aktiv / Limit: nicht ständig neu versuchen
   if(StringFind(antwort, "\"ok\":true") < 0)
   {
      g_tgVerbunden = false;
      g_tgFehler    = code;
      string beschr = "";
      JsonText(antwort, "description", 0, beschr);
      Print("ScalpScout Telegram: ", methode, " abgelehnt (HTTP ", code, ") ", beschr);
      return false;
   }
   g_tgVerbunden = true;
   g_tgFehler    = 0;
   return true;
}

// Nachricht senden; Rückgabe message_id (0 = nicht gesendet). tastatur = reply_markup-JSON oder "".
long TgNachrichtSenden(string html, string tastatur)
{
   if(!TgBereit())
      return 0;
   string body = "{\"chat_id\":\"" + JsonEscape(g_tgChat) + "\",\"text\":\"" + JsonEscape(html)
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
                 + ",\"text\":\"" + JsonEscape(html) + "\",\"parse_mode\":\"HTML\""
                 + ",\"reply_markup\":{\"inline_keyboard\":[]}}";
   string antwort = "";
   return TgAnfrage("editMessageText", body, antwort);
}

void TgCallbackAntwort(string cbId, string text)
{
   if(!TgBereit())
      return;
   string body = "{\"callback_query_id\":\"" + JsonEscape(cbId) + "\",\"text\":\"" + JsonEscape(text) + "\"}";
   string antwort = "";
   TgAnfrage("answerCallbackQuery", body, antwort);
}

// Eindeutige Signal-ID (Serverzeit-Sekunden, immer größer als die vorige)
int TgNeueSignalId()
{
   int id = (int)TimeCurrent();
   if(id <= g_sigId)
      id = g_sigId + 1;
   return id;
}

string TgTastatur(int id)
{
   string sid = IntegerToString(id);
   return "{\"inline_keyboard\":[[{\"text\":\"" + JsonEscape("✅ JA") + "\",\"callback_data\":\"ja_" + sid + "\"},"
          + "{\"text\":\"" + JsonEscape("❌ NEIN") + "\",\"callback_data\":\"nein_" + sid + "\"}]]}";
}

string TgSignalKopf(Plan &p)
{
   return "<b>" + HtmlEscape(Symbol()) + "</b>  " + ((p.richtung > 0) ? "🟢 KAUF" : "🔴 VERKAUF");
}

string TgSignalText(Plan &p)
{
   int ls = LotStellen(MarketInfo(Symbol(), MODE_LOTSTEP));
   return TgSignalKopf(p) + "\n"
        + "Einstieg: " + DoubleToString(p.preis, Digits) + "\n"
        + "SL: " + DoubleToString(p.sl, Digits) + " (" + DoubleToString(p.slDist / Point, 0) + " Pkt)\n"
        + "TP: " + DoubleToString(p.tp, Digits) + " (" + DoubleToString(p.tpDist / Point, 0) + " Pkt)\n"
        + "Lot: " + DoubleToString(p.lot, ls) + "\n"
        + "Kosten: " + KostenText(p.spreadPkt, p.kommPkt) + " Pkt\n"
        + "CRV 1:" + DoubleToString(p.crv, 2);
}

// Gewinn/Verlust aller offenen eigenen Positionen auf diesem Symbol
double OffenerGewinn()
{
   double summe = 0.0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber && OrderType() <= OP_SELL)
         summe += OrderProfit() + OrderSwap() + OrderCommission();
   }
   return summe;
}

string TgStatusText()
{
   double atr   = AktuelleATR();
   double sp    = SpreadPunkte();
   double ko    = KommissionPunkte();
   double maxSp = MaxSpreadAktuell(atr);
   double diff  = AccountEquity() - g_tagEquity;
   double proz  = (g_tagEquity > 0.0) ? diff / g_tagEquity * 100.0 : 0.0;
   string grund = "";
   bool   frei  = HandelErlaubt(grund, atr);
   string status = frei ? "Status: bereit" : "Blockiert: " + HtmlEscape(grund);
   return "<b>ScalpScout " + HtmlEscape(Symbol()) + "</b>\n"
        + "Modus: " + ModusText() + "\n"
        + "Kosten: " + KostenText(sp, ko) + " / max " + DoubleToString(maxSp, 1) + " Pkt\n"
        + "Tagesergebnis: " + DoubleToString(diff, 2) + " " + AccountCurrency() + " (" + DoubleToString(proz, 2) + " %)\n"
        + "Offene Positionen: " + IntegerToString(ZaehlePositionen()) + " ("
        + DoubleToString(OffenerGewinn(), 2) + " " + AccountCurrency() + ")\n"
        + status;
}

// Text für die Info-Zeile "Telegram: ..."
string TgInfoText(color &clr)
{
   string t;
   if(!g_tgAktiv)
   {
      clr = clrSilver;
      return "Telegram: aus";
   }
   if(g_tgGesperrt)
   {
      clr = clrOrangeRed;
      return "Telegram: Fehler 4060 - Extras>Optionen>Experts: https://api.telegram.org erlauben";
   }
   if(g_tgFehler != 0)
   {
      clr = clrOrangeRed;
      t   = "Telegram: Fehler " + IntegerToString(g_tgFehler);
   }
   else
   {
      clr = g_tgVerbunden ? clrLime : clrSilver;
      t   = g_tgVerbunden ? "Telegram: verbunden" : "Telegram: wartet";
   }
   if(g_tgPause)
   {
      clr = clrOrange;
      t  += " | Pausiert per Telegram";
   }
   return t;
}

// Textbefehle aus dem Chat: /status, /stop, /start
void TgBefehl(string text)
{
   string t = text;
   StringToLower(t);
   StringTrimLeft(t);
   StringTrimRight(t);
   if(StringFind(t, "/status") == 0)
      TgNachrichtSenden(TgStatusText(), "");
   else if(StringFind(t, "/stop") == 0)
   {
      g_tgPause = true;
      HinweisSetzen("Pausiert per Telegram");
      TgNachrichtSenden("⏸ Pausiert: neue Signale werden blockiert. /start hebt die Pause auf.", "");
   }
   else if(StringFind(t, "/start") == 0)
   {
      g_tgPause = false;
      HinweisSetzen("Pause per Telegram aufgehoben");
      TgNachrichtSenden("▶️ Pause aufgehoben: neue Signale sind wieder erlaubt.", "");
   }
}

// Ein einzelnes Update (Abschnitt ab "update_id") auswerten
void TgUpdateBehandeln(string seg)
{
   int pc = StringFind(seg, "\"callback_query\":");
   if(pc >= 0)
   {
      string cbId = "", data = "";
      if(!JsonText(seg, "id", pc, cbId) || !JsonText(seg, "data", pc, data))
         return;
      long chat = 0;
      int  pch  = StringFind(seg, "\"chat\":{", pc);
      bool hatChat = (pch >= 0 && JsonZahl(seg, "id", pch, chat));
      if(!hatChat)
      {
         int pf = StringFind(seg, "\"from\":{", pc);
         hatChat = (pf >= 0 && JsonZahl(seg, "id", pf, chat));
      }
      if(!hatChat || IntegerToString(chat) != g_tgChat)
      {
         Print("ScalpScout Telegram: Knopfdruck aus fremdem Chat ignoriert.");
         return;
      }

      int us = StringFind(data, "_");
      if(us < 0)
         return;
      string aktion = StringSubstr(data, 0, us);
      int    sid    = (int)StringToInteger(StringSubstr(data, us + 1));
      if(!g_sig.aktiv || sid != g_sigId)
      {
         TgCallbackAntwort(cbId, "Signal abgelaufen");
         return;
      }

      if(aktion == "ja")
      {
         string erg   = "";
         string kopf  = g_tgKopf;
         long   msgId = g_sigMsgId;
         bool   ok    = SignalAusfuehren(true, erg);
         TgCallbackAntwort(cbId, ok ? "ausgeführt" : "nicht ausgeführt");
         if(msgId > 0)
            TgNachrichtBearbeiten(msgId, kopf + "\n" + (ok ? "✅ ausgeführt: " + erg
                                                         : "⚠️ nicht ausgeführt: " + HtmlEscape(erg)));
         UiAktualisieren();
      }
      else if(aktion == "nein")
      {
         TgCallbackAntwort(cbId, "verworfen");
         SignalVerwerfen("per Telegram verworfen", "❌ verworfen");
         HinweisSetzen("Signal verworfen (Telegram)");
         UiAktualisieren();
      }
      return;
   }

   int pm = StringFind(seg, "\"message\":{");
   if(pm >= 0)
   {
      long chat = 0;
      int  pch  = StringFind(seg, "\"chat\":{", pm);
      if(pch < 0 || !JsonZahl(seg, "id", pch, chat))
         return;
      if(IntegerToString(chat) != g_tgChat)
      {
         Print("ScalpScout Telegram: Nachricht aus fremdem Chat ignoriert.");
         return;
      }
      string text = "";
      if(JsonText(seg, "text", pch, text))
         TgBefehl(text);
   }
}

// Antwort von getUpdates in einzelne Updates zerlegen und abarbeiten
void TgUpdatesVerarbeiten(string antwort)
{
   string marke = "\"update_id\":";
   int pos = StringFind(antwort, marke);
   while(pos >= 0)
   {
      int naechst = StringFind(antwort, marke, pos + StringLen(marke));
      string seg  = (naechst >= 0) ? StringSubstr(antwort, pos, naechst - pos) : StringSubstr(antwort, pos);
      long uid = 0;
      if(JsonZahl(seg, "update_id", 0, uid) && uid + 1 > g_tgOffset)
         g_tgOffset = uid + 1;          // zuerst bestätigen, dann behandeln (kein doppeltes Ausführen)
      TgUpdateBehandeln(seg);
      pos = naechst;
   }
}

// In OnTimer: alle TelegramAbfrageSek Sekunden neue Updates holen
void TgAbfragen()
{
   if(!TgBereit())
      return;
   datetime jetzt = TimeLocal();
   if(jetzt - g_tgLetzteAbfrage < MathMax(1, TelegramAbfrageSek))
      return;
   g_tgLetzteAbfrage = jetzt;

   string body = "{\"offset\":" + IntegerToString(g_tgOffset)
                 + ",\"timeout\":0,\"allowed_updates\":[\"callback_query\",\"message\"]}";
   string antwort = "";
   if(!TgAnfrage("getUpdates", body, antwort))
      return;
   TgUpdatesVerarbeiten(antwort);
}

// Meldung "Position #x geschlossen" für die aktuell selektierte (geschlossene) Order
void TgSchliessungMelden()
{
   int    ticket = OrderTicket();
   double profit = OrderProfit() + OrderSwap() + OrderCommission();
   double cp     = OrderClosePrice();
   double sl     = OrderStopLoss();
   double tp     = OrderTakeProfit();
   string kom    = OrderComment();
   StringToLower(kom);
   double tol    = 2.0 * Point;

   string grund = "manuell";
   if(StringFind(kom, "[tp]") >= 0)
      grund = "TP";
   else if(StringFind(kom, "[sl]") >= 0)
      grund = "SL";
   else if(tp > 0.0 && MathAbs(cp - tp) <= tol)
      grund = "TP";
   else if(sl > 0.0 && MathAbs(cp - sl) <= tol)
      grund = "SL";

   TgNachrichtSenden("<b>" + HtmlEscape(Symbol()) + "</b> Position #" + IntegerToString(ticket) + " geschlossen: "
                     + ((profit >= 0.0) ? "+" : "") + DoubleToString(profit, 2) + " " + AccountCurrency()
                     + " (" + grund + ")", "");
}

// Aktuell offene eigene Tickets merken (beim Start)
void TgOffenMerken()
{
   ArrayResize(g_tgOffen, 0);
   ArrayResize(g_tgVersuche, 0);
   int nn = 0;
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber || OrderType() > OP_SELL)
         continue;
      ArrayResize(g_tgOffen, nn + 1);
      ArrayResize(g_tgVersuche, nn + 1);
      g_tgOffen[nn]    = OrderTicket();
      g_tgVersuche[nn] = 0;
      nn++;
   }
}

// In OnTimer: neu geschlossene eigene Positionen erkennen und melden
void TgSchliessungenPruefen()
{
   if(!TelegramMeldeSchliessung || !TgBereit())
      return;

   int neu[];
   int neuV[];
   int nn = 0;
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber || OrderType() > OP_SELL)
         continue;
      ArrayResize(neu, nn + 1);
      ArrayResize(neuV, nn + 1);
      neu[nn]  = OrderTicket();
      neuV[nn] = 0;
      nn++;
   }

   int alt = ArraySize(g_tgOffen);
   for(int k = 0; k < alt; k++)
   {
      int  t = g_tgOffen[k];
      bool nochOffen = false;
      for(int j = 0; j < nn; j++)
      {
         if(neu[j] == t)
         {
            nochOffen = true;
            break;
         }
      }
      if(nochOffen)
         continue;
      if(OrderSelect(t, SELECT_BY_TICKET) && OrderCloseTime() > 0)
         TgSchliessungMelden();
      else if(g_tgVersuche[k] < 30)      // Historie evtl. noch nicht aktuell: später erneut suchen
      {
         ArrayResize(neu, nn + 1);
         ArrayResize(neuV, nn + 1);
         neu[nn]  = t;
         neuV[nn] = g_tgVersuche[k] + 1;
         nn++;
      }
   }

   ArrayResize(g_tgOffen, nn);
   ArrayResize(g_tgVersuche, nn);
   for(int m = 0; m < nn; m++)
   {
      g_tgOffen[m]    = neu[m];
      g_tgVersuche[m] = neuV[m];
   }
}

// In OnInit: Telegram prüfen, alte Updates überspringen, Begrüßung senden
void TelegramStarten()
{
   g_tgAktiv     = false;
   g_tgGesperrt  = false;
   g_tgVerbunden = false;
   g_tgFehler    = 0;
   g_tgOffset    = 0;
   g_tgSperreBis = 0;
   g_tgLetzteAbfrage = TimeLocal();
   ArrayResize(g_tgOffen, 0);
   ArrayResize(g_tgVersuche, 0);

   if(!TelegramAktiv || IsTesting())
      return;
   g_tgToken = TelegramToken;
   g_tgChat  = TelegramChatID;
   StringTrimLeft(g_tgToken);
   StringTrimRight(g_tgToken);
   StringTrimLeft(g_tgChat);
   StringTrimRight(g_tgChat);
   if(g_tgToken == "" || g_tgChat == "")
   {
      Print("ScalpScout Telegram: Token oder Chat-ID fehlt - Telegram bleibt aus.");
      return;
   }
   g_tgAktiv = true;

   // Alte Updates überspringen: nur das letzte holen und dahinter weiterlesen
   string antwort = "";
   if(TgAnfrage("getUpdates", "{\"offset\":-1,\"timeout\":0,\"allowed_updates\":[\"callback_query\",\"message\"]}", antwort))
   {
      int p = StringFind(antwort, "\"update_id\":");
      long uid = 0;
      if(p >= 0 && JsonZahl(antwort, "update_id", p, uid))
         g_tgOffset = uid + 1;
   }
   TgOffenMerken();
   TgNachrichtSenden("ScalpScout auf <b>" + HtmlEscape(Symbol()) + "</b> gestartet (Modus " + ModusText() + ")", "");
}

//+------------------------------------------------------------------+
//| Signal-Logik auf geschlossener M1-Kerze (Shift 1)                |
//+------------------------------------------------------------------+
// Rückgabe: +1 Long, -1 Short, 0 kein Signal
int SignalErkennen(double &atr)
{
   atr = 0.0;
   int mindestens = MathMax(MathMax(ATR_Periode, EMA_Periode * 2), VolumenKerzen + BreakoutKerzen) + 5;
   if(iBars(Symbol(), PERIOD_M1) < mindestens)
      return 0;

   atr = AktuelleATR();
   if(atr <= 0.0)
      return 0;

   double o1 = iOpen(Symbol(), PERIOD_M1, 1);
   double c1 = iClose(Symbol(), PERIOD_M1, 1);
   double koerper = MathAbs(c1 - o1);
   if(koerper <= ImpulsFaktor * atr)
      return 0;

   // Volumen: Kerze 1 gegen Durchschnitt der Kerzen davor (Shift 2 .. VolumenKerzen+1)
   double summe = 0.0;
   for(int i = 2; i <= VolumenKerzen + 1; i++)
      summe += (double)iVolume(Symbol(), PERIOD_M1, i);
   double schnitt = (VolumenKerzen > 0) ? summe / VolumenKerzen : 0.0;
   double vol1    = (double)iVolume(Symbol(), PERIOD_M1, 1);
   if(schnitt <= 0.0 || vol1 <= VolumenFaktor * schnitt)
      return 0;

   double ema = iMA(Symbol(), PERIOD_M1, EMA_Periode, 0, MODE_EMA, PRICE_CLOSE, 1);

   if(c1 > o1)   // bullische Kerze -> Long prüfen
   {
      int hi = iHighest(Symbol(), PERIOD_M1, MODE_HIGH, BreakoutKerzen, 2);
      if(hi < 0) return 0;
      if(c1 <= iHigh(Symbol(), PERIOD_M1, hi)) return 0;
      if(TrendFilterAktiv && c1 <= ema) return 0;
      return 1;
   }
   if(c1 < o1)   // bärische Kerze -> Short prüfen
   {
      int lo = iLowest(Symbol(), PERIOD_M1, MODE_LOW, BreakoutKerzen, 2);
      if(lo < 0) return 0;
      if(c1 >= iLow(Symbol(), PERIOD_M1, lo)) return 0;
      if(TrendFilterAktiv && c1 >= ema) return 0;
      return -1;
   }
   return 0;
}

void NeueKerzeAuswerten()
{
   double atr;
   int sig = SignalErkennen(atr);
   if(sig == 0)
      return;

   string txt = (sig > 0) ? "LONG" : "SHORT";
   string grund;

   if(!HandelErlaubt(grund, atr))
   {
      HinweisSetzen("Signal " + txt + " blockiert: " + grund);
      return;
   }

   Plan p;
   if(!BerechnePlan(sig, atr, p, grund))
   {
      HinweisSetzen("Signal " + txt + " ohne Trade: " + grund);
      return;
   }

   string meldung = "ScalpScout " + Symbol() + " " + txt + " @" + DoubleToString(p.preis, Digits)
                    + " SL " + DoubleToString(p.sl, Digits) + " TP " + DoubleToString(p.tp, Digits)
                    + " Lot " + DoubleToString(p.lot, 2) + " " + KostenText(p.spreadPkt, p.kommPkt)
                    + " CRV 1:" + DoubleToString(p.crv, 2);

   switch(g_modus)
   {
      case NUR_SIGNALE:
         Melden(meldung + " (nur Signal)");
         HinweisSetzen("Signal " + txt + " gemeldet (kein Trade)");
         TgNachrichtSenden(TgSignalText(p) + "\nnur Signal, kein Trade", "");
         break;

      case VOLLAUTOMATIK:
         if(OrderOeffnen(sig, atr, grund))
         {
            Melden(meldung + " - ausgeführt");
            HinweisSetzen("Auto-Trade " + txt + " eröffnet");
            TgNachrichtSenden(TgSignalText(p) + "\n✅ automatisch ausgeführt: #" + IntegerToString(g_orderTicket)
                              + " @" + DoubleToString(g_orderPreis, Digits), "");
         }
         else
            HinweisSetzen("Auto-Trade " + txt + " fehlgeschlagen: " + grund);
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
      Alert("ScalpScout: HandelStart/HandelEnde müssen das Format HH:MM haben (z. B. 08:00).");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(ATR_Periode < 1 || EMA_Periode < 1 || VolumenKerzen < 1 || BreakoutKerzen < 1 ||
      ImpulsFaktor <= 0.0 || VolumenFaktor <= 0.0 || SL_ATR <= 0.0 || TP_ATR <= 0.0 ||
      RisikoProzent <= 0.0 || MaxLot <= 0.0 || MaxOffenePositionen < 1 || SignalGueltigSek < 1 ||
      KommissionProLot < 0.0)
   {
      Alert("ScalpScout: Ungültige Eingabewerte (Perioden, Faktoren, Risiko, MaxLot müssen > 0 sein, Kommission nicht negativ).");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(Period() != PERIOD_M1)
      Print("ScalpScout WARNUNG: EA ist für den M1-Chart gedacht (aktuell: ", Period(), " Min.). Auswertung läuft trotzdem auf M1.");

   // Wirksame Betriebsart
   g_modus = Modus;
   if(IsTesting() && Modus == MANUELLE_FREIGABE)
   {
      g_modus = VOLLAUTOMATIK;
      Print("ScalpScout: Strategietester erkannt - Modus MANUELLE_FREIGABE wird wie VOLLAUTOMATIK behandelt.");
   }
   g_ui = (!IsTesting() || IsVisualMode());

   g_sig.aktiv = false;
   g_gestoppt  = false;
   g_hinweis   = "";
   g_histAnzahl = -1;
   g_sigId     = 0;
   g_sigMsgId  = 0;
   g_tgKopf    = "";
   g_tgPause   = false;

   // Tagesstart (live aus globalen Variablen wiederherstellen)
   g_gvTag    = "SSC_" + IntegerToString(AccountNumber()) + "_" + IntegerToString(MagicNumber) + "_tag";
   g_gvEquity = "SSC_" + IntegerToString(AccountNumber()) + "_" + IntegerToString(MagicNumber) + "_eq";
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

   Print("ScalpScout gestartet: ", Symbol(), ", Modus ", ModusText(), ", MaxLot ", DoubleToString(MaxLot, 2),
         ", Risiko ", DoubleToString(RisikoProzent, 1), " %, Digits ", Digits, ", Point ", DoubleToString(Point, Digits));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, PRAEFIX);
   Comment("");
   ChartRedraw(0);
   Print("ScalpScout beendet (Grund ", reason, ").");
}

void OnTick()
{
   TagPruefen();
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
   SignalPruefen();
   TgAbfragen();
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
      int antwort = MessageBox("Alle Positionen von ScalpScout (Magic " + IntegerToString(MagicNumber)
                               + ") auf " + Symbol() + " jetzt schließen?\n\nDanach sind neue Trades gesperrt, bis der EA neu gestartet wird.",
                               "ScalpScout - ALLES SCHLIESSEN", MB_YESNO | MB_ICONWARNING);
      if(antwort == IDYES)
         AlleSchliessen();
      UiAktualisieren();
   }
}
//+------------------------------------------------------------------+
