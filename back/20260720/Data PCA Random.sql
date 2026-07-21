SELECT res.conversation_id,
t.call_date,
extract(isoweek from call_date) as semana,
round(t.aht,0) aht,
round(t.fcr,0) fcr,
CASE 
        WHEN SAFE_CAST(t.nps AS INT64) BETWEEN 9 AND 10 THEN 100
        WHEN SAFE_CAST(t.nps AS INT64) BETWEEN 7 AND 8 THEN 0
        WHEN SAFE_CAST(t.nps AS INT64) BETWEEN 0 AND 6 THEN -100
        ELSE NULL 
    END AS nps_indicator,
t.nps,
cat.first_category,
cat.second_category,
cat.third_category,
concat(agent_action_description," ", call_reason, resolution_status," ",first_comment_category," ",second_category_comment," ",third_category_comment)
FROM `cuscare-data-dev.post_call_analytics.pca_conversation_summary` res
left join `cuscare-data-dev.post_call_analytics.pca_conversation_category` cat

on res.conversation_id=cat.conversation_id
left join `data-exp-contactcenter.100x100.third_calculated` as t on res.conversation_id=t.conversation_id
WHERE res.load_datetime between "2026-03-23" and '2026-04-05'
and cat.first_category="VENTAS"
order by rand()
LIMIT 300