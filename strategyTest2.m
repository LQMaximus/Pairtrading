
director = mclasses.director.Homework2Director([], 'homework_2');

% register strategy
directorParameters = [];
initParameters.startDate = datenum(2014, 6, 1);
initParameters.endDate = datenum(2015, 6, 1);
director.initialize(initParameters);

% register a long only strategy
PairTrading = PairStrategy(director.rootAllocator, 'PairStrategy');
strategyParameters = mclasses.strategy.longOnly.configParameter(PairTrading);
PairTrading.initialize(strategyParameters);

load("D:\BaiduSyncdisk\Codefield\Matlab\softengineer\homeworkCode2\sharedData\mat\marketInfo_securities_china.mat")
director.reset();
director.set_tradeDates(aggregatedDataStruct.sharedInformation.allDates);
director.run();
director.displayResult();