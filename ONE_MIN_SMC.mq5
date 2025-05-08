//+------------------------------------------------------------------+
//| Expert Advisor: SMC Market Entry EA for MT5                      |
//| Timeframe: M1                                                    |
//| Features: Order Block Detection, Risk Management, Multi-Pair     |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>

// Input parameters
input double RiskPercent = 1.0;            // Risk percentage per trade
input double RiskRewardRatio = 2.0;        // Risk:Reward ratio
input int OrderBlockLookback = 20;         // Bars to look back for order blocks
input double StopLossMultiplier = 1.5;     // ATR multiplier for stop loss
input int ATRPeriod = 14;                  // ATR period for dynamic stops
input int MaxSpread = 30;                  // Maximum allowed spread (points)
input bool TradeNewYorkSession = true;     // Trade NY session (8AM-12PM EST)
input bool TradeLondonSession = true;      // Trade London session (3AM-7AM EST)
input int MagicNumber = 202405;            // EA magic number
input int Slippage = 30;                   // Maximum allowed slippage (points)
input ENUM_TIMEFRAMES Timeframe = PERIOD_M1; // Global timeframe setting

// Global variables
CTrade trade;
CPositionInfo positionInfo;
CSymbolInfo symbolInfo;
CAccountInfo accountInfo;

int maHandle, atrHandle;  // Indicator handles

//+------------------------------------------------------------------+
//| OrderBlock structure                                             |
//+------------------------------------------------------------------+
struct OrderBlock {
   double price;
   datetime time;
   bool isBullish;
   double volume;
   double atr;
};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   
   // Initialize indicator handles
   maHandle = iMA(NULL, Timeframe, 20, 0, MODE_SMA, VOLUME_TICK);
   atrHandle = iATR(NULL, Timeframe, ATRPeriod);
   
   if(maHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE)
   {
      Print("Error creating indicator handles");
      return(INIT_FAILED);
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(maHandle);
   IndicatorRelease(atrHandle);
}

//+------------------------------------------------------------------+
//| Check if current time is within trading session                  |
//+------------------------------------------------------------------+
bool IsTradingSession()
{
   MqlDateTime timeNow;
   TimeCurrent(timeNow);
   int hour = timeNow.hour;
   
   // New York session (8AM-12PM EST = 13:00-17:00 GMT)
   if(TradeNewYorkSession && hour >= 13 && hour < 17)
      return true;
      
   // London session (3AM-7AM EST = 8:00-12:00 GMT)
   if(TradeLondonSession && hour >= 8 && hour < 12)
      return true;
      
  // return false;
  return true;
}

