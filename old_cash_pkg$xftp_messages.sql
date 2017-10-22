CREATE OR REPLACE PACKAGE pkg$xftp_messages IS
  CONST_OUR_ACCOUNT CONSTANT VARCHAR2(10) := 'MN484410';
  /*Используем эту константу в расчете баланса, при изменении логики необходимо обдумать!*/
  CONST_EXPIRING_ACCOUNT    CONSTANT VARCHAR2(10) := 'PP000003';
  CONST_DEPOSIT_ACCOUNT     CONSTANT VARCHAR2(10) := 'PP000013';
  CONST_SL_OVER_ACCOUNT     CONSTANT VARCHAR2(10) := 'PP000023';
  CONST_PAYFORSERVICES_TYPE CONSTANT VARCHAR2(50) := '41647e36-9d73-403a-8f97-1a969a74ca4f';
  CONST_CASHIN_TYPE         CONSTANT VARCHAR2(50) := 'a07fd9dc-d0fb-4c30-be94-b192a6cb2f11';

  CONST_CASHIN_SD CONSTANT VARCHAR2(50) := '2100246845';
  CONST_CASHIN_DEBITWALLETNO CONSTANT VARCHAR2(50) := '14200246845';
  

  CONST_SL_COST CONSTANT NUMBER := 1000;
  -- Author  : PILARTSER
  -- Created : 23.05.2016 11:37:12
  -- Purpose : формирование сообщений для pluspay

  FUNCTION getAmountCalcByDay(pCardNum      IN VARCHAR2,
                              pDate         IN DATE,
                              pSLTravelCost IN NUMBER) RETURN NUMBER;

  PROCEDURE createMessages(pDate IN DATE, pSLTravelCost IN NUMBER);

  PROCEDURE getClients(pDate IN DATE, pXml OUT CLOB);

  PROCEDURE getWallets(pDate IN DATE, pXml OUT CLOB);

  PROCEDURE getOperationHistory(pDate IN DATE, pXml OUT CLOB);

