classdef Homework2Director < mclasses.director.HFDirector
    
    properties (GetAccess = public, SetAccess = private)
    end
    
    methods (Access = public)
        
        function obj = Homework2Director(container, name)
            obj@mclasses.director.HFDirector(container, name);
        end
        
        function set_tradeDates(obj,tradeDatesArray)
            obj.tradeDates=tradeDatesArray;
        end
            
        function run(obj)
            endDate=obj.endDate;
            currentDate=obj.calculateStartDate();
            obj.importStrategy();
            while currentDate < endDate
                obj.currDate=currentDate;
                if ismember(currentDate, obj.tradeDates)
                    obj.beforeMarketOpen(currentDate);
                    obj.recordDailyPnlBOD(currentDate);
                    obj.executeOrder(currentDate);
                    obj.afterMarketClose(currentDate);
                    obj.recordDailyPnl(currentDate);
                    obj.examCash(currentDate);
                    obj.allocatorRebalance(currentDate);
                    obj.updateLFStrategy(currentDate);
                end
                currentDate=currentDate+1;
            end
        end
    end
end