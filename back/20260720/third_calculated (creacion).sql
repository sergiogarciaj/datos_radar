CREATE OR REPLACE TABLE `data-exp-contactcenter.100x100.third_calculated` AS

WITH b AS (
  SELECT 
  mes,
  canal,
  null as zona,
  "HUMAN" as is_human,
  valor
  FROM (
    SELECT 
      FORMAT_DATE('%Y-%m', meses) AS mes,
      SUM(demanda_voz_agente) AS voz,
      SUM(wa) AS wsp,
      SUM(livechat) AS chat,
      SUM(casos_validado_com_gabi) AS cases,
      SUM(redes_sociales_validado_rrss_tabela_jessie_ohmura_okedasem_marketing) as rrss
    FROM(
      SELECT 
      CASE
        WHEN mes = 'Ene24' THEN DATE(2024,01,01)
        WHEN mes = 'Feb24' THEN DATE(2024,02,01)
        WHEN mes = 'Mar24' THEN DATE(2024,03,01)
        WHEN mes = 'Apr24' THEN DATE(2024,04,01)
        WHEN mes = 'May24' THEN DATE(2024,05,01)
        WHEN mes = 'Jun24' THEN DATE(2024,06,01)
        WHEN mes = 'Jul24' THEN DATE(2024,07,01)
        WHEN mes = 'Aug24' THEN DATE(2024,08,01)
        WHEN mes = 'Sep24' THEN DATE(2024,09,01)
        WHEN mes = 'Oct24' THEN DATE(2024,10,01)
        WHEN mes = 'Nov24' THEN DATE(2024,11,01)
        WHEN mes = 'Dec24' THEN DATE(2024,12,01)
        WHEN mes = 'Ene25' THEN DATE(2025,01,01)
        WHEN mes = 'Feb25' THEN DATE(2025,02,01)
        WHEN mes = 'Mar25' THEN DATE(2025,03,01)
        WHEN mes = 'Apr25' THEN DATE(2025,04,01)
        WHEN mes = 'May25' THEN DATE(2025,05,01)
        WHEN mes = 'Jun25' THEN DATE(2025,06,01)
        WHEN mes = 'Jul25' THEN DATE(2025,07,01)
        WHEN mes = 'Aug25' THEN DATE(2025,08,01)
        WHEN mes = 'Sep25' THEN DATE(2025,09,01)
        WHEN mes = 'Oct25' THEN DATE(2025,10,01)
        WHEN mes = 'Nov25' THEN DATE(2025,11,01)
        WHEN mes = 'Dec25' THEN DATE(2025,12,01)
      END AS meses,
      *
      FROM `data-exp-contactcenter.100x100.new_calculated2`
    )
    GROUP BY ALL
  )
UNPIVOT(valor FOR canal IN (voz, wsp, chat, cases, rrss))

UNION ALL

  -- =========================
  -- B nuevo (desde 2026) = contact_rate_master
  -- =========================
  SELECT
    FORMAT_DATE('%Y-%m', date) AS mes,
    canal,
    zona,
    is_human,
    SUM(N_R) AS valor
  FROM (
    SELECT
      date,
      CASE
        WHEN channel = 'Calls' THEN 'voz'
        WHEN channel = 'WhatsApp Agent' THEN 'wsp'
        WHEN channel = 'Chat Web' THEN 'chat'
        WHEN channel = 'Cases' THEN 'cases'
        WHEN channel = 'Social Media' THEN 'rrss'
        WHEN channel = 'Voice Bot' THEN 'voz'
        WHEN channel = 'WhatsApp Bot' THEN 'wsp'
        ELSE NULL
      END AS canal,
      case when UPPER(country) = "BR" then "BR" else "SSC" end zona,
       case when channel in ("Voice Bot","WhatsApp Bot") then "NOT_HUMAN" else "HUMAN" end is_human,
      N_R
    FROM `data-exp-contactcenter.100x100.contact_rate_master`
    WHERE date >= DATE(2026,01,01)
      AND channel IN ('Calls','WhatsApp Agent','Chat Web','Cases','Social Media','Voice Bot','WhatsApp Bot')
      --and channel not in ('Voice Bot','WhatsApp Bot')
  )
  #WHERE canal IS NOT NULL
  GROUP BY mes, canal, zona, is_human
),
a AS (
  SELECT 
    FORMAT_DATE('%Y-%m', call_date) AS mes,
    CASE
      WHEN channel_type IS NULL THEN 'voz'
      WHEN channel_type = 'voice' THEN 'voz'
      WHEN channel_type IN ('open','whatsapp','bot_wsp') THEN 'wsp'
      WHEN channel_type = 'webmessaging' THEN 'chat'
      WHEN channel_type = 'CC' AND is_human = 'HUMAN' THEN 'voz'
      WHEN channel_type = 'CC' AND is_human = 'BOTH' THEN 'voz'
      WHEN channel_type = 'CC' AND is_human = 'NOT_HUMAN' THEN 'voz'
      WHEN channel_type = 'CASES' THEN 'cases'
    END as canal,
    mercado as zona,
    is_human,

    count(conversation_id) as valor
  FROM `data-exp-contactcenter.100x100.new_calculated`
  #WHERE is_human IN ('HUMAN','BOTH')
  GROUP BY ALL
  ORDER BY 1, 2
),
#   modificacion 12-12-2025
factores AS (
 /* SELECT a.mes,
  a.canal,
  CASE
    WHEN b.valor = 0 THEN null
    ELSE b.valor/a.valor
  END as factor
  
  FROM a
  LEFT JOIN b ON a.mes=b.mes AND a.canal = b.canal
  ORDER BY a.mes,a.canal */
   SELECT a.mes,
  a.canal,
  a.zona,
  a.is_human,
  CASE
    WHEN ( b.valor is null) THEN 0
    when b.valor = 0 then 0
    when a.valor=0 then 0
    ELSE b.valor/a.valor
  END as factor
  
  FROM a
  LEFT JOIN b
  ON (a.mes = b.mes
  AND a.canal = b.canal
  AND  a.zona = b.zona
  and a.is_human=b.is_human)
  ORDER BY a.mes,a.canal
),
tabla_principal AS (
  SELECT
  *,
  CASE
      WHEN channel_type IS NULL THEN 'voz'
      WHEN channel_type = 'voice' THEN 'voz'
      WHEN channel_type IN ('open','whatsapp','bot_wsp') THEN 'wsp'
      #WHEN channel_type = 'bot_wsp' THEN 'wsp'
      WHEN channel_type = 'webmessaging' THEN 'chat'
      WHEN channel_type = 'CC' AND is_human = 'HUMAN' THEN 'voz'
      WHEN channel_type = 'CC' AND is_human = 'BOTH' THEN 'voz'
      WHEN channel_type = 'CC' AND is_human = 'NOT_HUMAN' THEN 'voz'
      WHEN channel_type = 'CASES' THEN 'cases'
    END as canal,
    mercado as zona
  FROM `data-exp-contactcenter.100x100.new_calculated`
    
  
),
basefinal as (
SELECT 
* EXCEPT(category),
CASE
WHEN category = 'CAMBIO_VOLUNTARIO' THEN 'CAMBIO_VOLUNTARIO'
WHEN category = 'SIN INTENT' THEN 'OTROS'
WHEN category = 'INFORMACION_DE_VIAJE' THEN 'INFORMACION_DE_VIAJE'
WHEN category = 'VENTAS' THEN 'VENTAS'
WHEN category = 'SIN_CONTEXTO' THEN 'OTROS'
WHEN category = 'EXCEPCIONES' THEN 'EXCEPCIONES'
WHEN category = 'DEVOLUCIONES' THEN 'DEVOLUCIONES'
WHEN category = 'CHECK_IN' THEN 'CHECK_IN'
WHEN category = 'SILENCIO' THEN 'OTROS'
WHEN category = 'SERVICIOS_ESPECIALES' THEN 'SERVICIOS_ESPECIALES'
WHEN category = 'VENTAS y SERVICIOS_ESPECIALES' THEN 'SERVICIOS_ESPECIALES'
WHEN category = 'VENTAS_ANCILLARIES' THEN 'VENTAS_ANCILLARIES'
when category = 'VENTAS y VENTAS_ANCILLARIES' then 'VENTAS_ANCILLARIES'
WHEN category = 'LOGIN' THEN 'LOGIN'
WHEN category = 'PROBLEMAS_COMPRA_WEB' THEN 'VENTAS'
WHEN category = 'MASCOTAS' THEN 'SERVICIOS_ESPECIALES'
WHEN category = 'CORRECCION_NOMBRE' THEN 'CAMBIO_VOLUNTARIO'
WHEN category = 'RECLAMOS' THEN 'RECLAMOS'
WHEN category = 'CAMBIO_INVOLUNTARIO' THEN 'CAMBIO_INVOLUNTARIO'
WHEN category = 'Cambios Involuntarios' THEN 'CAMBIO_INVOLUNTARIO'
WHEN category = 'CANJE' THEN 'CANJE'
WHEN category = 'ASIGNACION_DE_ASIENTOS' THEN 'VENTAS_ANCILLARIES'
WHEN category = 'INFORMACION_DE_FRANQUICIA' THEN 'INFORMACION_DE_VIAJE'
WHEN category = 'RECLAMOS_EQUIPAJE' THEN 'RECLAMOS'
WHEN category = 'OTROS_FFP' THEN 'OTROS_FFP'
when category = 'OUTROS_FFP' THEN 'OTROS_FFP'
WHEN category = 'MENORES_NO_ACOMPANADOS' THEN 'SERVICIOS_ESPECIALES'
WHEN category = 'ACTUALIZAR_PERFIL_CUENTA' THEN 'OTROS_FFP'
WHEN category = 'SOLICITUD_DEVOLUCIONES' THEN 'DEVOLUCIONES'
WHEN category = 'SILENCE' THEN 'OTROS'
WHEN category = 'FFP' THEN 'OTROS_FFP'
WHEN category = 'CAMBIO_RUTA' THEN 'CAMBIO_VOLUNTARIO'
WHEN category = 'DEFAULT' THEN 'OTROS'
WHEN category = 'COMPROBANTE_COMPRA' THEN 'VENTAS'
WHEN category = 'ACREDITACION' THEN 'OTROS_FFP'
WHEN category = 'UPG' THEN 'CANJE'
#WHEN category = 'TRAVEL_VOUCHER' THEN 'OTROS'
WHEN category = 'CAMBIO_VOLUNTARIO_ERROR' THEN 'CAMBIO_VOLUNTARIO'
WHEN category = 'ESTADO_CASO' THEN 'RECLAMOS'
WHEN category = 'ENDOSO' THEN 'CAMBIO_VOLUNTARIO'
WHEN category = 'LATAM_WALLET' THEN 'OTROS'
WHEN category = 'RECLAMO_DEVOLUCIONES' THEN 'RECLAMOS'
WHEN category = 'SPLIT' THEN 'CAMBIO_VOLUNTARIO'
WHEN category = 'SILENCIO_AGENTE' THEN 'OTROS'
WHEN category = 'TRAVEL_VOUCHER' THEN 'TRAVEL_VOUCHER'
WHEN category = 'None' THEN 'OTROS'
ELSE 'NOT_CATEGORIZED'
END AS category
FROM
/*********************************************************/
(
SELECT 
tp.* EXCEPT(cat_bot,cat_pca,mercado,second_category,third_category),

case when factores.factor is null then 1 else factores.factor end as factor,
--1 as factor,
second_category,
third_category,
COALESCE(tp.cat_pca, tp.cat_bot,b.tip) AS category,

FROM tabla_principal AS tp
LEFT JOIN factores ON (tp.canal = factores.canal AND FORMAT_DATE('%Y-%m', tp.call_date) = factores.mes and tp.zona = factores.zona and tp.is_human=factores.is_human)
left join (select distinct TRIM(tip) as tip,conversationid as conversation_id FROM `data-exp-contactcenter.ws_tpo_resp.indicadores_t_stg`) as b on b.conversation_id = tp.conversation_id
/****************************

*****************************/
)

UNION ALL

SELECT
  'rrss' AS conversation_id,
  DATE(CONCAT(mes,'-01')) AS call_date,
  null AS skill_name,
  ARRAY_AGG('NO_FACTORY') AS factory_name,
  null AS market_code,
  canal AS channel_type,
  'HUMAN' AS is_human,
  null as skill_lookup,
  null as all_agents,
  canal AS canal,
  zona,
  valor AS factor,
  null,
  null,
  'NOT_CATEGORIZED' AS category,
  

FROM b
WHERE canal = 'rrss'
GROUP BY ALL),


