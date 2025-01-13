classdef PairStrategy < mclasses.strategy.LFBaseStrategy
    properties(Access = public)
        pairsignals;   % 信号内容
        open_bound;  % 开仓界限
        close_bound;  % close界限
        maxNumPairs;  % 最大可持有的交易对数量
        maxLoss;   % 用于止损的最大允许亏损值
        stopTradePeriod; % 避免在关闭后迅速购买的静默
        signalInitialized;  % 初始化标记        
        currStockPairs;  % 当前持有的交易对，是一个列表，每个元素包括两只股票代码
        currPairsInfo;  % 当前交易对列表,包含这一pair的各种信
        stopTradeLabel;   % 由于静默期，一段时间内不会再选择的股票                    
        numFigures;  % 绘制图表以查看结果的计数
            
        
    end
    
    methods
        function obj = PairStrategy(container, name)
        % PairStrategy - 构造函数用于初始化 PairStrategy 类的实例。
        %
        % 输入参数:
        %   container - 从 LFBaseStrategy 继承的容器对象。
        %   name - 策略的名称。
        %
        % 输出参数:
        %   obj - 初始化后的 PairStrategy 类实例。
        %
        % 描述:
        %   这个构造函数用于创建 PairStrategy 类的实例，它继承自 LFBaseStrategy 类。构造函数负责初始化类的各种属性和计数器，以及定义策略的初始状态。

            obj@mclasses.strategy.LFBaseStrategy(container, name);
            obj.open_bound = 1.5;
            obj.close_bound = 1.5;
            obj.maxNumPairs = 5;
            obj.maxLoss = -0.1;
            obj.stopTradePeriod = 5;
            obj.signalInitialized = 0;                       
            obj.currStockPairs = 0;  
            obj.currPairsInfo = cell(0);
            obj.stopTradeLabel = 0;                                                                    
            obj.numFigures = 10;
        end
   
        function [orderList , delayList] = generateOrders(obj, currDate, ~)
        % generateOrders - 生成每日交易对订单列表及延迟列表的函数。
        %
        % 输入参数:
        %   obj - 类的实例对象。
        %   currDate - 今天的日期索引。
        %
        % 输出参数:
        %   orderList - 包含我们持有的交易对列表。
        %   delayList - 一个与orderList相同大小的列表，填充为1。
        %
        % 描述:
        %   这个函数负责生成每日的交易对订单列表和延迟列表。函数首先检查信号是否已初始化，如果未初始化，则进行初始化。然后，它获取当前日期的交易对信号，并更新已有交易对的相关信息，包括关闭由于止损或其他原因的旧交易对，以及开立新交易对。最后，它构建orderList，其中包括要交易的订单，同时构建delayList，以确保其与orderList具有相同的大小。
        
        % 以下是该函数的详细执行步骤：
        %
        % 1. 检查信号是否已初始化，如果未初始化，进行初始化，并准备相关属性和数据结构。
        % 2. 获取当前日期的交易对信号，这通常包括确定哪些交易对需要进行交易操作。
        % 3. 更新已有交易对的相关信息，包括关闭那些由于止损或其他原因需要关闭的旧交易对。
        % 4. 确定要开立的新交易对。
        % 5. 构建orderList，其中包括要交易的订单，同时构建delayList以确保其与orderList具有相同的大小。
        
        % 函数返回orderList，它包含要进行交易的订单，以及delayList，它是一个与orderList相同大小的列表，填充为1，用于表示每个订单的延迟状态。

            orderList = [];
            
            % 如果信号未初始化，执行初始化操作
            if not(obj.signalInitialized)
               obj.pairsignals = PairSignal(currDate);  
               obj.pairsignals.CalPairHistory;
               obj.signalInitialized = 1; % 这一次的初始化操作只会执行一次
               obj.pairsignals.PairResult(currDate);
               obj.currStockPairs = obj.pairsignals.signalParameters(:, :, 1, 1) * 0; 
               obj.stopTradeLabel = obj.pairsignals.signalParameters(:, :, 1, 1) * 0 - 1; 
            end
            
            % 获取当前日期的交易对信号
            obj.pairsignals.PairResult(currDate);            
            % 更新已有交易对的相关信息
            obj.recordDailyPnl(currDate);            
            % 获取需要关闭的旧交易对
            [longOrder1, shortOrder1] = obj.closeConditions(currDate);  % 因为是关闭pair，因此要平的既可能是多头，也可能是空头      
            % 获取新的交易对
            [longOrder2, shortOrder2] = obj.openConditions(currDate);  % 因为是开启pair，因此要平的既可能是多头，也可能是空头           
            % 构建订单列表
            order = {shortOrder1, shortOrder2, longOrder1, longOrder2};         
            % 更新止损标签
            obj.stopTradeLabel = obj.stopTradeLabel - 1;         
            % 合并订单到orderList
            for i = 1:4
               if ~isempty(order{i}.assetCode)
                   orderList = [orderList, order{i}];
               end
            end
            
            % 计算订单数量，用于生成delayList
            [~, orderCount] = size(orderList);
            
            % 生成delayList，保证其与orderList大小一致
            delayList = ones(1, orderCount);
        end


         % 对预期收益进行排序，从小到大
        function bubbleSort(obj)
            len = length(obj.currPairsInfo);
            if len>2
                for i = 1:len
                    for j = 1:len-1
                        % 如果当前交易对的预期收益大于下一个交易对的预期收益
                        if obj.currPairsInfo{1, j}.expectReturn > obj.currPairsInfo{1, j+1}.expectReturn
                            % 交换两个交易对的位置
                            tools = obj.currPairsInfo{1, j+1};
                            obj.currPairsInfo{1, j+1} = obj.currPairsInfo{1, j};
                            obj.currPairsInfo{1, j} = tools;
                        end
                    end
                end
            end
        end

        function [longtOrder, shortOrder] = closeConditions(obj, currDate)
        % closeConditions - 检查当前交易对列表的函数，决定是否关闭交易对及其原因。
        %
        % 输入参数:
        %   obj - 类的实例对象。
        %   currDate - 当前日期的索引。
        %
        % 输出参数:
        %   longtOrder - 包含要执行的买入操作的订单列表。
        %   shortOrder - 包含要执行的卖出操作的订单列表。
        %
        % 描述:
        %   这个函数用于检查当前交易对列表，决定是否关闭交易对以及关闭的原因。函数首先获取当前日期的信号数据，并从中提取当前的 Z 分数和价差数值。接着，它检查每个交易对的条件，包括止损、协整性失败、以及停止盈利条件。如果某个交易对符合这些条件，函数将关闭该交易对，同时记录关闭的原因。最后，函数构建longtOrder和shortOrder，以包含要执行的买入和卖出操作的订单。
        %
        % 函数执行步骤：
        % 1. 获取当前日期的信号数据中的 Z 分数和价差数值。
        % 2. 遍历当前交易对列表，对于每个交易对执行以下步骤：
        %    a. 检查是否需要因止损而关闭交易对，记录关闭的原因。
        %    b. 检查协整性是否失败，如果失败，记录关闭的原因。
        %    c. 检查是否需要因停止盈利而关闭交易对，记录关闭的原因。
        %    d. 如果需要关闭交易对，执行关闭操作，同时将该交易对从列表中移除。
        %    e. 如果不需要关闭交易对，将其保留在列表中。
        % 3. 根据新的交易对列表构建买入操作的longtOrder和卖出操作的shortOrder。
        
        % 函数返回longtOrder和shortOrder，它们分别包含要执行的买入和卖出操作的订单，包括资产代码、数量、价格类型等信息。
            
            % 获取信号参数和市场数据
            currValidity = obj.pairsignals.signalParameters(:, :, end, 1);
            aggregatedDataStruct = obj.marketData.aggregatedDataStruct;
            dateLoc = find([obj.pairsignals.dateList{:, 1}] == currDate);
            close_day = obj.pairsignals.dateList{dateLoc+1, 1};

            % 初始化新的交易对列表
            newTrades = {};
            
            % 初始化用于记录持仓股票的信息
            longwindTicker = {};
            longQuant = [];
            shortwindTicker = {};
            shortQuant = [];
            
            % 获取当前交易对的相关信息
            for i = 1:length(obj.currPairsInfo)
                x1 = find(ismember(obj.pairsignals.stock_location, obj.currPairsInfo{1, i}.stock_A));
                x2 = find(ismember(obj.pairsignals.stock_location, obj.currPairsInfo{1, i}.stock_B));
                sign = false;

                % 获取当前交易对的相关信息
                stock_A = obj.currPairsInfo{1, i}.stock_A;
                stock_APrice = aggregatedDataStruct.stock.properties.fwd_close(dateLoc, stock_A);
                windTickers1 = aggregatedDataStruct.stock.description.tickers.windTicker(stock_A);  % wind股票代码

                stock_B = obj.currPairsInfo{1, i}.stock_B;                   
                stock_BPrice = aggregatedDataStruct.stock.properties.fwd_close(dateLoc, stock_B);                
                windTickers2 = aggregatedDataStruct.stock.description.tickers.windTicker(stock_B);

                pairPrice = stock_APrice-stock_BPrice*obj.currPairsInfo{1, i}.beta-obj.currPairsInfo{1, i}.alpha;
               
                if close_day > obj.currPairsInfo{1, i}.openDate  % 不能当天close    
                    Meann = obj.currPairsInfo{1, i}.mean;
                    profitCloseBound = obj.close_bound* obj.currPairsInfo{1, i}.sigma;
                    % 三个关闭仓位的条件
                    if (obj.currPairsInfo{1, i}.PnL < obj.maxLoss)
                        % 止损
                        if obj.numFigures>0
                            obj.specificPairPlot(obj.currPairsInfo{1, i}, 'Stop Loss', close_day)
                            obj.numFigures = obj.numFigures-1;
                        end                    
                        % 设置静默期
                        obj.stopTradeLabel(x1, x2) = obj.stopTradePeriod;
                        sign = true;                  
                    end
                      
                    label = 0;
                    if obj.currPairsInfo{1, i}.openZScore>0
                        label = 1;
                    elseif obj.currPairsInfo{1, i}.openZScore<0
                        label = -1;
                    end
                    if  -(pairPrice - Meann) * label > profitCloseBound                       
                        % 止盈
                        if obj.numFigures>0
                            obj.specificPairPlot(obj.currPairsInfo{1, i}, 'Stop Profit', close_day)
                            obj.numFigures = obj.numFigures-1;
                        end
                        
                        sign = true;
                    end
                    
                    
                    
                    if currValidity(x1, x2) ~= 1    
                        % 不满足协整平稳性
                        obj.stopTradeLabel(x1, x2) = obj.stopTradePeriod;                  
                        sign = true;
                    end
                    
                    if sign == true
                        % 关闭仓位
                        obj.currStockPairs(x1, :) = 0;  
                        obj.currStockPairs(:, x2) = 0;   
                        
                        if obj.currPairsInfo{1, i}.stock_APosition<0
                            longwindTicker{length(longwindTicker)+1} = windTickers1{1};
                            longQuant = [longQuant, 0];  % The target position change to 0 after closing
                        else
                            shortwindTicker{length(shortwindTicker)+1} = windTickers1{1};
                            shortQuant = [shortQuant, 0];
                        end
    
                        if obj.currPairsInfo{1, i}.stock_BPosition<0
                            longwindTicker{length(longwindTicker)+1} = windTickers2{1};
                            longQuant = [longQuant, 0];
                        else
                            shortwindTicker{length(shortwindTicker)+1} = windTickers2{1};
                            shortQuant = [shortQuant, 0];
                        end        
                    else
                        % 若不需要关闭，记录该交易对
                        newTrades{1, length(newTrades)+1} = obj.currPairsInfo{1, i};   
                   end            
                end
            end

            % 保存更新后的交易对列表
            obj.currPairsInfo = newTrades;  
            
            % 构建买入订单  
            longtOrder.operate = mclasses.asset.BaseAsset.ADJUST_LONG;
            longtOrder.account = obj.accounts('stockAccount');
            longtOrder.price = 'close';
            longtOrder.assetCode = longwindTicker;
            longtOrder.quantity = longQuant;
               
            % 构建卖出订单
            shortOrder.operate = mclasses.asset.BaseAsset.ADJUST_SHORT;
            shortOrder.account = obj.accounts('stockAccount');
            shortOrder.price = 'open';
            shortOrder.assetCode =  shortwindTicker;
            shortOrder.quantity = shortQuant;           
        end
        
        function recordDailyPnl(obj, currDate)
        % recordDailyPnl - 每天更新盈亏（PNL）并准备更改交易对
        
        % 输入参数:
        %   obj - 类的实例对象。
        %   currDate - 当前日期的索引。
        
        % 返回值:
        %   无返回值，但会更新实例对象中的交易对盈亏信息。
        
        % 描述:
        %   这个函数用于每天更新盈亏（PNL）并准备更改交易对。函数会计算当前持有交易对的盈亏情况，并更新实例对象中的交易对盈亏信息。为了计算盈亏，函数会使用当天的股票价格和交易对开仓时的价格。然后，函数会将计算的盈亏信息存储在交易对信息列表中。
        
        % 函数执行步骤：
        % 1. 获取当天的股票价格和交易对开仓时的价格。
        % 2. 计算当前持有交易对的盈亏情况。
        % 3. 更新实例对象中的交易对盈亏信息。
            % 获取聚合数据结构和当前日期的索引
            aggregatedDataStruct = obj.marketData.aggregatedDataStruct;
            dateLoc = find([obj.pairsignals.dateList{:, 1}] == currDate);
            
            % 遍历所有当前交易对
            for i = 1:length(obj.currPairsInfo)
                % 获取当前交易对的开仓日期的索引
                opendateLoc = find([obj.pairsignals.dateList{:, 1}] == obj.currPairsInfo{1, i}.openDate);
                
                % 获取当前交易对的股票 A 和股票 B
                stock_A = obj.currPairsInfo{1, i}.stock_A;
                stock_B = obj.currPairsInfo{1, i}.stock_B;
                
                % 获取当日的股票 A 和股票 B 的收盘价
                stock_APrice = aggregatedDataStruct.stock.properties.close(dateLoc, stock_A);  % 这里要用实际值，而不是fwd_close ZX
                stock_BPrice = aggregatedDataStruct.stock.properties.close(dateLoc, stock_B);
                
                % 获取开仓日的股票 A 和股票 B 的开盘价
                originPrice1 = aggregatedDataStruct.stock.properties.open(opendateLoc, stock_A);
                originPrice2 = aggregatedDataStruct.stock.properties.open(opendateLoc, stock_B);
                
                % 计算交易对的 PNL（利润与损失）
                obj.currPairsInfo{1, i}.PnL = ((stock_APrice - originPrice1) * obj.currPairsInfo{1, i}.stock_APosition ...
                    + (stock_BPrice - originPrice2) * obj.currPairsInfo{1, i}.stock_BPosition) ...
                    / (abs(originPrice1 * obj.currPairsInfo{1, i}.stock_APosition) ...
                    + abs(originPrice2 * obj.currPairsInfo{1, i}.stock_BPosition));
            end
        end

        function [longOrder, shortOrder] = openConditions(obj, currDate)
        % openConditions - 根据策略条件执行开仓操作的函数。
        %
        % 输入参数:
        %   obj - 类的实例对象。
        %   currDate - 当前日期的索引。
        %
        % 输出参数:
        %   longOrder - 包含要执行的买入操作的订单列表。
        %   shortOrder - 包含要执行的卖出操作的订单列表。
        %
        % 描述:
        %   这个函数根据策略条件执行开仓操作。函数首先获取当前日期的信号数据，然后根据策略条件计算每对交易对的期望收益、有效性和 Z 分数等相关参数。接着，它筛选出最具潜力的交易对，并执行买入操作。在执行买入操作之前，函数会检查已持有的交易对，如果需要，会先执行卖出操作以腾出资金。最后，函数构建longOrder和shortOrder，以包含要执行的买入和卖出操作的订单。
        %
        % 函数执行步骤：
        % 1. 获取当前日期的信号数据，包括期望收益、有效性和 Z 分数。
        % 2. 筛选出最具潜力的交易对，计算其买入方向和相关参数，执行买入操作。
        % 3. 如果已持有的交易对数量超过最大允许数量，根据策略条件执行卖出操作以腾出资金。
        % 4. 为每个执行的买入和卖出操作构建订单，包括资产代码、数量、价格类型等信息。
        % 5. 返回longOrder和shortOrder，以包含要执行的买入和卖出操作的订单。
            % 计算当天的日期索引
            dateLoc = find([obj.pairsignals.dateList{:, 1}] == currDate);
            
            % 获取信号相关的期望回报，有效性和z分数
            currentExpect = obj.pairsignals.signalParameters(:, :, end, 4);
            currValidity = obj.pairsignals.signalParameters(:, :, end, 1);    
            currentZscore_abs =  abs(obj.pairsignals.signalParameters(:, :, end, 2));
            
            % 可行的配对交易
            asset_available = (~obj.currStockPairs).*(obj.stopTradeLabel < 0);
            asset_quality = currValidity .* currentExpect .* (currentZscore_abs > obj.open_bound);
            availableExpect = asset_quality .* asset_available;
            
            % 初始化用于记录买入和卖出交易对的列表
            longwindTicker = {};
            longQuant = [];
            shortwindTicker = {};
            shortQuant = [];
            listLength = length(obj.currPairsInfo);  % 现在持有的pair数量
            waitLong = {};
            
            % 寻找期望回报最大的交易对
            for i = 1:obj.maxNumPairs
                maxEr = max(max(availableExpect)); 
                [x, y] = find(availableExpect == maxEr);
                
                if maxEr > 0
                    stock_A = obj.pairsignals.stock_location(x);
                    stock_B = obj.pairsignals.stock_location(y);   % 获取数据库中的股票索引
                    
                    % 记录买入和卖出方向
                    stock_APosition = -obj.pairsignals.signalParameters(x, y, end, 2) / abs(obj.pairsignals.signalParameters(x, y, end, 2));
                    stock_BPosition = obj.pairsignals.signalParameters(x, y, end, 7) / abs(obj.pairsignals.signalParameters(x, y, end, 7)) ...
                        * obj.pairsignals.signalParameters(x, y, end, 2) / abs(obj.pairsignals.signalParameters(x, y, end, 2)); 
            
                    openCost = 0;
                    openZScore = obj.pairsignals.signalParameters(x, y, end, 2);
                    PnL = 0;
                    openDate = obj.pairsignals.dateList{dateLoc+1, 1};   % 使用下一天的数据
                    beta = obj.pairsignals.signalParameters(x, y, end, 7);
                    alpha = obj.pairsignals.signalParameters(x, y, end, 6);
                    sigma = obj.pairsignals.signalParameters(x, y, end, 8);
                    res_mean = obj.pairsignals.signalParameters(x, y, end, 9);
                    
                    newStruct = struct('stock_A', stock_A, 'stock_B', stock_B, 'stock_APosition', stock_APosition, 'stock_BPosition', ...
                        stock_BPosition, 'openCost', openCost, 'openZScore', openZScore, 'PnL', PnL, 'openDate', openDate, ...
                        'expectReturn', maxEr, 'beta', beta, 'alpha', alpha, 'sigma', sigma, 'mean', res_mean);
                    
                    obj.bubbleSort();  % 根据条件排序
                    
                    if listLength < obj.maxNumPairs
                        % 如果当前交易对数量小于最大允许交易对数量，直接买入
                        waitLong{1, length(waitLong) + 1} = newStruct; % 记录新的交易对
                        listLength = listLength + 1;
                    else
                        if newStruct.expectReturn > obj.currPairsInfo{1, 1}.expectReturn
                            if obj.numFigures > 0
                                obj.specificPairPlot(obj.currPairsInfo{1, 1}, 'Change Position', currDate);
                                obj.numFigures = obj.numFigures - 1;
                            end
                            [longwindTicker, longQuant, shortwindTicker, shortQuant] = obj.conductClose(obj.currPairsInfo{1, 1}, longwindTicker, longQuant, shortwindTicker, shortQuant, currDate);
                            
                            waitLong{1, length(waitLong) + 1} = newStruct;     % 记录交易对，并保持长度不变
                        end
                    end
                    % 同一支股票一天只开仓一次
                    availableExpect(x, :) = 0;
                    availableExpect(:, y) = 0;
                else
                    break;
                end
            end
            
            % 计算每个交易对可用的资金
            everyCash = 0.8 * obj.calNetWorth(currDate) / obj.maxNumPairs;
            
            % 执行交易对的买入和卖出操作
            for j = 1:length(waitLong)
                [longwindTicker, longQuant, shortwindTicker, shortQuant] = obj.conductOpen(waitLong{1, j}, longwindTicker, longQuant, shortwindTicker, shortQuant, currDate, everyCash);
            end
            
            % 创建买入和卖出订单列表
            longOrder.operate = mclasses.asset.BaseAsset.ADJUST_LONG;
            longOrder.account = obj.accounts('stockAccount');
            longOrder.price = 'close';
            longOrder.assetCode = longwindTicker;
            longOrder.quantity = longQuant;
            
            shortOrder.operate = mclasses.asset.BaseAsset.ADJUST_SHORT;
            shortOrder.account = obj.accounts('stockAccount');
            shortOrder.price = 'open';
            shortOrder.assetCode = shortwindTicker;
            shortOrder.quantity = shortQuant;
        end

        function  [longwindTicker, longQuant, shortwindTicker, shortQuant] = conductOpen(obj, newStruct, longwindTicker, longQuant, shortwindTicker, shortQuant, currDate, everyCash)
        % conductOpen - 执行开仓操作的函数，计算购买新交易对所需的资金并执行交易。
        % 输入参数:
        %   obj - 类的实例对象。
        %   newStruct - 新的交易对信息。
        %   longwindTicker - 用于记录要购买的股票Wind指数代码的列表。
        %   longQuant - 用于跟踪购买的股票仓位数量的列表。
        %   shortwindTicker - 用于记录要卖出的股票Wind指数代码的列表。
        %   shortQuant - 用于跟踪卖出的股票仓位数量的列表。
        %   currDate - 当前日期的索引。
        %   everyCash - 分配给每个交易对的初始资金。
        
        % 输出参数:
        %   longwindTicker - 更新后的用于记录要购买的股票Wind指数代码的列表。
        %   longQuant - 更新后的用于跟踪购买的股票仓位数量的列表。
        %   shortwindTicker - 更新后的用于记录要卖出的股票Wind指数代码的列表。
        %   shortQuant - 更新后的用于跟踪卖出的股票仓位数量的列表。
        
        % 描述:
        %   这个函数执行开仓操作，计算购买新交易对所需的资金，并执行实际的交易操作。函数会根据新交易对的信息，包括股票代码、仓位、价格等，计算需要分配的资金，并计算实际购买的股票数量。然后，函数会更新用于记录要购买和卖出的股票Wind指数代码的列表和仓位数量列表。最后，函数将新的交易对信息添加到当前交易对信息列表中。
        
        % 函数执行步骤：
        % 1. 获取新交易对的信息，包括股票代码、仓位、价格等。
        % 2. 计算购买每只股票所需的资金，并计算实际购买的股票数量。
        % 3. 更新用于记录购买和卖出的股票Wind指数代码的列表和仓位数量列表。
        % 4. 将新的交易对信息添加到当前交易对信息列表中。
        
        % 函数返回更新后的股票Wind指数代码列表和仓位数量列表。
            
            % 获取聚合数据结构
            aggregatedDataStruct = obj.marketData.aggregatedDataStruct;
            
            % 查找当前日期在信号中的索引
            dateLoc = find([obj.pairsignals.dateList{:, 1}] == currDate);
            
            % 查找新交易对中stock_A和stock_B的索引
            x1 = find(ismember(obj.pairsignals.stock_location, newStruct.stock_A));
            x2 = find(ismember(obj.pairsignals.stock_location, newStruct.stock_B));
            
            % 更新当前交易对的持仓标志
            obj.currStockPairs(x1, :) = 1;
            obj.currStockPairs(:, x2) = 1;
            
            % 获取stock_A和stock_B的Wind标识
            windTickers1 = aggregatedDataStruct.stock.description.tickers.windTicker(newStruct.stock_A);
            windTickers2 = aggregatedDataStruct.stock.description.tickers.windTicker(newStruct.stock_B); % Wind股票代码
            
            % 获取stock_A和stock_B的远期价格
            fwdPrice1 = aggregatedDataStruct.stock.properties.fwd_close(dateLoc, newStruct.stock_A);
            fwdPrice2 = aggregatedDataStruct.stock.properties.fwd_close(dateLoc, newStruct.stock_B); % 价格用于确定需要投入的资金
            
            % 获取stock_A和stock_B的真实价格
            realPrice1 = aggregatedDataStruct.stock.properties.close(dateLoc, newStruct.stock_A);
            realPrice2 = aggregatedDataStruct.stock.properties.close(dateLoc, newStruct.stock_B); % 用于确定真实仓位的真实股价
            
            % 计算分配给stock_A和stock_B的资金
            cashFor1 = (1 * fwdPrice1) / (1 * fwdPrice1 + abs(newStruct.beta) * fwdPrice2) * everyCash;
            cashFor2 = (abs(newStruct.beta) * fwdPrice2) / (1 * fwdPrice1 + abs(newStruct.beta) * fwdPrice2) * everyCash;
         
            % 获取stock_A和stock_B的开仓成本价格
            costPrice1 = aggregatedDataStruct.stock.properties.open(dateLoc + 1, newStruct.stock_A);
            costPrice2 = aggregatedDataStruct.stock.properties.open(dateLoc + 1, newStruct.stock_B); % 使用次日开盘价计算成本
            
            % 计算交易后的真实stock_A和stock_B仓位
            realstock_APosition = floor(cashFor1 / costPrice1 / 100) * 100 * newStruct.stock_APosition;
            realstock_BPosition = floor(cashFor2 / costPrice2 / 100) * 100 * newStruct.stock_BPosition;  % 交易后的仓位
            
            % 更新新交易对的仓位(因为当前只知道close)
            newStruct.stock_APosition =  floor(cashFor1/realPrice1/100)*100*newStruct.stock_APosition;
            newStruct.stock_BPosition  = floor(cashFor2/realPrice2/100)*100*newStruct.stock_BPosition; 
          
            
            % 计算交易的成本
            newStruct.openCost = (abs(realstock_APosition) * costPrice1 + abs(realstock_BPosition) * costPrice2) * 2 / 10000; % 手续费设置为两万分之一
            
            % 根据新交易对的持仓方向更新持仓列表
            if newStruct.stock_APosition > 0
                longwindTicker{length(longwindTicker) + 1} = windTickers1{1};
                longQuant = [longQuant, newStruct.stock_APosition];
            else
                shortwindTicker{length(shortwindTicker) + 1} = windTickers1{1};
                shortQuant = [shortQuant, -newStruct.stock_APosition]; % 保存为正数
        
            end
        
            if newStruct.stock_BPosition > 0
                longwindTicker{length(longwindTicker) + 1} = windTickers2{1};
                longQuant = [longQuant, newStruct.stock_BPosition];
            else
                shortwindTicker{length(shortwindTicker) + 1} = windTickers2{1};
                shortQuant = [shortQuant, -newStruct.stock_BPosition];
        
            end
        
            % 将新交易对添加到当前交易对信息列表
            obj.currPairsInfo{1, length(obj.currPairsInfo) + 1} = newStruct;
        end

        function  [longwindTicker, longQuant, shortwindTicker, shortQuant] = conductClose(obj, closeStruct, longwindTicker, longQuant, shortwindTicker, shortQuant, currDate)
        % conductClose - 用于Change Position时，执行平仓操作的函数，记录仓位和目标仓位。

        % 输入参数:
        %   obj - 类的实例对象。
        %   closeStruct - 要平仓的交易对信息。
        %   longwindTicker - 用于记录要购买的股票Wind指数代码的列表。
        %   longQuant - 用于跟踪购买的股票仓位数量的列表。
        %   shortwindTicker - 用于记录要卖出的股票Wind指数代码的列表。
        %   shortQuant - 用于跟踪卖出的股票仓位数量的列表。    
        %   currDate - 当前日期的索引。
        
        % 输出参数:
        %   longwindTicker - 更新后的用于记录要购买的股票Wind指数代码的列表。
        %   longQuant - 更新后的用于跟踪购买的股票仓位数量的列表。
        %   shortwindTicker - 更新后的用于记录要卖出的股票Wind指数代码的列表。
        %   shortQuant - 更新后的用于跟踪卖出的股票仓位数量的列表。
        
        % 描述:
        %   这个函数执行平仓操作，记录仓位和目标仓位。函数会根据要平仓的交易对信息，包括股票代码、仓位等，记录平仓操作后的仓位状态和目标仓位。然后，函数会更新用于记录要购买和卖出的股票Wind指数代码的列表和仓位数量列表。最后，函数会删除当前交易对信息列表的第一个元素。
        
        % 函数执行步骤：
        % 1. 获取要平仓的交易对的信息，包括股票代码、仓位等。

            % 根据交易对结构中的股票A和股票B查找其在信号中的位置
            x1 = find(ismember(obj.pairsignals.stock_location, closeStruct.stock_A));
            x2 = find(ismember(obj.pairsignals.stock_location, closeStruct.stock_B));
            
            % 将交易对的仓位信息标记为0，表示平仓
            obj.currStockPairs(x1, :) = 0;
            obj.currStockPairs(:, x2) = 0;
            
            % 获取市场数据的聚合结构
            aggregatedDataStruct = obj.marketData.aggregatedDataStruct;
            
            % 获取股票A和股票B的Wind代码
            windTickers1 = aggregatedDataStruct.stock.description.tickers.windTicker(closeStruct.stock_A);
            windTickers2 = aggregatedDataStruct.stock.description.tickers.windTicker(closeStruct.stock_B);
            
            % 删除当前交易对信息列表中的第一个元素
            obj.currPairsInfo = {obj.currPairsInfo{2:end}};
            
            % 根据股票A的持仓方向，更新买入或卖出列表
            if closeStruct.stock_APosition < 0
                longwindTicker{length(longwindTicker)+1} = windTickers1{1};
                longQuant = [longQuant, 0];  % 目标持仓设置为0，表示平仓
            else
                shortwindTicker{length(shortwindTicker)+1} = windTickers1{1};
                shortQuant = [shortQuant, 0];
            end
            
            % 根据股票B的持仓方向，更新买入或卖出列表
            if closeStruct.stock_BPosition < 0
                longwindTicker{length(longwindTicker)+1} = windTickers2{1};
                longQuant = [longQuant, 0];
            else
                shortwindTicker{length(shortwindTicker)+1} = windTickers2{1};
                shortQuant = [shortQuant, 0];
            end
        end

        function specificPairPlot(obj, pairStruct, closeCause, endDate)

            aggregatedDataStruct = obj.marketData.aggregatedDataStruct;
            windName1 = aggregatedDataStruct.stock.description.tickers.shortName(pairStruct.stock_A);
            windName2 = aggregatedDataStruct.stock.description.tickers.shortName(pairStruct.stock_B);
            stockName1 = windName1{1};  % stock_A name
            stockName2 = windName2{1};  % stock_B name 
            
            startDate = pairStruct.openDate;
            
            % 留出空间绘制图片
            board_length = 2;      
            startDateIndex = find([obj.pairsignals.dateList{:, 1}] == startDate);
            startDateIndex_extend = startDateIndex-board_length;
            endDateIndex = find([obj.pairsignals.dateList{:, 1}] == endDate);
            endDateIndex_extend = endDateIndex+board_length;
            beta = pairStruct.beta;
            alpha = pairStruct.alpha;
            sigma = pairStruct.sigma;
            res_mean = pairStruct.mean;
            z_score = pairStruct.openZScore;

            % 股票对的价值
            fwdPrice1 = aggregatedDataStruct.stock.properties.fwd_close(startDateIndex_extend:endDateIndex_extend, pairStruct.stock_A);
            fwdPrice2 = aggregatedDataStruct.stock.properties.fwd_close(startDateIndex_extend:endDateIndex_extend, pairStruct.stock_B);
            portfolio_value = fwdPrice1-beta*fwdPrice2;   
            
            % 开仓时的上界
            shortout = alpha+res_mean+obj.open_bound*sigma;  
            longin = alpha+res_mean-obj.open_bound*sigma;
            % 开仓时的下界
            longout = alpha+res_mean+obj.close_bound*sigma; 
            shortin = alpha+res_mean-obj.close_bound*sigma; 
            % 均值
            Mean = alpha+res_mean;

            % 绘图
            figure
            dateList = [obj.pairsignals.dateList{:, 1}];
            xaxis = dateList(startDateIndex_extend:endDateIndex_extend);  
            plot(xaxis, portfolio_value, 'linestyle', '-', 'Color', 'black') 
            dateaxis('x', 17)
            
            % 均值、上界、下界
            line([xaxis(1), xaxis(end)], [Mean , Mean], 'linestyle', '--', 'Color', 'blue')
            text(xaxis(end), Mean, 'Mean', 'Color', 'blue')
            
            if z_score>0
                line([xaxis(1), xaxis(end)], [shortout, shortout], 'linestyle', '--', 'Color', 'magenta')
                text(xaxis(end), shortout, 'Upper', 'Color', 'magenta')
                line([xaxis(1), xaxis(end)], [shortin, shortin], 'linestyle', '--', 'Color', 'cyan')
                text(xaxis(end), shortin, 'Lower', 'Color', 'cyan')
    
                plottitle1 = [stockName1, stockName2, 'z_score>0'];
                plottitle2 = ['Close Condition: ', closeCause];
                title({plottitle1;plottitle2}) 
            else
                line([xaxis(1), xaxis(end)], [longout, longout], 'linestyle', '--', 'Color', 'magenta')
                text(xaxis(end), longout, 'Upper', 'Color', 'magenta')
                line([xaxis(1), xaxis(end)], [longin, longin], 'linestyle', '--', 'Color', 'cyan')
                text(xaxis(end), longin, 'Lower', 'Color', 'cyan')
    
                plottitle1 = [stockName1,' ', stockName2, 'z_score<0'];
                plottitle2 = ['Close Condition: ', closeCause];
                title({plottitle1;plottitle2}) 
            end

            
            % 开仓和平仓点
            ydata = get(gca, 'YLim');
            line([startDate, startDate], [min(ydata), max(ydata)], 'linestyle', '--', 'Color', 'red')
            text(startDate, max(ydata), 'Open Pair', 'Color', 'red')
            line([endDate, endDate], [min(ydata), max(ydata)], 'linestyle', '--', 'Color', 'green')
            text(endDate, max(ydata), 'Close Pair', 'Color', 'green')
        end

    end
end
        
       
       
