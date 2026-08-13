//+------------------------------------------------------------------+
//| XAU Scalper Adaptive V1                                          |
//| MT5 / MQL5                                                       |
//+------------------------------------------------------------------+
#property strict
#property version "1.00"

#include <Trade/Trade.mqh>
CTrade trade;

input string InpSymbol = "";
input ulong InpMagic = 26081301;
input double InpLot = 0.02;
input int InpMinScore = 62;
input int InpMinConfirmation = 2;
input int InpMinAddScore = 68;
input int InpMaxPositions = 8;
input int InpATRPeriod = 14;
input double InpSL_ATR = 1.50;
input double InpTrailStartATR = 1.00;
input double InpTrailNormalATR = 1.15;
input double InpTrailTightATR = 0.75;
input double InpTightenAtATR = 2.00;
input double InpMajorProfitATR = 3.00;
input double InpMaxSpread = 1200.0;
input double InpExtremeSpread = 2500.0;
input double InpHardDD = 15.0;
input bool InpUseNewsFilter = true;
input bool InpDebug = true;

string g_symbol = "";
int hATR_M1 = INVALID_HANDLE;
int hATR_M5 = INVALID_HANDLE;
int hEMA20_M5 = INVALID_HANDLE;
int hEMA50_M5 = INVALID_HANDLE;
int hRSI_M1 = INVALID_HANDLE;
int hADX_M5 = INVALID_HANDLE;
datetime g_lastBar = 0;
datetime g_lastTrade = 0;
double g_lastBuyScore = 0.0;
double g_lastSellScore = 0.0;
double g_peakEquity = 0.0;

double PointValue(){ return SymbolInfoDouble(g_symbol,SYMBOL_POINT); }
int DigitsValue(){ return (int)SymbolInfoInteger(g_symbol,SYMBOL_DIGITS); }
double NormalizePrice(double price){ return NormalizeDouble(price,DigitsValue()); }
double BidPrice(){ return SymbolInfoDouble(g_symbol,SYMBOL_BID); }
double AskPrice(){ return SymbolInfoDouble(g_symbol,SYMBOL_ASK); }
double SpreadPoints(){ double point=PointValue(); if(point<=0) return 999999; return (AskPrice()-BidPrice())/point; }

bool GetBuffer(int handle,int buffer,int shift,double &value)
{
   if(handle==INVALID_HANDLE) return false;
   double data[]; ArraySetAsSeries(data,true);
   if(CopyBuffer(handle,buffer,shift,1,data)!=1) return false;
   value=data[0]; return true;
}
double ATR_M1(int shift=1){ double v=0; GetBuffer(hATR_M1,0,shift,v); return v; }
double ATR_M5(int shift=1){ double v=0; GetBuffer(hATR_M5,0,shift,v); return v; }
double EMA20_M5(int shift=1){ double v=0; GetBuffer(hEMA20_M5,0,shift,v); return v; }
double EMA50_M5(int shift=1){ double v=0; GetBuffer(hEMA50_M5,0,shift,v); return v; }
double RSI_M1(int shift=1){ double v=50; GetBuffer(hRSI_M1,0,shift,v); return v; }
double ADX_M5(int shift=1){ double v=0; GetBuffer(hADX_M5,0,shift,v); return v; }

bool IsNewM1Bar()
{
   datetime t=iTime(g_symbol,PERIOD_M1,0);
   if(t==0) return false;
   if(t!=g_lastBar){ g_lastBar=t; return true; }
   return false;
}

bool M5Bull()
{
   double h1=iHigh(g_symbol,PERIOD_M5,1), h2=iHigh(g_symbol,PERIOD_M5,2);
   double l1=iLow(g_symbol,PERIOD_M5,1), l2=iLow(g_symbol,PERIOD_M5,2);
   return(h1>h2 && l1>l2);
}
bool M5Bear()
{
   double h1=iHigh(g_symbol,PERIOD_M5,1), h2=iHigh(g_symbol,PERIOD_M5,2);
   double l1=iLow(g_symbol,PERIOD_M5,1), l2=iLow(g_symbol,PERIOD_M5,2);
   return(h1<h2 && l1<l2);
}
bool M1Bull()
{
   double h1=iHigh(g_symbol,PERIOD_M1,1), h2=iHigh(g_symbol,PERIOD_M1,2);
   double l1=iLow(g_symbol,PERIOD_M1,1), l2=iLow(g_symbol,PERIOD_M1,2);
   return(h1>h2 && l1>l2);
}
bool M1Bear()
{
   double h1=iHigh(g_symbol,PERIOD_M1,1), h2=iHigh(g_symbol,PERIOD_M1,2);
   double l1=iLow(g_symbol,PERIOD_M1,1), l2=iLow(g_symbol,PERIOD_M1,2);
   return(h1<h2 && l1<l2);
}
bool BreakHigh(){ return iHigh(g_symbol,PERIOD_M1,1)>iHigh(g_symbol,PERIOD_M1,2); }
bool BreakLow(){ return iLow(g_symbol,PERIOD_M1,1)<iLow(g_symbol,PERIOD_M1,2); }