//+------------------------------------------------------------------+
//| Calculate position size based on account risk                    |
//+------------------------------------------------------------------+
double CalculateLotSize(string symbol, double stopLossPoints)
{
   if(!symbolInfo.Name(symbol))
      return 0.1;
      
   double accountBalance = accountInfo.Balance();
   if(accountBalance <= 0) return 0.1;
   
   double riskAmount = accountBalance * RiskPercent / 100.0;
   double tickValue, pointValue;
   
   if(!SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE, tickValue) ||
      !SymbolInfoDouble(symbol, SYMBOL_POINT, pointValue))
   {
      Print("Failed to get symbol values");
      return 0.1;
   }
   
   if(tickValue == 0 || pointValue == 0 || stopLossPoints == 0)
      return 0.1;
   
   double lotSize = (riskAmount / (stopLossPoints * pointValue)) / tickValue;
   lotSize = NormalizeDouble(lotSize, 2);
   
   // Ensure lot size is within broker limits
   double minLot, maxLot;
   SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN, minLot);
   SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX, maxLot);
   
   lotSize = fmax(lotSize, minLot);
   lotSize = fmin(lotSize, maxLot);
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Check if position already exists for this symbol                 |
//+------------------------------------------------------------------+
bool HasPosition(string symbol)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == symbol && positionInfo.Magic() == MagicNumber)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Enhanced Order Block detection                                   |
//+------------------------------------------------------------------+
bool FindOrderBlock(string symbol, OrderBlock &ob)
{
   ob.price = 0;
   ob.time = 0;
   ob.isBullish = false;
   ob.volume = 0;
   ob.atr = 0;
   
   // Get ATR for dynamic stop calculation
   double atrBuffer[];
   if(CopyBuffer(atrHandle, 0, 1, 2, atrBuffer) != 2)
      return false;
   
   ob.atr = atrBuffer[1];
   
   // Look for order blocks
   for(int i = OrderBlockLookback; i > 3; i--)
   {
      double high1 = iHigh(symbol, Timeframe, i);
      double low1 = iLow(symbol, Timeframe, i);
      double volume1 = iVolume(symbol, Timeframe, i);
      
      // Get MA value for volume
      double maBuffer[];
      if(CopyBuffer(maHandle, 0, i, 1, maBuffer) != 1)
         continue;
      double avgVolume = maBuffer[0];
      
      // Check for bullish order block
      if(IsSwingLow(symbol, i) && volume1 > avgVolume * 1.5)
      {
         ob.price = low1;
         ob.time = iTime(symbol, Timeframe, i);
         ob.isBullish = true;
         ob.volume = volume1;
         return true;
      }
      
      // Check for bearish order block
      if(IsSwingHigh(symbol, i) && volume1 > avgVolume * 1.5)
      {
         ob.price = high1;
         ob.time = iTime(symbol, Timeframe, i);
         ob.isBullish = false;
         ob.volume = volume1;
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check if bar is a swing low                                      |
//+------------------------------------------------------------------+
bool IsSwingLow(string symbol, int index)
{
   double low = iLow(symbol, Timeframe, index);
   
   for(int i = 1; i <= 3; i++)
   {
      if(iLow(symbol, Timeframe, index + i) < low || 
         iLow(symbol, Timeframe, index - i) < low)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Check if bar is a swing high                                     |
//+------------------------------------------------------------------+
bool IsSwingHigh(string symbol, int index)
{
   double high = iHigh(symbol, Timeframe, index);
   
   for(int i = 1; i <= 3; i++)
   {
      if(iHigh(symbol, Timeframe, index + i) > high || 
         iHigh(symbol, Timeframe, index - i) > high)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Validate stop levels before sending order                        |
//+------------------------------------------------------------------+
bool ValidateStopLevels(string symbol, double entryPrice, double &sl, double &tp, bool isBuy)
{
    if(!symbolInfo.Name(symbol))
        return false;
        
    symbolInfo.RefreshRates();
    
    double point, ask, bid, freezeLevel;
    if(!SymbolInfoDouble(symbol, SYMBOL_POINT, point) ||
       !SymbolInfoDouble(symbol, SYMBOL_ASK, ask) ||
       !SymbolInfoDouble(symbol, SYMBOL_BID, bid))
    {
        Print("Failed to get symbol info");
        return false;
    }
    
    freezeLevel *= point;
    double spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD) * point;
    double stopLevel = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
    double minStopDistance = stopLevel + spread;
    
    if(isBuy)
    {
        if(sl >= entryPrice - minStopDistance)
            sl = entryPrice - minStopDistance;
        if(tp <= entryPrice + minStopDistance)
            tp = entryPrice + minStopDistance * RiskRewardRatio;
    }
    else
    {
        if(sl <= entryPrice + minStopDistance)
            sl = entryPrice + minStopDistance;
        if(tp >= entryPrice - minStopDistance)
            tp = entryPrice - minStopDistance * RiskRewardRatio;
    }
    
    if(MathAbs(entryPrice - sl) <= freezeLevel)
        return false;
    
    if(SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_FULL)
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Execute trade with full validation                               |
//+------------------------------------------------------------------+
void ExecuteTrade(string symbol, OrderBlock &ob)
{
    if(!IsTradingSession() || HasPosition(symbol) || !symbolInfo.Name(symbol))
        return;
      
    symbolInfo.RefreshRates();
   
    double spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
    if(spread > MaxSpread)
        return;
   
    double point, entryPrice;
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    
    if(ob.isBullish)
    {
        if(!SymbolInfoDouble(symbol, SYMBOL_ASK, entryPrice) ||
           !SymbolInfoDouble(symbol, SYMBOL_POINT, point))
            return;
    }
    else
    {
        if(!SymbolInfoDouble(symbol, SYMBOL_BID, entryPrice) ||
           !SymbolInfoDouble(symbol, SYMBOL_POINT, point))
            return;
    }
   
    double sl = ob.isBullish 
        ? NormalizeDouble(ob.price - (ob.atr * StopLossMultiplier), digits)
        : NormalizeDouble(ob.price + (ob.atr * StopLossMultiplier), digits);
        
    double tp = ob.isBullish
        ? NormalizeDouble(entryPrice + (entryPrice - sl) * RiskRewardRatio, digits)
        : NormalizeDouble(entryPrice - (sl - entryPrice) * RiskRewardRatio, digits);
    
    if((ob.isBullish && (entryPrice - sl) < (ob.atr * 0.5)) ||
       (!ob.isBullish && (sl - entryPrice) < (ob.atr * 0.5)))
        return;
    
    double lotSize = CalculateLotSize(symbol, ob.isBullish ? (entryPrice - sl) : (sl - entryPrice));
    
    double margin;
    ENUM_ORDER_TYPE orderType = ob.isBullish ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    if(!OrderCalcMargin(orderType, symbol, lotSize, entryPrice, margin) ||
       margin > accountInfo.FreeMargin())
        return;
    
    if(!ValidateStopLevels(symbol, entryPrice, sl, tp, ob.isBullish))
        return;
   
    if(ob.isBullish)
        trade.Buy(lotSize, symbol, entryPrice, sl, tp, "SMC Buy");
    else
        trade.Sell(lotSize, symbol, entryPrice, sl, tp, "SMC Sell");
}

//+------------------------------------------------------------------+
//| Main tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{

  
    string symbols[] = {"EURUSD","GBPJPY", "GBPUSD","USDCAD", "USDJPY", "XAUUSD","USTEC","AUDUSD","NZDCAD","GBPCHF","EURGBP"};
   for(int i = 0; i < ArraySize(symbols); i++)
   {
          
      string symbol = symbols[i];
      Print("started=="+symbol);
      
      if(!SymbolSelect(symbol, true))
         continue;
         
      OrderBlock ob;
      if(FindOrderBlock(symbol, ob))
      {
         double currentAsk, currentBid;
         if(!SymbolInfoDouble(symbol, SYMBOL_ASK, currentAsk) || 
            !SymbolInfoDouble(symbol, SYMBOL_BID, currentBid))
            continue;
         
         if(ob.isBullish)
         {
            if(currentBid <= ob.price + (ob.atr * 0.2) && 
               currentBid >= ob.price - (ob.atr * 0.1))
               ExecuteTrade(symbol, ob);
         }
         else
         {
            if(currentAsk >= ob.price - (ob.atr * 0.2) && 
               currentAsk <= ob.price + (ob.atr * 0.1))
               ExecuteTrade(symbol, ob);
         }
      }
   }
}
//+------------------------------------------------------------------+
