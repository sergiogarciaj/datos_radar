CREATE OR REPLACE TABLE `cus-data-dev.radar.sgj_third`
PARTITION BY call_date
CLUSTER BY conversation_id AS

WITH

-- ============================================================
-- B: Demanda histórica (new_calculated2, pre-2026)
--    + datos actuales (contact_rate_master, 2026+)
-- ============================================================
b AS (

  -- Parte histórica: mapeo directo string → 'YYYY-MM' (sin roundtrip DATE)
  SELECT
    CASE mes
      WHEN 'Ene24' THEN '2024-01'  WHEN 'Feb24' THEN '2024-02'
      WHEN 'Mar24' THEN '2024-03'  WHEN 'Apr24' THEN '2024-04'
      WHEN 'May24' THEN '2024-05'  WHEN 'Jun24' THEN '2024-06'
      WHEN 'Jul24' THEN '2024-07'  WHEN 'Aug24' THEN '2024-08'
      WHEN 'Sep24' THEN '2024-09'  WHEN 'Oct24' THEN '2024-10'
      WHEN 'Nov24' THEN '2024-11'  WHEN 'Dec24' THEN '2024-12'
      WHEN 'Ene25' THEN '2025-01'  WHEN 'Feb25' THEN '2025-02'
      WHEN 'Mar25' THEN '2025-03'  WHEN 'Apr25' THEN '2025-04'
      WHEN 'May25' THEN '2025-05'  WHEN 'Jun25' THEN '2025-06'
      WHEN 'Jul25' THEN '2025-07'  WHEN 'Aug25' THEN '2025-08'
      WHEN 'Sep25' THEN '2025-09'  WHEN 'Oct25' THEN '2025-10'
      WHEN 'Nov25' THEN '2025-11'  WHEN 'Dec25' THEN '2025-12'
    END AS mes,
    canal,
    NULL    AS zona,
    'HUMAN' AS is_human,
    valor
  FROM (
    SELECT
      mes,
      SUM(demanda_voz_agente)                                                        AS voz,
      SUM(wa)                                                                        AS wsp,
      SUM(livechat)                                                                  AS chat,
      SUM(casos_validado_com_gabi)                                                   AS cases,
      SUM(redes_sociales_validado_rrss_tabela_jessie_ohmura_okedasem_marketing)      AS rrss
    FROM `data-exp-contactcenter.100x100.new_calculated2`
    GROUP BY mes
  )
  UNPIVOT(valor FOR canal IN (voz, wsp, chat, cases, rrss))

  UNION ALL

  -- Parte actual: 2026+ desde contact_rate_master
  SELECT
    FORMAT_DATE('%Y-%m', date) AS mes,
    CASE channel
      WHEN 'Calls'          THEN 'voz'
      WHEN 'WhatsApp Agent' THEN 'wsp'
      WHEN 'Chat Web'       THEN 'chat'
      WHEN 'Cases'          THEN 'cases'
      WHEN 'Social Media'   THEN 'rrss'
      WHEN 'Voice Bot'      THEN 'voz'
      WHEN 'WhatsApp Bot'   THEN 'wsp'
    END AS canal,
    CASE WHEN UPPER(country) = 'BR' THEN 'BR' ELSE 'SSC' END AS zona,
    CASE WHEN channel IN ('Voice Bot','WhatsApp Bot') THEN 'NOT_HUMAN' ELSE 'HUMAN' END AS is_human,
    SUM(N_R) AS valor
  FROM (
    SELECT
      date,
      channel,
      country,
      N_R
    FROM `data-exp-contactcenter.100x100.contact_rate_master`
    WHERE date >= DATE(2026, 01, 01)
      AND channel IN ('Calls','WhatsApp Agent','Chat Web','Cases','Social Media','Voice Bot','WhatsApp Bot')
  )
  GROUP BY mes, canal, zona, is_human
),

