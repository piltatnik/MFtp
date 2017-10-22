update t_data
set d = 1
where id in
(select id from cptt.t_data t
where t.date_of >= to_date('01.05.2017', 'dd.mm.yyyy')
      and t.date_of <= to_date('01.06.2017', 'dd.mm.yyyy')
      and t.d = 0
      and t.card_num = '0180000299')
