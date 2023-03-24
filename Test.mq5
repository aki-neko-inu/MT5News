#include <Trade\Trade.mqh>
#include <JAson.mqh>
#include <ErrorDescription.mqh>

input string Symbol1 = "USD JPY"; // 通貨ペア1
input string Symbol2 = "EUR USD"; // 通貨ペア2

input string NewsAPIKey = "YOUR_API_KEY";
input int RiskTolerance = 5; // リスク許容度: 1 (最低) から 10 (最高)

// Google Cloud API キーを設定
string GOOGLE_CLOUD_API_KEY = "your_google_cloud_api_key_here";

// Google Cloud Natural Language API のURL
string GOOGLE_CLOUD_NLP_API_URL = "https://language.googleapis.com/v1/documents:analyzeSentiment?key=" + GOOGLE_CLOUD_API_KEY;

CTrade Trade;
MqlCalendarValue EconomicEvents[];

datetime LastEventCheck;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   EventSetTimer(60); // タイマーを1分間隔で設定
   LastEventCheck = TimeCurrent();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer(); // タイマーを停止
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   MqlDateTime time;
   datetime current_time = TimeCurrent();
   TimeToStruct(current_time, time);
   int current_hour = time.hour;
   int current_minute = time.min;

   // 9時と21時にニュースデータを取得
   if ((current_hour == 9 || current_hour == 21) && current_minute == 0)
   {
      double sentiment_score = GetSentimentScore(Symbol1);
      AnalyzeNewsAndTrade(Symbol1, sentiment_score);
   }


   // 経済指標カレンダーからイベントの日時を1週間に1回取得
   if (WeeksBetween(current_time, LastEventCheck) >= 1)
   {
      LastEventCheck = current_time;
      GetEconomicEvents();
   }

   // 経済イベントが近い場合、ニュースデータを取得
   for (int i = 0; i < ArraySize(EconomicEvents); i++)
   {
      // if (MathAbs(EconomicEvents[i].time - current_time) < 60 * 5) // イベントの5分前
      if (MathAbs(EconomicEvents[i].time - current_time) <= 60) // イベントの発生時刻
      {
         double sentiment_score = GetSentimentScore(Symbol1);
         AnalyzeNewsAndTrade(Symbol1, sentiment_score);

         break;
      }
   }
}

//+------------------------------------------------------------------+
//| Get news data and analyze sentiment                              |
//+------------------------------------------------------------------+
double GetSentimentScore(string query)
{
   // URLエンコード（スペースを %20 に置き換え）
   StringReplace(query, " ", "%20");
   
   string url = StringFormat("https://contextualwebsearch.com/api/v2/NewsSearchApi?q=%s&apiKey=%s", query, NewsAPIKey);
   char data_char[];
   char news_data_char[];
   string header;
   if (WebRequest("GET", url, NULL, 0, data_char, news_data_char, header) == -1)
   {
      Print("Failed to get news data");
      
      return 0;
   }

    // 配列のサイズを取得
    int arraySize = ArraySize(news_data_char);

    // CharArrayToString 関数を使用して char 配列を string に変換
    string news_data = CharArrayToString(news_data_char, 0, arraySize - 1);

   // ニュースデータを解析し、買いまたは売りシグナルを判断する
   return AnalyzeSentiment(news_data);
}

void AnalyzeNewsAndTrade(string symbol, double sentiment_score)
{
    // パラメータ設定
    double lotSize = CalculateLotSize(RiskTolerance);
    int slippage = 10;
    double stopLoss = CalculateStopLoss(RiskTolerance);
    double takeProfit = CalculateTakeProfit(RiskTolerance);
    int trailingStop = CalculateTrailingStop(RiskTolerance);

    if (sentiment_score >= 0.2) // ポジティブなスコアがある場合
    {
        // 買いシグナル
        if (ExecuteMarketOrder(symbol, ORDER_TYPE_BUY, lotSize, slippage, stopLoss, takeProfit, trailingStop))
        {
            Print("Buy order executed successfully for ", symbol);
        }
    }
    else if (sentiment_score <= -0.2) // ネガティブなスコアがある場合
    {
        // 売りシグナル
        if (ExecuteMarketOrder(symbol, ORDER_TYPE_SELL, lotSize, slippage, stopLoss, takeProfit, trailingStop))
        {
            Print("Sell order executed successfully for ", symbol);
        }
    }
}

double CalculateLotSize(int riskTolerance)
{
    double baseLotSize = 0.01;
    double maxLotSize = 0.1;
    double step = (maxLotSize - baseLotSize) / 9;

    return baseLotSize + step * (riskTolerance - 1);
}

double CalculateStopLoss(int riskTolerance)
{
    double minStopLoss = 20 * Point();
    double maxStopLoss = 100 * Point();
    double step = (maxStopLoss - minStopLoss) / 9;

    return maxStopLoss - step * (riskTolerance - 1);
}

