-- Usuarios activos por mes (COUNT DISTINCT: no se puede sumar entre meses)
CREATE TABLE mart_usuarios_activos_mensual AS
SELECT make_date(d.year, d.month, 1)                 AS mes,
       COUNT(DISTINCT w.customer_id)                 AS usuarios_activos,
       COUNT(*) FILTER (WHERE w.customer_id IS NULL) AS visitas_anonimas,
       COUNT(*)                                      AS visitas
FROM fact_web_session AS w
JOIN dim_date AS d ON d.date_key = w.date_key
GROUP BY d.year, d.month
ORDER BY mes;