/*pca AS(
  SELECT
  conversation_id_original as conversation_id,
  first_category,
  second_category,
  third_category
  FROM `cuscare-data-prod.post_call_analytics.pca_conversation_category`
  WHERE load_datetime  >= '2024-01-01' AND load_datetime < CURRENT_DATE()
  ),*/
-- 1. Calculamos los tiempos totales desde la tabla Quality (q)
quality_metrics AS (
    SELECT 
        conversation_id,
        -- Usamos IFNULL para que si un dato viene vacío lo trate como 0 y no anule la suma
        SUM(IFNULL(talk_time_second, 0)) as total_talk_time,
        SUM(IFNULL(held_time_second, 0)) as total_held_time,
        SUM(IFNULL(after_call_work_time_second, 0)) as total_acw
    FROM `cuscare-data-prod.contact_center_interaction.conversation_detail_unified`
    GROUP BY conversation_id
),
-- 2. Preparamos el NPS desde Medallia (m)
medallia_data AS (
    SELECT 
        conversation_id, 
        MAX(nps) as nps -- O AVG(nps), para asegurar una fila por ID
    FROM `data-exp-contactcenter.TR_Reporting.KS_NPS_CC_V3`
    GROUP BY conversation_id
),
retention as 
(
  SELECT conversation_id,
  is_hvc,
  is_recontact
   FROM `cus-data-prod.voicebot_metrics.voicebot_retention` 
where date(conversation_start_dt)>="2024-01-01"
)

