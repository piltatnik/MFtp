PL/SQL Developer Test script 3.0
31
-- Created on 12.07.2017 by PILAR 
DECLARE
  -- Local variables here
  i INTEGER;
BEGIN
  FOR rec IN (SELECT 'Транзакция '||to_char(trans_id)||' '||CASE type_message
                       WHEN 1 THEN
                        'Карту '||num_to_ean(card_num)||' (наш card_num:'||card_num||') создали'
                       WHEN 3 THEN
                        CASE op_type
                          WHEN 'CASH' THEN
                           'Карту '||num_to_ean(card_num)||' (наш card_num:'||card_num||') пополнили (кто пополнил: '||debitwalletno||') на сумму '
                          ELSE
                           'С карты '||num_to_ean(card_num)||' (наш card_num:'||card_num||') списали (кому списали: '||creditwalletno||') сумму '
                        END || to_char(amount)
                     END 
                     || ' в дату ' ||to_char(value_date, 'dd.mm.yyyy HH24:MI:SS') 
                     ||' и она попала в файл 03_ophist_transport_'||to_char(date_message, 'ddmmyyyy_HH24MISS')||'.xml '
                     --||' (сформирован : '||to_char(date_message, 'dd.mm.yyyy HH24:MI:SS') ||');' 
                     AS text
              FROM T$XFTP_MESSAGES
              WHERE card_num = ean_to_num(:pCard)
              AND type_message <> 2
              ORDER BY type_message,
                       value_date,
                       date_message,
                       op_type)
  LOOP
    dbms_output.put_line(rec.text);
  END LOOP;
END;
1
pCard
1
2031500043776
5
0
