//+------------------------------------------------------------------+
//|  ScalpScout/Fern.mqh - gemeinsame Funktionen von ScalpScout und  |
//|  ScalpScout Asia: Telegram-Fernsteuerung, gespeicherte           |
//|  Fern-Einstellungen (GlobalVariables), Diagnose, Tagesbericht.   |
//|  ScalpScout Trend hat eine eigene Umsetzung und nutzt diese      |
//|  Datei nicht. Einbinden nach Kern.mqh.                           |
//+------------------------------------------------------------------+
#property strict

string HaekchenText(bool ok)
{
   return ok ? "✓" : "✗";
}

// "HH:MM" aus Minuten seit 00:00
string MinutenText(int m)
{
   return IntegerToString(m / 60, 2, '0') + ":" + IntegerToString(m % 60, 2, '0');
}

// "H:MM" oder "HH:MM" -> Minuten seit 00:00; -1 bei ungültiger Eingabe
int ZeitLesen(string s)
{
   StringTrimLeft(s);
   StringTrimRight(s);
   if(StringLen(s) == 4 && StringGetCharacter(s, 1) == ':')
      s = "0" + s;
   return ParseHHMM(s);
}

// Zahl aus Telegram lesen: Komma oder Punkt, optional "%" am Ende, nur Ziffern und ein Dezimaltrenner
bool ZahlLesen(string s, double &w)
{
   StringTrimLeft(s);
   StringTrimRight(s);
   StringReplace(s, ",", ".");
   int n = StringLen(s);
   if(n > 0 && StringGetCharacter(s, n - 1) == '%')
   {
      s = StringSubstr(s, 0, n - 1);
      StringTrimRight(s);
      n = StringLen(s);
   }
   if(n == 0 || n > 12)
      return false;
   int punkte = 0, ziffern = 0;
   for(int i = 0; i < n; i++)
   {
      ushort c = StringGetCharacter(s, i);
      if(c >= '0' && c <= '9')
         ziffern++;
      else if(c == '.')
         punkte++;
      else
         return false;
   }
   if(ziffern == 0 || punkte > 1)
      return false;
   w = StringToDouble(s);
   return true;
}

double MinLotWert()
{
   double m = MarketInfo(Symbol(), MODE_MINLOT);
   return (m > 0.0) ? m : 0.01;
}

// Höchster per Telegram erlaubter Lot-Deckel: FernMaxLotObergrenze, höchstens Broker-MaxLot
double MaxLotGrenze()
{
   double g = FernMaxLotObergrenze;
   double b = MarketInfo(Symbol(), MODE_MAXLOT);
   if(b > 0.0 && b < g)
      g = b;
   return g;
}

int LotStellenAktuell()
{
   double step = MarketInfo(Symbol(), MODE_LOTSTEP);
   return LotStellen((step > 0.0) ? step : 0.01);
}

string LotText(double lot)
{
   return DoubleToString(lot, LotStellenAktuell());
}

string LimitText(double proz)
{
   return (proz > 0.0) ? DoubleToString(proz, 1) + " %" : "aus";
}

string GeldText(double v)
{
   return ((v >= 0.0) ? "+" : "") + DoubleToString(v, 2) + " " + AccountCurrency();
}

string ModusName(ENUM_MODUS m)
{
   switch(m)
   {
      case MANUELLE_FREIGABE: return "Manuelle Freigabe";
      case VOLLAUTOMATIK:     return "Vollautomatik";
      case NUR_SIGNALE:       return "Nur Signale";
   }
   return "?";
}

void FernSpeichern(string name, double wert)
{
   if(IsTesting())
      return;
   ResetLastError();
   if(GlobalVariableSet(FernSchluessel(name), wert) == 0)
      LogFehler("GlobalVariableSet " + name, GetLastError());
}

void FernLoeschen(string name)
{
   if(IsTesting())
      return;
   string k = FernSchluessel(name);
   if(GlobalVariableCheck(k))
      GlobalVariableDel(k);
}

bool FernLesen(string name, double &v)
{
   string k = FernSchluessel(name);
   if(!GlobalVariableCheck(k))
      return false;
   v = GlobalVariableGet(k);
   return true;
}

void ListeAnfuegen(string &liste, string eintrag)
{
   liste += ((liste == "") ? "" : ", ") + eintrag;
}

// Betriebsart wechseln (sofort wirksam) und merken. Vollautomatik wird nie gespeichert.
void ModusSetzen(ENUM_MODUS neu)
{
   g_modus = neu;
   if(neu != MANUELLE_FREIGABE && g_sig.aktiv)
      SignalVerwerfen("Moduswechsel", "⌛ verworfen (Moduswechsel)");
   if(neu == g_modusInput || neu == VOLLAUTOMATIK)
      FernLoeschen("modus");
   else
      FernSpeichern("modus", (double)neu);
   HinweisSetzen("Modus: " + ModusText() + " (Telegram)");
}

