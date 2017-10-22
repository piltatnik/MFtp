PL/SQL Developer Test script 3.0
11
BEGIN
  --ÅÑËÈ ÍÓÆÍÀ ÎÏÐÅÄÅËÅÍÍÀß ÄÀÒÀ - çàêîìåíòèòü
  --select sysdate into :pDate;
  pkg$xftp_messages.createmessages(pdate => :pdate, pSLTravelCost => :pSLTravelCost);
  
  pkg$xftp_messages.getClients(pdate => :pdate, pxml => :pxml);
  pkg$xftp_messages.getOperationHistory(pdate => :pdate, pxml => :pxml3);
  pkg$xftp_messages.getWallets(pdate => :pdate, pxml => :pxml2);
  
  --COMMIT;
END;
6
pdate
1
31.05.2017 22:26:00
12
cur
1
<Cursor>
-116
pxml
1
<CLOB>
4208
pxml2
1
<CLOB>
4208
pxml3
1
<CLOB>
4208
pSLTravelCost
1
19
3
0