-- ============================================================
-- TABLA PRINCIPAL: Lectura única de new_calculated.
-- Se define ANTES que el CTE a para que a pueda derivarse
-- de aquí y evitar un segundo scan completo de la tabla.
-- ============================================================
tabla_principal AS (
  -- Columnas explícitas de new_calculated (equivalente al SELECT * del original).
  SELECT
    conversation_id,
    (SELECT agent_id FROM UNNEST(skill_lookup) ORDER BY aht DESC LIMIT 1) as agent_id,
    (SELECT bp_executive_num FROM UNNEST(skill_lookup) ORDER BY aht DESC LIMIT 1) as agent_bp,
    (SELECT aht FROM UNNEST(skill_lookup) ORDER BY aht DESC LIMIT 1) as agent_aht,
    call_date,
    skill_name,
    factory_name,
    market_code,
    channel_type,
    cat_bot,
    is_human,
    skill_lookup,
    all_agents,
    cat_pca,
    second_category,
    third_category,
    mercado,
    sag_name,
    CASE
      WHEN channel_type IS NULL                            THEN 'voz'
      WHEN channel_type = 'voice'                         THEN 'voz'
      WHEN channel_type IN ('open','whatsapp','bot_wsp')  THEN 'wsp'
      WHEN channel_type = 'webmessaging'                  THEN 'chat'
      WHEN channel_type = 'CC' AND is_human = 'HUMAN'     THEN 'voz'
      WHEN channel_type = 'CC' AND is_human = 'BOTH'      THEN 'voz'
      WHEN channel_type = 'CC' AND is_human = 'NOT_HUMAN' THEN 'voz'
      WHEN UPPER(channel_type) = 'CASES'                         THEN 'cases'
    END AS canal,
    mercado AS zona
  FROM `cus-data-dev.radar.sgj_intermedia`
),

-- a: conteo agregado derivado de tabla_principal (evita doble scan de new_calculated)
a AS (
  SELECT
    FORMAT_DATE('%Y-%m', call_date) AS mes,
    canal,
    zona,
    is_human,
    COUNT(conversation_id) AS valor
  FROM tabla_principal
  GROUP BY ALL
),

-- ============================================================
-- FACTORES DE ESCALADO
-- ============================================================
factores AS (
  -- Periodo pre-2026: ajuste global por canal/mes sin distinción de zona en b
  SELECT
    a.mes,
    a.canal,
    a.zona,
    a.is_human,
    CASE
      WHEN a.is_human = 'NOT_HUMAN' THEN 1.0
      ELSE
        CASE
          WHEN b.valor IS NULL OR b.valor = 0 OR a_global.valor_global = 0 THEN 0
          ELSE b.valor / a_global.valor_global
        END
    END AS factor
  FROM a
  LEFT JOIN (
    SELECT
      mes,
      canal,
      is_human,
      SUM(valor) AS valor_global
    FROM a
    WHERE mes < '2026-01'
    GROUP BY mes, canal, is_human
  ) a_global
    ON  a.mes      = a_global.mes
    AND a.canal    = a_global.canal
    AND a.is_human = a_global.is_human
  LEFT JOIN b
    ON  a.mes      = b.mes
    AND a.canal    = b.canal
    AND b.zona IS NULL
    AND a.is_human = b.is_human
  WHERE a.mes < '2026-01'

  UNION ALL

  -- Periodo 2026+: ajuste específico por zona e is_human
  SELECT
    a.mes,
    a.canal,
    a.zona,
    a.is_human,
    CASE
      WHEN b.valor IS NULL OR b.valor = 0 OR a.valor = 0 THEN 0
      ELSE b.valor / a.valor
    END AS factor
  FROM a
  LEFT JOIN b
    ON  a.mes      = b.mes
    AND a.canal    = b.canal
    AND a.zona     = b.zona
    AND a.is_human = b.is_human
  WHERE a.mes >= '2026-01'
),