// Grund ohne wechselnde Zahlen, damit gleiche Gründe zusammengezählt werden
string GrundKurz(string grund)
{
   if(StringFind(grund, "Lot ") == 0)
      return "Lot unter MinLot (Risiko zu klein)";
   if(StringFind(grund, "MaxLot-Deckel") == 0)
      return "MaxLot unter MinLot";
   if(StringFind(grund, "Nicht genug freie Margin") == 0)
      return "Nicht genug freie Margin";
   int p = StringFind(grund, " (");
   if(p > 0)
      grund = StringSubstr(grund, 0, p);
   return grund;
}

// Ein erkanntes Signal wurde nicht gehandelt: zählen und Grund merken
void DiagVerworfen(string grund)
{
   g_dgVerworfen++;
   string k = GrundKurz(grund);
   for(int i = 0; i < g_dgGrundAnz; i++)
   {
      if(g_dgGrund[i] == k)
      {
         g_dgGrundN[i]++;
         return;
      }
   }
   if(g_dgGrundAnz < 20)
   {
      g_dgGrund[g_dgGrundAnz]  = k;
      g_dgGrundN[g_dgGrundAnz] = 1;
      g_dgGrundAnz++;
   }
}

void PositionenVerwalten()
{
   if(!g_beAktiv && !g_trailingAktiv)
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
         if(g_beAktiv && gewinn >= BeSchwelle(typ, offen, sl, atr))
         {
            double be = NormalizeDouble(offen + BE_PufferPunkte * Point, Digits);
            if(sl == 0.0 || be > sl + Point / 2.0)
               neu = be;
         }
         if(g_trailingAktiv && gewinn >= TrailingStartATR * atr)
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
         if(g_beAktiv && gewinn >= BeSchwelle(typ, offen, sl, atr))
         {
            double be = NormalizeDouble(offen - BE_PufferPunkte * Point, Digits);
            if(sl == 0.0 || be < sl - Point / 2.0)
               neu = be;
         }
         if(g_trailingAktiv && gewinn >= TrailingStartATR * atr)
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
            Print(EA_NAME + ": SL #", OrderTicket(), " nachgezogen auf ", DoubleToString(neu, Digits));
      }
   }
}

string ModusText()
{
   return ModusName(g_modus);
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

// Offene eigene Positionen (Symbol + Magic)
string TgPositionenText()
{
   string zeilen = "";
   int    n      = 0;
   double summe  = 0.0;
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber || OrderType() > OP_SELL)
         continue;
      double gw = OrderProfit() + OrderSwap() + OrderCommission();
      summe += gw;
      n++;
      if(n <= 25)
         zeilen += "#" + IntegerToString(OrderTicket()) + " " + (OrderType() == OP_BUY ? "BUY " : "SELL ")
                   + LotText(OrderLots()) + " @" + DoubleToString(OrderOpenPrice(), Digits)
                   + " SL " + (OrderStopLoss() > 0.0 ? DoubleToString(OrderStopLoss(), Digits) : "-")
                   + " TP " + (OrderTakeProfit() > 0.0 ? DoubleToString(OrderTakeProfit(), Digits) : "-")
                   + " | " + GeldText(gw) + "\n";
   }
   if(n == 0)
      return "Keine offenen Positionen (" + HtmlEscape(Symbol()) + ", Magic " + IntegerToString(MagicNumber) + ").";
   return "<b>Offene Positionen " + HtmlEscape(Symbol()) + "</b>\n" + zeilen + "Summe: " + GeldText(summe);
}

// Heute (Serverzeit-Tag) geschlossene Trades dieses EAs aus der Kontohistorie
string TgHeuteText()
{
   datetime tag0 = (datetime)((long)TimeCurrent() / 86400 * 86400);
   int    n = 0, gew = 0, verl = 0, tBest = 0, tSchlecht = 0;
   double summe = 0.0, best = 0.0, schlecht = 0.0;
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;
      if(OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol() || OrderType() > OP_SELL)
         continue;
      if(OrderCloseTime() < tag0)
         continue;
      double gw = OrderProfit() + OrderSwap() + OrderCommission();
      if(n == 0 || gw > best)
      {
         best  = gw;
         tBest = OrderTicket();
      }
      if(n == 0 || gw < schlecht)
      {
         schlecht   = gw;
         tSchlecht  = OrderTicket();
      }
      n++;
      summe += gw;
      if(gw > 0.0)
         gew++;
      else if(gw < 0.0)
         verl++;
   }
   if(n == 0)
      return "Heute noch keine geschlossenen Trades (" + HtmlEscape(Symbol()) + ", Magic " + IntegerToString(MagicNumber)
             + "). Hinweis: Die Kontohistorie muss im Terminal geladen sein.";
   return "<b>Heute geschlossen " + HtmlEscape(Symbol()) + "</b>\n"
        + IntegerToString(n) + " Trades: " + IntegerToString(gew) + " Gewinner, " + IntegerToString(verl) + " Verlierer\n"
        + "Summe: " + GeldText(summe) + "\n"
        + "Bester: #" + IntegerToString(tBest) + " " + GeldText(best) + "\n"
        + "Schlechtester: #" + IntegerToString(tSchlecht) + " " + GeldText(schlecht);
}

