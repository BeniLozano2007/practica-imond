-- Ranking de productos por ventas sin IVA, con el puesto calculado dentro de cada
-- combinación de mes, canal y provincia (incluye las filas 'Todos').
CREATE TABLE mart_ranking_productos_mensual AS
WITH ventas_producto AS (
    SELECT CASE WHEN GROUPING(d.year)     = 1 THEN 'Todos' ELSE strftime(make_date(d.year, d.month, 1), '%Y-%m') END AS mes,
           CASE WHEN GROUPING(ch.name)    = 1 THEN 'Todos' ELSE ch.name    END AS canal,
           CASE WHEN GROUPING(a.province) = 1 THEN 'Todas' ELSE a.province END AS provincia,
           p.name                      AS producto,
           SUM(i.quantity)             AS unidades,
           ROUND(SUM(i.line_total), 2) AS ventas_sin_iva
    FROM fact_sales_order_item AS i
    JOIN fact_sales_order AS o  ON o.order_id    = i.order_id
    JOIN dim_date         AS d  ON d.date_key    = o.date_key
    JOIN dim_channel      AS ch ON ch.channel_id = o.channel_id
    JOIN dim_address      AS a  ON a.address_id  = o.shipping_address_id
    JOIN dim_product      AS p  ON p.product_key = i.product_key
    WHERE o.is_sale
    GROUP BY CUBE ((d.year, d.month), ch.name, a.province), p.name
)
SELECT mes,
       canal,
       provincia,
       producto,
       unidades,
       ventas_sin_iva,
       RANK() OVER (PARTITION BY mes, canal, provincia ORDER BY ventas_sin_iva DESC) AS puesto
FROM ventas_producto
ORDER BY mes, canal, provincia, puesto;
