-- =====================================================================
-- 04_marts.sql — Data marts para el tablero
-- =====================================================================
-- Tablas resumidas que se construyen SOLO a partir del modelo estrella
-- (fact_* y dim_*). Acá se hacen los cálculos pesados (JOIN, filtros,
-- COUNT DISTINCT, rankings) para que el tablero solo sume o divida.
--
-- Se guardan cantidades sumables (ventas, pedidos, promotores...) en lugar
-- de promedios, para que el tablero pueda combinarlas al filtrar:
--   Ticket promedio = SUM(ventas) / SUM(pedidos)
--   NPS             = (SUM(promotores) - SUM(detractores)) / SUM(respuestas) * 100
-- =====================================================================


-- Ventas por mes, canal y provincia -> Ventas, Ticket promedio, Ventas por provincia
CREATE TABLE mart_ventas_mensual AS
SELECT make_date(d.year, d.month, 1) AS mes,
       ch.name                       AS canal,
       a.province                    AS provincia,
       COUNT(*)                      AS pedidos,
       SUM(f.total_amount)           AS ventas
FROM fact_sales_order AS f
JOIN dim_date    AS d  ON d.date_key    = f.date_key
JOIN dim_channel AS ch ON ch.channel_id = f.channel_id
JOIN dim_address AS a  ON a.address_id  = f.shipping_address_id
WHERE f.is_sale
GROUP BY d.year, d.month, ch.name, a.province
ORDER BY mes, canal, provincia;


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


-- Ranking mensual por producto (por ventas sin IVA, ambos canales)
CREATE TABLE mart_ranking_productos_mensual AS
SELECT make_date(d.year, d.month, 1) AS mes,
       p.name                        AS producto,
       SUM(i.quantity)               AS unidades,
       SUM(i.line_total)             AS ventas_sin_iva,
       RANK() OVER (PARTITION BY d.year, d.month ORDER BY SUM(i.line_total) DESC) AS puesto
FROM fact_sales_order_item AS i
JOIN dim_product AS p ON p.product_key = i.product_key
JOIN dim_date    AS d ON d.date_key    = i.date_key
WHERE i.is_sale
GROUP BY d.year, d.month, p.name
ORDER BY mes, puesto;
