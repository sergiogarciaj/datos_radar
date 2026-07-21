with t as
(
  SELECT id as conversation_id,
dialog  as text
FROM `data-exp-ebiz-channels.genesys.dialogo_completo` res

)
select 
bot.conversation_id,
t.text
from `cuscare-data-prod.virtual_assistant_metrics.bot_retention`  as bot
left join t 
on bot.conversation_id=t.conversation_id
where date(conversation_start_datetime) between "2026-03-01" and "2026-03-31"
and originating_direction_type="inbound"
and channel_type="message"
and voicebot_category_process in ("SEAT_ASSIGNMENT_PROBLEM")
and t.text is not null
and bp_agent_transferred_bot is not null
order by rand()
limit 300