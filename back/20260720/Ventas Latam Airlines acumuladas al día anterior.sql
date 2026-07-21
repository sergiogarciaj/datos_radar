SELECT
  EXTRACT(MONTH FROM juro.pnr_date) AS mes,
  CAST(ROUND(SUM(CASE WHEN EXTRACT(YEAR FROM juro.pnr_date) = 2024 THEN juro.revenue_seg_usd + juro.yq_seg_usd ELSE 0 END)) AS INT64) AS vta_2024,
  CAST(ROUND(SUM(CASE WHEN EXTRACT(YEAR FROM juro.pnr_date) = 2025 THEN juro.revenue_seg_usd + juro.yq_seg_usd ELSE 0 END)) AS INT64) AS vta_2025,
  FORMAT("%.2f%%", SAFE_DIVIDE(
    SUM(CASE WHEN EXTRACT(YEAR FROM juro.pnr_date) = 2025 THEN juro.revenue_seg_usd + juro.yq_seg_usd ELSE 0 END) - 
    SUM(CASE WHEN EXTRACT(YEAR FROM juro.pnr_date) = 2024 THEN juro.revenue_seg_usd + juro.yq_seg_usd ELSE 0 END),
    SUM(CASE WHEN EXTRACT(YEAR FROM juro.pnr_date) = 2024 THEN juro.revenue_seg_usd + juro.yq_seg_usd ELSE 0 END)
  ) * 100) AS variacion_25_vs_24_pct,
  CAST(ROUND(SUM(CASE WHEN EXTRACT(YEAR FROM juro.pnr_date) = 2026 THEN juro.revenue_seg_usd + juro.yq_seg_usd ELSE 0 END)) AS INT64) AS vta_2026,
  FORMAT("%.2f%%", SAFE_DIVIDE(
    SUM(CASE WHEN EXTRACT(YEAR FROM juro.pnr_date) = 2026 THEN juro.revenue_seg_usd + juro.yq_seg_usd ELSE 0 END) - 
    SUM(CASE WHEN EXTRACT(YEAR FROM juro.pnr_date) = 2025 THEN juro.revenue_seg_usd + juro.yq_seg_usd ELSE 0 END),
    SUM(CASE WHEN EXTRACT(YEAR FROM juro.pnr_date) = 2025 THEN juro.revenue_seg_usd + juro.yq_seg_usd ELSE 0 END)
  ) * 100) AS variacion_26_vs_25_pct
FROM `bc-co-giperf-dev-bt6q.GI_VENTAS.juro2_comercial` AS juro
WHERE juro.pnr_date >= '2024-01-01'
  AND juro.status_coupon NOT IN ('NOGO', 'IROP', 'VOID')
  AND FORMAT_DATE('%m%d', juro.pnr_date) <= FORMAT_DATE('%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY 1
ORDER BY 1