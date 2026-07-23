DROP TABLE IF EXISTS `cus-data-dev.radar.sgj_calculated`;

CREATE OR REPLACE TABLE `cus-data-dev.radar.sgj_calculated`
PARTITION BY call_date
CLUSTER BY conversation_id AS



WITH agent_data AS (
  SELECT
    agent_id,
    agent_bp_number,
    agent_email,
    supervisor_bp_number
  FROM `cuscare-data-prod.contact_center_staffing.contact_center_staff_consolidated`
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY agent_id
    ORDER BY load_datetime DESC
  ) = 1
),

ranked_staff AS (
  SELECT 
    bp_num,
    LOWER(employee_email) AS employee_email,
    ROW_NUMBER() OVER(PARTITION BY LOWER(employee_email) ORDER BY load_dt DESC) AS rn
  FROM `sp-te-segdlak-prod-ky3g.dmt_hhrr_staffing_us.staff_history`
  WHERE employee_email IS NOT NULL
),

sap as (
SELECT 
  bp_num,
  employee_email,
  /* Aquí puedes listar las columnas específicas de tu '*' si lo deseas */
FROM ranked_staff
WHERE rn = 1
),

ret AS (
  SELECT
    conversation_id,
    ANY_VALUE(market_code) AS market_code
  FROM `cuscare-data-prod.virtual_assistant_metrics.bot_retention`
  WHERE DATE(conversation_start_datetime) >= '2024-01-01'
    AND DATE(conversation_start_datetime) <= CURRENT_DATE()
  GROUP BY conversation_id
),

basequ_enriched AS ( 
  SELECT DISTINCT 
    qua.conversation_id, 
    qua.conversation_date AS call_date,
    qua.queue_name AS skill_name, 
    qua.factory_name AS factory_name, 
    qua.talk_time_second + COALESCE(qua.held_time_second, 0) + COALESCE(qua.after_call_work_time_second, 0) AS aht, 
    qua.message_type, 
    qua.agent_bp_number AS bp_executive_num,
    qua.agent_id,
    qua.sag_name AS sag_name,
    -- Columnas explícitas del diccionario de skills
    sk.Canal_de_Atencion,
    sk.Departamento_SAG,
    sk.Division,
    sk.Fabrica AS Fabrica_dic,
    sk.ID_Cola,
    sk.Cola_con_Demanda,
    sk.Jefatura,
    sk.SubGerente,
    sk.Gerencia,
    sk.Script,
    sk.ID_Script,
    ret.market_code
  FROM `cuscare-data-prod.contact_center_interaction.conversation_detail_unified` AS qua 
  LEFT JOIN (
    -- Deduplicación preventiva de skills
    SELECT * EXCEPT (rn)
    FROM (
      SELECT *,
        ROW_NUMBER() OVER (
          PARTITION BY TRIM(Nombre_de_Cola)
          ORDER BY
            (CASE WHEN Gerencia IS NOT NULL AND Gerencia != 'N/A' THEN 0 ELSE 1 END) ASC,
            (CASE WHEN ID_Cola IS NOT NULL AND ID_Cola != 'N/A' THEN 0 ELSE 1 END) ASC,
            (CASE WHEN Cola_con_Demanda = 'SI' THEN 0 ELSE 1 END) ASC,
            (CASE WHEN SubGerente IS NOT NULL AND SubGerente != 'N/A' THEN 0 ELSE 1 END) ASC,
            (CASE WHEN Script IS NOT NULL AND Script != 'N/A' THEN 0 ELSE 1 END) ASC
        ) AS rn
      FROM `data-exp-contactcenter.100x100.asociacion_skill`
    )
    WHERE rn = 1
  ) sk 
    ON TRIM(sk.Nombre_de_Cola) = TRIM(qua.queue_name)
  LEFT JOIN ret 
    ON qua.conversation_id = ret.conversation_id
  WHERE 1=1
    --AND EXTRACT(MONTH FROM qua.conversation_date) = 1
    --AND EXTRACT(YEAR FROM qua.conversation_date) = 2026   
    AND EXTRACT(YEAR FROM qua.conversation_date) >= 2024 
    AND qua.conversation_date <= CURRENT_DATE() 
    AND qua.factory_name IN (
      'AeC', 'Almacontact', 'KONECTA BR', 'Konecta', 
      'Estado', 'Augusta', 'Field Support Canales', 'Field Support Brasil'
    ) 
    AND qua.originating_direction_type = 'inbound' 
    AND qua.talk_time_second IS NOT NULL 
    AND UPPER(qua.queue_name) NOT LIKE '%CARGO%'
    AND TRIM(qua.queue_name) NOT IN (
      'AMC_WSP_BAG_ES',
      'NO_ USAR_ KON_BR_WSP_BAG_PT',
      'NO_USAR_KON_BR_WSP_BAG_PT',
      'AEC_WSP_BAG_PT',
      'AMC_WSP_BAG_EN',
      'KON_BR_WSP_BAG_PROACTIVE_PT',
      'AMC_WSP_BAG_PROACTIVE_ES',
      'AEC_WSP_BAG_PROACTIVE_PT',
      'AEC_WSP_BAG_SOLIX_Y_ENVIO_DOCS_PT',
      'AMC_WSP_BAG_PROACTIVE_EN',
      'AMC_CASO_EQUIPAJE_ES',
      'AMC_TRANSFER_EQUIPAJE_ES',
      'KON_BR_WSP_BAG_OUTBOUND_PT',
      'AMC_CASO_EQUIPAJE_EN',
      'AEC_PROBLEMAS_EQUIPAJE_PT',
      'KON_BR_HUB_QUIEBRE_EQUIPAJE_PT',
      'AEC_VOZ_EQUIPAJES_TRANSFER_PT'
    )
)