-- ============================================================
-- BASE FINAL: Normalización de categorías + filas RRSS
-- ============================================================
basefinal AS (
  SELECT
    * EXCEPT(category),
    CASE category
      WHEN 'CAMBIO_VOLUNTARIO'             THEN 'CAMBIO_VOLUNTARIO'
      WHEN 'SIN INTENT'                    THEN 'OTROS'
      WHEN 'INFORMACION_DE_VIAJE'          THEN 'INFORMACION_DE_VIAJE'
      WHEN 'VENTAS'                        THEN 'VENTAS'
      WHEN 'SIN_CONTEXTO'                  THEN 'OTROS'
      WHEN 'EXCEPCIONES'                   THEN 'EXCEPCIONES'
      WHEN 'DEVOLUCIONES'                  THEN 'DEVOLUCIONES'
      WHEN 'CHECK_IN'                      THEN 'CHECK_IN'
      WHEN 'SILENCIO'                      THEN 'OTROS'
      WHEN 'SERVICIOS_ESPECIALES'          THEN 'SERVICIOS_ESPECIALES'
      WHEN 'VENTAS y SERVICIOS_ESPECIALES' THEN 'SERVICIOS_ESPECIALES'
      WHEN 'VENTAS_ANCILLARIES'            THEN 'VENTAS_ANCILLARIES'
      WHEN 'VENTAS y VENTAS_ANCILLARIES'   THEN 'VENTAS_ANCILLARIES'
      WHEN 'LOGIN'                         THEN 'LOGIN'
      WHEN 'PROBLEMAS_COMPRA_WEB'          THEN 'VENTAS'
      WHEN 'MASCOTAS'                      THEN 'SERVICIOS_ESPECIALES'
      WHEN 'CORRECCION_NOMBRE'             THEN 'CAMBIO_VOLUNTARIO'
      WHEN 'RECLAMOS'                      THEN 'RECLAMOS'
      WHEN 'CAMBIO_INVOLUNTARIO'           THEN 'CAMBIO_INVOLUNTARIO'
      WHEN 'Cambios Involuntarios'         THEN 'CAMBIO_INVOLUNTARIO'
      WHEN 'CANJE'                         THEN 'CANJE'
      WHEN 'ASIGNACION_DE_ASIENTOS'        THEN 'VENTAS_ANCILLARIES'
      WHEN 'INFORMACION_DE_FRANQUICIA'     THEN 'INFORMACION_DE_VIAJE'
      WHEN 'RECLAMOS_EQUIPAJE'             THEN 'RECLAMOS'
      WHEN 'OTROS_FFP'                     THEN 'OTROS_FFP'
      WHEN 'OUTROS_FFP'                    THEN 'OTROS_FFP'
      WHEN 'MENORES_NO_ACOMPANADOS'        THEN 'SERVICIOS_ESPECIALES'
      WHEN 'ACTUALIZAR_PERFIL_CUENTA'      THEN 'OTROS_FFP'
      WHEN 'SOLICITUD_DEVOLUCIONES'        THEN 'DEVOLUCIONES'
      WHEN 'SILENCE'                       THEN 'OTROS'
      WHEN 'FFP'                           THEN 'OTROS_FFP'
      WHEN 'CAMBIO_RUTA'                   THEN 'CAMBIO_VOLUNTARIO'
      WHEN 'DEFAULT'                       THEN 'OTROS'
      WHEN 'COMPROBANTE_COMPRA'            THEN 'VENTAS'
      WHEN 'ACREDITACION'                  THEN 'OTROS_FFP'
      WHEN 'UPG'                           THEN 'CANJE'
      WHEN 'CAMBIO_VOLUNTARIO_ERROR'       THEN 'CAMBIO_VOLUNTARIO'
      WHEN 'ESTADO_CASO'                   THEN 'RECLAMOS'
      WHEN 'ENDOSO'                        THEN 'CAMBIO_VOLUNTARIO'
      WHEN 'LATAM_WALLET'                  THEN 'OTROS'
      WHEN 'RECLAMO_DEVOLUCIONES'          THEN 'RECLAMOS'
      WHEN 'SPLIT'                         THEN 'CAMBIO_VOLUNTARIO'
      WHEN 'SILENCIO_AGENTE'               THEN 'OTROS'
      WHEN 'TRAVEL_VOUCHER'                THEN 'TRAVEL_VOUCHER'
      WHEN 'None'                          THEN 'OTROS'
      ELSE 'NOT_CATEGORIZED'
    END AS category
  FROM (
    SELECT
      tp.* EXCEPT(cat_bot, cat_pca, mercado, second_category, third_category),
      COALESCE(factores.factor, 1) AS factor,
      IF(tp.canal = 'cases', cases_cat.second_category, tp.second_category) AS second_category,
      IF(tp.canal = 'cases', cases_cat.third_category, tp.third_category) AS third_category,
      IF(
        tp.canal = 'cases',
        COALESCE(cases_cat.first_category, tp.cat_pca, tp.cat_bot, tip_data.tip),
        COALESCE(tp.cat_pca, tp.cat_bot, tip_data.tip)
      ) AS category
    FROM tabla_principal AS tp
    LEFT JOIN factores
      ON  tp.canal                            = factores.canal
      AND FORMAT_DATE('%Y-%m', tp.call_date)  = factores.mes
      AND (factores.zona is null or tp.zona   = factores.zona)
      AND tp.is_human                         = factores.is_human
    LEFT JOIN (
      SELECT DISTINCT TRIM(tip) AS tip, conversationid AS conversation_id
      FROM `data-exp-contactcenter.ws_tpo_resp.indicadores_t_stg`
    ) AS tip_data ON tip_data.conversation_id = tp.conversation_id
    LEFT JOIN `cuscare-data-prod.post_call_analytics.post_text_analytics_conversation_category` AS cases_cat ON cases_cat.conversation_id = tp.conversation_id
  )

  UNION ALL

  -- Filas de RRSS (demanda agregada, sin conversación individual)
  SELECT
    'rrss'                   AS conversation_id,
    NULL                     AS agent_id, 
    NULL                     AS agent_bp,
    NULL                     AS agent_aht,
    DATE(CONCAT(mes, '-01')) AS call_date,
    NULL                     AS skill_name,
    ARRAY_AGG('NO_FACTORY')  AS factory_name,
    NULL                     AS market_code,
    canal                    AS channel_type,
    'HUMAN'                  AS is_human,
    NULL                     AS skill_lookup,
    NULL                     AS all_agents,
    CAST(NULL AS STRING)     AS sag_name,
    canal                    AS canal,
    zona,
    valor                    AS factor,
    NULL,
    NULL,
    'NOT_CATEGORIZED'        AS category
  FROM b
  WHERE canal = 'rrss'
  GROUP BY ALL
),

