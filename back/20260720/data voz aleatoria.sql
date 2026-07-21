SELECT res.conversation_id,
t.call_date,
extract(isoweek from call_date) as semana,
t.aht,
t.fcr,
t.nps,
r.voicebot_category_process,
concat(agent_action_description, call_reason, resolution_status)
FROM cuscare-data-dev.post_call_analytics.pca_conversation_summary res
left join cuscare-data-dev.post_call_analytics.pca_conversation_category cat
on res.conversation_id=cat.conversation_id
left join `data-exp-ebiz-channels.radar.sgj_third` as t on res.conversation_id=t.conversation_id
left join `cuscare-data-prod.virtual_assistant_metrics.bot_retention` as r on res.conversation_id=r.conversation_id
left join `cuscare-data-prod.virtual_assistant_model.bot_transcription` as bt  on res.conversation_id=bt.conversation_id

WHERE res.load_datetime between "2026-01-01" and '2026-05-31'
and category="INFORMACION_DE_VIAJE"
and t.second_category in ("FRANQUICIA_EQUIPAJE","CONSULTA_PNR_TKT","DOCUMENTACION_VIAJE","INFO_VUELO")
and t.is_hvc =0
order by rand()
LIMIT 300