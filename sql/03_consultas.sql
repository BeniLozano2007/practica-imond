-- Definiciones:
--   * Venta: pedido PAID o FULFILLED (is_sale).
--   * Ticket promedio: ventas / pedidos.
--   * Usuarios activos: clientes distintos que iniciaron sesión en la web.
--   * NPS: % promotores (9-10) − % detractores (0-6).


-- ---------------------------------------------------------------------
-- Controles de carga
-- ---------------------------------------------------------------------

-- Dimensión producto (ejemplo del profe)
SELECT product_key, name, category, family, list_price
FROM dim_product
ORDER BY product_key;

-- Filas de cada hecho vs. su tabla de origen (tienen que coincidir)
SELECT 'fact_sales_order'      AS tabla, (SELECT COUNT(*) FROM fact_sales_order)      AS filas_dw, (SELECT COUNT(*) FROM raw.sales_order)      AS filas_raw
UNION ALL
SELECT 'fact_sales_order_item',          (SELECT COUNT(*) FROM fact_sales_order_item),          (SELECT COUNT(*) FROM raw.sales_order_item)
UNION ALL
SELECT 'fact_web_session',               (SELECT COUNT(*) FROM fact_web_session),               (SELECT COUNT(*) FROM raw.web_session)
UNION ALL
SELECT 'fact_nps_response',              (SELECT COUNT(*) FROM fact_nps_response),              (SELECT COUNT(*) FROM raw.nps_response);

-- Vacíos esperados: pedidos online sin tienda y registros anónimos
SELECT (SELECT COUNT(*) FROM fact_sales_order  WHERE store_id    IS NULL) AS pedidos_online_sin_tienda,
       (SELECT COUNT(*) FROM fact_web_session  WHERE customer_id IS NULL) AS visitas_anonimas,
       (SELECT COUNT(*) FROM fact_nps_response WHERE customer_id IS NULL) AS encuestas_anonimas;


-- ---------------------------------------------------------------------
-- KPIs del período completo
-- ---------------------------------------------------------------------

-- Ventas, pedidos y ticket promedio
SELECT COUNT(*)                    AS pedidos,
       ROUND(SUM(total_amount), 2) AS ventas,
       ROUND(AVG(total_amount), 2) AS ticket_promedio
FROM fact_sales_order
WHERE is_sale;

-- Usuarios activos
SELECT COUNT(DISTINCT customer_id)                 AS usuarios_activos,
       COUNT(*) FILTER (WHERE customer_id IS NULL) AS visitas_anonimas
FROM fact_web_session;

-- NPS (el promedio de una columna 1/0 es la proporción)
SELECT COUNT(*)                                               AS respuestas,
       ROUND(AVG(is_promoter)  * 100, 1)                      AS pct_promotores,
       ROUND(AVG(is_detractor) * 100, 1)                      AS pct_detractores,
       ROUND((AVG(is_promoter) - AVG(is_detractor)) * 100, 1) AS nps
FROM fact_nps_response;


-- ---------------------------------------------------------------------
-- KPIs por mes
-- ---------------------------------------------------------------------

-- Ventas, pedidos y ticket promedio por mes
SELECT d.year,
       d.month,
       COUNT(*)                      AS pedidos,
       ROUND(SUM(f.total_amount), 2) AS ventas,
       ROUND(AVG(f.total_amount), 2) AS ticket_promedio
FROM fact_sales_order AS f
JOIN dim_date AS d ON d.date_key = f.date_key
WHERE f.is_sale
GROUP BY d.year, d.month
ORDER BY d.year, d.month;

-- Usuarios activos por mes
SELECT d.year,
       d.month,
       COUNT(DISTINCT w.customer_id)                 AS usuarios_activos,
       COUNT(*) FILTER (WHERE w.customer_id IS NULL) AS visitas_anonimas
FROM fact_web_session AS w
JOIN dim_date AS d ON d.date_key = w.date_key
GROUP BY d.year, d.month
ORDER BY d.year, d.month;

-- NPS por mes (fecha de respuesta)
SELECT d.year,
       d.month,
       COUNT(*)                                                   AS respuestas,
       ROUND((AVG(n.is_promoter) - AVG(n.is_detractor)) * 100, 1) AS nps
FROM fact_nps_response AS n
JOIN dim_date AS d ON d.date_key = n.date_key
GROUP BY d.year, d.month
ORDER BY d.year, d.month;


-- ---------------------------------------------------------------------
-- KPIs por provincia, canal y producto
-- ---------------------------------------------------------------------

-- Ventas por provincia (según la dirección de envío; en tienda es la de la tienda)
SELECT a.province                    AS provincia,
       COUNT(*)                      AS pedidos,
       ROUND(SUM(f.total_amount), 2) AS ventas,
       ROUND(SUM(f.total_amount) * 100.0 / SUM(SUM(f.total_amount)) OVER (), 1) AS pct_del_total
FROM fact_sales_order AS f
JOIN dim_address AS a ON a.address_id = f.shipping_address_id
WHERE f.is_sale
GROUP BY a.province
ORDER BY ventas DESC;

-- Ventas y ticket promedio por canal
SELECT ch.name                       AS canal,
       COUNT(*)                      AS pedidos,
       ROUND(SUM(f.total_amount), 2) AS ventas,
       ROUND(AVG(f.total_amount), 2) AS ticket_promedio
FROM fact_sales_order AS f
JOIN dim_channel AS ch ON ch.channel_id = f.channel_id
WHERE f.is_sale
GROUP BY ch.name
ORDER BY ventas DESC;

-- Ranking mensual por producto (por ventas sin IVA)
SELECT d.year,
       d.month,
       p.name                      AS producto,
       SUM(i.quantity)             AS unidades,
       ROUND(SUM(i.line_total), 2) AS ventas_sin_iva,
       RANK() OVER (PARTITION BY d.year, d.month ORDER BY SUM(i.line_total) DESC) AS puesto
FROM fact_sales_order_item AS i
JOIN dim_product AS p ON p.product_key = i.product_key
JOIN dim_date    AS d ON d.date_key    = i.date_key
WHERE i.is_sale
GROUP BY d.year, d.month, p.name
ORDER BY d.year, d.month, puesto;