// Tastatur mit zwei Knöpfen für Bestätigungen
string TgTastaturCfg(string textJa, string dataJa, string textNein, string dataNein)
{
   return "{\"inline_keyboard\":[[{\"text\":\"" + JsonEscape(textJa) + "\",\"callback_data\":\"" + dataJa + "\"},"
          + "{\"text\":\"" + JsonEscape(textNein) + "\",\"callback_data\":\"" + dataNein + "\"}]]}";
}

// Offene Bestätigungs-Anfragen, deren 60 Sekunden um sind: Nachricht ändern, Knöpfe entfernen
void TgCfgAblaufPruefen()
{
   if(g_cfgAutoMsg > 0 && TimeLocal() > g_cfgAutoBis)
   {
      long m = g_cfgAutoMsg;
      g_cfgAutoMsg = 0;
      TgNachrichtBearbeiten(m, "⌛ Bestätigung abgelaufen (60 s) - Modus unverändert.");
   }
   if(g_cfgSchlMsg > 0 && TimeLocal() > g_cfgSchlBis)
   {
      long m = g_cfgSchlMsg;
      g_cfgSchlMsg = 0;
      TgNachrichtBearbeiten(m, "⌛ Bestätigung abgelaufen (60 s) - nichts geschlossen.");
   }
   if(g_cfgZuMsg > 0 && TimeLocal() > g_cfgZuBis)
   {
      long m = g_cfgZuMsg;
      g_cfgZuMsg = 0;
      TgNachrichtBearbeiten(m, "⌛ Bestätigung abgelaufen (60 s) - Position bleibt offen.");
   }
   if(g_cfgHandMsg > 0 && TimeLocal() > g_cfgHandBis)
   {
      long m = g_cfgHandMsg;
      g_cfgHandMsg = 0;
      TgNachrichtBearbeiten(m, "⌛ Bestätigung abgelaufen (30 s) - kein Trade eröffnet.");
   }
   if(g_cfgStartMsg > 0 && TimeLocal() > g_cfgStartBis)
   {
      long m = g_cfgStartMsg;
      g_cfgStartMsg = 0;
      TgNachrichtBearbeiten(m, "⌛ Bestätigung abgelaufen (60 s) - Sperre bleibt.");
   }
}

