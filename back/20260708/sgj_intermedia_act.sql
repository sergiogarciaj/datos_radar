DECLARE start_date DATE;
SET start_date = DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH);

CREATE OR REPLACE TABLE `cus-data-dev.radar.sgj_intermedia_temp` AS
WITH 
-- 1. Agrupación preliminar del segmento que requiere consolidación
grouped_raw_agg AS (
  SELECT
    conversation_id,
    ANY_VALUE(call_date) AS call_date,
    ARRAY_CONCAT_AGG(skill_name) AS skill_name_raw,
    ARRAY_CONCAT_AGG(factory_name) AS factory_name_raw,
    ANY_VALUE(market_code) AS market_code,
    ANY_VALUE(channel_type) AS channel_type,
    ANY_VALUE(cat_bot) AS cat_bot,
    ANY_VALUE(is_human) AS is_human,
    ARRAY_CONCAT_AGG(skill_lookup) AS skill_lookup_raw,
    ARRAY_CONCAT_AGG(all_agents) AS all_agents_raw,
    ANY_VALUE(mercado) AS mercado,
    ANY_VALUE(cat_pca) AS fallback_cat_pca,
    ANY_VALUE(second_category) AS fallback_second_category,
    ANY_VALUE(third_category) AS fallback_third_category
  FROM `cus-data-dev.radar.sgj_calculated`
  WHERE channel_type IN ('webmessaging', 'whatsapp')
    AND is_human = 'HUMAN'
    AND call_date >= start_date -- ⚡ OPTIMIZACIÓN
  GROUP BY conversation_id
),

-- 2. Deduplicación de arreglos
grouped_raw AS (
  SELECT
    conversation_id,
    call_date,
    CASE 
      WHEN skill_name_raw IS NULL THEN NULL
      ELSE ARRAY(SELECT DISTINCT x FROM UNNEST(skill_name_raw) x)
    END AS skill_name,
    CASE 
      WHEN factory_name_raw IS NULL THEN NULL
      ELSE ARRAY(SELECT DISTINCT x FROM UNNEST(factory_name_raw) x)
    END AS factory_name,
    market_code,
    channel_type,
    cat_bot,
    is_human,
    CASE 
      WHEN skill_lookup_raw IS NULL THEN NULL
      ELSE ARRAY(SELECT DISTINCT AS STRUCT * FROM UNNEST(skill_lookup_raw))
    END AS skill_lookup,
    CASE 
      WHEN all_agents_raw IS NULL THEN NULL
      ELSE ARRAY(SELECT DISTINCT AS STRUCT * FROM UNNEST(all_agents_raw))
    END AS all_agents,
    mercado,
    fallback_cat_pca,
    fallback_second_category,
    fallback_third_category
  FROM grouped_raw_agg
),

-- 3. Cálculo del AHT total por agente para cada conversación
agent_aht AS (
  SELECT
    g.conversation_id,
    sl.agent_id,
    SUM(sl.aht) AS total_aht
  FROM grouped_raw g
  CROSS JOIN UNNEST(g.skill_lookup) sl
  WHERE sl.agent_id IS NOT NULL
  GROUP BY g.conversation_id, sl.agent_id
),

-- 4. Identificación del agente con mayor AHT para cada conversación
best_agent AS (
  SELECT 
    conversation_id,
    agent_id,
    ROW_NUMBER() OVER (PARTITION BY conversation_id ORDER BY total_aht DESC, agent_id ASC) AS rn
  FROM agent_aht
),

-- 5. Extracción de las categorías asociadas al agente con mayor AHT desde el array all_agents
best_agent_categories AS (
  SELECT
    g.conversation_id,
    (
      SELECT AS STRUCT 
        aa.first_category AS cat_pca, 
        aa.second_category, 
        aa.third_category
      FROM UNNEST(g.all_agents) aa
      WHERE aa.agent_id = ba.agent_id
      LIMIT 1
    ) AS cats
  FROM grouped_raw g
  INNER JOIN best_agent ba
    ON g.conversation_id = ba.conversation_id
  WHERE ba.rn = 1
),

-- 6. Consolidación final del segmento agrupado con sus categorías resueltas
grouped_final AS (
  SELECT
    g.conversation_id,
    g.call_date,
    g.skill_name,
    g.factory_name,
    g.market_code,
    g.channel_type,
    g.cat_bot,
    g.is_human,
    g.skill_lookup,
    COALESCE(bac.cats.cat_pca, g.fallback_cat_pca) AS cat_pca,
    COALESCE(bac.cats.second_category, g.fallback_second_category) AS second_category,
    COALESCE(bac.cats.third_category, g.fallback_third_category) AS third_category,
    g.all_agents,
    g.mercado
  FROM grouped_raw g
  LEFT JOIN best_agent_categories bac
    ON g.conversation_id = bac.conversation_id
)

-- Selección final: Unión de registros sin agrupar + registros agrupados con su nueva lógica de categorías
SELECT
  conversation_id,
  call_date,
  skill_name,
  factory_name,
  market_code,
  channel_type,
  cat_bot,
  is_human,
  skill_lookup,
  cat_pca,
  second_category,
  third_category,
  all_agents,
  mercado
FROM `cus-data-dev.radar.sgj_calculated`
WHERE (channel_type NOT IN ('webmessaging', 'whatsapp')
   OR is_human != 'HUMAN'
   OR is_human IS NULL)
   AND call_date >= start_date -- ⚡ OPTIMIZACIÓN

UNION ALL

SELECT
  conversation_id,
  call_date,
  skill_name,
  factory_name,
  market_code,
  channel_type,
  cat_bot,
  is_human,
  skill_lookup,
  cat_pca,
  second_category,
  third_category,
  all_agents,
  mercado
FROM grouped_final;

DELETE FROM `cus-data-dev.radar.sgj_intermedia`
WHERE call_date >= start_date;

INSERT INTO `cus-data-dev.radar.sgj_intermedia`
SELECT * FROM `cus-data-dev.radar.sgj_intermedia_temp`;

DROP TABLE `cus-data-dev.radar.sgj_intermedia_temp`;
