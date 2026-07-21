SELECT
    EXTRACT(MONTH FROM `effective_start_date_utc`) AS month_number,
    SUM(`handletime_seconds`) / NULLIF(SUM(`handle_qty`), 0) AS average_handle_time
FROM
    `data-exp-contactcenter.CC_Reporting.GA_queue_voice_performance`
WHERE
    EXTRACT(YEAR FROM `effective_start_date_utc`) = EXTRACT(YEAR FROM CURRENT_DATE())
GROUP BY
    month_number
ORDER BY
    month_number