// Knopfdruck "cfg_..." (Bestätigung Vollautomatik / Alle schließen). msgId = Nachricht mit den Knöpfen.
void TgCfgCallback(string cbId, string data, long msgId)
{
   if(data == "cfg_auto_ja" || data == "cfg_auto_nein")
   {
      if(g_cfgAutoMsg <= 0 || msgId != g_cfgAutoMsg)
      {
         TgCallbackAntwort(cbId, "abgelaufen");
         if(msgId > 0)
            TgNachrichtBearbeiten(msgId, "⌛ Anfrage nicht mehr gültig.");
         return;
      }
      g_cfgAutoMsg = 0;
      if(TimeLocal() > g_cfgAutoBis)
      {
         TgCallbackAntwort(cbId, "abgelaufen");
         TgNachrichtBearbeiten(msgId, "⌛ Bestätigung abgelaufen (60 s) - Modus unverändert.");
         return;
      }
      if(data == "cfg_auto_ja")
      {
         ModusSetzen(VOLLAUTOMATIK);
         Print(EA_NAME + " Fern: Modus → Vollautomatik (per Telegram bestätigt)");
         TgCallbackAntwort(cbId, "Vollautomatik an");
         TgNachrichtBearbeiten(msgId, "✅ Vollautomatik eingeschaltet. Wechsel zurück: /modus manuell oder /modus signale. "
                                      + "Nach einem Neustart gilt wieder der Input-Modus.");
      }
      else
      {
         TgCallbackAntwort(cbId, "abgebrochen");
         TgNachrichtBearbeiten(msgId, "❌ Abgebrochen - Modus unverändert (" + ModusText() + ").");
      }
      UiAktualisieren();
      return;
   }

   if(data == "cfg_schl_ja" || data == "cfg_schl_nein")
   {
      if(g_cfgSchlMsg <= 0 || msgId != g_cfgSchlMsg)
      {
         TgCallbackAntwort(cbId, "abgelaufen");
         if(msgId > 0)
            TgNachrichtBearbeiten(msgId, "⌛ Anfrage nicht mehr gültig.");
         return;
      }
      g_cfgSchlMsg = 0;
      if(TimeLocal() > g_cfgSchlBis)
      {
         TgCallbackAntwort(cbId, "abgelaufen");
         TgNachrichtBearbeiten(msgId, "⌛ Bestätigung abgelaufen (60 s) - nichts geschlossen.");
         return;
      }
      if(data == "cfg_schl_ja")
      {
         TgCallbackAntwort(cbId, "schließe ...");
         Print(EA_NAME + " Fern: Alle schließen (per Telegram bestätigt)");
         int gz = 0, fe = 0;
         AlleSchliessen(gz, fe);
         TgNachrichtBearbeiten(msgId, "✅ Alle schließen ausgeführt: " + IntegerToString(gz) + " geschlossen, "
                                      + IntegerToString(fe) + " Fehler. Neue Trades sind gesperrt - mit /start wieder freigeben.");
      }
      else
      {
         TgCallbackAntwort(cbId, "abgebrochen");
         TgNachrichtBearbeiten(msgId, "❌ Abgebrochen - nichts geschlossen.");
      }
      UiAktualisieren();
      return;
   }
   if(StringFind(data, "cfg_zu_") == 0)
   {
      string rest = StringSubstr(data, 7);
      int    us   = StringFind(rest, "_");
      int    tk   = (us > 0) ? (int)StringToInteger(StringSubstr(rest, 0, us)) : 0;
      string ans  = (us > 0) ? StringSubstr(rest, us + 1) : "";
      if(g_cfgZuMsg <= 0 || msgId != g_cfgZuMsg || tk != g_cfgZuTicket || (ans != "ja" && ans != "nein"))
      {
         TgCallbackAntwort(cbId, "abgelaufen");
         if(msgId > 0)
            TgNachrichtBearbeiten(msgId, "⌛ Anfrage nicht mehr gültig.");
         return;
      }
      g_cfgZuMsg = 0;
      if(TimeLocal() > g_cfgZuBis)
      {
         TgCallbackAntwort(cbId, "abgelaufen");
         TgNachrichtBearbeiten(msgId, "⌛ Bestätigung abgelaufen (60 s) - Position bleibt offen.");
         return;
      }
      if(ans == "ja")
      {
         TgCallbackAntwort(cbId, "schließe ...");
         string fe = "";
         if(PositionSchliessen(tk, fe))
            TgNachrichtBearbeiten(msgId, "✅ Position #" + IntegerToString(tk) + " geschlossen.");
         else
            TgNachrichtBearbeiten(msgId, "⚠️ #" + IntegerToString(tk) + " nicht geschlossen: " + HtmlEscape(fe));
      }
      else
      {
         TgCallbackAntwort(cbId, "abgebrochen");
         TgNachrichtBearbeiten(msgId, "❌ Abgebrochen - Position #" + IntegerToString(tk) + " bleibt offen.");
      }
      UiAktualisieren();
      return;
   }

   if(data == "cfg_hand_ja" || data == "cfg_hand_nein")
   {
      if(g_cfgHandMsg <= 0 || msgId != g_cfgHandMsg)
      {
         TgCallbackAntwort(cbId, "abgelaufen");
         if(msgId > 0)
            TgNachrichtBearbeiten(msgId, "⌛ Anfrage nicht mehr gültig.");
         return;
      }
      g_cfgHandMsg = 0;
      if(TimeLocal() > g_cfgHandBis)
      {
         TgCallbackAntwort(cbId, "abgelaufen");
         TgNachrichtBearbeiten(msgId, "⌛ Bestätigung abgelaufen (30 s) - kein Trade eröffnet.");
         return;
      }
      if(data == "cfg_hand_ja")
      {
         TgCallbackAntwort(cbId, "sende Order ...");
         Print(EA_NAME + " Fern: Hand-Trade ", (g_cfgHandRicht > 0 ? "KAUF" : "VERKAUF"), " (per Telegram bestätigt)");
         TgNachrichtBearbeiten(msgId, TgHandAusfuehren());
      }
      else
      {
         TgCallbackAntwort(cbId, "abgebrochen");
         TgNachrichtBearbeiten(msgId, "❌ Abgebrochen - kein Trade eröffnet.");
      }
      UiAktualisieren();
      return;
   }

   if(data == "cfg_start_ja" || data == "cfg_start_nein")
   {
      if(g_cfgStartMsg <= 0 || msgId != g_cfgStartMsg)
      {
         TgCallbackAntwort(cbId, "abgelaufen");
         if(msgId > 0)
            TgNachrichtBearbeiten(msgId, "⌛ Anfrage nicht mehr gültig.");
         return;
      }
      g_cfgStartMsg = 0;
      if(TimeLocal() > g_cfgStartBis)
      {
         TgCallbackAntwort(cbId, "abgelaufen");
         TgNachrichtBearbeiten(msgId, "⌛ Bestätigung abgelaufen (60 s) - Sperre bleibt.");
         return;
      }
      if(data == "cfg_start_ja")
      {
         g_gestoppt = false;
         g_tgPause  = false;
         HinweisSetzen("Kill-Switch-Sperre per Telegram gelöst");
         Print(EA_NAME + " Fern: Kill-Switch-Sperre gelöst (per Telegram bestätigt)");
         TgCallbackAntwort(cbId, "Sperre gelöst");
         TgNachrichtBearbeiten(msgId, "✅ Kill-Switch-Sperre gelöst, neue Trades sind wieder erlaubt.");
      }
      else
      {
         TgCallbackAntwort(cbId, "abgebrochen");
         TgNachrichtBearbeiten(msgId, "❌ Abgebrochen - Sperre bleibt, bis /start bestätigt wird.");
      }
      UiAktualisieren();
      return;
   }
   TgCallbackAntwort(cbId, "unbekannt");
}