--CTE puente
,pte AS (
  SELECT 
    participant_id, 
    agent_id
  FROM (
    SELECT 
      participant_id, 
      user_id as agent_id,
      -- Cambia el ORDER BY según tu lógica (ej. por una columna de fecha)
      ROW_NUMBER() OVER (PARTITION BY participant_id ORDER BY user_id DESC) as rn
    FROM `cuscare-data-prod.contact_center_interaction_model.participant_session`
  )
  WHERE rn = 1
)

-- CTE Categorías Crudas (PCA Voz + Chat/WhatsApp)
,raw_data AS (
  SELECT
    conversation_id,
    pte.agent_id,
    first_category,
    second_category,
    third_category
  FROM `cuscare-data-prod.post_call_analytics.pca_conversation_category` cat   
  LEFT JOIN pte ON pte.participant_id = cat.participant_id
  WHERE load_datetime >= '2024-01-01' 
    AND load_datetime < CURRENT_DATE()

  UNION ALL

  SELECT
    conversation_id,
    pte.agent_id,
    first_category,
    second_category,
    third_category
  FROM `cuscare-data-prod.post_call_analytics.post_whatsapp_analytics_conversation_category` cat   
  LEFT JOIN pte ON pte.participant_id = cat.participant_id
  WHERE load_datetime >= '2024-01-01' 
    AND load_datetime < CURRENT_DATE()
),

-- CTE PCA por Agente: Obtiene la mejor categoría para cada par (conversation_id, agent_id)
pca_by_agent AS (
  SELECT * EXCEPT(rn)
  FROM (
    SELECT
      conversation_id,
      agent_id,
      first_category,
      second_category,
      third_category,
      ROW_NUMBER() OVER(
        PARTITION BY conversation_id, COALESCE(agent_id, 'NULL_AGENT')
        ORDER BY 
          (CASE WHEN first_category IN ('OTROS', 'SIN_CONTEXTO') THEN 1 ELSE 0 END) ASC
      ) AS rn
    FROM raw_data
  )
  WHERE rn = 1
),

-- CTE PCA a nivel conversación para obtener el array completo de agentes
pca_convo AS (
  SELECT
    conversation_id,
    ARRAY_AGG(
      STRUCT(
        agent_id,
        first_category,
        second_category,
        third_category
      ) ORDER BY 
        (CASE WHEN first_category IN ('OTROS', 'SIN_CONTEXTO') THEN 1 ELSE 0 END) ASC, 
        agent_id ASC
    ) AS all_agents
  FROM raw_data
  GROUP BY conversation_id
),

