PL/SQL Developer Test script 3.0
52
-- Created on 27.08.2017 by PILAR 
declare 
  -- Local variables here
  i integer;
begin
  -- Test statements here
  open :cur for with rowset as
  (SELECT 
           '03_ophist_transport_14082017_235959_2017-08-15 10-23-22.xml' as fileName,
           to_char(extractValue(VALUE(t), 'OPER/DOCNO')) as docNo,
           to_date(extractValue(VALUE(t), 'OPER/VALUEDATE'), 'dd.mm.yyyy HH24:MI:SS') AS valueDate,
           to_number(extractValue(VALUE(t), 'OPER/CREDITVALUE'), '9999999999999999.99') as creditValue,
           extractValue(VALUE(t), 'OPER/TRANTYPE')as tranType,
           extractValue(VALUE(t), 'OPER/DEBITWALLETNO') as debitWalletNo,
           extractValue(VALUE(t), 'OPER/CREDITWALLETNO') as creditWalletNo
                  FROM TABLE(XMLSequence(xmltype(:pxml20170825102322).extract('LIST/OPER'))) t
    UNION ALL
    SELECT 
           '03_ophist_transport_15082017_235959_2017-08-16 09-54-35.xml' as fileName,
           to_char(extractValue(VALUE(t), 'OPER/DOCNO')) as docNo,
           to_date(extractValue(VALUE(t), 'OPER/VALUEDATE'), 'dd.mm.yyyy HH24:MI:SS') AS valueDate,
           to_number(extractValue(VALUE(t), 'OPER/CREDITVALUE'), '9999999999999999.99') as creditValue,
           extractValue(VALUE(t), 'OPER/TRANTYPE')as tranType,
           extractValue(VALUE(t), 'OPER/DEBITWALLETNO') as debitWalletNo,
           extractValue(VALUE(t), 'OPER/CREDITWALLETNO') as creditWalletNo
                  FROM TABLE(XMLSequence(xmltype(:pxml20170816095435).extract('LIST/OPER'))) t
    UNION ALL
    SELECT 
           '03_ophist_transport_16082017_235959_2017-08-17 10-26-38.xml' as fileName,
           to_char(extractValue(VALUE(t), 'OPER/DOCNO')) as docNo,
           to_date(extractValue(VALUE(t), 'OPER/VALUEDATE'), 'dd.mm.yyyy HH24:MI:SS') AS valueDate,
           to_number(extractValue(VALUE(t), 'OPER/CREDITVALUE'), '9999999999999999.99') as creditValue,
           extractValue(VALUE(t), 'OPER/TRANTYPE')as tranType,
           extractValue(VALUE(t), 'OPER/DEBITWALLETNO') as debitWalletNo,
           extractValue(VALUE(t), 'OPER/CREDITWALLETNO') as creditWalletNo
                  FROM TABLE(XMLSequence(xmltype(:pxml20170817102638).extract('LIST/OPER'))) t
                  )
             
   select rs.fileName, rs.trantype, rs.docNo, rs.valueDate, rs.creditValue, rs.debitWalletNo, rs.creditWalletNo
                  --rs.filename,rs.trantype, count(1) as cnt, sum(creditValue) as "sum"
   from rowset rs
   LEFT JOIN cptt.t$xftp_messages mes
      ON mes.doc_no = rs.docNo
   left join cptt.T_DATA t
        on rs.valueDate = t.date_of
           AND ean_to_num(decode(rs.tranType, '41647e36-9d73-403a-8f97-1a969a74ca4f', rs.debitWalletNo, rs.creditWalletNo)) = t.card_num
           AND case when rs.docNo LIKE '%\_%' ESCAPE '\' then substr(rs.docNo, 1, length(rs.docNo)-2) else rs.docNo end = t.id
   WHERE t.date_of is null
   order by rs.fileName, rs.trantype, rs.docNo, rs.valueDate, rs.creditValue, rs.debitWalletNo, rs.creditWalletNo
   --group by rs.filename,rs.trantype
   ;
end;
4
cur
1
<Cursor>
116
pxml20170825102322
1
<CLOB>
4208
pxml20170816095435
1
<CLOB>
4208
pxml20170817102638
1
<CLOB>
4208
0