,staff_latest AS (
  -- Último registro por agente según load_date
  SELECT
    agent_id,
    agent_bp_number,
    agent_name,
    supervisor_bp_number
  FROM `cuscare-data-prod.contact_center_staffing_model.staff_contact_center`
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY agent_id
    ORDER BY load_date DESC
  ) = 1
),

agents_conv AS (
  -- Todas las apariciones de agentes por conversación (ya con BP y supervisor)
  SELECT
    ps.conversation_id,
    ps.participant_id AS agent_id,
    s.agent_bp_number,
    s.agent_name,
    s.supervisor_bp_number,
    ps.load_datetime 
  FROM `cuscare-data-prod.contact_center_interaction_model.participant_session` ps
  left join  staff_latest as s  ON ps.participant_id = s.agent_id
  WHERE ps.purpose = "agent"
),

agents_agg AS (
  -- Resumen por conversación: último agente + concatenado de todos
  SELECT
    conversation_id,

    -- concat de todos los agentes que pasaron por la conversación
    STRING_AGG(
      DISTINCT CAST(agent_bp_number AS STRING),
      ','
    ) AS all_agent_bp_numbers,

        STRING_AGG(
      DISTINCT CAST(supervisor_bp_number AS STRING),
      ','
    ) AS all_supervisor_bp_numbers,

    -- último agente según el tiempo
    ARRAY_AGG(agent_bp_number ORDER BY load_datetime DESC LIMIT 1)[OFFSET(0)] AS last_agent_bp_number,
    ARRAY_AGG(agent_name ORDER BY load_datetime DESC LIMIT 1)[OFFSET(0)]      AS last_agent_name,
    ARRAY_AGG(supervisor_bp_number ORDER BY load_datetime DESC LIMIT 1)[OFFSET(0)] AS last_supervisor_bp_number
    

  FROM agents_conv
  GROUP BY conversation_id
),

