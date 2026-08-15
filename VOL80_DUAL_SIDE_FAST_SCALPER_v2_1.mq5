//+------------------------------------------------------------------+
//| VOL80 DUAL-SIDE FAST SCALPER v2.1                               |
//| PR #1 Adaptive SL+ 3 Zona                                        |
//| PR #2 Recovery tanpa langsung reverse                            |
//| PR #3 Momentum Re-entry / Add-on                                 |
//| Telegram Logger + P/L Calculator                                 |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

//==================================================================
// GENERAL
//==================================================================
input ulong   MagicNumber          = 808080;
input double  LotSize              = 0.01;
input bool    AllowBuy             = true;
input bool    AllowSell            = true;
input int     MaxPositions         = 3;
input int     SlippagePoints       = 100;

//==================================================================
// SCORE ENGINE
//==================================================================
input double MinimumScore          = 65.0;
input double MinimumScoreGap       = 12.0;

//==================================================================
// CANDLE
//==================================================================
input double MinimumBodyRatio      = 0.35;
input double StrongBodyRatio       = 0.60;

//==================================================================
// BREAKOUT
//==================================================================
input int     BreakoutLookback     = 5;
input double BreakoutBufferATR     = 0.05;

//==================================================================
// MOMENTUM
//==================================================================
input int     MomentumLookback     = 3;
input double MomentumATRMinimum    = 0.20;

//==================================================================
// VOLUME
//==================================================================
input bool    UseVolumeScore       = true;
input int     VolumeLookback       = 10;
input double VolumeBoost           = 1.10;

//==================================================================
// EMA MICRO FILTER
//==================================================================
input bool    UseEMA               = true;
input int     FastEMA              = 5;
input int     SlowEMA              = 13;

//==================================================================
// RSI OPTIONAL FILTER
//==================================================================
input bool    UseRSIFilter         = false;
input int     RSIPeriod            = 7;
input double BuyRSIMin             = 30.0;
input double SellRSIMax            = 70.0;

//==================================================================
// ATR
//==================================================================
input int     ATRPeriod            = 14;
input double SL_ATR_Multiplier     = 1.30;

//==================================================================
// PR #1 - ADAPTIVE SL+ 3 ZONA
// Zone 1 = BE lock, Zone 2 = profit lock, Zone 3 = active trailing
//==================================================================
input bool    UseAdaptiveSL3Zone   = true;

input double Zone1_ATR_Trigger     = 0.45;
input double Zone1_ATR_Lock        = 0.05;

input double Zone2_ATR_Trigger     = 0.90;
input double Zone2_ATR_Lock        = 0.35;

input double Zone3_ATR_Trigger     = 1.40;
input double Zone3_ATR_Distance     = 0.65;

input double TrailStep_ATR         = 0.08;

// Legacy-compatible toggles
input bool    UseBreakEven         = true;
input double BE_ATR_Trigger        = 0.45;
input double BE_ATR_Lock           = 0.08;
input bool    UseTrailing          = true;
input double Trail_ATR_Multiplier  = 0.80;

//==================================================================
// PR #2 - RECOVERY TANPA LANGSUNG REVERSE
//==================================================================
input bool    UseRecovery          = true;
input int     RecoveryDelaySec     = 20;
input double RecoveryMinScore      = 72.0;
input double RecoveryScoreGap      = 15.0;
input double RecoveryATRDistance   = 0.35;
input int     MaxRecoveryEntries   = 1;

//==================================================================
// PR #3 - MOMENTUM RE-ENTRY / ADD-ON
//==================================================================
input bool    UseMomentumAddon     = true;
input double AddonMinScore         = 72.0;
input double AddonScoreGap         = 12.0;
input double AddonATRDistance      = 0.60;
input int     MaxAddonEntries      = 2;
input int     AddonCooldownSec     = 15;

//==================================================================
// LAYER
//==================================================================
input bool    UseLayer             = true;
input int     MaxLayers            = 3;
input double LayerATRDistance      = 0.60;

//==================================================================
// SAFETY
//==================================================================
input int     MaxSpreadPoints      = 0;
input int     CooldownAfterLossSec = 0;

//==================================================================
// TELEGRAM LOGGER
//==================================================================
input bool    EnableTelegram       = false;
input string  TelegramBotToken     = "";
input string  TelegramChatID       = "";
input bool    TelegramEntryLog     = true;
input bool    TelegramExitLog      = true;
input bool    TelegramSignalLog    = true;
input bool    TelegramErrorLog     = true;
input bool    TelegramSummaryLog   = true;

