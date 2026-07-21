SELECT 
is_human,
extract(month from call_date) as mes,
sum(case when canal='voz' then factor else 0 end) as voz,
avg(

  case when nps is null then NULL   
when nps in ("9","10") then 100
when nps in ("0","1","2","3","4","5","6") then -100
else 0
end
) as nps
 FROM `cus-data-dev.radar.sgj_third` 
 WHERE 
 1=1
 and call_date between "2026-01-01" and "2026-12-31"
 and canal='voz'
 group by all
 order by mes, is_human