-- ============================================================
-- ENRIQUECIMIENTO: NPS, Agentes, FCR, Calidad
-- (AHT proviene de skill_lookup[SAFE_OFFSET(0)].aht en sgj_calculated)
-- ============================================================
medallia_data AS (
  SELECT
    conversation_id,
    SAFE_CAST(advisor_bp_number AS INT64) AS agent_bp_number,
    last_sag_contact_description,
    nps
  FROM `cus-data-prod.dmt_customer_us.medallia_contact_center_responses`
),

retention AS (
  SELECT
    conversation_id,
    is_hvc,
    is_recontact
  FROM `cus-data-prod.voicebot_metrics.voicebot_retention`
  WHERE DATE(conversation_start_dt) >= '2024-01-01'
)


--CTE puente
,pte AS (
  SELECT DISTINCT
    m.conversation_id,
    m.participant_id,
    s.agent_id
  FROM (
    SELECT conversation_id, participant_id, SAFE_CAST(agent_bp_number AS INT64) AS agent_bp_number
    FROM `cuscare-data-prod.post_call_analytics.pca_audio_process`
    WHERE participant_id IS NOT NULL
    
    UNION DISTINCT
    
    SELECT conversation_id, participant_id, SAFE_CAST(agent_bp_number AS INT64) AS agent_bp_number
    FROM `cuscare-data-prod.post_call_analytics.post_text_analytics_audios_process`
    WHERE participant_id IS NOT NULL

    UNION DISTINCT

    SELECT conversation_id, participant_id, SAFE_CAST(agent_bp_number AS INT64) AS agent_bp_number
    FROM `cuscare-data-prod.post_call_analytics.post_whatsapp_analytics_process`
    WHERE participant_id IS NOT NULL
  ) m
  JOIN (
    SELECT
      agent_id,
      agent_bp_number
    FROM `cuscare-data-prod.contact_center_staffing.contact_center_staff_consolidated`
    QUALIFY ROW_NUMBER() OVER (
      PARTITION BY agent_id
      ORDER BY load_datetime DESC
    ) = 1
  ) s ON m.agent_bp_number = s.agent_bp_number
)