//==================================================================
// GLOBAL
//==================================================================
int hATR      = INVALID_HANDLE;
int hFastEMA  = INVALID_HANDLE;
int hSlowEMA  = INVALID_HANDLE;
int hRSI      = INVALID_HANDLE;

datetime LastM1Bar       = 0;
datetime LastLossTime    = 0;
datetime LastAddonTime   = 0;
datetime LastRecoveryTime= 0;

int RecoveryEntriesToday = 0;
int AddonEntriesToday    = 0;

double SessionProfit     = 0.0;
double SessionLoss       = 0.0;
int    SessionWins       = 0;
int    SessionLosses     = 0;
int    SessionTrades     = 0;

//==================================================================
// URL ENCODER FOR TELEGRAM
//==================================================================
string UrlEncode(string text)
{
   uchar data[];
   StringToCharArray(text, data, 0, WHOLE_ARRAY, CP_UTF8);

   string out = "";

   for(int i = 0; i < ArraySize(data) - 1; i++)
   {
      uchar c = data[i];

      if((c >= '0' && c <= '9') ||
         (c >= 'A' && c <= 'Z') ||
         (c >= 'a' && c <= 'z') ||
         c == '-' || c == '_' || c == '.' || c == '~')
      {
         out += CharToString(c);
      }
      else if(c == ' ')
      {
         out += "%20";
      }
      else
      {
         out += StringFormat("%%%02X", c);
      }
   }

   return out;
}

//==================================================================
// TELEGRAM
//==================================================================
bool SendTelegram(string message)
{
   if(!EnableTelegram)
      return true;

   if(TelegramBotToken == "" || TelegramChatID == "")
      return false;

   string url =
      "https://api.telegram.org/bot" +
      TelegramBotToken +
      "/sendMessage?chat_id=" +
      UrlEncode(TelegramChatID) +
      "&text=" +
      UrlEncode(message);

   char post[];
   char result[];
   string headers;

   ResetLastError();

   int timeout = 5000;

   int code = WebRequest(
      "GET",
      url,
      "",
      "",
      timeout,
      post,
      0,
      result,
      headers
   );

   if(code == -1)
   {
      if(TelegramErrorLog)
         Print("TELEGRAM ERROR | WebRequest=", GetLastError(),
               " | Tambahkan https://api.telegram.org ke WebRequest Allow List.");

      return false;
   }

   if(code < 200 || code >= 300)
   {
      if(TelegramErrorLog)
         Print("TELEGRAM HTTP ERROR = ", code);

      return false;
   }

   return true;
}

void TelegramSignal(string msg)
{
   if(TelegramSignalLog)
      SendTelegram(msg);
}

//==================================================================
// INIT
//==================================================================
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);

   hATR = iATR(_Symbol, PERIOD_M1, ATRPeriod);

   hFastEMA = iMA(
      _Symbol, PERIOD_M1, FastEMA, 0, MODE_EMA, PRICE_CLOSE
   );

   hSlowEMA = iMA(
      _Symbol, PERIOD_M1, SlowEMA, 0, MODE_EMA, PRICE_CLOSE
   );

   hRSI = iRSI(
      _Symbol, PERIOD_M1, RSIPeriod, PRICE_CLOSE
   );

   if(hATR == INVALID_HANDLE ||
      hFastEMA == INVALID_HANDLE ||
      hSlowEMA == INVALID_HANDLE ||
      hRSI == INVALID_HANDLE)
   {
      Print("ERROR: Indicator handle gagal dibuat.");
      return INIT_FAILED;
   }

   Print("================================================");
   Print("VOL80 DUAL-SIDE FAST SCALPER v2.1");
   Print("PR#1 Adaptive SL+ 3 Zona");
   Print("PR#2 Recovery tanpa langsung reverse");
   Print("PR#3 Momentum Re-entry / Add-on");
   Print("Telegram Logger + P/L Calculator");
   Print("================================================");

   if(EnableTelegram)
      SendTelegram(
         "VOL80 v2.1 ONLINE\n" +
         _Symbol +
         " M1\nMagic: " +
         (string)MagicNumber
      );

   return INIT_SUCCEEDED;
}

//==================================================================
// DEINIT
//==================================================================
void OnDeinit(const int reason)
{
   if(hATR != INVALID_HANDLE)
      IndicatorRelease(hATR);

   if(hFastEMA != INVALID_HANDLE)
      IndicatorRelease(hFastEMA);

   if(hSlowEMA != INVALID_HANDLE)
      IndicatorRelease(hSlowEMA);

   if(hRSI != INVALID_HANDLE)
      IndicatorRelease(hRSI);
}