-- Procesamiento unificado y detallado. 
-- Mapea las categorías PCA a nivel de segmento antes de envolverlas en arrays.
qu AS (
  SELECT
    b.conversation_id,
    b.call_date,
    b.message_type,
    b.market_code,
    b.Canal_de_Atencion, 
    b.sag_name,
    -- Unión inteligente: prioriza coincidencia exacta, de lo contrario fallback al agente nulo de PCA
    COALESCE(pca_exact.first_category, pca_fallback.first_category) AS first_category,
    COALESCE(pca_exact.second_category, pca_fallback.second_category) AS second_category,
    COALESCE(pca_exact.third_category, pca_fallback.third_category) AS third_category,
    -- Arrays de un solo elemento para mantener la estructura compatible
    [b.skill_name] AS skill_name,
    [b.factory_name] AS factory_name,
    [b.aht] AS aht_by_skill,
    [STRUCT(
      b.skill_name AS skill_name,
      b.bp_executive_num,
      b.agent_id,
      b.aht,
      b.Canal_de_Atencion,
      b.Departamento_SAG,
      b.Division,
      b.Fabrica_dic,
      b.ID_Cola,
      b.Cola_con_Demanda,
      b.Jefatura,
      b.SubGerente,
      b.Gerencia,
      b.Script,
      b.ID_Script
    )] AS skill_lookup,
    IF(b.bp_executive_num IS NULL, [], [b.bp_executive_num]) AS bp_executive_num,
    IF(b.agent_id IS NULL, [], [b.agent_id]) AS agent_id
  FROM basequ_enriched AS b
  -- 1. Intentar unir por conversación y agente exacto
  LEFT JOIN pca_by_agent AS pca_exact
    ON b.conversation_id = pca_exact.conversation_id
    AND b.agent_id = pca_exact.agent_id
  -- 2. Si no hay agente exacto, usar la fila donde agent_id es NULL para esa conversación
  LEFT JOIN pca_by_agent AS pca_fallback
    ON b.conversation_id = pca_fallback.conversation_id
    AND pca_fallback.agent_id IS NULL
),

-- CTE Casos: Filtros aplicados a reclamos/casos humanos
base AS (
  SELECT
    c.ticket_id,
    created_dt,
    agent_group_name,
    factory_name,
    CASE WHEN language_name LIKE 'PT%' THEN 'BR' ELSE 'SSC' END AS language_name,
    contact_form_name,
    agent_name,
    subject_desc,
    tag_list,
    solved_dt,
    claim_ai_typification,
    claim_ai_subtypification,
    CASE
      when c.agent_email="4194242@outsourcing-account.com" then 4194242
      when c.agent_email="4306874@outsourcing-account.com" then 4306874
      when c.agent_email="4357929@outsourcing-account.com" then 4357929
      when c.agent_email="4365466@outsourcing-account.com" then 4365466
      when ad.agent_bp_number IS NOT NULL then ad.agent_bp_number
      when ad.agent_bp_number is null then sap.bp_num
      else null
      end as agent_bp_number,
    ad.agent_id,
    c.agent_email
  FROM `cuscare-data-prod.cases.cus_claim` AS c
  LEFT JOIN (
    SELECT
      c_in.ticket_id,
      ad_in.agent_bp_number,
      ad_in.agent_id,
      ROW_NUMBER() OVER (
        PARTITION BY c_in.ticket_id
        ORDER BY
          ABS(DATE_DIFF(PARSE_DATE('%Y%m', CAST(ad_in.period_id AS STRING)), DATE_TRUNC(DATE(c_in.created_dt), MONTH), MONTH)) ASC,
          CASE WHEN ad_in.period_id >= CAST(FORMAT_DATE('%Y%m', DATE(c_in.created_dt)) AS INT64) THEN 0 ELSE 1 END ASC,
          ad_in.load_datetime DESC
      ) AS rn
    FROM `cuscare-data-prod.cases.cus_claim` c_in
    JOIN `cuscare-data-prod.contact_center_staffing.contact_center_staff_consolidated` ad_in
      ON LOWER(c_in.agent_email) = LOWER(ad_in.agent_email)
  ) ad ON c.ticket_id = ad.ticket_id AND ad.rn = 1
  left join sap on lower(c.agent_email)=sap.employee_email
  WHERE 1=1
    --AND created_dt between '2026-01-01' and '2026-01-31'
    AND EXTRACT(YEAR FROM created_dt) IN (2024, 2025, 2026)
    AND NOT REGEXP_CONTAINS(tag_list, r"monoquebrado|multiquebrado")
    AND tag_list NOT LIKE '%project_child%'
    AND UPPER(agent_name) != 'LATAM AIRLINES'
    AND NOT REGEXP_CONTAINS(UPPER(subject_desc), r"TEST GOPE")
    AND NOT REGEXP_CONTAINS(agent_group_name, r"(?i)SOPORTE|SUPORTE")
    AND DATETIME_DIFF(solved_dt, created_dt, SECOND) > 10
    AND (
      -- Caso general
      (
        agent_group_name != 'HVC KON BR'
        AND UPPER(contact_form_name) NOT IN ('AGWS', 'WEB DEVOLUCIONES', 'URA', 'SPECIAL SERVICES')
      )
      OR
      -- Excepción específica
      (
        agent_group_name = 'HVC KON BR'
        AND UPPER(contact_form_name) = 'SPECIAL SERVICES'
      )
    )
),