,name_agent AS (
  SELECT
    agent_bp_number,
    agent_name
  FROM `cuscare-data-prod.contact_center_staffing_model.staff_contact_center`
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY agent_bp_number
    ORDER BY load_date DESC
  ) = 1
),

staff_latest AS (
  SELECT
    agent_id,
    agent_bp_number,
    supervisor_bp_number
  FROM `cuscare-data-prod.contact_center_staffing.contact_center_staff_consolidated`
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY agent_id
    ORDER BY load_datetime DESC
  ) = 1
),

staff_latest_bp AS (
  SELECT
    agent_bp_number,
    supervisor_bp_number
  FROM `cuscare-data-prod.contact_center_staffing.contact_center_staff_consolidated`
  WHERE agent_bp_number IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY agent_bp_number
    ORDER BY load_datetime DESC
  ) = 1
),

agents_conv AS (
  SELECT
    ps.conversation_id,
    ps.participant_id     AS agent_id,
    s.agent_bp_number,
    n.agent_name,
    s.supervisor_bp_number,
    ps.load_datetime
  FROM `cuscare-data-prod.contact_center_interaction_model.participant_session` ps
  LEFT JOIN staff_latest AS s ON ps.participant_id   = s.agent_id
  LEFT JOIN name_agent   AS n ON s.agent_bp_number   = n.agent_bp_number
  WHERE ps.purpose = 'agent'
),

agents_agg AS (
  SELECT
    conversation_id,
    STRING_AGG(DISTINCT CAST(agent_bp_number      AS STRING), ',') AS all_agent_bp_numbers,
    STRING_AGG(DISTINCT CAST(supervisor_bp_number AS STRING), ',') AS all_supervisor_bp_numbers,
    ARRAY_AGG(agent_bp_number      ORDER BY load_datetime DESC LIMIT 1)[OFFSET(0)] AS last_agent_bp_number,
    ARRAY_AGG(agent_name           ORDER BY load_datetime DESC LIMIT 1)[OFFSET(0)] AS last_agent_name,
    ARRAY_AGG(supervisor_bp_number ORDER BY load_datetime DESC LIMIT 1)[OFFSET(0)] AS last_supervisor_bp_number
  FROM agents_conv
  GROUP BY conversation_id
),

-- QUALIFY deduplica correctamente: 1 fila por conversation_id.
-- La versión original retornaba N filas (window sin deduplicar),
-- lo que causaba los duplicados que el SELECT DISTINCT parchaba.
fcr AS (
  SELECT DISTINCT
    pca.conversation_id,
    pte.agent_id,
    is_first_call_resolution,
    reason_resolution_fcr
  FROM (
    SELECT conversation_id, participant_id, is_first_call_resolution, reason_resolution_fcr, load_datetime
    FROM `cuscare-data-prod.post_call_analytics.pca_resolution_fcr`
    UNION ALL
    SELECT conversation_id, participant_id, is_first_call_resolution, reason_resolution_fcr, load_datetime
    FROM `cuscare-data-prod.post_call_analytics.post_whatsapp_analytics_resolution_fcr`
  ) pca
  LEFT JOIN pte ON pte.conversation_id = pca.conversation_id AND pte.participant_id = pca.participant_id
  WHERE is_first_call_resolution IS NOT NULL
    AND load_datetime >= '2024-01-01'
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY pca.conversation_id, COALESCE(pte.agent_id, 'NULL_AGENT')
    ORDER BY pte.agent_id
  ) = 1
),