//==================================================================
// BUFFER
//==================================================================
double BufferValue(int handle, int shift)
{
   double buffer[];
   ArraySetAsSeries(buffer, true);

   if(CopyBuffer(handle, 0, shift, 1, buffer) <= 0)
      return EMPTY_VALUE;

   return buffer[0];
}

//==================================================================
// ATR
//==================================================================
double GetATR()
{
   double atr = BufferValue(hATR, 1);

   if(atr == EMPTY_VALUE || atr <= 0)
      return 0.0;

   return atr;
}

//==================================================================
// RSI
//==================================================================
double GetRSI()
{
   double rsi = BufferValue(hRSI, 1);

   if(rsi == EMPTY_VALUE)
      return -1.0;

   return rsi;
}

//==================================================================
// NEW M1 BAR
//==================================================================
bool IsNewM1Bar()
{
   datetime barTime = iTime(_Symbol, PERIOD_M1, 0);

   if(barTime <= 0)
      return false;

   if(barTime != LastM1Bar)
   {
      LastM1Bar = barTime;
      return true;
   }

   return false;
}

//==================================================================
// SPREAD
//==================================================================
bool SpreadOK()
{
   if(MaxSpreadPoints <= 0)
      return true;

   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return false;

   double spread = (tick.ask - tick.bid) / _Point;

   return spread <= MaxSpreadPoints;
}

//==================================================================
// POSITION COUNT
//==================================================================
int CountPositions(int direction = 0)
{
   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber)
         continue;

      long type = PositionGetInteger(POSITION_TYPE);

      if(direction == 1 && type != POSITION_TYPE_BUY)
         continue;

      if(direction == -1 && type != POSITION_TYPE_SELL)
         continue;

      count++;
   }

   return count;
}

//==================================================================
// COUNT CLOSED DEALS TODAY
//==================================================================
void RefreshDailyCounters()
{
   datetime dayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));

   if(!HistorySelect(dayStart, TimeCurrent()))
      return;

   RecoveryEntriesToday = 0;
   AddonEntriesToday = 0;
   SessionProfit = 0.0;
   SessionLoss = 0.0;
   SessionWins = 0;
   SessionLosses = 0;
   SessionTrades = 0;

   int total = HistoryDealsTotal();

   for(int i = 0; i < total; i++)
   {
      ulong deal = HistoryDealGetTicket(i);

      if(deal == 0)
         continue;

      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol)
         continue;

      if(HistoryDealGetInteger(deal, DEAL_MAGIC) != (long)MagicNumber)
         continue;

      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      string comment = HistoryDealGetString(deal, DEAL_COMMENT);

      if(entry == DEAL_ENTRY_IN)
      {
         if(StringFind(comment, "RECOVERY") >= 0)
            RecoveryEntriesToday++;

         if(StringFind(comment, "ADDON") >= 0)
            AddonEntriesToday++;
      }

      if(entry == DEAL_ENTRY_OUT)
      {
         double p = HistoryDealGetDouble(deal, DEAL_PROFIT) +
                    HistoryDealGetDouble(deal, DEAL_SWAP) +
                    HistoryDealGetDouble(deal, DEAL_COMMISSION);

         SessionTrades++;

         if(p >= 0.0)
         {
            SessionProfit += p;
            SessionWins++;
         }
         else
         {
            SessionLoss += MathAbs(p);
            SessionLosses++;
         }
      }
   }
}

//==================================================================
// LAST POSITION PRICE
//==================================================================
double LastPositionPrice(int direction)
{
   double price = 0.0;
   datetime latest = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber)
         continue;

      long type = PositionGetInteger(POSITION_TYPE);

      if(direction == 1 && type != POSITION_TYPE_BUY)
         continue;

      if(direction == -1 && type != POSITION_TYPE_SELL)
         continue;

      datetime openTime =
         (datetime)PositionGetInteger(POSITION_TIME);

      if(openTime >= latest)
      {
         latest = openTime;
         price = PositionGetDouble(POSITION_PRICE_OPEN);
      }
   }

   return price;
}

//==================================================================
// LAST POSITION TICKET
//==================================================================
ulong LastPositionTicket(int direction)
{
   ulong result = 0;
   datetime latest = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber)
         continue;

      long type = PositionGetInteger(POSITION_TYPE);

      if(direction == 1 && type != POSITION_TYPE_BUY)
         continue;

      if(direction == -1 && type != POSITION_TYPE_SELL)
         continue;

      datetime openTime =
         (datetime)PositionGetInteger(POSITION_TIME);

      if(openTime >= latest)
      {
         latest = openTime;
         result = ticket;
      }
   }

   return result;
}