double CalculateTakeProfit(int riskTolerance)
{
    double minTakeProfit = 40 * Point();
    double maxTakeProfit = 200 * Point();
    double step = (maxTakeProfit - minTakeProfit) / 9;

    return minTakeProfit + step * (riskTolerance - 1);
}

int CalculateTrailingStop(int riskTolerance)
{
    int minTrailingStop = 10;
    int maxTrailingStop = 50;
    int step = (maxTrailingStop - minTrailingStop) / 9;

    return maxTrailingStop - step * (riskTolerance - 1);
}

bool ExecuteMarketOrder(string symbol, int operation, double lotSize, int slippage, double stopLoss, double takeProfit, int trailingStop)
{
    // オーダー処理を実装します。
    // オーダー処理後、トレーリングストップが設定されている場合、トレーリングストップを適用します。
    MqlTradeRequest request;
    MqlTradeResult result;

    ZeroMemory(request);

    request.action = TRADE_ACTION_DEAL;
    request.symbol = symbol;
    request.volume = lotSize;
    request.type = operation;
    request.price = operation == ORDER_TYPE_BUY ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);
    request.sl = stopLoss;
    request.tp = takeProfit;
    request.deviation = slippage;
    request.magic = 0;
    request.type_filling = ORDER_FILLING_RETURN;

    if (!OrderSend(request, result))
    {
        Print("OrderSend failed with error: ", GetLastError());
        return false;
    }

    // オーダー処理が成功した場合、トレーリングストップを適用する（設定されている場合）
    if (trailingStop > 0)
    {
        ulong ticket = result.order;
        MqlTradeRequest modifyRequest;
        MqlTradeResult modifyResult;

        ZeroMemory(modifyRequest);

        modifyRequest.action = TRADE_ACTION_SLTP;
        modifyRequest.order = ticket;
        modifyRequest.type = operation;

        if (operation == ORDER_TYPE_BUY)
        {
            double currentAsk = SymbolInfoDouble(symbol, SYMBOL_ASK);
            modifyRequest.sl = currentAsk - trailingStop * Point();
            modifyRequest.tp = takeProfit;
        }
        else
        {
            double currentBid = SymbolInfoDouble(symbol, SYMBOL_BID);
            modifyRequest.sl = currentBid + trailingStop * Point();
            modifyRequest.tp = takeProfit;
        }

        if (!OrderSend(modifyRequest, modifyResult))
        {
            Print("Failed to modify order with error: ", GetLastError());
            return false;
        }
    }

    return true;
}

//+------------------------------------------------------------------+
//| ニュースタイトルの感情分析 |
//+------------------------------------------------------------------+
double AnalyzeSentiment(string news_title)
{
    // リクエストボディを作成
    string request_body = "{\"document\":{\"type\":\"PLAIN_TEXT\",\"content\":\"" + news_title + "\"}}";
    char request_body_char[];
    
    // string型からchar[]型への変換
    StringToCharArray(request_body, request_body_char);

    // WebRequest()を使ってAPIからデータを取得
    char result[];
    string headers;
    int res = WebRequest("POST", GOOGLE_CLOUD_NLP_API_URL, "Content-Type: application/json", 0, request_body_char, result, headers);
    if (res == -1)
    {
        Print("WebRequest failed. Error code: ", GetLastError());
        return 0.0;
    }

    string result_string = CharArrayToString(result);
    
    // JSONデータを解析
    CJAVal jsRoot;
    if (!jsRoot.Deserialize(result_string))
    {
        Print("JSON deserialization failed");
        return 0.0;
    }

    // 感情分析のスコアを取得
    // string sentiment_score_str = jsRoot.At("documentSentiment").At("score").AsString();
    CJAVal documentSentiment = jsRoot["documentSentiment"];
    CJAVal score = documentSentiment["score"];
    double sentiment_score = StringToDouble(score.ToStr());

    return sentiment_score;
}

int WeeksBetween(datetime time1, datetime time2)
{
    return (int)(MathAbs(time1 - time2) / 86400 / 7);
}

//+------------------------------------------------------------------+
//| Get economic events from the calendar |
//+------------------------------------------------------------------+
void GetEconomicEvents()
{
   // 経済カレンダーから経済イベントを取得し、EconomicEvents[]配列に格納します。
   MqlCalendarValue events[];
   datetime from_time = TimeCurrent();
   datetime to_time = from_time + 7 * 86400; // 1週間後

   int total_events = CalendarValueHistory(events, from_time, to_time, NULL, "JPY");

   if (total_events <= 0)
   {
      Print("Failed to get economic events");
      return;
   }

   ArrayResize(EconomicEvents, total_events);

   for (int i = 0; i < total_events; i++)
   {
      EconomicEvents[i].time = events[i].time;
      EconomicEvents[i].currency = events[i].currency;
      EconomicEvents[i].description = events[i].description;
   }
}
