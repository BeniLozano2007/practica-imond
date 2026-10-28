-- NPS por mes y canal (fecha de respuesta)
CREATE TABLE mart_nps_mensual AS
SELECT make_date(d.year, d.month, 1) AS mes,
       ch.name                       AS canal,
       COUNT(*)                      AS respuestas,
       SUM(n.is_promoter)            AS promotores,
       SUM(n.is_detractor)           AS detractores
FROM fact_nps_response AS n
JOIN dim_date    AS d  ON d.date_key    = n.date_key
JOIN dim_channel AS ch ON ch.channel_id = n.channel_id
GROUP BY d.year, d.month, ch.name
ORDER BY mes, canal;