//==================================================================
// CANDLE HELPERS
//==================================================================
double GetBodyRatio(MqlRates &candle)
{
   double range = candle.high - candle.low;

   if(range <= 0)
      return 0.0;

   double body = MathAbs(candle.close - candle.open);

   return body / range;
}

int CandleDirection(MqlRates &candle)
{
   if(candle.close > candle.open)
      return 1;

   if(candle.close < candle.open)
      return -1;

   return 0;
}

//==================================================================
// BREAKOUT
//==================================================================
double PreviousHighest(MqlRates &rates[], int lookback)
{
   double highest = -DBL_MAX;

   for(int i = 2; i < lookback + 2; i++)
      if(rates[i].high > highest)
         highest = rates[i].high;

   return highest;
}

double PreviousLowest(MqlRates &rates[], int lookback)
{
   double lowest = DBL_MAX;

   for(int i = 2; i < lookback + 2; i++)
      if(rates[i].low < lowest)
         lowest = rates[i].low;

   return lowest;
}

//==================================================================
// VOLUME
//==================================================================
double GetVolumeRatio(MqlRates &rates[])
{
   double average = 0.0;

   for(int i = 2; i < VolumeLookback + 2; i++)
      average += (double)rates[i].tick_volume;

   average /= VolumeLookback;

   if(average <= 0)
      return 0.0;

   return (double)rates[1].tick_volume / average;
}

//==================================================================
// EMA
//==================================================================
int EMADirection()
{
   if(!UseEMA)
      return 0;

   double fast = BufferValue(hFastEMA, 1);
   double slow = BufferValue(hSlowEMA, 1);

   if(fast == EMPTY_VALUE || slow == EMPTY_VALUE)
      return 0;

   if(fast > slow)
      return 1;

   if(fast < slow)
      return -1;

   return 0;
}

//==================================================================
// MOMENTUM
//==================================================================
int MomentumDirection(MqlRates &rates[], double atr)
{
   if(atr <= 0)
      return 0;

   double move =
      rates[1].close -
      rates[MomentumLookback + 1].close;

   if(move >= atr * MomentumATRMinimum)
      return 1;

   if(move <= -atr * MomentumATRMinimum)
      return -1;

   return 0;
}

//==================================================================
// SCORE ENGINE
//==================================================================
double CalculateBuyScore(MqlRates &rates[], double atr)
{
   double score = 0.0;

   int direction = CandleDirection(rates[1]);
   double bodyRatio = GetBodyRatio(rates[1]);

   if(direction == 1)
      score += 20.0;

   if(bodyRatio >= MinimumBodyRatio)
      score += 15.0;

   if(bodyRatio >= StrongBodyRatio)
      score += 10.0;

   double previousHigh = PreviousHighest(rates, BreakoutLookback);

   if(rates[1].close > previousHigh + atr * BreakoutBufferATR)
      score += 25.0;

   if(MomentumDirection(rates, atr) == 1)
      score += 15.0;

   if(UseVolumeScore)
   {
      double volumeRatio = GetVolumeRatio(rates);

      if(volumeRatio >= VolumeBoost)
         score += 10.0;
   }

   if(UseEMA && EMADirection() == 1)
      score += 15.0;

   if(UseRSIFilter)
   {
      double rsi = GetRSI();

      if(rsi >= BuyRSIMin)
         score += 5.0;
      else
         score -= 10.0;
   }

   return MathMax(0.0, MathMin(score, 100.0));
}

double CalculateSellScore(MqlRates &rates[], double atr)
{
   double score = 0.0;

   int direction = CandleDirection(rates[1]);
   double bodyRatio = GetBodyRatio(rates[1]);

   if(direction == -1)
      score += 20.0;

   if(bodyRatio >= MinimumBodyRatio)
      score += 15.0;

   if(bodyRatio >= StrongBodyRatio)
      score += 10.0;

   double previousLow = PreviousLowest(rates, BreakoutLookback);

   if(rates[1].close < previousLow - atr * BreakoutBufferATR)
      score += 25.0;

   if(MomentumDirection(rates, atr) == -1)
      score += 15.0;

   if(UseVolumeScore)
   {
      double volumeRatio = GetVolumeRatio(rates);

      if(volumeRatio >= VolumeBoost)
         score += 10.0;
   }

   if(UseEMA && EMADirection() == -1)
      score += 15.0;

   if(UseRSIFilter)
   {
      double rsi = GetRSI();

      if(rsi <= SellRSIMax)
         score += 5.0;
      else
         score -= 10.0;
   }

   return MathMax(0.0, MathMin(score, 100.0));
}

