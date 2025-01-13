classdef PairSignal < handle  % 类用于实现配对交易信号的计算和管理
    properties(Access = public)
        dateNumIdx = []; %储存datenum格式的日期和对应位置的索引,两列
        startDate; % 起始日期
        RegBetaStore = []; % 存储beta的回归历史记录
        startDateIdx; % 起始日期在日期列表中的位置
        RegAlphaStore = []; % 存储alpha的回归历史记录
        % forwardPrices = []; % 存储未来价格
        
        stockNameCodeIdx = []; %储存string格式的股票名缩写和double格式的股票代码,以及对应位置的索引,cell
        closePrice = []; %储存全部股票的收盘价数据
        closePriceAdj = []; %储存全部股票的调整后收盘价,向前调整
        stockSelectedIdx = []; % 储存选中的股票的索引
        stockSelectedCode = []; % 储存选中的股票的代码,double
        stockSelectedCount = 0; % 储存选中的股票的总数
        pairsMatrix = []; % 股票对的logic矩阵,如果为1则说明这一对股票是需要的
        % 初始化 wr/ws 的值
        windowReg = 45;    % regression window
        windowSmooth = 20;    % smoothing window
%         stock_location; % 股票位置
%         stock_count; % 股票数量，即length(stock_location)做循环的边界
        signalParameters = zeros(1, 1, 1, 9) % X = zeros(sz1,…,szN) （返回由零组成的 sz1×…×szN 数组，其中 sz1,…,szN 指示每个维度的大小）
        propertyNameList =  {'validity', 'zScore', 'dislocation', 'expectedReturn', 'halfLife', 'alpha', 'beta','sigma','mean'};
        stockUniverse; % 格式obj.stockUniverse = [code, shortname]
        dateList; % 日期映射表，包含日期代码和实际日期的二维单元数组，大小为2210*2
        findWindowRegDone = 0;
    end
    
    methods(Access = private)
        function dateIdx = ConvertDatenumToDateIndex(obj,dateNum)
            %{
            将日期转换为对应的位置索引
            %}
            dateIdx = obj.dateNumIdx(:,2);
            dateIdx = dateIdx(obj.dateNumIdx(:,1)==dateNum);
        end

        function stkIdx = ConvertStkCodeToStkIndex(obj,stkCode)
            %{
            将股票代码转换为对应的位置索引
            Parameter:
                stkCode: 包含string格式的股票代码,列向量
            Return:
                stkIdx: 包含double格式的对应股票的位置索引,列向量
            %}
            stkIdx = cell2mat(obj.stkNameCodeIdx(:,3));
            stkIdx = stkIdx(obj.stkNameCodeIdx(:,2)==stkCode);
        end

        function stkIdx = ConvertStkNameToStkIndex(obj,stkName)
            %{
            将股票代码转换为对应的位置索引
            Parameter:
                stkName: 包含string格式的股票名缩写,列向量
            Return:
                stkIdx: 包含double格式的对应股票的位置索引,列向量
            %}
            stkIdx = obj.stkNameCodeIdx(:,3);
            stkIdx = stkIdx(obj.stkNameCodeIdx(:,1)==stkName);
        end

        function obj = FetchData(obj)
            %{
            获取数据并初始化
            %}
            % 获取市场数据
            marketData = mclasses.staticMarketData.BasicMarketLoader.getInstance(); % 创建marketdata实例
            generalData = marketData.getAggregatedDataStruct; % 获取实例中的AggregatedDataStruct
            load ('validPairs.mat','validPairs');
            % 初始化信息
            obj.dateNumIdx = [datenum(generalData.sharedInformation.allDateStr,'yyyymmdd'), (1:length(generalData.sharedInformation.allDateStr))'];
            stockCount = length(generalData.stock.description.tickers.officialTicker);
            obj.stockNameCodeIdx = cell(stockCount, 3);
            obj.stockNameCodeIdx(:, 1) = arrayfun(@(x) generalData.stock.description.tickers.shortName{x}, (1:stockCount)', 'UniformOutput', false);
            obj.stockNameCodeIdx(:, 2) = arrayfun(@(x) str2double(generalData.stock.description.tickers.officialTicker{x}), (1:stockCount)', 'UniformOutput', false);
            obj.stockNameCodeIdx(:, 3) = arrayfun(@(x) x, (1:stockCount)', 'UniformOutput', false);
            obj.closePrice = generalData.stock.properties.close;
            obj.closePriceAdj = generalData.stock.properties.fwd_close;
            % 初始化PairMatrix
            secondCol = cell2mat(obj.stockNameCodeIdx(:,2));
            thirdCol = cell2mat(obj.stockNameCodeIdx(:,3));
            obj.stockSelectedIdx = thirdCol(ismember(secondCol, [validPairs(:, 2); validPairs(:, 3)]));
            obj.stockSelectedCode = secondCol(obj.stockSelectedIdx);
            obj.stockSelectedCount = length(obj.stockSelectedIdx);
            obj.pairsMatrix = false(obj.stockSelectedCount,obj.stockSelectedCount);
            % 提取validPairs中的股票对,并将信息储存到pairsMatrix中
            for i = 1:obj.stockSelectedCount-1
                for j = i+1:obj.stockSelectedCount
                    for k = 1:length(validPairs)
                        if obj.stockSelectedCode(i) == validPairs(k,2) && obj.stockSelectedCode(j) == validPairs(k,3)
                            obj.pairsMatrix(i,j) = 1;
                        end
                        if obj.stockSelectedCode(j) == validPairs(k,2) && obj.stockSelectedCode(i) == validPairs(k,3)
                            obj.pairsMatrix(i,j) = 1;
                        end
                    end
                end
            end
        end


        function [alpha, beta, p, epsilon_vec] = LinearReg(obj,y,X)
            %{
            对两个向量进行线性回归
            Parameter:
                X: 自变量,向量
                y: 因变量,向量
            Return:
                alpha: 截距项的值
                beta: 斜率项的值
                p: beta的p值
                epsilon_vec: 残差的值,向量
            %}
            [b, ~, r, ~, stats] = regress(y, [ones(length(X), 1), X]);
            alpha = b(1);
            beta = b(2);
            epsilon_vec = r;
            p = stats(3);
        end
        
        function [alpha_vec, beta_vec, p_vec, epsilon_m] = LinearRegTimeSeries(obj,y,X,window)
            %{
             对两个时间序列进行线性回归,按照窗口大小随着时间的推移进行回归
             Parameter:
                priceOfStockSelected: 所选取的股票的价格序列矩阵
                startDate: 所使用的数据的开始日期
                endDate: 所使用的数据的结束日期
                windowForReg: 进行局部回归的时间窗口
             Return:
                alpha_vec: 截距项的值,向量
                beta_vec: 斜率项的值,向量
                p_vec: 对应beta的p值,向量
                epsilin_m: 对应残差的值,矩阵,不同的列表示不同的时间下window回归的结果
            %}
            y_len = length(y)-window;
            %初始化输出变量
            alpha_vec = nan(y_len,1);
            beta_vec = nan(y_len,1);
            p_vec = nan(y_len,1);
            epsilon_m = nan(window, y_len);
            %提取时间窗口,减少索引操作
            y_buffer = buffer(y, window, window-1);
            X_buffer = buffer(X, window, window-1);
            y_buffer = y_buffer(:,30:end);
            X_buffer = X_buffer(:,30:end);
            %遍历每个窗口进行回归
            for i = 1:size(y_buffer, 2)
                [alpha, beta, p, epsilon_vec] = obj.LinearReg(y_buffer(:, i), X_buffer(:, i));
                alpha_vec(i, :) = alpha;
                beta_vec(i, :) = beta;
                p_vec(i,:) = p;
                epsilon_m(:,i) = epsilon_vec;
            end
        end

        function obj = OptimizeWindowReg(obj, dateNumBeginHistory, dateNumEndHistory)
            %{
             找到最优的回归窗口,最优的目标为:平稳的协整的pairs数量;约束条件为:保证窗口长度大于所有满足局部条件(即在有效数据的80%个window中都保持协整)的pairs的halflife
            %}
            % 如果已经运行过一次,那么直接跳过
            if obj.findWindowRegDone == 1
                return
            end
            dataForWindows = zeros(length(90:5:300),3);  % 储存每个window得到的评价指标,
            halfLifeMax = 0;
            m = 1;
            % 遍历得到符合条件的window
            for window = 90:5:300
                pairsCointCount = 0;
                for i = 1:obj.stockSelectedCount-1
                    for j = i+1:obj.stockSelectedCount
                        if obj.pairsMatrix(i,j)==1
                            dateIdxBeginHistory= obj.ConvertDatenumToDateIndex(dateNumBeginHistory);
                            dateIdxEndHistory = obj.ConvertDatenumToDateIndex(dateNumEndHistory);
                            closePriceAdjStocki = obj.closePriceAdj(dateIdxBeginHistory:dateIdxEndHistory,obj.stockSelectedIdx(i));
                            closePriceAdjStockj = obj.closePriceAdj(dateIdxBeginHistory:dateIdxEndHistory,obj.stockSelectedIdx(j));
                            [~, ~, p_vec, epsilon_m]=obj.LinearRegTimeSeries(closePriceAdjStocki,closePriceAdjStockj,window);
                            
                            pairsCointWindowCount = 0;
                            for k = 1:size(epsilon_m,2)
                                [~, p] = adftest(epsilon_m(:,k));
                                % 只有协整的时候才进行OUcalibration
                                if p<=0.05 && p_vec(k)<=0.05
                                    pairsCointWindowCount = pairsCointWindowCount+1;
%                                     [~, ~, lambda] = OU_Calibrate_LS(epsilon_m(:), 1);
%                                     halfLife = 1/lambda;
%                                     if halfLife > halfLifeMax
%                                         halfLifeMax = halfLife;
%                                     end
                                end
                            end
                            if pairsCointWindowCount/size(epsilon_m,2) >= 0.8
                                pairsCointCount = pairsCointCount + 1;
                            end
                        end
                    end
                end
                dataForWindows(m,1) = window;
                dataForWindows(m,2) = halfLifeMax;
                dataForWindows(m,3) = pairsCointCount/sum(obj.pairsMatrix,'all');
                m = m+1;
            end
            condHalfLife = (dataForWindows(:,1)>=3*dataForWindows(:,2));
            windowSelected = [dataForWindows(condHalfLife,1),dataForWindows(condHalfLife,1)];
            % 找到最多的window
            windowBest = windowSelected((dataForWindows(:,3)==max(dataForWindows(:,3))),1);
            obj.windowReg = windowBest;
            fprintf('最符合标准的window长度为%d\n',windowBest);
            obj.findWindowRegDone = 1;
        end

        
        function stockFilter = FindPairsInSameIndustry(obj,industryInfo,industryIndex)
            %{
            寻找指定行业的股票索引
            %}
            stockFilter = (sum(industryInfo == industryIndex)>1);
        end

        function isInSameIndustry = IsPairsInSameIndustry(obj,industryInfo,stock1Index,stock2Index)
            %{
            判断两只股票是否在同一行业内
            %}
            isInSameIndustry = (industryInfo(stock1Index)==industryInfo(stock2Index));
        end


        function obj = FilterPairsCorrelatedAndPassADF(obj,startDateForRoughFinding,endDateForRoughFinding,threshold)
            %{
            使用指定时间内的股票的调整后收盘价,对所有股票进行回归,并对残差进行ADF检验,保留线性关系显著且通过ADF检验的股票对(即将不满足的对的pairMatrix对应位置设置为0)
            参数:
                startDateForRoughFinding:筛选所用的起始时间,datenum格式的日期
                endDateForRoughFinding:筛选所用的结束时间,datenum格式的日期
            %}
            if nargin <= 3
                threshold = 0.05;
            end
            %如果筛选时间超出范围,那么选取整个日期列表的起始和结尾
            if startDateForRoughFinding < obj.dateNumIdx(1,1)
                startDateForRoughFinding = obj.dateNumIdx(1,1);
            end
            if endDateForRoughFinding > obj.dateNumIdx(end,1)
                endDateForRoughFinding = obj.dateNumIdx(end,1);
            end
            startDateForRoughFindingInd= obj.ConvertDatenumToDateIndex(startDateForRoughFinding);
            endDateForRoughFindingInd = obj.ConvertDatenumToDateIndex(endDateForRoughFinding);
            
            closeAdjAllStockNeeded = obj.closePrice(startDateForRoughFindingInd:endDateForRoughFindingInd, obj.stockSelectedIdx);

            p_matrix = false(obj.stockSelectedCount, obj.stockSelectedCount);
            p_adf_matrix = false(obj.stockSelectedCount, obj.stockSelectedCount);

            % 如果是目标股票对,那么进行回归和ADF检验
            for i = 1:obj.stockSelectedCount-1
                for j = i+1:obj.stockSelectedCount
                    if obj.pairsMatrix(i,j) ~= 0
                        if sum(isnan(closeAdjAllStockNeeded(:,i)),'all')>0 || sum(isnan(closeAdjAllStockNeeded(:,j)),'all')>0
                            obj.pairsMatrix(i,:) = 0;
                            obj.pairsMatrix(:,j) = 0;
                            continue
                        end
                        [~, ~, p, epsilon_vec] = obj.LinearReg(closeAdjAllStockNeeded(:,i),closeAdjAllStockNeeded(:,j));
                        p_matrix(i,j) = p;   %保存的是第i只股票为因变量,第j只股票为自变量的对应p值
                        [~, p_adf_matrix(i,j)] = adftest(epsilon_vec);
                    end
                end
            end
            
            stockFilter = (p_matrix <= threshold & p_adf_matrix <= threshold);
            fprintf('有%d个pair没有通过检验\n', sum(stockFilter, 'all'));
            obj.pairsMatrix(stockFilter) = 0;
            fprintf('剩余%d个pair通过了测试\n',sum(obj.pairsMatrix,'all'));
        end
    end

    methods(Access = public)
        function obj = PairSignal(startDateCode)
            %{
            初始化实例
            Parameter: startDateCode (type: double)
            Return: obj
            %}
			
            obj.startDate = startDateCode;
            % 获取市场数据
            %             marketData = mclasses.staticMarketData.BasicMarketLoader.getInstance(); % 创建marketdata实例
            %             generalData = marketData.getAggregatedDataStruct; % 获取实例中的AggregatedDataStruct
            %             HS300_list_2019Janu = load ('C:\Users\27261\Desktop\3_Courses in PHBS\3_16_Software Engineer\Project\HS300_list_2019Janu.mat');
            %
            %             % 构建stock_location
            %             stockSectorFilter = generalData.stock.sectorClassification.levelOne == 11; % 选行业
            %
            %             % 查看行业内的股票数
            %             % numStocksMatchingCondition = sum(stockSectorFilter);
            %             % fprintf('Number of stocks meeting the condition: %d\n', numStocksMatchingCondition);
            %             stock_location = find(sum(stockSectorFilter) > 1);
            %             stock_location = stock_location(1:30);
            %             obj.stock_location = stock_location;
            %             obj.stock_count = length(stock_location);
            %
            
            %待删除             % 得到整个时间范围内,具有强相关性的股票对的逻辑索引矩阵
            %             stockFilterCorrStrong = obj.FindPairsCorrelatedStrongly(closeAdjAllStock,startDateForRoughFinding,endDateForRoughFinding,0.05);
            %             %       % 得到整个时间范围内,处于相同行业的股票对的逻辑索引矩阵
            %             %             stockFilterInSameIndustry = obj.IsPairsInSameIndustry();
            

            % 得到筛选后的股票索引

            %             % 将股票价格存储为forwardPrices
            %             obj.forwardPrices = generalData.stock.properties.fwd_close(:, stock_location);
            %             % 将股票名称和代码存储为stockUniverse
            %             code=generalData.stock.description.tickers.officialTicker(stock_location);
            %             shortname = generalData.stock.description.tickers.shortName(stock_location);
            %             obj.stockUniverse = [code, shortname]; % obj.stockUniverse｛i, 2｝返回其名称
            %             % 对于第i只股票，obj.stockUniverse｛i, 1｝返回其股票代码
            % 获取市场数据
            obj.FetchData();
            % 筛选具有强相关性并且残差通过ADF检验的股票对
            dateBeginHistory = datenum(2014,1,2);
            dateEndHistory = datenum(2018,12,28);
            obj.FilterPairsCorrelatedAndPassADF(dateBeginHistory,dateEndHistory);
            % 得到最优的window长度
            obj.OptimizeWindowReg(dateBeginHistory,dateEndHistory);
            % 
            % 

            %待删除             dateId = generalData.sharedInformation.allDates;
            %             realTradeDate = generalData.sharedInformation.allDateStr;
            %             dateId = num2cell(dateId);
            %             realTradeDate = cellstr(realTradeDate);
            %             obj.dateList = [dateId, realTradeDate];
            %             % 初始化 obj.startDateLocation
            %             obj.startDateIdx = find(cell2mat(obj.dateList(:, 1)) == obj.startDate);
        end
        

        function obj = CalPairHistory(obj)
            %{
            计算所有配对组合(ws-1)天的alpha和beta值 (before startDate)
            Parameter: obj
            Return: obj
            %}

            for stock1 = 1:1:obj.stock_count-1 % 通过嵌套的循环遍历所有的股票对
                for stock2 = stock1+1:1:obj.stock_count
                    for dateLocation = obj.startDateIdx - obj.windowSmooth + 1:1:obj.startDateIdx - 1 %获得足够的历史数据(regression window)用于回归分析
                        Y = obj.forwardPrices(dateLocation-obj.windowReg+1:dateLocation, stock1);
                        X = obj.forwardPrices(dateLocation-obj.windowReg+1:dateLocation, stock2);
                        % 计算Y和X中的 NaN 数量
                        YNaNNum = sum(isnan(Y));
                        XNaNNum = sum(isnan(X));
                        % 计算每个元素的出现次数
                        Y_stat = tabulate(Y);
                        X_stat = tabulate(X);
                        % 如果Y和X中存在NaN，或者stock1或stock2的价格在超过20%的时间段内没有变化，则将NaN填充到回归历史中，表示该股票对的 alpha 和 beta 无法计算
                        if YNaNNum+XNaNNum >= 1 || max(Y_stat(:, 3)) > 20|| max(X_stat(:, 3)) > 20
                            obj.RegAlphaStore(stock1, stock2, dateLocation) = NaN;
                            obj.RegBetaStore(stock1, stock2, dateLocation) = NaN;
                        else
                            % 如果价格数据中没有NaN值且股票价格变动符合要求，则进行多元线性回归分析。通过回归分析计算出alpha和beta的值，并在回归历史记录中相应位置存储这些值。
                            [b, ~, ~, ~, ~] = regress(Y, [ones(obj.windowReg, 1), X]);
                            obj.RegAlphaStore(stock1, stock2, dateLocation) = b(1);
                            obj.RegBetaStore(stock1, stock2, dateLocation) = b(2);
                            % obj.RegAlphaStore和obj.RegBetaStore存储了所有配对在起始日期之前的过去ws-1天的alpha和beta值
                        end
                    end
                end
            end
        end

        
        % 计算给定日期的股票参数值
        function obj = CalParameters(obj, stock1, stock2, dateCode, alpha, beta, residual)
            %{
            Parameter: 
                obj
                stock1: double, 对应行业中某只股票的index
                stock2: double
                datecode: double, 开始日期
                alpha: double, 回归常数项
                beta: double, 回归系数
                residual: double, 回归残差
            Return: 
                obj
            %}

            % 计算日期位置
            dateLocation = find(cell2mat(obj.dateList(:, 1)) == dateCode);
            stockPrice1 = obj.forwardPrices(dateLocation, stock1);
            stockPrice2 = obj.forwardPrices(dateLocation, stock2);
            % 计算 dislocation
            dislocation = stockPrice1 - beta * stockPrice2 - alpha;
            obj.signalParameters(stock1, stock2, dateLocation, 3) = dislocation;
            % 计算 z-score
            zScore = (dislocation-mean(residual))/std(residual);
            obj.signalParameters(stock1, stock2, dateLocation, 2) = zScore;
            % 计算 halflife
            [~, ~, lambda] = OU_Calibrate_LS(residual, 1);
            halfLife = 1/lambda;

            obj.signalParameters(stock1, stock2, dateLocation,  5) = halfLife;  
            % 计算 trading cost
            tradingCost = stockPrice1+abs(beta)*stockPrice2;
            % 计算 expected return
            if halfLife > 0
                expectedReturn = abs(dislocation)/(2*tradingCost)/(halfLife/256);
            else
                expectedReturn = 0;
            end
            obj.signalParameters(stock1, stock2, dateLocation, 4) = expectedReturn;
            % 计算 entry point boundary
            sigma = std(residual);
            obj.signalParameters(stock1, stock2, dateLocation, 8) = sigma;
            obj.signalParameters(stock1, stock2, dateLocation, 6) = alpha;
            obj.signalParameters(stock1, stock2, dateLocation, 7) = beta;
            obj.signalParameters(stock1, stock2, dateLocation, 9) = mean(residual);
        end

        function obj = PairResult(obj, dateCode) % 生成交易信号并计算股票对（stock pairs）的参数和指标
            %{
            Parameter: 
                obj
                dateCode: double, 开始日期
            Return: 
                obj
            %}

            % 获取日期位置
            dateLocation = find(cell2mat(obj.dateList(:, 1)) == dateCode);
            for stock1 = 1:1:obj.stock_count-1
                for stock2 = stock1+1:1:obj.stock_count
                    % 计算当天的alpha和beta，并将它们存储到回归历史中
                    Y = obj.forwardPrices(dateLocation-obj.windowReg+1:dateLocation, stock1);
                    X = obj.forwardPrices(dateLocation-obj.windowReg+1:dateLocation, stock2);
                     % 计算Y和X中的 NaN 数量
                    YNaNNum = sum(isnan(Y));
                    XNaNNum = sum(isnan(X));
                    % 计算每个元素的出现次数
                    Y_stat = tabulate(Y);
                    X_stat = tabulate(X);
                    % 如果Y和X中存在NaN，或者stock1或stock2的价格在超过20%的时间段内没有变化，则将NaN填充到回归历史中，表示该股票对的 alpha 和 beta 无法计算
                    if YNaNNum+XNaNNum >= 1 || max(Y_stat(:, 3)) > 20 || max(X_stat(:, 3)) > 20
                        obj.RegAlphaStore(stock1, stock2, dateLocation) = NaN;
                        obj.RegBetaStore(stock1, stock2, dateLocation) = NaN;
                    else
                         % 多元线性回归
                        [b, ~, ~, ~, ~] = regress(Y, [ones(obj.windowReg, 1), X]);
                        obj.RegAlphaStore(stock1, stock2, dateLocation) = b(1);
                        obj.RegBetaStore(stock1, stock2, dateLocation) = b(2); 
                    end

                    alphaNaNNum = sum(isnan(obj.RegAlphaStore(stock1, stock2, dateLocation - obj.windowSmooth + 1:dateLocation)));
                    betaNaNNum = sum(isnan(obj.RegBetaStore(stock1, stock2, dateLocation - obj.windowSmooth + 1:dateLocation)));
                    % 如果回归历史中存在NaN，则这个pair无效，并将所有参数设置为0。
                    stockPrice1 = obj.forwardPrices(dateLocation - obj.windowSmooth + 1:dateLocation, stock1);
                    stockPrice2 = obj.forwardPrices(dateLocation - obj.windowSmooth + 1:dateLocation, stock2);
                    stock_stat1 = tabulate(stockPrice1);
                    stock_stat2 = tabulate(stockPrice2);
                    if alphaNaNNum+betaNaNNum >= 1 || max(stock_stat1(:, 3)) > 30 || max(stock_stat2(:, 3)) > 30
                        obj.signalParameters(stock1, stock2, dateLocation, :) = zeros(9, 1);
                    else
                        alphaSeries = zeros(obj.windowSmooth, 1);
                        betaSeries = zeros(obj.windowSmooth, 1);
                        alphaSeries(:, 1) = obj.RegAlphaStore(stock1, stock2, dateLocation - obj.windowSmooth + 1:dateLocation);
                        betaSeries(:, 1) = obj.RegBetaStore(stock1, stock2, dateLocation - obj.windowSmooth + 1:dateLocation);
                        % 通过 Wilcoxon 秩和检验判断 alpha 和 beta 分布是否发生变化
                        wilNum = floor(obj.windowSmooth/2);
                        % 检查alpha和beta的分布是否发生变化
                        [~, h_alpha] = ranksum(alphaSeries(1:wilNum, 1), alphaSeries(obj.windowSmooth-wilNum+1:obj.windowSmooth, 1));
                        [~, h_beta] = ranksum(betaSeries(1:wilNum, 1), betaSeries(obj.windowSmooth-wilNum+1:obj.windowSmooth, 1));
                        % 如果 alpha 或 beta 分布发生变化，则将该股票对的所有参数设为零
                        if (h_alpha == 1) || (h_beta == 1)
                            obj.signalParameters(stock1, stock2, dateLocation, :) = zeros(9, 1);
                        else
                            % 否则，计算回归历史窗口内的平均 alpha 和 beta 值
                            averageAlpha = mean(obj.RegAlphaStore(stock1, stock2, dateLocation - obj.windowSmooth + 1:dateLocation));
                            averageBeta = mean(obj.RegBetaStore(stock1, stock2, dateLocation - obj.windowSmooth + 1:dateLocation));
                            residual = stockPrice1 - averageAlpha - averageBeta*stockPrice2;
                            % 对残差进行平稳性检验（Augmented Dickey-Fuller Test）
                            [~, p] = adftest(residual);
                            % 如果残差序列是stationary，则计算并存储参数 
                            if p <= 0.05
                                obj.signalParameters(stock1, stock2, dateLocation, 1) = 1;
                                obj.CalParameters(stock1, stock2, dateCode, averageAlpha, averageBeta, residual);
                            % 如果残差序列不是stationary，那么所有参数被置为0
                            else
                                obj.signalParameters(stock1, stock2, dateLocation, :) = zeros(9, 1);
                            end
                        end
                    end
                end
            end
        end
    end
end