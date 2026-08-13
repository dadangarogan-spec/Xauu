//+------------------------------------------------------------------+
//| XAU_M1_Momentum_Pullback_Grid.mq5                                |
//| M5 trend + M1 pullback trigger + limited ATR grid                |
//+------------------------------------------------------------------+
#property strict
#property version "1.00"

#include <Trade/Trade.mqh>
CTrade trade;

input double LotSize            = 0.02;
input int    MaxPositions       = 5;
input int    FastEMA             = 9;
input int    SlowEMA             = 21;
input int    ATRPeriod           = 14;
input double SL_ATR              = 1.5;
input double TP_ATR              = 1.0;
input double Grid_ATR            = 0.70;
input int    MaxSpreadPoints     = 100;
input int    MagicNumber         = 26081301;
input bool   UseTradingHours     = true;
input int    StartHour           = 7;
input int    EndHour             = 23;

int hEmaFastM5, hEmaSlowM5, hEmaFastM1, hEmaSlowM1, hATR;
datetime lastBar=0;

bool TradingTime()
{
   if(!UseTradingHours) return true;
   MqlDateTime t; TimeToStruct(TimeCurrent(),t);
   if(StartHour <= EndHour) return (t.hour >= StartHour && t.hour < EndHour);
   return (t.hour >= StartHour || t.hour < EndHour);
}

double BufferValue(int handle,int shift)
{
   double b[];
   if(CopyBuffer(handle,0,shift,1,b)!=1) return 0;
   return b[0];
}

double ATR(int shift=1){ return BufferValue(hATR,shift); }

int CountPositions()
{
   int n=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      n++;
   }
   return n;
}

int Direction()
{
   double f=BufferValue(hEmaFastM5,1);
   double s=BufferValue(hEmaSlowM5,1);
   if(f>s) return 1;
   if(f<s) return -1;
   return 0;
}

bool SpreadOK()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return false;
   double spread=(tick.ask-tick.bid)/_Point;
   return spread<=MaxSpreadPoints;
}

bool HasInitialEntry()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
         (int)PositionGetInteger(POSITION_MAGIC)==MagicNumber)
         return true;
   }
   return false;
}

double LastEntryPrice(int dir)
{
   double price=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      long type=PositionGetInteger(POSITION_TYPE);
      if((dir==1 && type==POSITION_TYPE_BUY) ||
         (dir==-1 && type==POSITION_TYPE_SELL))
      {
         double p=PositionGetDouble(POSITION_PRICE_OPEN);
         if(price==0 || (dir==1 && p<price) || (dir==-1 && p>price))
            price=p;
      }
   }
   return price;
}

bool PullbackTrigger(int dir)
{
   double f1=BufferValue(hEmaFastM1,1);
   double s1=BufferValue(hEmaSlowM1,1);
   double f2=BufferValue(hEmaFastM1,2);
   double s2=BufferValue(hEmaSlowM1,2);

   double close1=iClose(_Symbol,PERIOD_M1,1);
   double low1=iLow(_Symbol,PERIOD_M1,1);
   double high1=iHigh(_Symbol,PERIOD_M1,1);

   // Momentum direction + pullback/reclaim of fast EMA.
   if(dir==1)
      return (f1>s1 && close1>f1 && low1<=f1 && f1>=f2);
   if(dir==-1)
      return (f1<s1 && close1<f1 && high1>=f1 && f1<=f2);

   return false;
}

void OpenTrade(int dir)
{
   double atr=ATR(1);
   if(atr<=0) return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return;

   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double sl,tp;

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(30);

   if(dir==1)
   {
      sl=NormalizeDouble(tick.ask-atr*SL_ATR,digits);
      tp=NormalizeDouble(tick.ask+atr*TP_ATR,digits);
      trade.Buy(LotSize,_Symbol,0,sl,tp,"M1 Pullback");
   }
   else
   {
      sl=NormalizeDouble(tick.bid+atr*SL_ATR,digits);
      tp=NormalizeDouble(tick.bid-atr*TP_ATR,digits);
      trade.Sell(LotSize,_Symbol,0,sl,tp,"M1 Pullback");
   }
}

void TryGrid(int dir)
{
   int count=CountPositions();
   if(count<=0 || count>=MaxPositions) return;

   double atr=ATR(1);
   if(atr<=0) return;

   double last=LastEntryPrice(dir);
   if(last<=0) return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return;

   double distance=atr*Grid_ATR;

   // Add only after price moves against the existing position.
   if(dir==1 && tick.bid <= last-distance)
      OpenTrade(dir);
   if(dir==-1 && tick.ask >= last+distance)
      OpenTrade(dir);
}

int OnInit()
{
   hEmaFastM5=iMA(_Symbol,PERIOD_M5,FastEMA,0,MODE_EMA,PRICE_CLOSE);
   hEmaSlowM5=iMA(_Symbol,PERIOD_M5,SlowEMA,0,MODE_EMA,PRICE_CLOSE);
   hEmaFastM1=iMA(_Symbol,PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE);
   hEmaSlowM1=iMA(_Symbol,PERIOD_M1,SlowEMA,0,MODE_EMA,PRICE_CLOSE);
   hATR=iATR(_Symbol,PERIOD_M1,ATRPeriod);

   if(hEmaFastM5==INVALID_HANDLE || hEmaSlowM5==INVALID_HANDLE ||
      hEmaFastM1==INVALID_HANDLE || hEmaSlowM1==INVALID_HANDLE ||
      hATR==INVALID_HANDLE)
      return INIT_FAILED;

   trade.SetExpertMagicNumber(MagicNumber);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(hEmaFastM5);
   IndicatorRelease(hEmaSlowM5);
   IndicatorRelease(hEmaFastM1);
   IndicatorRelease(hEmaSlowM1);
   IndicatorRelease(hATR);
}

void OnTick()
{
   if(!TradingTime() || !SpreadOK()) return;

   // Process once per new M1 candle for initial entries.
   datetime bar=iTime(_Symbol,PERIOD_M1,0);
   if(bar==lastBar)
   {
      int d=Direction();
      if(d!=0) TryGrid(d);
      return;
   }
   lastBar=bar;

   int d=Direction();
   if(d==0) return;

   if(!HasInitialEntry() && PullbackTrigger(d))
      OpenTrade(d);
   else
      TryGrid(d);
}
