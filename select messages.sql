--delete from cptt.t$xftp_messages;
--сообщени€ генерируемые при открытии карты
WITH active_card AS
 (SELECT nvl(trans.new_card_series, trans.card_series) AS series,
         row_number() OVER(PARTITION BY card_num ORDER BY date_of) AS ord,
         trans.card_num,
         nvl(trans.amount, 0) AS amount,
         nvl(amount_bail, 0) AS amount_bail,
         trans.id,
         div.id_operator AS id_agent
  FROM cptt.t_data   trans,
       cptt.division div
  WHERE trans.id_division = div.id
  AND div.id_operator NOT IN (SELECT id FROM cptt.ref$xftp_agents_locked)
  AND trans.kind IN (7, 8)
       --AND card_num LIKE '018%'
  AND nvl(trans.new_card_series, trans.card_series) IN ('10', '60')
  /*AND NOT EXISTS (SELECT 1
         FROM cptt.t$xftp_Messages m
         WHERE m.card_num = trans.card_num)*/),
message_from_active AS
 (SELECT dummy.type_message,
         trunc(SYSDATE) AS date_message,
         ac.card_num,
         CASE dummy.num
           WHEN 1 THEN
            0
           WHEN 2 THEN
            ac.amount - ac.amount_bail
           ELSE
            ac.amount_bail
         END AS amount,
         dummy.op_type,
         CASE dummy.num
           WHEN 1 THEN
            NULL
           WHEN 2 THEN
            to_char(ac.id_agent)
           WHEN 3 THEN
            to_char(ac.id_agent)
           ELSE
            num_to_ean(ac.card_num)
         END AS DEBITWALLETNO,
         CASE dummy.num
           WHEN 1 THEN
            NULL
           WHEN 2 THEN
            num_to_ean(ac.card_num)
           WHEN 3 THEN
            num_to_ean(ac.card_num)
           WHEN 4 THEN
            'PP000013'
         END AS CREDITWALLETNO,
         id AS trans_id
  FROM active_card ac
  INNER JOIN ( /*1 - создание карты, 2 сумма внесенна€ на карту, 3 - внесение залогова€ сумма, 4 - списание залоговой суммы*/
             SELECT LEVEL AS num,
                     CASE LEVEL
                       WHEN 1 THEN
                        1
                       ELSE
                        3
                     END AS type_message,
                     CASE LEVEL
                       WHEN 1 THEN
                        NULL
                       WHEN 2 THEN
                        'CASH'
                       WHEN 3 THEN
                        'CASH'
                       ELSE
                        'PAY'
                     END AS op_type
             FROM dual
             CONNECT BY LEVEL <= 4) dummy
  ON (dummy.num <= 2 OR ac.amount_bail >0)
  WHERE ac.ord = 1)
SELECT mfa.* FROM message_from_active mfa;