compliance_unique AS (
  SELECT
    c.conversation_id,
    pte.agent_id,
    m1_welcome_weight,
    m2_inquiry_weight,
    m3_empathy_weight,
    m4_expectation_adjustment_weight,
    m5_management_weight,
    m6_information_provision_weight,
    m7_service_confirmation_weight,
    m8_farewell_weight,
    (IFNULL(m1_welcome_weight, 0) + IFNULL(m2_inquiry_weight, 0) +
     IFNULL(m3_empathy_weight, 0) + IFNULL(m4_expectation_adjustment_weight, 0) +
     IFNULL(m5_management_weight, 0) + IFNULL(m6_information_provision_weight, 0) +
     IFNULL(m7_service_confirmation_weight, 0) + IFNULL(m8_farewell_weight, 0)) AS nota_calidad
  FROM `cuscare-data-prod.post_call_analytics.pca_compliance` c
  left join pte on pte.conversation_id = c.conversation_id and pte.participant_id = c.participant_id
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY c.conversation_id,pte.agent_id
    ORDER BY pte.agent_id DESC  
  ) = 1
),

-- ============================================================
-- FINAL BASE: Une todo con métricas de calidad
-- ============================================================
final_base AS (
  SELECT
    base.*,
    CASE
      WHEN market_code IN ('CL', 'CHILE')                                   THEN 'CL'
      WHEN market_code IN ('BR', 'BRASIL', 'PT-BR', 'PT', 'PORTUGUÊS (BRASIL)') THEN 'BR'
      WHEN market_code IN ('AR', 'ARGENTINA')                               THEN 'AR'
      WHEN market_code IN ('PE', 'PERU')                                    THEN 'PE'
      WHEN market_code IN ('CO', 'COLOMBIA')                                THEN 'CO'
      WHEN market_code IN ('UY', 'URUGUAY')                                 THEN 'UY'
      WHEN market_code IN ('PY', 'PARAGUAY')                                THEN 'PY'
      WHEN market_code IN ('EC', 'ECUADOR')                                 THEN 'EC'
      WHEN market_code IN ('MX', 'MEXICO')                                  THEN 'MX'
      WHEN market_code IN ('US', 'USA')                                     THEN 'US'
      WHEN market_code IN ('UK', 'REINO UNIDO', 'GRAN BRETAÑA')             THEN 'GB'
      WHEN market_code IN ('FR', 'FRANCIA')                                 THEN 'FR'
      WHEN market_code IN ('DE', 'ALEMANIA')                                THEN 'DE'
      WHEN market_code IN ('IT', 'ITALIA')                                  THEN 'IT'
      WHEN market_code IN ('ES', 'ESPAÑA')                                  THEN 'ES'
      WHEN market_code IN ('PT', 'PORTUGAL')                                THEN 'PT'
      WHEN market_code IN ('CH', 'SUIZA')                                   THEN 'CH'
      WHEN market_code IN ('BE', 'BELGICA')                                 THEN 'BE'
      WHEN market_code IN ('AT', 'AUSTRIA')                                 THEN 'AT'
      WHEN market_code IN ('AU', 'AUSTRALIA')                               THEN 'AU'
      WHEN market_code IN ('NZ', 'NUEVA ZELANDA')                           THEN 'NZ'
      WHEN market_code IN ('CA', 'CANADA')                                  THEN 'CA'
      WHEN market_code IN ('ZA', 'SUDAFRICA', 'ÁFRICA')                     THEN 'ZA'
      WHEN market_code IN ('DK', 'DINAMARCA')                               THEN 'DK'
      WHEN market_code IN ('SE', 'SUECIA')                                  THEN 'SE'
      WHEN market_code IN ('NO', 'NORUEGA')                                 THEN 'NO'
      WHEN market_code IN ('IE', 'IRLANDA')                                 THEN 'IE'
      WHEN market_code IN ('IL', 'ISRAEL')                                  THEN 'IL'
      WHEN market_code IN ('CARIBE')                                        THEN 'CB'
      WHEN market_code IN ('EU', 'EUROPA')                                  THEN 'EU'
      WHEN market_code IN ('ASIA')                                          THEN 'AS'
      WHEN market_code IN ('CUALQUIER OTRO MERCADO', 'OTHERS')              THEN 'OT'
      ELSE 'OT'
    END AS country_code,
    CASE
      WHEN base.canal = 'voz' THEN base.agent_aht
      ELSE SAFE_DIVIDE(base.agent_aht, base.factor)
    END AS aht,
    m.nps,
    base.factor AS factor_pca,
    CASE
      WHEN base.canal = 'cases' THEN
        CASE
          WHEN TRIM(SAFE_CAST(cases_fcr.is_first_call_resolution AS STRING)) = 'true' THEN 1
          WHEN TRIM(SAFE_CAST(cases_fcr.is_first_call_resolution AS STRING)) = 'false' THEN 0
          ELSE NULL
        END
      WHEN TRIM(fcr.is_first_call_resolution) = 'true'  THEN 1
      WHEN TRIM(fcr.is_first_call_resolution) = 'false' THEN 0
      WHEN TRIM(fcrchat.fcr_ai) = 'resuelve'            THEN 1
      WHEN TRIM(fcrchat.fcr_ai) IN (
        'deriva', 'crea caso', 'agente deja de contestar', 'short',
        'no se puede hacer', 'posterga', 'falla sistema',
        'recontacto', 'no se puede determinar'
      )                                                 THEN 0
      ELSE NULL
    END AS fcr,
    IF(base.canal = 'cases', cases_fcr.reason_resolution_fcr, fcr.reason_resolution_fcr) AS reason_resolution_fcr,
    -- Reutiliza nota_calidad precalculada con IFNULL desde compliance_unique.
    -- La suma directa de la versión original producía NULL si algún peso era NULL.
    d.nota_calidad,
    -- alias ag reemplaza alias a para evitar shadowing del CTE a
    base.agent_bp AS last_agent_bp_number,
    na.agent_name AS last_agent_name,
    COALESCE(sl.supervisor_bp_number, sl_bp.supervisor_bp_number) AS last_supervisor_bp_number,
    ag.all_agent_bp_numbers,
    ag.all_supervisor_bp_numbers,
    r.is_hvc,
    r.is_recontact
  FROM basefinal AS base
  LEFT JOIN medallia_data     m       
    ON base.conversation_id = m.conversation_id
    AND (base.canal <> 'voz' OR base.is_human = 'NOT_HUMAN' OR base.agent_bp = m.agent_bp_number)
  -- Modificado: FCR ahora realiza el cruce utilizando conversation_id y agent_id
  LEFT JOIN fcr                       ON base.conversation_id = fcr.conversation_id AND (fcr.agent_id IS NULL OR base.agent_id = fcr.agent_id)
  LEFT JOIN (
    SELECT DISTINCT conversationid, fcr_ai
    FROM `data-exp-contactcenter.ws_tpo_resp.indicadores_t_stg`
  ) AS fcrchat                        ON base.conversation_id = fcrchat.conversationid
  LEFT JOIN `cuscare-data-prod.post_call_analytics.post_text_analytics_resolution_fcr` AS cases_fcr
    ON base.conversation_id = cases_fcr.conversation_id
  LEFT JOIN compliance_unique d       ON base.conversation_id = d.conversation_id AND (d.agent_id IS NULL OR base.agent_id = d.agent_id)
  LEFT JOIN name_agent        na      ON base.agent_bp        = na.agent_bp_number
  LEFT JOIN staff_latest      sl      ON base.agent_id        = sl.agent_id
  LEFT JOIN staff_latest_bp   sl_bp   ON base.agent_bp        = sl_bp.agent_bp_number
  LEFT JOIN agents_agg        ag      ON base.conversation_id = ag.conversation_id
  LEFT JOIN retention         r       ON base.conversation_id = r.conversation_id
),

