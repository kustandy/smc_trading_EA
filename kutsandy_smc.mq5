//+------------------------------------------------------------------+
//| Expert Advisor: Enhanced SMC Market Entry EA for MT5             |
//| Description: Multi-pair, M5, Advanced Order Block detection,     |
//|              Improved Risk Management, and Position Control      |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

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

// Global variables
CTrade trade;
CPositionInfo positionInfo;
CSymbolInfo symbolInfo;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OrderBlock structure with enhanced properties                    |
//+------------------------------------------------------------------+
struct OrderBlock {
   double price;
   datetime time;
   bool isBullish;
   double volume;
   double atr;
};

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
    //SHOULD RETURN FALSE  
   return true;
}

//+------------------------------------------------------------------+
//| Calculate position size based on account risk                    |
//+------------------------------------------------------------------+
double CalculateLotSize(string symbol, double stopLossPoints)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * RiskPercent / 100.0;
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double pointValue = SymbolInfoDouble(symbol, SYMBOL_POINT);
   
   if(tickValue == 0 || pointValue == 0 || stopLossPoints == 0)
      return 0.1; // Default fallback
   
   double lotSize = (riskAmount / (stopLossPoints * pointValue)) / tickValue;
   lotSize = NormalizeDouble(lotSize, 2);
   
   // Ensure lot size is within broker limits
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   
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
   int atrHandle = iATR(symbol, PERIOD_M1, ATRPeriod);
   if(CopyBuffer(atrHandle, 0, 1, 2, atrBuffer) != 2)
      return false;
   
   ob.atr = atrBuffer[1];
   
   // Create MA handle for volume
   int maHandle = iMA(symbol, PERIOD_M5, 20, 0, MODE_SMA, VOLUME_TICK);
   
   // Look for order blocks
   for(int i = OrderBlockLookback; i > 3; i--)
   {
      double high1 = iHigh(symbol, PERIOD_M5, i);
      double low1 = iLow(symbol, PERIOD_M5, i);
      double volume1 = iVolume(symbol, PERIOD_M5, i);
      
      // Get MA value for volume
      double maBuffer[];
      if(CopyBuffer(maHandle, 0, i, 1, maBuffer) != 1)
         continue;
      double avgVolume = maBuffer[0];
      
      // Check for bullish order block
      if(IsSwingLow(symbol, i) && volume1 > avgVolume * 1.5)
      {
         ob.price = low1;
         ob.time = iTime(symbol, PERIOD_M5, i);
         ob.isBullish = true;
         ob.volume = volume1;
         return true;
      }
      
      // Check for bearish order block
      if(IsSwingHigh(symbol, i) && volume1 > avgVolume * 1.5)
      {
         ob.price = high1;
         ob.time = iTime(symbol, PERIOD_M5, i);
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
   double low = iLow(symbol, PERIOD_M5, index);
   
   // Check left side (previous bars)
   for(int i = 1; i <= 3; i++)
   {
      if(iLow(symbol, PERIOD_M5, index + i) < low)
         return false;
   }
   
   // Check right side (following bars)
   for(int i = 1; i <= 3; i++)
   {
      if(iLow(symbol, PERIOD_M5, index - i) < low)
         return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if bar is a swing high                                     |
//+------------------------------------------------------------------+
bool IsSwingHigh(string symbol, int index)
{
   double high = iHigh(symbol, PERIOD_M5, index);
   
   // Check left side (previous bars)
   for(int i = 1; i <= 3; i++)
   {
      if(iHigh(symbol, PERIOD_M5, index + i) > high)
         return false;
   }
   
   // Check right side (following bars)
   for(int i = 1; i <= 3; i++)
   {
      if(iHigh(symbol, PERIOD_M5, index - i) > high)
         return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Execute trade with enhanced risk management                      |
//+------------------------------------------------------------------+
void ExecuteTrade(string symbol, OrderBlock &ob)
{
   // Check trading conditions
   if(!IsTradingSession())
      return;
      
   if(HasPosition(symbol))
      return;
      
   if(!symbolInfo.Name(symbol))
      return;
      
   symbolInfo.RefreshRates();
   
   // Check spread
   double spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   if(spread > MaxSpread)
      return;
   
   // Calculate stop loss and take profit
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   
   double sl = 0, tp = 0;
   double lotSize = 0;
   
   if(ob.isBullish)
   {
      // Bullish order block - buy trade
      sl = NormalizeDouble(ob.price - (ob.atr * StopLossMultiplier), digits);
      tp = NormalizeDouble(ask + (ask - sl) * RiskRewardRatio, digits);
      
      // Ensure SL is not too close to current price
      if((ask - sl) < (ob.atr * 0.5))
         return;
         
      lotSize = CalculateLotSize(symbol, ask - sl);
      
      trade.Buy(lotSize, symbol, sl, tp, "SMC Enhanced Buy");
   }
   else
   {
      // Bearish order block - sell trade
      sl = NormalizeDouble(ob.price + (ob.atr * StopLossMultiplier), digits);
      tp = NormalizeDouble(bid - (sl - bid) * RiskRewardRatio, digits);
      
      // Ensure SL is not too close to current price
      if((sl - bid) < (ob.atr * 0.5))
         return;
         
      lotSize = CalculateLotSize(symbol, sl - bid);
      
      trade.Sell(lotSize, symbol, sl, tp, "SMC Enhanced Sell");
   }
}

//+------------------------------------------------------------------+
//| Main tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   Print("==START==");
   string symbols[] = {"EURUSD", "GBPUSD", "USDJPY", "XAUUSD","USTEC","AUDUSD","NZDCAD","GBPCHF","EURGBP"};
   
   for(int i = 0; i < ArraySize(symbols); i++)
   {
      string symbol = symbols[i];
      
      // Refresh symbol data
      if(!SymbolSelect(symbol, true))
         continue;
         
      OrderBlock ob;
      if(FindOrderBlock(symbol, ob))
      {
         // Check if price is retesting the order block
         double currentAsk = SymbolInfoDouble(symbol, SYMBOL_ASK);
         double currentBid = SymbolInfoDouble(symbol, SYMBOL_BID);
         
         if(ob.isBullish)
         {
            // For bullish OB, check if price is retesting from above
            if(currentBid <= ob.price + (ob.atr * 0.2) && currentBid >= ob.price - (ob.atr * 0.1))
               ExecuteTrade(symbol, ob);
         }
         else
         {
            // For bearish OB, check if price is retesting from below
            if(currentAsk >= ob.price - (ob.atr * 0.2) && currentAsk <= ob.price + (ob.atr * 0.1))
               ExecuteTrade(symbol, ob);
         }
      }
   }
}
//+------------------------------------------------------------------+
