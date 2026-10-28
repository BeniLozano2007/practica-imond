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
