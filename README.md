# Pairtrading
## Signal
propertyies:
dateNumIdx:日期列表,包含datenum格式的日期和对应位置的索引,也就是两列;

stockNameCodeIdx:股票列表,包含string格式的股票名缩写和股票代码,以及对应位置的索引,也就是三列;

closePrice: 全部股票的收盘价

closePriceAdj:全部股票的调整后收盘价,向前调整

pairsLocationMatrix: n*n矩阵,里面包含bool值,如果为真,说明是纳入考虑的pair;

methods:
FetchData 获取所需的所有数据,并处理为需要的格式

ConvertDatenumToDateIndex 输入datenum格式的日期列表,找到对应的索引,并按顺序返回为列表,输出为列向量

ConvertStkCodeToStkIndex 输入string格式的股票代码列表,找到对应的索引,并按顺序返回为列表,输出为列向量

LinearReg(y,X) 回归得到截距,斜率,斜率的p值,epsilon向量,向量为列向量

LinearRegTimeSeries

FindPairsInSameIndustry 得到在同一行业的股票对应行索引

FindPairsCorrelatedStrongly 输入股票索引列向量,回归的起始时间,回归的结束时间,p值的约束,输出筛选后的股票索引列向量,n*n的bool矩阵,其中值为1表示pair可以使用