// Änderung melden: Journal + Telegram + Oberfläche
void TgGeaendert(string name, string alt, string neu)
{
   string z = name + ": " + alt + " → " + neu;
   Print(EA_NAME + " Fern: ", z, " (per Telegram)");
   TgNachrichtSenden("✅ " + HtmlEscape(z), "");
   UiAktualisieren();
}

// Zahl prüfen (Bereich mn..mx). Bei Fehler Meldung mit erlaubtem Bereich, Rückgabe false.
bool TgBereichOK(string cmd, string arg, double mn, double mx, int dez, string einheit, double &w)
{
   if(ZahlLesen(arg, w) && w >= mn - 1e-9 && w <= mx + 1e-9)
   {
      w = MathMax(mn, MathMin(mx, w));
      return true;
   }
   TgNachrichtSenden("⚠️ " + cmd + ": " + ((arg == "") ? "Wert fehlt" : "ungültiger Wert '" + HtmlEscape(arg) + "'")
                     + ". Erlaubt: " + DoubleToString(mn, dez) + " bis " + DoubleToString(mx, dez) + einheit + ".", "");
   return false;
}

// /modus manuell | signale | auto
void TgModusBefehl(string arg)
{
   if(arg == "manuell" || arg == "freigabe")
   {
      if(g_modus == MANUELLE_FREIGABE)
      {
         TgNachrichtSenden("Modus ist bereits: " + ModusText(), "");
         return;
      }
      string alt = ModusText();
      ModusSetzen(MANUELLE_FREIGABE);
      TgGeaendert("Modus", alt, ModusText());
   }
   else if(arg == "signale" || arg == "signal")
   {
      if(g_modus == NUR_SIGNALE)
      {
         TgNachrichtSenden("Modus ist bereits: " + ModusText(), "");
         return;
      }
      string alt = ModusText();
      ModusSetzen(NUR_SIGNALE);
      TgGeaendert("Modus", alt, ModusText());
   }
   else if(arg == "auto" || arg == "vollautomatik" || arg == "automatik")
   {
      if(g_modus == VOLLAUTOMATIK)
      {
         TgNachrichtSenden("Modus ist bereits: " + ModusText(), "");
         return;
      }
      if(g_cfgAutoMsg > 0)      // frühere offene Anfrage ersetzen
         TgNachrichtBearbeiten(g_cfgAutoMsg, "⌛ ersetzt durch neue Anfrage.");
      g_cfgAutoMsg = TgNachrichtSenden("⚠️ <b>Vollautomatik</b> einschalten?\nDer EA eröffnet dann Trades selbst, ohne Freigabe "
                                       + "(Risiko " + DoubleToString(g_risiko, 1) + " %, MaxLot " + LotText(g_maxLot)
                                       + ").\nBestätigung gilt 60 Sekunden.",
                                       TgTastaturCfg("✅ Vollautomatik einschalten", "cfg_auto_ja",
                                                     "❌ Abbrechen", "cfg_auto_nein"));
      g_cfgAutoBis = TimeLocal() + 60;
   }
   else
      TgNachrichtSenden("⚠️ /modus: manuell, signale oder auto erwartet. Aktuell: " + ModusText() + ".", "");
}

// /schliessen: erst Rückfrage per Knöpfe (die Ausführung kommt aus TgCfgCallback)
void TgSchliessenAnfrage()
{
   int n = ZaehlePositionen();
   if(n == 0)
   {
      TgNachrichtSenden("Keine offenen Positionen - nichts zu schließen.", "");
      return;
   }
   if(g_cfgSchlMsg > 0)
      TgNachrichtBearbeiten(g_cfgSchlMsg, "⌛ ersetzt durch neue Anfrage.");
   g_cfgSchlMsg = TgNachrichtSenden("⚠️ <b>Alle " + IntegerToString(n) + " Position(en)</b> auf " + HtmlEscape(Symbol())
                                    + " jetzt schließen? Aktuell " + GeldText(OffenerGewinn())
                                    + ".\nDanach sind neue Trades gesperrt - mit /start wieder freigeben.\n"
                                      + "Bestätigung gilt 60 Sekunden.",
                                    TgTastaturCfg("✅ Alle schließen", "cfg_schl_ja", "❌ Abbrechen", "cfg_schl_nein"));
   g_cfgSchlBis = TimeLocal() + 60;
}

// Ticket aus Text lesen (ganze positive Zahl)
bool TicketLesen(string s, int &ticket)
{
   double w = 0.0;
   if(!ZahlLesen(s, w) || w < 1.0 || w > 2147483000.0 || MathAbs(w - MathRound(w)) > 1e-9)
      return false;
   ticket = (int)MathRound(w);
   return true;
}

// Wählt das Ticket aus, wenn es eine offene Position dieses EAs ist (Symbol + Magic)
bool EigenePositionWaehlen(int ticket)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET))
      return false;
   return (OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber && OrderType() <= OP_SELL
           && OrderCloseTime() == 0);
}

