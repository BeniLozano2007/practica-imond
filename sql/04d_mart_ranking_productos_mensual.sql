-- =====================================================================
-- 04d_mart_ranking_productos_mensual.sql — Data mart
-- =====================================================================
-- Se construye solo a partir del modelo estrella (fact_* y dim_*).
-- =====================================================================

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
