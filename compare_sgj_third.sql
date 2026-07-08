SELECT
  'row_count' AS metric,
  CAST(COUNT(*) AS STRING) AS original,
  CAST((SELECT COUNT(*) FROM `cus-data-dev.radar2.sgj_third`) AS STRING) AS test,
  IF(COUNT(*) = (SELECT COUNT(*) FROM `cus-data-dev.radar2.sgj_third`), 'OK', 'DIFF') AS status
FROM `cus-data-dev.radar.sgj_third`

UNION ALL

SELECT
  'sum_factor' AS metric,
  CAST(ROUND(SUM(factor), 4) AS STRING) AS original,
  CAST(ROUND((SELECT SUM(factor) FROM `cus-data-dev.radar2.sgj_third`), 4) AS STRING) AS test,
  IF(ABS(SUM(factor) - (SELECT SUM(factor) FROM `cus-data-dev.radar2.sgj_third`)) < 0.01, 'OK', 'DIFF') AS status
FROM `cus-data-dev.radar.sgj_third`

UNION ALL

SELECT
  'sum_factor_plus' AS metric,
  CAST(ROUND(SUM(factor_plus), 4) AS STRING) AS original,
  CAST(ROUND((SELECT SUM(factor_plus) FROM `cus-data-dev.radar2.sgj_third`), 4) AS STRING) AS test,
  IF(ABS(SUM(factor_plus) - (SELECT SUM(factor_plus) FROM `cus-data-dev.radar2.sgj_third`)) < 0.01, 'OK', 'DIFF') AS status
FROM `cus-data-dev.radar.sgj_third`

UNION ALL

SELECT
  'kept_bot_category_count' AS metric,
  'N/A' AS original,
  CAST((SELECT COUNTIF(kept_bot_category = TRUE) FROM `cus-data-dev.radar2.sgj_third`) AS STRING) AS test,
  'OK' AS status
FROM (SELECT 1)