// /zu <ticket>: Rückfrage mit Knöpfen (60 s)
void TgZuAnfrage(string arg)
{
   int ticket = 0;
   if(!TicketLesen(arg, ticket))
   {
      TgNachrichtSenden("⚠️ /zu: Ticketnummer erwartet, z. B. /zu 12345678 (siehe /positionen).", "");
      return;
   }
   if(!EigenePositionWaehlen(ticket))
   {
      TgNachrichtSenden("⚠️ /zu: #" + IntegerToString(ticket) + " ist keine offene Position dieses EAs (Symbol, Magic).", "");
      return;
   }
   double gw = OrderProfit() + OrderSwap() + OrderCommission();
   string txt = "#" + IntegerToString(ticket) + " " + (OrderType() == OP_BUY ? "BUY " : "SELL ") + LotText(OrderLots())
                + " @" + DoubleToString(OrderOpenPrice(), Digits) + " | " + GeldText(gw);
   if(g_cfgZuMsg > 0)
      TgNachrichtBearbeiten(g_cfgZuMsg, "⌛ ersetzt durch neue Anfrage.");
   g_cfgZuTicket = ticket;
   g_cfgZuMsg = TgNachrichtSenden("⚠️ Position schließen?\n" + HtmlEscape(txt) + "\nBestätigung gilt 60 Sekunden.",
                                  TgTastaturCfg("✅ Schließen", "cfg_zu_" + IntegerToString(ticket) + "_ja",
                                                "❌ Abbrechen", "cfg_zu_" + IntegerToString(ticket) + "_nein"));
   g_cfgZuBis = TimeLocal() + 60;
}

// /sl und /tp: <ticket> <preis>   bzw.   /sl <ticket> be
void TgSlTpBefehl(string cmd, string arg)
{
   bool istSL = (cmd == "/sl");
   int sp = StringFind(arg, " ");
   string a1 = arg, a2 = "";
   if(sp > 0)
   {
      a1 = StringSubstr(arg, 0, sp);
      a2 = StringSubstr(arg, sp + 1);
      StringTrimLeft(a2);
      StringTrimRight(a2);
   }
   int ticket = 0;
   if(!TicketLesen(a1, ticket) || a2 == "")
   {
      TgNachrichtSenden("⚠️ " + cmd + ": Format " + cmd + " &lt;ticket&gt; &lt;preis&gt;" + (istSL ? " oder /sl &lt;ticket&gt; be" : "")
                        + ". Tickets siehe /positionen.", "");
      return;
   }
   if(!EigenePositionWaehlen(ticket))
   {
      TgNachrichtSenden("⚠️ " + cmd + ": #" + IntegerToString(ticket) + " ist keine offene Position dieses EAs (Symbol, Magic).", "");
      return;
   }
   int    typ    = OrderType();
   double offen  = OrderOpenPrice();
   double slAlt  = OrderStopLoss();
   double tpAlt  = OrderTakeProfit();
   double preis  = 0.0;
   if(istSL && a2 == "be")
      preis = NormalizeDouble(offen + ((typ == OP_BUY) ? 1 : -1) * BE_PufferPunkte * Point, Digits);
   else if(ZahlLesen(a2, preis) && preis > 0.0)
      preis = NormalizeDouble(preis, Digits);
   else
   {
      TgNachrichtSenden("⚠️ " + cmd + ": ungültiger Preis '" + HtmlEscape(a2) + "'.", "");
      return;
   }

   // richtige Seite und Mindestabstand (StopLevel) zum aktuellen Kurs
   RefreshRates();
   double stopLvl = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   double grenze;
   bool   ok;
   string regel;
   if(typ == OP_BUY)
   {
      if(istSL) { grenze = NormalizeDouble(Bid - stopLvl, Digits); ok = (preis <= grenze); regel = "höchstens " + DoubleToString(grenze, Digits); }
      else      { grenze = NormalizeDouble(Bid + stopLvl, Digits); ok = (preis >= grenze); regel = "mindestens " + DoubleToString(grenze, Digits); }
   }
   else
   {
      if(istSL) { grenze = NormalizeDouble(Ask + stopLvl, Digits); ok = (preis >= grenze); regel = "mindestens " + DoubleToString(grenze, Digits); }
      else      { grenze = NormalizeDouble(Ask - stopLvl, Digits); ok = (preis <= grenze); regel = "höchstens " + DoubleToString(grenze, Digits); }
   }
   if(!ok)
   {
      TgNachrichtSenden("⚠️ " + cmd + " #" + IntegerToString(ticket) + ": " + DoubleToString(preis, Digits) + " nicht erlaubt. "
                        + (typ == OP_BUY ? "BUY" : "SELL") + "-" + (istSL ? "SL" : "TP") + " muss " + regel
                        + " liegen (Kurs " + DoubleToString(typ == OP_BUY ? Bid : Ask, Digits) + ", StopLevel "
                        + DoubleToString(stopLvl / Point, 0) + " Pkt)"
                        + ((istSL && a2 == "be") ? " - die Position ist noch nicht weit genug im Gewinn." : "."), "");
      return;
   }

   ResetLastError();
   double neuSL = istSL ? preis : slAlt;
   double neuTP = istSL ? tpAlt : preis;
   if(!OrderModify(ticket, offen, neuSL, neuTP, 0, clrDodgerBlue))
   {
      int err = GetLastError();
      LogFehler("OrderModify #" + IntegerToString(ticket), err);
      TgNachrichtSenden("⚠️ " + cmd + " #" + IntegerToString(ticket) + " fehlgeschlagen: " + HtmlEscape(FehlerText(err))
                        + " (" + IntegerToString(err) + ")", "");
      return;
   }
   double alt = istSL ? slAlt : tpAlt;
   TgGeaendert((istSL ? "SL" : "TP") + " #" + IntegerToString(ticket),
               (alt > 0.0) ? DoubleToString(alt, Digits) : "-", DoubleToString(preis, Digits));
}

