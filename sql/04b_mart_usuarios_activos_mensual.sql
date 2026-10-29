-- Usuarios activos (clientes distintos logueados) por mes, más la fila 'Todos' del período.
-- Solo se filtra por fecha: las visitas no tienen canal, provincia ni producto.
CREATE TABLE mart_usuarios_activos_mensual AS
SELECT CASE WHEN GROUPING(d.year) = 1 THEN 'Todos' ELSE strftime(make_date(d.year, d.month, 1), '%Y-%m') END AS mes,
       COUNT(DISTINCT w.customer_id)                 AS usuarios_activos,
       COUNT(*) FILTER (WHERE w.customer_id IS NULL) AS visitas_anonimas,
       COUNT(*)                                      AS visitas
FROM fact_web_session AS w
JOIN dim_date AS d ON d.date_key = w.date_key
GROUP BY CUBE ((d.year, d.month))
ORDER BY mes;