fcr as (

  select
  conversation_id,
  first_value(is_first_call_resolution) over (partition by conversation_id order by participant_id) as is_first_call_resolution

  from `cuscare-data-prod.post_call_analytics.pca_resolution_fcr`
)

,compliance_unique AS (
  SELECT
    conversation_id,
    -- Traemos los pesos individuales si los necesitas
    m1_welcome_weight,
    m2_inquiry_weight,
    m3_empathy_weight,
    m4_expectation_adjustment_weight,
    m5_management_weight,
    m6_information_provision_weight,
    m7_service_confirmation_weight,
    m8_farewell_weight,
    -- Calculamos la nota total manejando los nulos para que no arruinen la suma
    (IFNULL(m1_welcome_weight,0) + IFNULL(m2_inquiry_weight,0) + 
     IFNULL(m3_empathy_weight,0) + IFNULL(m4_expectation_adjustment_weight,0) + 
     IFNULL(m5_management_weight,0) + IFNULL(m6_information_provision_weight,0) + 
     IFNULL(m7_service_confirmation_weight,0) + IFNULL(m8_farewell_weight,0)) as nota_calidad
  FROM `cuscare-data-prod.post_call_analytics.pca_compliance`
  -- Esta es la clave: particionamos por conversación pero elegimos solo una fila
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY conversation_id 
    ORDER BY participant_id DESC -- O 'load_datetime' si quieres el registro más reciente
  ) = 1
)