//==================================================================
// LAYER DISTANCE
//==================================================================
bool LayerDistanceOK(int direction, double atr)
{
   if(!UseLayer)
      return true;

   int count = CountPositions(direction);

   if(count <= 0)
      return true;

   if(count >= MaxLayers)
      return false;

   double lastPrice = LastPositionPrice(direction);

   if(lastPrice <= 0)
      return false;

   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return false;

   double currentPrice =
      (direction == 1) ? tick.ask : tick.bid;

   double distance = MathAbs(currentPrice - lastPrice);

   if(distance < atr * LayerATRDistance)
      return false;

   if(direction == 1 && currentPrice <= lastPrice)
      return false;

   if(direction == -1 && currentPrice >= lastPrice)
      return false;

   return true;
}

//==================================================================
// COOLDOWN
//==================================================================
bool CooldownOK()
{
   if(CooldownAfterLossSec <= 0)
      return true;

   if(LastLossTime <= 0)
      return true;

   return (TimeCurrent() - LastLossTime >= CooldownAfterLossSec);
}

//==================================================================
// OPEN BUY
//==================================================================
bool OpenBuy(string tag = "VOL80 DUAL BUY")
{
   if(!AllowBuy || !SpreadOK() || !CooldownOK())
      return false;

   if(CountPositions() >= MaxPositions)
      return false;

   double atr = GetATR();

   if(atr <= 0)
      return false;

   if(tag == "VOL80 DUAL BUY" && !LayerDistanceOK(1, atr))
      return false;

   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return false;

   double sl = NormalizeDouble(
      tick.ask - atr * SL_ATR_Multiplier,
      _Digits
   );

   bool result = trade.Buy(
      LotSize, _Symbol, 0.0, sl, 0.0, tag
   );

   if(!result)
   {
      Print("BUY FAILED: ", trade.ResultRetcodeDescription());
      return false;
   }

   Print("BUY OPENED | ", tag,
         " | Price=", DoubleToString(tick.ask, _Digits),
         " | SL=", DoubleToString(sl, _Digits));

   return true;
}

//==================================================================
// OPEN SELL
//==================================================================
bool OpenSell(string tag = "VOL80 DUAL SELL")
{
   if(!AllowSell || !SpreadOK() || !CooldownOK())
      return false;

   if(CountPositions() >= MaxPositions)
      return false;

   double atr = GetATR();

   if(atr <= 0)
      return false;

   if(tag == "VOL80 DUAL SELL" && !LayerDistanceOK(-1, atr))
      return false;

   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return false;

   double sl = NormalizeDouble(
      tick.bid + atr * SL_ATR_Multiplier,
      _Digits
   );

   bool result = trade.Sell(
      LotSize, _Symbol, 0.0, sl, 0.0, tag
   );

   if(!result)
   {
      Print("SELL FAILED: ", trade.ResultRetcodeDescription());
      return false;
   }

   Print("SELL OPENED | ", tag,
         " | Price=", DoubleToString(tick.bid, _Digits),
         " | SL=", DoubleToString(sl, _Digits));

   return true;
}

//==================================================================
// SIGNAL DATA
//==================================================================
bool LoadSignal(double &buyScore,
                double &sellScore,
                double &atr,
                MqlRates &rates[])
{
   ArraySetAsSeries(rates, true);

   int requiredBars =
      MathMax(
         MathMax(BreakoutLookback + 5, VolumeLookback + 5),
         MomentumLookback + 5
      );

   if(CopyRates(
      _Symbol, PERIOD_M1, 0, requiredBars, rates
   ) < requiredBars)
   {
      Print("Not enough M1 history.");
      return false;
   }

   atr = GetATR();

   if(atr <= 0)
      return false;

   buyScore = CalculateBuyScore(rates, atr);
   sellScore = CalculateSellScore(rates, atr);

   return true;
}

//==================================================================
// PR #2 - RECOVERY WITHOUT DIRECT REVERSE
// A recovery entry is only allowed after a delay and when the new
// momentum signal is strong. It never opens opposite side instantly.
//==================================================================
bool RecoverySignalReady(int &direction,
                         double &score,
                         double &gap)
{
   direction = 0;
   score = 0.0;
   gap = 0.0;

   if(!UseRecovery)
      return false;

   if(RecoveryEntriesToday >= MaxRecoveryEntries)
      return false;

   if(LastLossTime <= 0)
      return false;

   if(TimeCurrent() - LastLossTime < RecoveryDelaySec)
      return false;

   MqlRates rates[];
   double atr = 0.0;
   double buyScore = 0.0;
   double sellScore = 0.0;

   if(!LoadSignal(buyScore, sellScore, atr, rates))
      return false;

   gap = MathAbs(buyScore - sellScore);

   if(gap < RecoveryScoreGap)
      return false;

   if(buyScore >= RecoveryMinScore && buyScore > sellScore)
   {
      direction = 1;
      score = buyScore;
      return true;
   }

   if(sellScore >= RecoveryMinScore && sellScore > buyScore)
   {
      direction = -1;
      score = sellScore;
      return true;
   }

   return false;
}