END pkg$xftp_messages;
/
CREATE OR REPLACE PACKAGE BODY pkg$xftp_messages IS

  FUNCTION getAmountCalcByDay(pCardNum      IN VARCHAR2,
                              pDate         IN DATE,
                              pSLTravelCost IN NUMBER) RETURN NUMBER AS
    vResult NUMBER := 0;
    --vCreateMessage cptt.t$xftp_messages%type;
    vSeries          VARCHAR2(5);
    vCreateDate      DATE;
    vIdCard          NUMBER;
    vLastExpiredDate DATE;
  BEGIN
    BEGIN
      SELECT nvl(t_c.new_card_series, t_c.card_series) AS series,
             c.date_message,
             t_c.id_card
      INTO vSeries,
           vCreateDate,
           vIdCard
      FROM cptt.t$xftp_messages c
      INNER JOIN cptt.t_data t_c
      ON (c.type_message = 1 AND c.card_num = pCardNum AND
         c.trans_id = t_c.id)
      WHERE rownum = 1;
    EXCEPTION
      WHEN OTHERS THEN
        BEGIN
          dbms_output.put_line('Ранее не создавался');
          RETURN(0);
        END;
    END;
    BEGIN
      SELECT o.value_date
      INTO vLastExpiredDate
      FROM cptt.t$xftp_messages o
      WHERE o.type_message = 3
      AND o.card_num = pCardNum
      AND o.date_message <= pDate
      AND o.creditwalletno = CONST_EXPIRING_ACCOUNT
      AND rownum = 1
      ORDER BY o.date_message DESC;
    EXCEPTION
      WHEN OTHERS THEN
        vLastExpiredDate := NULL;
    END;
    IF (vSeries IN ('90', '10')) THEN
      SELECT nvl(SUM(CASE
                       WHEN t.kind IN (7, 8, 10, 11) THEN
                        nvl(t.amount, 0) - nvl(t.amount_bail, 0)
                       ELSE
                        nvl(t.amount_bail, 0) - nvl(t.amount, 0)
                     END),
                 0)
      INTO vResult
      FROM cptt.t_data t
      WHERE t.id_card = vIdCard
      AND t.kind IN (7, 8, 10, 11, 16)
      AND t.travel_doc_kind IN (0, 1, 4)
           --AND (t.card_num like '015%' OR t.card_num like '018%')
      AND (vLastExpiredDate IS NULL OR t.date_of >= vLastExpiredDate)
      AND t.Date_Of <= pDate;
    ELSIF (vSeries = '60') THEN
      SELECT nvl(SUM(CASE
                       WHEN t.kind IN (7, 8, 10, 11) THEN
                        nvl(t.amount, 0) - nvl(t.amount_bail, 0)
                       ELSE
                        nvl(t.amount_bail, 0) - nvl(pSLTravelCost, 0)
                     END),
                 0)
      INTO vResult
      FROM cptt.t_data t
      WHERE t.id_card = vIdCard
      AND t.kind IN (7, 8, 12, 13, 17)
      AND t.travel_doc_kind IN (2, 3, 5, 6, 7, 8)
           --AND (card_num like '015%' OR card_num like '018%')
      AND (vLastExpiredDate IS NULL OR t.date_of > vLastExpiredDate)
      AND t.Date_Of <= pDate
      AND t.date_to + 1 - 1 / 24 / 60 >= pDate;
      IF (vResult < 0) THEN
        vResult := 0;
      END IF;
    ELSE
      raise_application_error(-20000, 'test');
      RETURN(0);
    END IF;
    RETURN(vResult);
  END;

  FUNCTION getLastOperation(pCardNum IN VARCHAR2, pDate IN DATE)
    RETURN cptt.t$xftp_messages%ROWTYPE AS
    vResult cptt.t$xftp_messages%ROWTYPE;
  BEGIN
    SELECT *
    INTO vResult
    FROM cptt.t$xftp_messages t
    WHERE t.type_message = 3
    AND t.card_num = pCardNum
    AND t.value_date <= pDate
    AND rownum = 1
    ORDER BY t.value_date DESC;
    RETURN(vResult);
  EXCEPTION
    WHEN OTHERS THEN
      RETURN NULL;
  END;

  PROCEDURE createClients(pDate IN DATE) AS
  BEGIN
    --сообщения генерируемые при открытии карты
    FOR rec IN (WITH active_card AS
                   (SELECT nvl(trans.new_card_series, trans.card_series) AS series,
                          row_number() OVER(PARTITION BY card_num ORDER BY date_of) AS ord,
                          trans.card_num,
                          nvl(trans.amount, 0) AS amount,
                          nvl(amount_bail, 0) AS amount_bail,
                          div.id_operator AS id_agent,
                          date_of AS value_date,
                          trans.id
                   FROM cptt.t_data   trans,
                        cptt.division div
                   WHERE trans.id_division = div.id
                   AND div.id_operator NOT IN
                         (SELECT id FROM cptt.ref$xftp_agents_locked)
                   AND trans.d = 0
                   AND trans.kind IN (7, 8)
                        --AND card_num LIKE '018%'
                   AND nvl(trans.new_card_series, trans.card_series) IN
                         ('10', '60', '90')
                   AND (trans.card_num LIKE '015%' OR
                         trans.card_num LIKE '018%')
                   AND NOT EXISTS (SELECT 1
                          FROM cptt.t$xftp_Messages m
                          WHERE m.card_num = trans.card_num)
                   AND date_of < trunc(pDate) + 1),
                  message_from_active AS
                   (SELECT dummy.type_message,
                          pDate AS date_message,
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
                             pkg$xftp_messages.CONST_CASHIN_DEBITWALLETNO
                            WHEN 3 THEN
                             pkg$xftp_messages.CONST_CASHIN_DEBITWALLETNO
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
                             CONST_DEPOSIT_ACCOUNT
                          END AS CREDITWALLETNO,
                          id_agent,
                          value_date,
                          id AS trans_id,
                          to_char(ac.id) || '_' || to_char(dummy.num) AS doc_no
                   FROM active_card ac
                   INNER JOIN ( /*1 - создание карты, 2 сумма внесенная на карту, 3 - внесение залоговая сумма, 4 - списание залоговой суммы*/
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
                   ON (dummy.num <= 2 OR ac.amount_bail > 0)
                   WHERE ac.ord = 1)
                  SELECT mfa.type_message,
                         date_message,
                         card_num,
                         amount,
                         op_type,
                         debitwalletno,
                         creditwalletno,
                         id_agent,
                         value_date,
                         trans_id,
                         doc_no
                  FROM message_from_active mfa)
    LOOP
      INSERT INTO cptt.t$xftp_messages
        (type_message,
         date_message,
         card_num,
         amount,
         op_type,
         debitwalletno,
         creditwalletno,
         id_agent,
         value_date,
         trans_id,
         doc_no)
      VALUES
        (rec.type_message,
         rec.date_message,
         rec.card_num,
         rec.amount,
         rec.op_type,
         rec.debitwalletno,
         rec.creditwalletno,
         rec.id_agent,
         rec.value_date,
         rec.trans_id,
         rec.doc_no);
    END LOOP;
  
  END;

  PROCEDURE createOperationHistory(pDate IN DATE, pSLTravelCost IN NUMBER) AS
    vLastOp cptt.t$xftp_messages%ROWTYPE;
    vAmount NUMBER := 0;
  BEGIN
    --часть операций генерится в createClients
  
    --первым делом списания, так как в т.ч. от них генерится баланс
    --вычисляем все сгорания для EP
    FOR rec IN (SELECT c.card_num,
                       c.trans_id AS create_trans_id
                FROM cptt.t$xftp_messages c
                INNER JOIN cptt.t_data t_c
                ON (c.type_message = 1 AND c.trans_id = t_c.id)
                WHERE nvl(t_c.new_card_series, t_c.card_series) IN
                      ('10', '90')
                AND NOT EXISTS
                 (SELECT 1
                       FROM cptt.t$xftp_messages o
                       WHERE o.type_message = 3
                       AND o.card_num = c.card_num
                       AND o.value_date > trunc(pDate) - 365))
    LOOP
      vLastOp := getLastOperation(rec.card_num, pDate);
      vAmount := cptt.pkg$xftp_messages.getAmountCalcByDay(rec.card_num,
                                                           nvl(vLastOp.Value_Date + 365,
                                                               pDate) -
                                                           1 / 24 / 60,
                                                           pSLTravelCost);
      --
      IF (vAmount > 0) AND ((vLastOp.Creditwalletno IS NULL) OR
         (vLastOp.Creditwalletno !=
         cptt.pkg$xftp_messages.CONST_EXPIRING_ACCOUNT)) THEN
        INSERT INTO cptt.t$xftp_messages
          (type_message,
           date_message,
           card_num,
           amount,
           op_type,
           debitwalletno,
           creditwalletno,
           id_agent,
           value_date,
           trans_id,
           doc_no)
        VALUES
          (3,
           pDate,
           rec.card_num,
           cptt.pkg$xftp_messages.getAmountCalcByDay(rec.card_num,
                                                     nvl(vLastOp.Value_Date + 365,
                                                         pDate) -
                                                     1 / 24 / 60,
                                                     pSLTravelCost),
           'PAY',
           num_to_ean(rec.card_num),
           cptt.pkg$xftp_messages.CONST_EXPIRING_ACCOUNT,
           NULL,
           nvl(vLastOp.Value_Date + 365, pDate) - 1 / 24 / 60,
           NULL,
           to_char(rec.create_trans_id) || '_' ||
           nvl(vLastOp.Value_Date + 365, pDate) - 1 / 24 / 60);
      END IF;
    END LOOP;
    --списание sl
    FOR rec IN (SELECT card_num,
                       trans_id,
                       trunc(date_to) + 1 - 1 / 24 / 60 AS value_date
                FROM (SELECT DISTINCT c.card_num,
                                      c.trans_id,
                                      t_o.date_to
                      /*для всех открытых и прошедших через нас карт SL получаем массив date_to*/
                      FROM cptt.t$xftp_messages c
                      INNER JOIN cptt.t_data t_c
                      ON (c.type_message = 1 AND c.trans_id = t_c.id AND
                         nvl(t_c.new_card_series, t_c.card_series) IN ('60') AND
                         c.date_message <= pDate)
                      INNER JOIN cptt.t$xftp_messages o
                      ON (c.card_num = o.card_num)
                      INNER JOIN cptt.t_data t_o
                      ON (o.trans_id = t_o.id)) all_date_to
                WHERE date_to + 1 < pDate -- отбираем те, что истекли
                AND NOT EXISTS (SELECT *
                       FROM cptt.t$xftp_messages exp
                       WHERE exp.value_date = trunc(all_date_to.date_to) + 1 -
                             1 / 24 / 60
                       AND exp.op_type = 'PAY'
                       AND exp.creditwalletno =
                             cptt.pkg$xftp_messages.CONST_EXPIRING_ACCOUNT
                       AND exp.type_message = 3)
                --и при этом мы о них не извещали
                )
    LOOP
      vAmount := cptt.pkg$xftp_messages.getAmountCalcByDay(rec.card_num,
                                                           rec.value_date,
                                                           pSLTravelCost);
      IF (vAmount > 0) THEN
        INSERT INTO cptt.t$xftp_messages
          (type_message,
           date_message,
           card_num,
           amount,
           op_type,
           debitwalletno,
           creditwalletno,
           id_agent,
           value_date,
           trans_id,
           doc_no)
        VALUES
          (3,
           pDate,
           rec.card_num,
           vAmount,
           'PAY',
           num_to_ean(rec.card_num),
           cptt.pkg$xftp_messages.CONST_EXPIRING_ACCOUNT,
           NULL,
           rec.value_date,
           NULL,
           to_char(rec.trans_id) || '_' ||
           to_char(rec.trans_id, 'ddmmyyyyHH24MISS'));
      END IF;
    END LOOP;
  
    --выбираем все пополнения с kind = 10,11,12,13
  
    FOR rec IN (SELECT 3 AS type_message,
                       pDate date_message,
                       card_num,
                       amount,
                       op_type,
                       debitwalletno,
                       creditwalletno,
                       id_agent,
                       value_date,
                       trans_id,
                       to_char(trans_id) AS doc_no
                FROM (SELECT trans.card_num,
                             nvl(trans.amount, 0) - nvl(trans.amount_bail, 0) AS amount,
                             'CASH' AS op_type,
                             pkg$xftp_messages.CONST_CASHIN_DEBITWALLETNO AS debitwalletno,
                             num_to_ean(trans.card_num) AS creditwalletno,
                             div.id_operator AS id_agent,
                             trans.date_of AS value_date,
                             trans.id AS trans_id
                      FROM cptt.t_data   trans,
                           cptt.division div
                      WHERE trans.id_division = div.id
                      AND div.id_operator NOT IN
                            (SELECT id FROM cptt.ref$xftp_agents_locked)
                      AND trans.d = 0
                      AND trans.kind IN (10, 11, 12, 13)
                           --AND card_num LIKE '018%'
                      AND (trans.card_num LIKE '015%' OR
                            trans.card_num LIKE '018%')
                      AND nvl(trans.new_card_series, trans.card_series) IN
                            ('10', '60', '90')
                      AND NOT EXISTS (SELECT 1
                             FROM cptt.t$xftp_Messages m
                             WHERE m.trans_id = trans.id)
                      AND date_of < trunc(pDate) + 1))
    LOOP
      INSERT INTO cptt.t$xftp_messages
        (type_message,
         date_message,
         card_num,
         amount,
         op_type,
         debitwalletno,
         creditwalletno,
         id_agent,
         value_date,
         trans_id,
         doc_no)
      VALUES
        (rec.type_message,
         rec.date_message,
         rec.card_num,
         rec.amount,
         rec.op_type,
         rec.debitwalletno,
         rec.creditwalletno,
         rec.id_agent,
         rec.value_date,
         rec.trans_id,
         rec.doc_no);
    END LOOP;
  
    --выбираем все kind = 16 для 10 и 90 серии (проезд EP)
    FOR rec IN (SELECT 3 AS type_message,
                       pDate date_message,
                       card_num,
                       amount,
                       op_type,
                       debitwalletno,
                       creditwalletno,
                       id_agent,
                       value_date,
                       trans_id,
                       to_char(trans_id) AS doc_no
                FROM (SELECT trans.card_num,
                             nvl(trans.amount, 0) - nvl(trans.amount_bail, 0) AS amount,
                             'PAY' AS op_type,
                             num_to_ean(trans.card_num) AS debitwalletno,
                             pkg$xftp_messages.CONST_OUR_ACCOUNT AS creditwalletno,
                             div.id_operator AS id_agent,
                             date_of AS value_date,
                             trans.id AS trans_id
                      FROM cptt.t_data   trans,
                           cptt.division div
                      WHERE trans.id_division = div.id
                      AND div.id_operator NOT IN
                            (SELECT id FROM cptt.ref$xftp_agents_locked)
                      AND trans.d = 0
                      AND trans.kind IN (16)
                           --AND card_num LIKE '018%'
                      AND (trans.card_num LIKE '015%' OR
                            trans.card_num LIKE '018%')
                      AND nvl(trans.new_card_series, trans.card_series) IN
                            ('10', '90')
                      AND NOT EXISTS (SELECT 1
                             FROM cptt.t$xftp_Messages m
                             WHERE m.trans_id = trans.id)
                      AND date_of < trunc(pDate) + 1))
    LOOP
      INSERT INTO cptt.t$xftp_messages
        (type_message,
         date_message,
         card_num,
         amount,
         op_type,
         debitwalletno,
         creditwalletno,
         id_agent,
         value_date,
         trans_id,
         doc_no)
      VALUES
        (rec.type_message,
         rec.date_message,
         rec.card_num,
         rec.amount,
         rec.op_type,
         rec.debitwalletno,
         rec.creditwalletno,
         rec.id_agent,
         rec.value_date,
         rec.trans_id,
         rec.doc_no);
    END LOOP;
    
    --выбираем все kind = 17 для 60 серии (проезд SL)
    FOR rec IN (SELECT trans.card_num,
                       pSLTravelCost AS amount,
                       getAmountCalcByDay(trans.card_num,
                                          trans.date_of - 1 / 24 / 60 / 60,
                                          pSLTravelCost) AS amount_pre_trans,
                       num_to_ean(trans.card_num) AS debitwalletno,
                       div.id_operator AS id_agent,
                       date_of AS value_date,
                       trans.id AS trans_id
                FROM cptt.t_data   trans,
                     cptt.division div
                WHERE trans.id_division = div.id
                AND div.id_operator NOT IN
                      (SELECT id FROM cptt.ref$xftp_agents_locked)
                AND trans.d = 0
                AND trans.kind IN (17)
                     --AND card_num LIKE '018%'
                AND (trans.card_num LIKE '015%' OR trans.card_num LIKE '018%')
                AND nvl(trans.new_card_series, trans.card_series) IN ('60')
                AND travel_doc_kind IN (2, 3, 5, 6, 7, 8)
                AND NOT EXISTS
                 (SELECT 1
                       FROM cptt.t$xftp_Messages m
                       WHERE m.trans_id = trans.id)
                AND trans.id_card IN (SELECT t_o.id_card
                                     FROM cptt.t_data          t_o,
                                          cptt.t$xftp_messages o
                                     WHERE t_o.id = o.trans_id
                                     AND o.type_message = 1)
                AND date_of < trunc(pDate) + 1)
    LOOP
       IF (rec.amount_pre_trans >= rec.amount) THEN
           --если денег на счете больше, чем стоит поездка, то списываем с карты на наш счет
           INSERT INTO cptt.t$xftp_messages
             (type_message,
              date_message,
              card_num,
              amount,
              op_type,
              debitwalletno,
              creditwalletno,
              id_agent,
              value_date,
              trans_id,
              doc_no)
           VALUES
             (3,
              pDate,
              rec.card_num,
              rec.amount,
              'PAY',
              num_to_ean(rec.card_num),
              pkg$xftp_messages.CONST_OUR_ACCOUNT,
              rec.id_agent,
              rec.value_date,
              rec.trans_id,
              to_char(rec.trans_id));
         
         ELSE
           --иначе списываем со счета плюспея на наш счет стоимость поездки превышающую баланс
           INSERT INTO cptt.t$xftp_messages
             (type_message,
              date_message,
              card_num,
              amount,
              op_type,
              debitwalletno,
              creditwalletno,
              id_agent,
              value_date,
              trans_id,
              doc_no)
           VALUES
             (3,
              pDate,
              rec.card_num,
              rec.amount - rec.amount_pre_trans,
              'PAY',
              pkg$xftp_messages.CONST_SL_OVER_ACCOUNT,
              pkg$xftp_messages.CONST_OUR_ACCOUNT,
              rec.id_agent,
              rec.value_date,
              rec.trans_id,
              to_char(rec.trans_id) || '_1');
           --и если баланс не пустой, то списываем остаток баланса с карты клиента на наш счет
           IF (rec.amount_pre_trans > 0) THEN
             INSERT INTO cptt.t$xftp_messages
               (type_message,
                date_message,
                card_num,
                amount,
                op_type,
                debitwalletno,
                creditwalletno,
                id_agent,
                value_date,
                trans_id,
                doc_no)
             VALUES
               (3,
                pDate,
                rec.card_num,
                rec.amount_pre_trans,
                'PAY',
                num_to_ean(rec.card_num),
                pkg$xftp_messages.CONST_OUR_ACCOUNT,
                rec.id_agent,
                rec.value_date,
                rec.trans_id,
                to_char(rec.trans_id) || '_2');
           END IF;
         END IF;
      
    END LOOP;
  
  END;

  PROCEDURE createWallets(pDate IN DATE, pSLTravelCost IN NUMBER) AS
  BEGIN
    FOR rec IN (SELECT 2 AS type_message,
                       pDate date_message,
                       o.card_num,
                       cptt.pkg$xftp_messages.getAmountCalcByDay(card_num,
                                                                 pDate,
                                                                 pSLTravelCost) AS amount,
                       NULL op_type,
                       NULL AS debitwalletno,
                       NULL AS creditwalletno,
                       NULL AS id_agent,
                       NULL AS trans_id
                FROM (SELECT DISTINCT card_num
                      FROM cptt.t$xftp_messages
                      WHERE type_message = 3
                      AND date_message = pDate) o)
    LOOP
      INSERT INTO cptt.t$xftp_messages
        (type_message,
         date_message,
         card_num,
         amount,
         op_type,
         debitwalletno,
         creditwalletno,
         id_agent,
         trans_id)
      VALUES
        (rec.type_message,
         rec.date_message,
         rec.card_num,
         rec.amount,
         rec.op_type,
         rec.debitwalletno,
         rec.creditwalletno,
         rec.id_agent,
         rec.trans_id);
    END LOOP;
  END;

  PROCEDURE createMessages(pDate IN DATE, pSLTravelCost IN NUMBER) AS
  BEGIN
    --DELETE FROM cptt.t$xftp_messages;
    createClients(pDate);
    createOperationHistory(pDate, pSLTravelCost);
    createWallets(pDate, pSLTravelCost);
  END;

  PROCEDURE getClients(pDate IN DATE, pXml OUT CLOB) AS
    vXml    sys.xmltype;
    vLength NUMBER;
  BEGIN
    SELECT xmlroot(xmlelement("LIST",
                              (SELECT xmlagg(xmlelement("PERSONE",
                                                        xmlelement("DATE_TIME_CREATE",
                                                                   to_char(t.date_of,
                                                                           'dd.mm.yyyy HH24:MI')),
                                                        xmlelement("IDCLIENT",
                                                                   to_char(t.id_card)),
                                                        xmlelement("DATE_TIME_MODIFY",
                                                                   to_char(t.date_of,
                                                                           'dd.mm.yyyy HH24:MI')),
                                                        xmlelement("SOURCE_MODIFY",
                                                                   'Transport'),
                                                        xmlelement("CATEGORY",
                                                                   ''),
                                                        xmlelement("CHANNEL",
                                                                   'Transport'),
                                                        xmlelement("GROUP",
                                                                   'User unidentified'),
                                                        xmlelement("STATUS",
                                                                   ''),
                                                        xmlelement("SEGMENTATION",
                                                                   ''),
                                                        xmlelement("NOTIFYMETHOD",
                                                                   ''),
                                                        xmlelement("SD",
                                                                   pkg$xftp_messages.CONST_CASHIN_SD),
                                                        xmlelement("OP", ''),
                                                        xmlelement("AP",
                                                                   to_char(t.id_term)),
                                                        xmlelement("CONTACTTYPE",
                                                                   ''),
                                                        xmlelement("NAME_FIRST",
                                                                   ''),
                                                        xmlelement("NAME_MIDDLE",
                                                                   ''),
                                                        xmlelement("NAME_LAST",
                                                                   ''),
                                                        xmlelement("OCCUPATION",
                                                                   ''),
                                                        xmlelement("BIRTHDAY",
                                                                   ''),
                                                        xmlelement("BIRTHPLACE",
                                                                   ''),
                                                        xmlelement("RESIDENT",
                                                                   ''),
                                                        xmlelement("SEX", ''),
                                                        xmlelement("DOCUMENT_TYPE",
                                                                   ''),
                                                        xmlelement("DOCUMENT_GIVENDATE",
                                                                   ''),
                                                        xmlelement("DOCUMENT_GIVENPLACE",
                                                                   ''),
                                                        xmlelement("DOCUMENT_NO",
                                                                   ''),
                                                        xmlelement("DOCUMENT_SERIES",
                                                                   ''),
                                                        xmlelement("DOCUMENT_DEPARTMENT",
                                                                   ''),
                                                        xmlelement("INN", ''),
                                                        xmlelement("SNILS", ''),
                                                        xmlelement("SECRETWORD",
                                                                   ''),
                                                        xmlelement("ADDRTYPE",
                                                                   ''),
                                                        xmlelement("EMAILTYPE",
                                                                   ''),
                                                        xmlelement("EMAIL", ''),
                                                        xmlelement("MOBILEPHONE",
                                                                   ''),
                                                        xmlelement("COUNTRYRES",
                                                                   ''),
                                                        xmlelement("PHONE", ''),
                                                        xmlelement("ADDRESS",
                                                                   ''),
                                                        xmlelement("COUNTRYLIVE",
                                                                   ''),
                                                        xmlelement("ZIPLIVE",
                                                                   ''),
                                                        xmlelement("REGIONLIVE_NAME",
                                                                   ''),
                                                        xmlelement("CITYLIVE_NAME",
                                                                   ''),
                                                        xmlelement("STREETLIVE_NAME",
                                                                   ''),
                                                        xmlelement("HOUSELIVE",
                                                                   ''),
                                                        xmlelement("BUILDINGLIVE",
                                                                   ''),
                                                        xmlelement("FRAMELIVE",
                                                                   ''),
                                                        xmlelement("FLATLIVE",
                                                                   ''),
                                                        xmlelement("STATUS_ID",
                                                                   'User unidentified'),
                                                        xmlelement("REGISTRATIONCOUNTRY",
                                                                   'РФ'),
                                                        xmlelement("REGISTRATIONREGION",
                                                                   '')
                                                        --           
                                                        ))
                               FROM cptt.t$xftp_messages m,
                                    cptt.t_data          t
                               WHERE m.trans_id = t.id
                               AND m.type_message = 1
                               AND m.date_message = pDate)),
                   version '1.0" encoding="UTF-8')
    INTO vXml
    FROM dual;
    SELECT length(extract(vXML, '//LIST/PERSONE[1]/DATE_TIME_CREATE'))
    INTO vLength
    FROM dual;
    IF (vLength = 0)
    
     THEN
      dbms_lob.createtemporary(pXml, NULL);
    ELSE
      SELECT vXml.getclobval() INTO pXml FROM dual;
    END IF;
  
  EXCEPTION
    WHEN OTHERS THEN
      dbms_lob.createtemporary(pXml, NULL);
  END;

  PROCEDURE getWallets(pDate IN DATE, pXml OUT CLOB) AS
    vXml sys.xmltype;
  BEGIN
    SELECT xmlroot(xmlelement("LIST",
                              (SELECT xmlagg(xmlelement("WALLET",
                                                        xmlelement("WALLETNO",
                                                                   num_to_ean(w.card_num)),
                                                        xmlelement("CREATEDATE",
                                                                   to_char(t_c.date_of,
                                                                           'dd.mm.yyyy')),
                                                        xmlelement("WALLETTYPE",
                                                                   '002'),
                                                        xmlelement("CURRENCYNO",
                                                                   'RUB'),
                                                        xmlelement("IDCLIENT",
                                                                   to_char(t_c.id_card)),
                                                        xmlelement("REMAIN",
                                                                   to_char(w.amount,
                                                                           'FM999999999999990.00')),
                                                        xmlelement("REMAINUPDATEDATE",
                                                                   to_char(w.date_message,
                                                                           'dd.mm.yyyy')),
                                                        xmlelement("AP",
                                                                   to_char(c.id_agent)),
                                                        xmlelement("SD",
                                                                   to_char(t_c.id_term)),
                                                        xmlelement("OP", ''),
                                                        xmlelement("CLOSEDATE",
                                                                   '')
                                                        --           
                                                        ))
                               FROM cptt.t$xftp_messages w
                               INNER JOIN cptt.t$xftp_messages c
                               ON (w.type_message = 2 AND
                                  w.date_message = pDate AND
                                  w.card_num = c.card_num AND
                                  c.type_message = 1)
                               INNER JOIN cptt.t_data t_c
                               ON (c.trans_id = t_c.id))),
                   version '1.0" encoding="UTF-8')
    INTO vXml
    FROM dual;
    SELECT vXml.getclobval() INTO pXml FROM dual;
  EXCEPTION
    WHEN OTHERS THEN
      dbms_lob.createtemporary(pXml, NULL);
  END;

  PROCEDURE getOperationHistory(pDate IN DATE, pXml OUT CLOB) AS
    vXml sys.xmltype;
  BEGIN
    SELECT xmlroot(xmlelement("LIST",
                              (SELECT xmlagg(xmlelement("OPER",
                                                        xmlelement("DOCNO",
                                                                   m.doc_no),
                                                        xmlelement("OPDATE",
                                                                   to_char(m.date_message,
                                                                           'dd.mm.yyyy')),
                                                        xmlelement("CHANNEL",
                                                                   'transport'),
                                                        xmlelement("TRANTYPE",
                                                                   decode(m.op_type,
                                                                          'CASH',
                                                                          CONST_CASHIN_TYPE,
                                                                          'PAY',
                                                                          CONST_PAYFORSERVICES_TYPE)),
                                                        xmlelement("DESCRIPTION",
                                                                   ''),
                                                        --для даты списания - синтетическая дата
                                                        xmlelement("VALUEDATE",
                                                                   to_char(m.value_date,
                                                                           'dd.mm.yyyy HH24:MI:SS')),
                                                        xmlelement("DEBITWALLETNO",
                                                                   m.debitwalletno),
                                                        xmlelement("DEBITCURRENCY",
                                                                   'RUB'),
                                                        xmlelement("DEBITVALUE",
                                                                   to_char(m.amount,
                                                                           'FM999999999999990.00')),
                                                        xmlelement("CREDITWALLETNO",
                                                                   m.creditwalletno),
                                                        xmlelement("CREDITCURRENCY",
                                                                   'RUB'),
                                                        xmlelement("CREDITVALUE",
                                                                   to_char(m.amount,
                                                                           'FM999999999999990.00')),
                                                        xmlelement("SP_ID", ''),
                                                        xmlelement("SOURCE",
                                                                   'transport'),
                                                        xmlelement("SD",
                                                                   decode(m.op_type,
                                                                          'CASH',
                                                                          pkg$xftp_messages.CONST_CASHIN_SD,
                                                                          '')),
                                                        xmlelement("AP",
                                                                   decode(m.op_type,
                                                                          'CASH',
                                                                          to_char(t.id_term),
                                                                          '')),
                                                        xmlelement("OP", ''),
                                                        xmlelement("RSCH", ''),
                                                        xmlelement("DOCNO_PARENT",
                                                                   '')
                                                        --           
                                                        ))
                               FROM cptt.t$xftp_messages m,
                                    cptt.t_data          t
                               WHERE m.trans_id = t.id(+)
                               AND m.type_message = 3
                               AND m.date_message = pDate)),
                   version '1.0" encoding="UTF-8')
    INTO vXml
    FROM dual;
    SELECT vXml.getclobval() INTO pXml FROM dual;
  EXCEPTION
    WHEN OTHERS THEN
      dbms_lob.createtemporary(pXml, NULL);
  END;
END pkg$xftp_messages;
/