,final_base as (

select base.*,
CASE 
  WHEN market_code IN ('CL', 'CHILE') THEN 'CL'
  WHEN market_code IN ('BR', 'BRASIL','PT-BR','PT','PORTUGUÊS (BRASIL)') THEN 'BR'
  WHEN market_code IN ('AR', 'ARGENTINA') THEN 'AR'
  WHEN market_code IN ('PE', 'PERU') THEN 'PE'
  WHEN market_code IN ('CO', 'COLOMBIA') THEN 'CO'
  WHEN market_code IN ('UY', 'URUGUAY') THEN 'UY'
  WHEN market_code IN ('PY', 'PARAGUAY') THEN 'PY'
  WHEN market_code IN ('EC', 'ECUADOR') THEN 'EC'
  WHEN market_code IN ('MX', 'MEXICO') THEN 'MX'
  WHEN market_code IN ('US', 'USA') THEN 'US'
  WHEN market_code IN ('UK', 'REINO UNIDO', 'GRAN BRETAÑA') THEN 'GB'
  WHEN market_code IN ('FR', 'FRANCIA') THEN 'FR'
  WHEN market_code IN ('DE', 'ALEMANIA') THEN 'DE'
  WHEN market_code IN ('IT', 'ITALIA') THEN 'IT'
  WHEN market_code IN ('ES', 'ESPAÑA') THEN 'ES'
  WHEN market_code IN ('PT', 'PORTUGAL') THEN 'PT'
  WHEN market_code IN ('CH', 'SUIZA') THEN 'CH'
  WHEN market_code IN ('BE', 'BELGICA') THEN 'BE'
  WHEN market_code IN ('AT', 'AUSTRIA') THEN 'AT'
  WHEN market_code IN ('AU', 'AUSTRALIA') THEN 'AU'
  WHEN market_code IN ('NZ', 'NUEVA ZELANDA') THEN 'NZ'
  WHEN market_code IN ('CA', 'CANADA') THEN 'CA'
  WHEN market_code IN ('ZA', 'SUDAFRICA', 'ÁFRICA') THEN 'ZA'
  WHEN market_code IN ('DK', 'DINAMARCA') THEN 'DK'
  WHEN market_code IN ('SE', 'SUECIA') THEN 'SE'
  WHEN market_code IN ('NO', 'NORUEGA') THEN 'NO'
  WHEN market_code IN ('IE', 'IRLANDA') THEN 'IE'
  WHEN market_code IN ('IL', 'ISRAEL') THEN 'IL'
  WHEN market_code IN ('CARIBE') THEN 'CB' -- si quieres definir un código propio
  WHEN market_code IN ('EU', 'EUROPA') THEN 'EU'
  WHEN market_code IN ('ASIA') THEN 'AS'
  WHEN market_code IN ('CUALQUIER OTRO MERCADO', 'OTHERS') THEN 'OT'
  ELSE 'OT'
END AS country_code,

SAFE_DIVIDE((q.total_talk_time + q.total_held_time + q.total_acw ),base.factor) as aht,
m.nps,
base.factor as factor_pca,
case
when trim(fcr.is_first_call_resolution) = "true" then 1 
when trim(fcr.is_first_call_resolution) = "false" then 0
when trim(fcrchat.fcr_ai) = "resuelve" then 1 
when trim(fcrchat.fcr_ai) in ("deriva","crea caso","agente deja de contestar","short","no se puede hacer","posterga","falla sistema","recontacto","no se puede determinar") then 0  
else null end as fcr,
(m1_welcome_weight+m2_inquiry_weight+m3_empathy_weight+m4_expectation_adjustment_weight
+m5_management_weight+m6_information_provision_weight+m7_service_confirmation_weight
+m8_farewell_weight) as nota_calidad,
a.last_agent_bp_number,
a.last_agent_name,
a.last_supervisor_bp_number,
a.all_agent_bp_numbers,
a.all_supervisor_bp_numbers,
r.is_hvc,
r.is_recontact
from basefinal as base

LEFT JOIN quality_metrics q ON base.conversation_id = q.conversation_id
LEFT JOIN medallia_data m ON base.conversation_id = m.conversation_id
left join  fcr on base.conversation_id=fcr.conversation_id
left join (select distinct conversationid,fcr_ai from `data-exp-contactcenter.ws_tpo_resp.indicadores_t_stg`) as  fcrchat on base.conversation_id=fcrchat.conversationid
left join compliance_unique as d on base.conversation_id=d.conversation_id
LEFT JOIN agents_agg as a  ON base.conversation_id = a.conversation_id
left join retention as r on base.conversation_id = r.conversation_id
),
  
 
pro AS (
  SELECT
    DATE(call_date) AS call_date,
    canal,
    CASE WHEN market_code="BR" THEN "BR" ELSE "SSC" END AS market,
    SUM(CASE WHEN category<>"NOT_CATEGORIZED" THEN factor ELSE 0 END) AS fac_cat,
    COALESCE(SUM(factor),0) AS factor_sum,
   /* CASE
      WHEN COALESCE(SUM(factor),0) <> 0 THEN
        SAFE_DIVIDE(SUM(CASE WHEN category<>"NOT_CATEGORIZED" THEN factor ELSE 0 END), COALESCE(SUM(factor),0))
      ELSE NULL
    END AS factor_pca*/
    1 as factor_pca
  FROM final_base
  WHERE is_human="HUMAN"
    AND canal IN ('wsp','voz','chat')
  GROUP BY call_date, canal, market
),
with_factor_plus AS (
  SELECT
    fb.*,
    CASE
      WHEN fb.factor = 0 OR fb.factor IS NULL THEN 0
      WHEN (
        CASE
          WHEN fb.category="NOT_CATEGORIZED" THEN fb.factor
          WHEN fb.is_human="NOT_HUMAN" THEN fb.factor
          ELSE COALESCE(p.factor_pca,0)
        END
      ) = 0 THEN 0
      ELSE SAFE_DIVIDE(
        fb.factor,
        CASE
          WHEN fb.category="NOT_CATEGORIZED" THEN fb.factor
          WHEN fb.is_human="NOT_HUMAN" THEN fb.factor
          ELSE COALESCE(p.factor_pca,0)
        END
      )
    END AS factor_plus
  FROM final_base fb
  LEFT JOIN pro p
    ON DATE(fb.call_date) = p.call_date
   AND fb.canal = p.canal
   AND (CASE WHEN fb.market_code="BR" THEN "BR" ELSE "SSC" END) = p.market
),