// /be und /trailing: an | aus
void TgSchalter(string cmd, string arg)
{
   bool an;
   if(arg == "an" || arg == "ein" || arg == "on" || arg == "1")
      an = true;
   else if(arg == "aus" || arg == "off" || arg == "0")
      an = false;
   else
   {
      TgNachrichtSenden("⚠️ " + cmd + ": an oder aus erwartet. Aktuell: "
                        + ((cmd == "/be" ? g_beAktiv : g_trailingAktiv) ? "an" : "aus") + ".", "");
      return;
   }
   if(cmd == "/be")
   {
      string alt = g_beAktiv ? "an" : "aus";
      g_beAktiv = an;
      FernSpeichern("be", an ? 1.0 : 0.0);
      TgGeaendert("Break-even", alt, an ? "an" : "aus");
   }
   else
   {
      string alt = g_trailingAktiv ? "an" : "aus";
      g_trailingAktiv = an;
      FernSpeichern("trailing", an ? 1.0 : 0.0);
      TgGeaendert("Trailing", alt, an ? "an" : "aus");
   }
}

string BerichtZeitText(int m)
{
   return (m >= 0) ? MinutenText(m) + " Serverzeit" : "aus";
}

string TgBerichtText()
{
   string abw = FernAbweichungen();
   return "<b>Tagesbericht " + HtmlEscape(Symbol()) + " " + TimeToString(TimeCurrent(), TIME_DATE) + "</b>\n"
        + TgHeuteText() + "\n"
        + "Kontostand " + DoubleToString(AccountBalance(), 2) + ", Equity " + DoubleToString(AccountEquity(), 2) + " "
        + AccountCurrency() + "\n"
        + "Offene Positionen: " + IntegerToString(ZaehlePositionen()) + " (" + GeldText(OffenerGewinn()) + ")\n"
        + "Fern-Einstellungen: " + ((abw == "") ? "keine (Inputs aktiv)" : HtmlEscape(abw));
}

// /bericht ohne Argument = sofort senden; /bericht HH:MM setzt die Uhrzeit; /bericht aus schaltet ab
void TgBerichtBefehl(string arg)
{
   if(arg == "")
   {
      TgNachrichtSenden(TgBerichtText(), "");
      return;
   }
   int m = -1;
   if(arg != "aus" && arg != "off")
   {
      m = ZeitLesen(arg);
      if(m < 0)
      {
         TgNachrichtSenden("⚠️ /bericht: HH:MM (Serverzeit) oder aus erwartet. Ohne Angabe wird der Bericht sofort gesendet.", "");
         return;
      }
   }
   string alt = BerichtZeitText(g_berichtMin);
   g_berichtMin = m;
   FernSpeichern("bericht", (double)m);
   if(m >= 0)      // heute schon nach der neuen Uhrzeit: erst morgen
   {
      datetime t = TimeCurrent();
      if(TimeHour(t) * 60 + TimeMinute(t) >= m)
         g_berichtTag = (datetime)((long)t / 86400 * 86400);
      else
         g_berichtTag = 0;
   }
   TgGeaendert("Tagesbericht", alt, BerichtZeitText(g_berichtMin));
}

// In OnTimer: Tagesbericht einmal pro Serverzeit-Tag ab der eingestellten Uhrzeit senden
void TagesberichtPruefen()
{
   if(g_berichtMin < 0 || !TgBereit() || TimeLocal() < g_berichtRetry)
      return;
   datetime t     = TimeCurrent();
   datetime heute = (datetime)((long)t / 86400 * 86400);
   if(g_berichtTag == heute || TimeHour(t) * 60 + TimeMinute(t) < g_berichtMin)
      return;
   if(TgNachrichtSenden(TgBerichtText(), "") > 0)
   {
      g_berichtTag = heute;
      if(!IsTesting())
         GlobalVariableSet(FernSchluessel("berichttag"), (double)heute);
   }
   else
      g_berichtRetry = TimeLocal() + 60;
}