//==================================================================
// PR #3 - MOMENTUM ADDON / RE-ENTRY
// Only adds in the same direction as the current strong momentum.
//==================================================================
bool MomentumAddonReady(int &direction,
                        double &score,
                        double &gap)
{
   direction = 0;
   score = 0.0;
   gap = 0.0;

   if(!UseMomentumAddon)
      return false;

   if(AddonEntriesToday >= MaxAddonEntries)
      return false;

   if(TimeCurrent() - LastAddonTime < AddonCooldownSec)
      return false;

   if(CountPositions() <= 0)
      return false;

   MqlRates rates[];
   double atr = 0.0;
   double buyScore = 0.0;
   double sellScore = 0.0;

   if(!LoadSignal(buyScore, sellScore, atr, rates))
      return false;

   gap = MathAbs(buyScore - sellScore);

   if(gap < AddonScoreGap)
      return false;

   if(buyScore >= AddonMinScore && buyScore > sellScore)
      direction = 1;
   else if(sellScore >= AddonMinScore && sellScore > buyScore)
      direction = -1;
   else
      return false;

   // Do not add against the existing basket.
   if(direction == 1 && CountPositions(1) <= 0)
      return false;

   if(direction == -1 && CountPositions(-1) <= 0)
      return false;

   return true;
}

//==================================================================
// MAIN SIGNAL
//==================================================================
void ProcessSignal()
{
   if(!SpreadOK() || !CooldownOK())
      return;

   MqlRates rates[];
   double atr = 0.0;
   double buyScore = 0.0;
   double sellScore = 0.0;

   if(!LoadSignal(buyScore, sellScore, atr, rates))
      return;

   double gap = MathAbs(buyScore - sellScore);

   Print(
      "VOL80 SIGNAL | BUY=", DoubleToString(buyScore, 1),
      " | SELL=", DoubleToString(sellScore, 1),
      " | GAP=", DoubleToString(gap, 1),
      " | RSI=", DoubleToString(GetRSI(), 1)
   );

   TelegramSignal(
      "VOL80 SIGNAL\n" +
      _Symbol + " M1\n" +
      "BUY: " + DoubleToString(buyScore, 1) +
      "\nSELL: " + DoubleToString(sellScore, 1) +
      "\nGAP: " + DoubleToString(gap, 1)
   );

   if(gap < MinimumScoreGap)
      return;

   // Normal entry only when there is no active basket.
   if(CountPositions() == 0)
   {
      if(buyScore >= MinimumScore && buyScore > sellScore)
      {
         OpenBuy("VOL80 DUAL BUY");
         return;
      }

      if(sellScore >= MinimumScore && sellScore > buyScore)
      {
         OpenSell("VOL80 DUAL SELL");
         return;
      }

      return;
   }

   // PR #3: add-on/re-entry in the SAME direction.
   int addonDirection = 0;
   double addonScore = 0.0;
   double addonGap = 0.0;

   if(MomentumAddonReady(
      addonDirection,
      addonScore,
      addonGap
   ))
   {
      bool opened = false;

      if(addonDirection == 1)
      {
         double addonATR = GetATR();

         if(LayerDistanceOK(1, addonATR))
            opened = OpenBuy("VOL80 MOMENTUM ADDON");
      }
      else if(addonDirection == -1)
      {
         double addonATR = GetATR();

         if(LayerDistanceOK(-1, addonATR))
            opened = OpenSell("VOL80 MOMENTUM ADDON");
      }

      if(opened)
      {
         LastAddonTime = TimeCurrent();
         AddonEntriesToday++;
      }
   }
}

