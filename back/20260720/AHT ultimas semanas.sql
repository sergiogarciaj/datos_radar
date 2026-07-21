SELECT
    EXTRACT(WEEK FROM effective_start_date_utc) AS week_number,
    SUM(handletime_seconds) / SUM(handle_qty) AS average_handle_time
FROM
    `data-exp-contactcenter.CC_Reporting.GA_queue_voice_performance`
WHERE
    EXTRACT(YEAR FROM effective_start_date_utc) = EXTRACT(YEAR FROM CURRENT_DATE())
    AND EXTRACT(WEEK FROM effective_start_date_utc) BETWEEN EXTRACT(WEEK FROM CURRENT_DATE()) - 4 AND EXTRACT(WEEK FROM CURRENT_DATE()) 
GROUP BY
    week_number
ORDER BY
    week_number
