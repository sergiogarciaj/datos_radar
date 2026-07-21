with 
ant2 as    
(
  SELECT
    sl.bp_executive_num as bp,
    MIN(call_date) AS fecha_aparicion_mas_antigua
FROM
    `data-exp-contactcenter.100x100.third_calculated`,
    UNNEST(skill_lookup) AS sl
WHERE
    sl.bp_executive_num IS NOT NULL
GROUP BY
    1
    order by 1
)
,base as   
(
  select distinct bp_num,coalesce(entry_company_date,lt1,lt) as entry_company_date
   from
  (select distinct bp_num,
  FIRST_VALUE(entry_company_date IGNORE NULLS) OVER (
    PARTITION BY bp_num 
    ORDER BY load_dt ASC) as 
  entry_company_date,
  --case when bp_num<4862947 then DATE_ADD(DATE '1899-12-30', INTERVAL CAST((812680 - 0.322 * bp_num + 0.0000000338 * POW(bp_num, 2)) AS INT64) DAY)  else null end AS lt
   FIRST_VALUE(load_dt) OVER (
  PARTITION BY bp_num 
  ORDER BY load_dt ASC
  ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
) AS lt,
 ant2.fecha_aparicion_mas_antigua as lt1
   --min(load_dt) over (partition by bp_num) as lt
   from `sp-te-segdlak-prod-ky3g.dmt_hhrr_staffing_us.staff_history` h left join ant2 on ant2.bp=h.bp_num
   --group by all

  union all
  select distinct bp_num,
  FIRST_VALUE(entry_company_date IGNORE NULLS) OVER (
    PARTITION BY bp_num 
    ORDER BY load_dt ASC) as
  entry_company_date,
 --case when bp_num<4862947 then DATE_ADD(DATE '1899-12-30', INTERVAL CAST((812680 - 0.322 * bp_num + 0.0000000338 * POW(bp_num, 2)) AS INT64) DAY)  else null end AS lt
 FIRST_VALUE(load_dt) OVER (
  PARTITION BY bp_num 
  ORDER BY load_dt ASC
  ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
) AS lt,
 ant2.fecha_aparicion_mas_antigua as lt1
  from `sp-te-segdlak-prod-ky3g.dmt_hhrr_staffing_us.staff_daily` h left join ant2 on ant2.bp=h.bp_num
  ) 
)
,ant as   
(
select   bp_num,
conversation_id,
date_diff(current_date(), entry_company_date, DAY) as a,
entry_company_date,
aht/60 as aht,
fcr,
CASE 
        WHEN SAFE_CAST(t.nps AS INT64) BETWEEN 9 AND 10 THEN 100
        WHEN SAFE_CAST(t.nps AS INT64) BETWEEN 7 AND 8 THEN 0
        WHEN SAFE_CAST(t.nps AS INT64) BETWEEN 0 AND 6 THEN -100
        ELSE NULL 
    END AS nps_indicator,
call_date,
category,
t.skill_lookup[SAFE_OFFSET(0)].skill_name AS skill_name,
t.skill_lookup[SAFE_OFFSET(0)].bp_executive_num,
all_agent_bp_numbers,
t.factory_name,
t.last_supervisor_bp_number,
from
`data-exp-contactcenter.100x100.third_calculated` t
left join
 base
on safe_CAST(t.skill_lookup[SAFE_OFFSET(0)].bp_executive_num AS INT64)=base.bp_num
where t.canal="voz"
and is_human="HUMAN"
)
/*
select 
all_agent_bp_numbers,
bp_executive_num,
conversation_id
 from ant
where
call_date > "2026-01-01" 
and entry_company_date is null
*/

select
factory_name[safe_offset(0)] as fabrica,
--last_supervisor_bp_number,
 --skill_name,
case when a <=1 then "S/I"
     when (a<=30 and a>1) then "a 0-30"
     when a<=60 then "b 30-60"
     when a<=90 then "c 60-90"
     when a<=120 then "d 90-120"
     when a<=150 then "e 120-150"
     when a<=180 then "f 150-180"
     when a>180  then "g >180"
     else "S/I"
     end antig_agent_days,
 ROUND(AVG(aht), 2) AS aht_min,
  ROUND(AVG(fcr), 2) AS fcr,
  ROUND(AVG(SAFE_CAST(nps_indicator AS INT64)), 2) AS nps,
 count(distinct conversation_id) vol,
 count(distinct bp_num) as q_agent,
 ROUND(AVG(a), 2) AS antiguedad_med,   
    
from ant 
where
call_date > "2026-01-01" 
--and category="CAMBIO_VOLUNTARIO"
--and skill_name="KON_LUA_ES"
group by all
order by 1,2