//==================================================================
// PR #1 - ADAPTIVE SL+ 3 ZONA
// SL moves only in the profitable direction.
//==================================================================
void ManagePositions()
{
   double atr = GetATR();

   if(atr <= 0)
      return;

   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return;

   double trailStep = atr * TrailStep_ATR;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber)
         continue;

      long type = PositionGetInteger(POSITION_TYPE);

      double openPrice =
         PositionGetDouble(POSITION_PRICE_OPEN);

      double currentSL =
         PositionGetDouble(POSITION_SL);

      double currentTP =
         PositionGetDouble(POSITION_TP);

      double newSL = currentSL;

      //============================================================
      // BUY
      //============================================================
      if(type == POSITION_TYPE_BUY)
      {
         double profitDistance = tick.bid - openPrice;

         if(profitDistance <= 0)
            continue;

         if(UseAdaptiveSL3Zone)
         {
            // Zone 1
            if(profitDistance >= atr * Zone1_ATR_Trigger)
            {
               double sl1 =
                  openPrice + atr * Zone1_ATR_Lock;

               if(currentSL == 0 || sl1 > newSL)
                  newSL = sl1;
            }

            // Zone 2
            if(profitDistance >= atr * Zone2_ATR_Trigger)
            {
               double sl2 =
                  openPrice + atr * Zone2_ATR_Lock;

               if(currentSL == 0 || sl2 > newSL)
                  newSL = sl2;
            }

            // Zone 3 - trail follows price continuously by ATR
            if(profitDistance >= atr * Zone3_ATR_Trigger)
            {
               double sl3 =
                  tick.bid - atr * Zone3_ATR_Distance;

               if(currentSL == 0 || sl3 > newSL)
                  newSL = sl3;
            }
         }
         else
         {
            // Legacy BE + trailing
            if(UseBreakEven &&
               profitDistance >= atr * BE_ATR_Trigger)
            {
               double be =
                  openPrice + atr * BE_ATR_Lock;

               if(currentSL == 0 || be > newSL)
                  newSL = be;
            }

            if(UseTrailing &&
               profitDistance >= atr * BE_ATR_Trigger)
            {
               double trail =
                  tick.bid - atr * Trail_ATR_Multiplier;

               if(currentSL == 0 || trail > newSL)
                  newSL = trail;
            }
         }

         newSL = NormalizeDouble(newSL, _Digits);

         if(currentSL > 0 &&
            newSL <= currentSL + trailStep)
            continue;

         if(newSL <= 0 || newSL >= tick.bid)
            continue;

         if(!trade.PositionModify(
            ticket, newSL, currentTP
         ))
         {
            Print(
               "BUY SL+ FAILED | Ticket=", ticket,
               " | ", trade.ResultRetcodeDescription()
            );
         }
      }

      //============================================================
      // SELL
      //============================================================
      if(type == POSITION_TYPE_SELL)
      {
         double profitDistance = openPrice - tick.ask;

         if(profitDistance <= 0)
            continue;

         if(UseAdaptiveSL3Zone)
         {
            // Zone 1
            if(profitDistance >= atr * Zone1_ATR_Trigger)
            {
               double sl1 =
                  openPrice - atr * Zone1_ATR_Lock;

               if(currentSL == 0 || sl1 < newSL)
                  newSL = sl1;
            }

            // Zone 2
            if(profitDistance >= atr * Zone2_ATR_Trigger)
            {
               double sl2 =
                  openPrice - atr * Zone2_ATR_Lock;

               if(currentSL == 0 || sl2 < newSL)
                  newSL = sl2;
            }

            // Zone 3
            if(profitDistance >= atr * Zone3_ATR_Trigger)
            {
               double sl3 =
                  tick.ask + atr * Zone3_ATR_Distance;

               if(currentSL == 0 || sl3 < newSL)
                  newSL = sl3;
            }
         }
         else
         {
            if(UseBreakEven &&
               profitDistance >= atr * BE_ATR_Trigger)
            {
               double be =
                  openPrice - atr * BE_ATR_Lock;

               if(currentSL == 0 || be < newSL)
                  newSL = be;
            }

            if(UseTrailing &&
               profitDistance >= atr * BE_ATR_Trigger)
            {
               double trail =
                  tick.ask + atr * Trail_ATR_Multiplier;

               if(currentSL == 0 || trail < newSL)
                  newSL = trail;
            }
         }

         newSL = NormalizeDouble(newSL, _Digits);

         if(currentSL > 0 &&
            newSL >= currentSL - trailStep)
            continue;

         if(newSL <= tick.ask || newSL <= 0)
            continue;

         if(!trade.PositionModify(
            ticket, newSL, currentTP
         ))
         {
            Print(
               "SELL SL+ FAILED | Ticket=", ticket,
               " | ", trade.ResultRetcodeDescription()
            );
         }
      }
   }
}