// /start bei gesetzter Kill-Switch-Sperre: Rückfrage per Knöpfe (60 s)
void TgStartAnfrage()
{
   if(g_cfgStartMsg > 0)
      TgNachrichtBearbeiten(g_cfgStartMsg, "⌛ ersetzt durch neue Anfrage.");
   g_cfgStartMsg = TgNachrichtSenden("▶️ Pause aufgehoben.\n⚠️ Der Kill-Switch hat neue Trades gesperrt. Sperre jetzt lösen?\n"
                                     + "Bestätigung gilt 60 Sekunden.",
                                     TgTastaturCfg("✅ Sperre lösen", "cfg_start_ja", "❌ Abbrechen", "cfg_start_nein"));
   g_cfgStartBis = TimeLocal() + 60;
}

// Textbefehle aus dem Chat (nur vom berechtigten Chat, Prüfung in TgUpdateBehandeln)
void TgBefehl(string text)
{
   string t = text;
   StringTrimLeft(t);
   StringTrimRight(t);
   if(StringGetCharacter(t, 0) != '/')
      return;
   string cmd = t;
   string arg = "";
   int sp = StringFind(t, " ");
   if(sp > 0)
   {
      cmd = StringSubstr(t, 0, sp);
      arg = StringSubstr(t, sp + 1);
   }
   StringToLower(cmd);
   StringToLower(arg);
   StringTrimLeft(arg);
   StringTrimRight(arg);
   int at = StringFind(cmd, "@");      // "/status@meinbot" aus Gruppen
   if(at > 0)
      cmd = StringSubstr(cmd, 0, at);

   if(cmd == "/hilfe" || cmd == "/help")
      TgNachrichtSenden(TgHilfeText(), "");
   else if(cmd == "/status")
      TgNachrichtSenden(TgStatusText(), "");
   else if(cmd == "/diag")
      TgNachrichtSenden(TgDiagText(), "");
   else if(cmd == "/stop")
   {
      g_tgPause = true;
      HinweisSetzen("Pausiert per Telegram");
      TgNachrichtSenden("⏸ Pausiert: neue Signale werden blockiert. /start hebt die Pause auf.", "");
   }
   else if(cmd == "/start")
   {
      g_tgPause = false;
      HinweisSetzen("Pause per Telegram aufgehoben");
      if(g_gestoppt)
         TgStartAnfrage();
      else
         TgNachrichtSenden("▶️ Pause aufgehoben: neue Signale sind wieder erlaubt. Befehle: /hilfe", "");
   }
   else if(cmd == "/modus")
      TgModusBefehl(arg);
   else if(cmd == "/positionen")
      TgNachrichtSenden(TgPositionenText(), "");
   else if(cmd == "/heute")
      TgNachrichtSenden(TgHeuteText(), "");
   else if(cmd == "/schliessen" || cmd == "/schließen")
      TgSchliessenAnfrage();
   else if(cmd == "/reset")
      TgReset();
   else if(cmd == "/zu")
      TgZuAnfrage(arg);
   else if(cmd == "/sl" || cmd == "/tp")
      TgSlTpBefehl(cmd, arg);
   else if(cmd == "/kauf")
      TgHandTradeAnfrage(1, arg);
   else if(cmd == "/verkauf")
      TgHandTradeAnfrage(-1, arg);
   else if(cmd == "/be" || cmd == "/trailing")
      TgSchalter(cmd, arg);
   else if(cmd == "/bericht")
      TgBerichtBefehl(arg);
   else if(!TgEinstellung(cmd, arg))
      TgNachrichtSenden("Unbekannter Befehl " + HtmlEscape(cmd) + ". Alle Befehle: /hilfe", "");
   UiAktualisieren();
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
         Print(EA_NAME + " Telegram: Knopfdruck aus fremdem Chat ignoriert.");
         return;
      }

      if(StringFind(data, "cfg_") == 0)      // Einstellungs-Rückfragen (Vollautomatik, Alle schließen)
      {
         long mid = 0;
         int  pmm = StringFind(seg, "\"message\":{", pc);
         if(pmm >= 0)
            JsonZahl(seg, "message_id", pmm, mid);
         TgCfgCallback(cbId, data, mid);
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
         Print(EA_NAME + " Telegram: Nachricht aus fremdem Chat ignoriert.");
         return;
      }
      string text = "";
      if(JsonText(seg, "text", pch, text))
         TgBefehl(text);
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
      Print(EA_NAME + " Telegram: Token oder Chat-ID fehlt - Telegram bleibt aus.");
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
   g_cfgAutoMsg = 0;
   g_cfgSchlMsg = 0;
   g_cfgZuMsg = 0;
   g_cfgHandMsg = 0;
   g_cfgStartMsg = 0;
   string gruss = EA_NAME + " auf <b>" + HtmlEscape(Symbol()) + "</b> gestartet (Modus " + ModusText() + ")\nBefehle: /hilfe";
   if(g_fernInfo != "")
      gruss += "\nFern-Einstellungen aktiv: " + HtmlEscape(g_fernInfo);
   TgNachrichtSenden(gruss, "");
}