-- CTE Bots Unificado: Interacciones de bots (Voz y WhatsApp)
bots AS ( 
  SELECT 
    conversation_id AS interaction_id,
    entity_id,
    customer_id,
    DATE(conversation_start_datetime) AS call_date,
    market_code,
    channel_type,
    is_voicebot,
    is_has_queue,
    intent_type,
    category_voicebot_typification,
    voicebot_category_process
  FROM `cuscare-data-prod.virtual_assistant_metrics.bot_retention`
  WHERE 1=1
    --AND DATE(conversation_start_datetime) between '2026-01-01' and '2026-01-31'
    AND DATE(conversation_start_datetime) >= '2024-01-01' 
    AND DATE(conversation_start_datetime) < CURRENT_DATE()
    AND originating_direction_type = 'inbound'
    AND is_voicebot = 1
    AND is_has_queue = 0
    AND channel_type IN ('voice', 'message')
),

-- CTE Unión de Canales de Llamadas (Humanas y Bots)
full_calls AS (
  SELECT 
    COALESCE(qu.conversation_id, bot.interaction_id) AS conversation_id,
    COALESCE(qu.call_date, bot.call_date) AS call_date,
    qu.skill_name,
    qu.factory_name AS factory_name,
    COALESCE(SAFE_CAST(qu.market_code AS STRING), bot.market_code) AS market_code,
    COALESCE(qu.message_type, bot.channel_type) AS channel_type,
    bot.category_voicebot_typification AS cat_bot,
    CASE
      WHEN qu.conversation_id IS NULL THEN 'NOT_HUMAN'
      WHEN bot.interaction_id IS NULL THEN 'HUMAN'
      WHEN qu.conversation_id = bot.interaction_id THEN 'BOTH'
    END AS is_human,
    qu.skill_lookup,
    qu.sag_name,
    -- Pasamos las categorías mapeadas por segmento
    qu.first_category AS cat_pca,
    qu.second_category,
    qu.third_category
  FROM qu
  FULL JOIN (
    SELECT 
      interaction_id, 
      call_date, 
      market_code, 
      channel_type, 
      category_voicebot_typification 
    FROM bots 
    WHERE channel_type = 'voice'
  ) AS bot
    ON qu.conversation_id = bot.interaction_id
  UNION ALL
  SELECT
    interaction_id AS conversation_id,
    call_date,
    NULL AS skill_name,
    NULL AS factory_name,
    market_code,
    'bot_wsp' AS channel_type,
    category_voicebot_typification AS cat_bot,
    'NOT_HUMAN' AS is_human,
    NULL AS skill_lookup,
    CAST(NULL AS STRING) AS sag_name,
    NULL AS cat_pca,
    NULL AS second_category,
    NULL AS third_category
  FROM bots
  WHERE channel_type = 'message'
),

