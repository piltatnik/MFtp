PL/SQL Developer Test script 3.0
14
begin
  -- Call the procedure
  pkg$xftp_messages.getoperationhistory(pdate => :pdate,
                                        pxml => :pxml);
  open :cur for with rowset as
  (SELECT extractValue(VALUE(t), 'OPER/CREDITWALLETNO') AS creditwalletno,
                         extractValue(VALUE(t), 'OPER/TRANTYPE') AS trantype,
                         to_date(extractValue(VALUE(t), 'OPER/VALUEDATE'), 'dd.mm.yyyy HH24:MI:SS') AS valuedate,
                         extractValue(VALUE(t), 'OPER/CREDITVALUE') AS creditvalue
                  FROM TABLE(XMLSequence(xmltype(:pxml).extract('LIST/OPER'))) t)
   select * from rowset 
   where trantype = '41647e36-9d73-403a-8f97-1a969a74ca4f'
         AND creditwalletno = 'MN484410';
end;
3
pdate
1
03.07.2017 23:59:59
12
pxml
1
<CLOB>
112
cur
1
<Cursor>
116
0