-- ============================================================
-- FACTOR PCA (proporcionalidad por categoría)
-- ============================================================
pro AS (
  SELECT
    DATE(call_date)                                                      AS call_date,
    canal,
    market_code,
    SUM(CASE WHEN category <> 'NOT_CATEGORIZED' THEN factor ELSE 0 END) AS fac_cat,
    COALESCE(SUM(factor), 0)                                            AS factor_sum
  FROM final_base
  WHERE is_human = 'HUMAN'
    AND (
      canal IN ('wsp', 'voz', 'chat')
      OR (canal = 'cases' AND DATE(call_date) >= '2026-01-01')
    )
  GROUP BY call_date, canal, market_code
),

with_factor_plus AS (
  SELECT
    fb.*,
    CASE
      -- Si factor es 0 o nulo, factor_plus es 0
      WHEN fb.factor = 0 OR fb.factor IS NULL THEN 0

      -- HUMAN, canal en ('wsp', 'voz', 'chat', 'cases') y fila categorizada -> se escala proporcionalmente.
      -- (Para cases, solo si es 2026+ y p.fac_cat > 0)
      WHEN fb.is_human = 'HUMAN' 
           AND (
             fb.canal IN ('wsp', 'voz', 'chat')
             OR (fb.canal = 'cases' AND DATE(fb.call_date) >= '2026-01-01')
           )
           AND fb.category <> 'NOT_CATEGORIZED' 
           AND p.fac_cat > 0 THEN
        SAFE_DIVIDE(fb.factor, SAFE_DIVIDE(p.fac_cat, p.factor_sum))

      -- NOT_CATEGORIZED -> factor_plus = 0 (excepto cases pre-2026)
      WHEN fb.category = 'NOT_CATEGORIZED' 
           AND (fb.canal <> 'cases' OR DATE(fb.call_date) < '2026-01-01') THEN
        IF(fb.canal = 'cases', fb.factor, 0)
        
      -- NOT_CATEGORIZED para cases 2026+ -> 0
      WHEN fb.category = 'NOT_CATEGORIZED' THEN 0

      -- NOT_HUMAN -> factor_plus = 1.0 (según el comportamiento original)
      WHEN fb.is_human = 'NOT_HUMAN' THEN 1.0

      -- Fallback para otros canales/casos (como cases pre-2026 o cases sin datos de pro)
      ELSE fb.factor
    END AS factor_plus
  FROM final_base fb
  LEFT JOIN pro p
    ON  DATE(fb.call_date) = p.call_date
    AND fb.canal           = p.canal
    AND fb.market_code     = p.market_code
)