-- CTE Unión Temporal (Llamadas + Casos)
final_union AS (
  SELECT 
    full_calls.conversation_id,
    full_calls.call_date,
    full_calls.skill_name,
    full_calls.factory_name,
    full_calls.market_code,
    full_calls.channel_type,
    full_calls.cat_bot,
    full_calls.is_human,
    full_calls.skill_lookup,
    full_calls.cat_pca,
    full_calls.second_category,
    full_calls.third_category,
    full_calls.sag_name,
    -- Adjuntamos el historial completo de agentes desde la CTE agregada a nivel de conversación
    pca_convo.all_agents,
    null as agent_email,
  FROM full_calls
  LEFT JOIN pca_convo 
    ON full_calls.conversation_id = pca_convo.conversation_id

  UNION ALL

  SELECT
    ticket_id AS conversation_id,
    DATE(MIN(created_dt)) AS call_date,
    ARRAY_AGG(DISTINCT agent_group_name IGNORE NULLS) AS skill_name,
    ARRAY_AGG(DISTINCT COALESCE(factory_name,'NO_FACTORY') IGNORE NULLS) AS factory_name,
    ARRAY_AGG(language_name IGNORE NULLS ORDER BY created_dt DESC LIMIT 1)[OFFSET(0)] AS market_code,
    'cases' AS channel_type,
    ARRAY_AGG(claim_ai_typification IGNORE NULLS ORDER BY created_dt DESC LIMIT 1)[OFFSET(0)] AS cat_bot,
    'HUMAN' AS is_human,

    -- MOLDE REAL ALINEADO PARA CASES
    [STRUCT(
      CAST(NULL AS STRING) AS skill_name,
      CAST(agent_bp_number AS INT64) AS bp_executive_num,
      ANY_VALUE(agent_id) AS agent_id,
      CAST(NULL AS FLOAT64) AS aht,
      'cases' AS Canal_de_Atencion,
      CAST(NULL AS STRING) AS Departamento_SAG,
      CAST(NULL AS STRING) AS Division,
      CAST(NULL AS STRING) AS Fabrica_dic,
      CAST(NULL AS STRING) AS ID_Cola, 
      CAST(NULL AS STRING) AS Cola_con_Demanda,
      CAST(NULL AS STRING) AS Jefatura,
      CAST(NULL AS STRING) AS SubGerente,
      CAST(NULL AS STRING) AS Gerencia,
      CAST(NULL AS STRING) AS Script,
      CAST(NULL AS STRING) AS ID_Script
    )] AS skill_lookup,

    ARRAY_AGG(claim_ai_subtypification IGNORE NULLS ORDER BY created_dt DESC LIMIT 1)[OFFSET(0)] AS cat_pca,
    NULL AS second_category,
    NULL AS third_category,
    CAST(NULL AS STRING) AS sag_name,
    NULL AS all_agents,
    agent_email,
  FROM base
  GROUP BY ticket_id, agent_bp_number, agent_email
)

-- INSERCIÓN FINAL Y RESOLUCIÓN DE MERCADOS
--, calculated as (
SELECT 
  u.conversation_id,
  u.call_date,
  u.skill_name,
  u.factory_name,
  COALESCE(u.market_code, UPPER(s.country), 'SSC') AS market_code,
  case when u.channel_type is null then 'voice' else u.channel_type end as channel_type,
  u.cat_bot,
  u.is_human,
  u.skill_lookup,
  u.cat_pca,
  u.second_category,
  u.third_category,
  u.all_agents,
  u.agent_email,
  u.sag_name,
  CASE 
    WHEN u.market_code = 'BR' THEN 'BR'
    WHEN (u.market_code IS NULL AND s.country IS NOT NULL) THEN UPPER(s.country)
    WHEN u.market_code IS NOT NULL THEN 'SSC'
    ELSE 'SSC'
  END AS mercado
FROM final_union AS u
LEFT JOIN `data-exp-contactcenter.ws_tpo_resp.novoz` AS s
  ON u.skill_name[SAFE_OFFSET(0)] = s.sagg