//==================================================================
// TRADE TRANSACTION + P/L CALCULATOR
//==================================================================
void OnTradeTransaction(
   const MqlTradeTransaction &trans,
   const MqlTradeRequest &request,
   const MqlTradeResult &result
)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   ulong deal = trans.deal;

   if(deal == 0 || !HistoryDealSelect(deal))
      return;

   if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol)
      return;

   if(HistoryDealGetInteger(deal, DEAL_MAGIC) != (long)MagicNumber)
      return;

   long entryType =
      HistoryDealGetInteger(deal, DEAL_ENTRY);

   double profit =
      HistoryDealGetDouble(deal, DEAL_PROFIT);

   double swap =
      HistoryDealGetDouble(deal, DEAL_SWAP);

   double commission =
      HistoryDealGetDouble(deal, DEAL_COMMISSION);

   double net = profit + swap + commission;

   double price =
      HistoryDealGetDouble(deal, DEAL_PRICE);

   string comment =
      HistoryDealGetString(deal, DEAL_COMMENT);

   if(entryType == DEAL_ENTRY_IN)
   {
      long dealType =
         HistoryDealGetInteger(deal, DEAL_TYPE);

      string side =
         (dealType == DEAL_TYPE_BUY) ? "BUY" : "SELL";

      Print(
         "========== VOL80 ENTRY ==========\n",
         "SIDE=", side,
         " | PRICE=", DoubleToString(price, _Digits),
         " | LOT=", DoubleToString(
            HistoryDealGetDouble(deal, DEAL_VOLUME), 2
         ),
         " | TAG=", comment
      );

      if(TelegramEntryLog)
      {
         SendTelegram(
            "VOL80 ENTRY\n" +
            _Symbol +
            "\nSide: " + side +
            "\nPrice: " + DoubleToString(price, _Digits) +
            "\nLot: " + DoubleToString(
               HistoryDealGetDouble(deal, DEAL_VOLUME), 2
            ) +
            "\nTag: " + comment
         );
      }

      return;
   }

   if(entryType == DEAL_ENTRY_OUT)
   {
      SessionTrades++;

      if(net >= 0.0)
      {
         SessionProfit += net;
         SessionWins++;
      }
      else
      {
         SessionLoss += MathAbs(net);
         SessionLosses++;
         LastLossTime = TimeCurrent();
      }

      double netToday =
         SessionProfit - SessionLoss;

      double winRate = 0.0;

      if(SessionTrades > 0)
         winRate =
            100.0 * SessionWins / SessionTrades;

      string resultText =
         (net > 0.0) ? "PROFIT" :
         (net < 0.0) ? "LOSS" : "BREAK EVEN";

      Print(
         "========== VOL80 CLOSED ==========\n",
         "RESULT=", resultText,
         " | Net=", DoubleToString(net, 2),
         " | Today Net=", DoubleToString(netToday, 2),
         " | Profit=", DoubleToString(SessionProfit, 2),
         " | Loss=", DoubleToString(SessionLoss, 2),
         " | Wins=", SessionWins,
         " | Losses=", SessionLosses,
         " | WR=", DoubleToString(winRate, 1), "%"
      );

      if(TelegramExitLog)
      {
         SendTelegram(
            "VOL80 CLOSED\n" +
            _Symbol +
            "\nResult: " + resultText +
            "\nNet: " + DoubleToString(net, 2) +
            "\nToday Net: " + DoubleToString(netToday, 2) +
            "\nProfit: " + DoubleToString(SessionProfit, 2) +
            "\nLoss: " + DoubleToString(SessionLoss, 2) +
            "\nWins/Losses: " +
            (string)SessionWins + "/" +
            (string)SessionLosses +
            "\nWR: " + DoubleToString(winRate, 1) + "%"
         );
      }
   }
}

//==================================================================
// MAIN
//==================================================================
void OnTick()
{
   // SL+ berjalan setiap tick.
   ManagePositions();

   if(!IsNewM1Bar())
      return;

   RefreshDailyCounters();

   // Recovery hanya setelah loss dan delay.
   int recoveryDirection = 0;
   double recoveryScore = 0.0;
   double recoveryGap = 0.0;

   if(RecoverySignalReady(
      recoveryDirection,
      recoveryScore,
      recoveryGap
   ))
   {
      bool opened = false;

      if(recoveryDirection == 1)
         opened = OpenBuy("VOL80 RECOVERY BUY");
      else if(recoveryDirection == -1)
         opened = OpenSell("VOL80 RECOVERY SELL");

      if(opened)
      {
         LastRecoveryTime = TimeCurrent();
         RecoveryEntriesToday++;
         return;
      }
   }

   ProcessSignal();
}
//+------------------------------------------------------------------+