/* 2) Factor de corrección (reemplaza tus UPDATEs) */
fc AS (
  SELECT
    DATE(call_date) AS fecha,
    canal,
    SAFE_DIVIDE(
      SUM(factor),
      SUM(CASE WHEN category <> 'NOT_CATEGORIZED' THEN factor_plus END)
    ) AS factor_correccion
  FROM with_factor_plus
  WHERE canal IN ('voz','wsp')
    AND is_human='HUMAN'
  GROUP BY fecha, canal
)

SELECT distinct
  wfp.* EXCEPT(factor_plus),
  CASE
    WHEN wfp.canal IN ('voz','wsp')
     AND wfp.is_human='HUMAN'
     AND wfp.category <> 'NOT_CATEGORIZED'
    AND fc.factor_correccion IS NOT NULL
    THEN wfp.factor_plus * fc.factor_correccion
    ELSE wfp.factor_plus
  END AS factor_plus
FROM with_factor_plus wfp
LEFT JOIN fc
 ON DATE(wfp.call_date) = fc.fecha
 AND wfp.canal = fc.canal;

 UPDATE `data-exp-contactcenter.100x100.third_calculated`
SET 
  fcr = NULL,
  nota_calidad = NULL
WHERE is_human = "HUMAN"
  AND canal = "voz"
  AND category = "NOT_CATEGORIZED"
  AND call_date > "2026-01-01"
  AND fcr IS NOT NULL;