-- ============================================================
-- SELECT FINAL
-- El UPDATE original (fcr/nota_calidad = NULL para voz
-- NOT_CATEGORIZED > 2026-01-01) queda integrado aquí como
-- expresiones CASE, eliminando la segunda pasada DML.
-- ============================================================
SELECT DISTINCT
  wfp.* EXCEPT(fcr, nota_calidad),
  -- UPDATE integrado: anula fcr para voz NOT_CATEGORIZED posterior a 2026-01-01
  CASE
    WHEN wfp.is_human   = 'HUMAN'
      AND wfp.canal     = 'voz'
      AND wfp.category  = 'NOT_CATEGORIZED'
      AND DATE(wfp.call_date) > '2026-01-01'
    THEN NULL
    ELSE wfp.fcr
  END AS fcr,
  -- UPDATE integrado: anula nota_calidad solo cuando fcr tampoco era NULL
  -- (replica exactamente la condición AND fcr IS NOT NULL del UPDATE original)
  CASE
    WHEN wfp.is_human   = 'HUMAN'
      AND wfp.canal     = 'voz'
      AND wfp.category  = 'NOT_CATEGORIZED'
      AND DATE(wfp.call_date) > '2026-01-01'
      AND wfp.fcr IS NOT NULL
    THEN NULL
    ELSE wfp.nota_calidad
  END AS nota_calidad
FROM with_factor_plus wfp