double Momentum(int direction)
{
   double atr=ATR_M1(1); if(atr<=0) return 0;
   double move=iClose(g_symbol,PERIOD_M1,1)-iClose(g_symbol,PERIOD_M1,2);
   if(direction<0) move=-move;
   double x=MathAbs(move)/atr; if(x>1.5) x=1.5;
   return(x/1.5)*100.0;
}
double VolatilityScore()
{
   double a1=ATR_M1(1), a5=ATR_M5(1);
   if(a1<=0 || a5<=0) return 0;
   double ratio=a1/(a5/MathSqrt(5.0));
   if(ratio<0.25) return 20;
   if(ratio>2.0) return 100;
   return 20+((ratio-0.25)/1.75)*80;
}


double PriceActionScore(int direction)
{
   double score=0;
   if(direction>0 && M1Bull()) score+=35;
   if(direction<0 && M1Bear()) score+=35;
   if(direction>0 && BreakHigh()) score+=25;
   if(direction<0 && BreakLow()) score+=25;
   double o=iOpen(g_symbol,PERIOD_M1,1), c=iClose(g_symbol,PERIOD_M1,1);
   double h=iHigh(g_symbol,PERIOD_M1,1), l=iLow(g_symbol,PERIOD_M1,1);
   double range=h-l;
   if(range>0 && MathAbs(c-o)/range>=0.55) score+=20;
   if(score>100) score=100;
   return score;
}
double RSIScore(int direction)
{
   double rsi=RSI_M1(1);
   if(direction>0){ if(rsi>=50 && rsi<=70) return 100; if(rsi>45 && rsi<75) return 70; if(rsi<35) return 55; return 30; }
   if(rsi<=50 && rsi>=30) return 100;
   if(rsi<55 && rsi>25) return 70;
   if(rsi>65) return 55;
   return 30;
}
double TickVolumeScore()
{
   long v1=iVolume(g_symbol,PERIOD_M1,1), v2=iVolume(g_symbol,PERIOD_M1,2), v3=iVolume(g_symbol,PERIOD_M1,3);
   if(v1<=0 || v2<=0 || v3<=0) return 50;
   double avg=((double)v2+(double)v3)/2.0; if(avg<=0) return 50;
   double ratio=(double)v1/avg;
   if(ratio>=1.50) return 100; if(ratio>=1.20) return 80; if(ratio>=1.00) return 60;
   return 40;
}
double M5Score(int direction)
{
   double ema20=EMA20_M5(1), ema50=EMA50_M5(1), price=iClose(g_symbol,PERIOD_M5,1);
   if(ema20==0 || ema50==0) return 0;
   double score=0;
   if(direction>0){ if(price>ema20) score+=15; if(ema20>ema50) score+=15; if(M5Bull()) score+=15; }
   else{ if(price<ema20) score+=15; if(ema20<ema50) score+=15; if(M5Bear()) score+=15; }
   return score;
}
double CounterTrendPenalty(int direction)
{
   double ema20=EMA20_M5(1), ema50=EMA50_M5(1), adx=ADX_M5(1);
   if(ema20==0 || ema50==0) return 0;
   bool strongBull=(ema20>ema50 && M5Bull() && adx>=25);
   bool strongBear=(ema20<ema50 && M5Bear() && adx>=25);
   if(direction<0 && strongBull) return 20;
   if(direction>0 && strongBear) return 20;
   return 0;
}
string DetectMode(int direction)
{
   double mom=Momentum(direction);
   if(direction>0){
      if(BreakHigh() && mom>=65) return "BREAKOUT";
      if(M1Bull() && mom>=55) return "MOMENTUM";
      if(RSI_M1(1)<45 && M1Bull()) return "PULLBACK";
      if(!M1Bull() && mom>=60) return "REVERSAL";
   } else {
      if(BreakLow() && mom>=65) return "BREAKOUT";
      if(M1Bear() && mom>=55) return "MOMENTUM";
      if(RSI_M1(1)>55 && M1Bear()) return "PULLBACK";
      if(!M1Bear() && mom>=60) return "REVERSAL";
   }
   return "MIXED";
}
bool BuildSignal(int direction,double &score,int &confirmations,string &mode)
{
   score=0; confirmations=0; mode="";
   double pa=PriceActionScore(direction), rsi=RSIScore(direction), mom=Momentum(direction);
   double vol=VolatilityScore(), tick=TickVolumeScore(), m5=M5Score(direction);
   double penalty=CounterTrendPenalty(direction);
   score=m5*0.20+pa*0.25+rsi*0.15+mom*0.20+vol*0.10+tick*0.10-penalty;
   if(score<0) score=0; if(score>100) score=100;
   mode=DetectMode(direction);
   bool structure=(direction>0)?(M1Bull()||BreakHigh()):(M1Bear()||BreakLow());
   if(structure) confirmations++;
   if(mom>=55) confirmations++;
   if(rsi>=60) confirmations++;
   if(tick>=60) confirmations++;
   if(confirmations<InpMinConfirmation) return false;
   double required=InpMinScore;
   if(penalty>0) required+=8;
   if(mom>=80) required-=3;
   if(required<55) required=55;
   return(score>=required);
}
int CountPositions(int direction=0)
{
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--){
      ulong ticket=PositionGetTicket(i); if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=g_symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      long type=PositionGetInteger(POSITION_TYPE);
      if(direction==1 && type!=POSITION_TYPE_BUY) continue;
      if(direction==-1 && type!=POSITION_TYPE_SELL) continue;
      count++;
   }
   return count;
}
int CurrentDirection()
{
   int buy=CountPositions(1), sell=CountPositions(-1);
   if(buy>0 && sell==0) return 1;
   if(sell>0 && buy==0) return -1;
   if(buy>0 && sell>0) return 99;
   return 0;
}
double DrawdownPercent()
{
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_peakEquity<=0) g_peakEquity=equity;
   if(equity>g_peakEquity) g_peakEquity=equity;
   if(g_peakEquity<=0) return 0;
   return((g_peakEquity-equity)/g_peakEquity)*100.0;
}
bool SpreadAllowed(double score)
{
   double spread=SpreadPoints();
   if(spread<=InpMaxSpread) return true;
   if(score>=78 && spread<=InpExtremeSpread) return true;
   return false;
}
double NormalizeLot(double lot)
{
   double minLot=SymbolInfoDouble(g_symbol,SYMBOL_VOLUME_MIN), maxLot=SymbolInfoDouble(g_symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(g_symbol,SYMBOL_VOLUME_STEP); if(step<=0) step=0.01;
   lot=MathMax(minLot,MathMin(maxLot,lot)); lot=MathFloor(lot/step)*step;
   return NormalizeDouble(lot,2);
}
bool OpenTrade(int direction,double score,string reason)
{
   if(CountPositions()>=InpMaxPositions || DrawdownPercent()>=InpHardDD || !SpreadAllowed(score)) return false;
   if(g_lastTrade>0 && TimeCurrent()-g_lastTrade<10) return false;
   int current=CurrentDirection(); if(current==-direction || current==99) return false;
   if(current==direction){
      if(direction>0 && score<=g_lastBuyScore) return false;
      if(direction<0 && score<=g_lastSellScore) return false;
      if(score<InpMinAddScore) return false;
   }
   double atr=ATR_M1(1); if(atr<=0) return false;
   double slDistance=atr*InpSL_ATR, point=PointValue();
   double minStop=SymbolInfoInteger(g_symbol,SYMBOL_TRADE_STOPS_LEVEL)*point;
   if(slDistance<minStop) slDistance=minStop+point;
   double lot=NormalizeLot(InpLot); if(lot<=0) return false;
   trade.SetExpertMagicNumber(InpMagic); trade.SetDeviationInPoints(100);
   bool result=false;
   if(direction>0){
      double sl=NormalizePrice(AskPrice()-slDistance);
      result=trade.Buy(lot,g_symbol,0,sl,0,"Adaptive BUY");
      if(result) g_lastBuyScore=score;
   } else {
      double sl=NormalizePrice(BidPrice()+slDistance);
      result=trade.Sell(lot,g_symbol,0,sl,0,"Adaptive SELL");
      if(result) g_lastSellScore=score;
   }
   if(result){ g_lastTrade=TimeCurrent(); if(InpDebug) Print("ENTRY ",direction>0?"BUY":"SELL"," | Lot=",DoubleToString(lot,2)," | Score=",DoubleToString(score,1)," | ",reason); }
   return result;
}


void ManageTrailing()
{
   double atr=ATR_M1(1); if(atr<=0) return;
   for(int i=PositionsTotal()-1;i>=0;i--){
      ulong ticket=PositionGetTicket(i); if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=g_symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      long type=PositionGetInteger(POSITION_TYPE);
      double open=PositionGetDouble(POSITION_PRICE_OPEN), oldSL=PositionGetDouble(POSITION_SL), tp=PositionGetDouble(POSITION_TP);
      double price=(type==POSITION_TYPE_BUY)?BidPrice():AskPrice();
      double profitDist=(type==POSITION_TYPE_BUY)?price-open:open-price;
      if(profitDist<=0) continue;
      double profitATR=profitDist/atr; if(profitATR<InpTrailStartATR) continue;
      double multiplier=InpTrailNormalATR;
      if(profitATR>=InpTightenAtATR) multiplier=InpTrailTightATR;
      if(profitATR>=InpMajorProfitATR) multiplier=(Momentum(type==POSITION_TYPE_BUY?1:-1)>=75)?0.95:0.60;
      double distance=atr*multiplier, newSL=0;
      if(type==POSITION_TYPE_BUY){
         newSL=NormalizePrice(price-distance);
         if(oldSL>0 && newSL<=oldSL) continue;
         if(newSL>=price) continue;
      } else {
         newSL=NormalizePrice(price+distance);
         if(oldSL>0 && newSL>=oldSL) continue;
         if(newSL<=price) continue;
      }
      trade.SetExpertMagicNumber(InpMagic); trade.PositionModify(ticket,newSL,tp);
   }
}
double BasketProfit(int direction=0)
{
   double total=0;
   for(int i=PositionsTotal()-1;i>=0;i--){
      ulong ticket=PositionGetTicket(i); if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=g_symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      long type=PositionGetInteger(POSITION_TYPE);
      if(direction==1 && type!=POSITION_TYPE_BUY) continue;
      if(direction==-1 && type!=POSITION_TYPE_SELL) continue;
      total+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
   }
   return total;
}
void ManageBasketProtection()
{
   int direction=CurrentDirection(); if(direction!=1 && direction!=-1) return;
   double basket=BasketProfit(direction); if(basket<=0) return;
   double equity=AccountInfoDouble(ACCOUNT_EQUITY); if(equity<=0) return;
   double basketPct=(basket/equity)*100.0; if(basketPct<0.75) return;
   if(Momentum(direction)>=45) return;
   double atr=ATR_M1(1); if(atr<=0) return;
   for(int i=PositionsTotal()-1;i>=0;i--){
      ulong ticket=PositionGetTicket(i); if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=g_symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      long type=PositionGetInteger(POSITION_TYPE);
      if(direction==1 && type!=POSITION_TYPE_BUY) continue;
      if(direction==-1 && type!=POSITION_TYPE_SELL) continue;
      double open=PositionGetDouble(POSITION_PRICE_OPEN), oldSL=PositionGetDouble(POSITION_SL), tp=PositionGetDouble(POSITION_TP);
      double price=(direction==1)?BidPrice():AskPrice(), distance=atr*0.55, newSL;
      if(direction==1){
         newSL=NormalizePrice(price-distance);
         if(newSL>open && (oldSL==0 || newSL>oldSL)) trade.PositionModify(ticket,newSL,tp);
      } else {
         newSL=NormalizePrice(price+distance);
         if(newSL<open && (oldSL==0 || newSL<oldSL)) trade.PositionModify(ticket,newSL,tp);
      }
   }
}
bool NewsBlocked()
{
   if(!InpUseNewsFilter) return false;
   datetime now=TimeTradeServer(); if(now<=0) now=TimeCurrent();
   MqlCalendarValue values[];
   int total=CalendarValueHistory(values,now-1800,now+1800,NULL,"USD");
   if(total<=0) return false;
   for(int i=0;i<total;i++){
      MqlCalendarEvent event;
      if(!CalendarEventById(values[i].event_id,event)) continue;
      if(event.importance==CALENDAR_IMPORTANCE_HIGH){
         datetime t=values[i].time;
         if(now>=t-30*60 && now<=t+30*60) return true;
      }
   }
   return false;
}
void CheckEntry()
{
   if(DrawdownPercent()>=InpHardDD || NewsBlocked() || CountPositions()>=InpMaxPositions) return;
   int current=CurrentDirection(); if(current==99) return;
   double buyScore=0,sellScore=0; int buyConf=0,sellConf=0; string buyMode="",sellMode="";
   bool buyOK=false,sellOK=false;
   if(current==0 || current==1) buyOK=BuildSignal(1,buyScore,buyConf,buyMode);
   if(current==0 || current==-1) sellOK=BuildSignal(-1,sellScore,sellConf,sellMode);
   if(current==1){ if(buyOK) OpenTrade(1,buyScore,buyMode); return; }
   if(current==-1){ if(sellOK) OpenTrade(-1,sellScore,sellMode); return; }
   if(buyOK && sellOK){ if(buyScore>=sellScore) OpenTrade(1,buyScore,buyMode); else OpenTrade(-1,sellScore,sellMode); return; }
   if(buyOK){ OpenTrade(1,buyScore,buyMode); return; }
   if(sellOK){ OpenTrade(-1,sellScore,sellMode); return; }
}
void Dashboard()
{
   if(!InpDebug) return;
   string direction="NONE"; int d=CurrentDirection();
   if(d==1) direction="BUY"; if(d==-1) direction="SELL"; if(d==99) direction="HEDGE";
   Comment("XAU SCALPER ADAPTIVE V1\n","Symbol: ",g_symbol,"\n","Lot: ",DoubleToString(InpLot,2),"\n",
      "M1 ATR: ",DoubleToString(ATR_M1(1),DigitsValue()),"\n","Spread: ",DoubleToString(SpreadPoints(),1)," pts\n",
      "Positions: ",CountPositions(),"/",InpMaxPositions,"\n","Direction: ",direction,"\n",
      "Buy Score: ",DoubleToString(g_lastBuyScore,1),"\n","Sell Score: ",DoubleToString(g_lastSellScore,1),"\n",
      "DD: ",DoubleToString(DrawdownPercent(),2),"%\n","News: ",NewsBlocked()?"BLOCKED":"OPEN");
}
int OnInit()
{
   g_symbol=InpSymbol; if(g_symbol=="") g_symbol=_Symbol;
   if(!SymbolSelect(g_symbol,true)) return INIT_FAILED;
   hATR_M1=iATR(g_symbol,PERIOD_M1,InpATRPeriod);
   hATR_M5=iATR(g_symbol,PERIOD_M5,InpATRPeriod);
   hEMA20_M5=iMA(g_symbol,PERIOD_M5,20,0,MODE_EMA,PRICE_CLOSE);
   hEMA50_M5=iMA(g_symbol,PERIOD_M5,50,0,MODE_EMA,PRICE_CLOSE);
   hRSI_M1=iRSI(g_symbol,PERIOD_M1,14,PRICE_CLOSE);
   hADX_M5=iADX(g_symbol,PERIOD_M5,14);
   if(hATR_M1==INVALID_HANDLE || hATR_M5==INVALID_HANDLE || hEMA20_M5==INVALID_HANDLE ||
      hEMA50_M5==INVALID_HANDLE || hRSI_M1==INVALID_HANDLE || hADX_M5==INVALID_HANDLE){
      Print("Indicator initialization failed."); return INIT_FAILED;
   }
   g_peakEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   trade.SetExpertMagicNumber(InpMagic); trade.SetDeviationInPoints(100);
   Print("XAU Scalper Adaptive V1 READY | ",g_symbol," | LOT ",DoubleToString(InpLot,2));
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason)
{
   if(hATR_M1!=INVALID_HANDLE) IndicatorRelease(hATR_M1);
   if(hATR_M5!=INVALID_HANDLE) IndicatorRelease(hATR_M5);
   if(hEMA20_M5!=INVALID_HANDLE) IndicatorRelease(hEMA20_M5);
   if(hEMA50_M5!=INVALID_HANDLE) IndicatorRelease(hEMA50_M5);
   if(hRSI_M1!=INVALID_HANDLE) IndicatorRelease(hRSI_M1);
   if(hADX_M5!=INVALID_HANDLE) IndicatorRelease(hADX_M5);
   Comment("");
}
void OnTick()
{
   ManageTrailing();
   ManageBasketProtection();
   Dashboard();
   if(!IsNewM1Bar()) return;
   CheckEntry();
}
//+------------------------------------------------------------------+
//| END                                                              |
//+------------------------------------------------------------------+
