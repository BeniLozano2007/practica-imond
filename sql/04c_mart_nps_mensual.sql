-- NPS por mes y canal (fecha de respuesta), con las filas 'Todos'.
-- Solo fecha y canal: la encuesta no tiene pedido, provincia ni producto.
CREATE TABLE mart_nps_mensual AS
SELECT CASE WHEN GROUPING(d.year)  = 1 THEN 'Todos' ELSE strftime(make_date(d.year, d.month, 1), '%Y-%m') END AS mes,
       CASE WHEN GROUPING(ch.name) = 1 THEN 'Todos' ELSE ch.name END AS canal,
       COUNT(*)                                                   AS respuestas,
       SUM(n.is_promoter)                                         AS promotores,
       SUM(n.is_detractor)                                        AS detractores,
       ROUND((AVG(n.is_promoter) - AVG(n.is_detractor)) * 100, 1) AS nps
FROM fact_nps_response AS n
JOIN dim_date    AS d  ON d.date_key    = n.date_key
JOIN dim_channel AS ch ON ch.channel_id = n.channel_id
GROUP BY CUBE ((d.year, d.month), ch.name)
ORDER BY mes, canal;
