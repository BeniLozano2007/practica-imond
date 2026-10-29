-- Ventas, pedidos y ticket promedio por mes, canal, provincia y producto.
-- El total de cada pedido (con IVA y envío) se reparte entre sus productos según su
-- peso en el subtotal. GROUP BY CUBE agrega las filas 'Todos' de cada filtro.
CREATE TABLE mart_ventas_mensual AS
WITH lineas AS (
    SELECT d.year,
           d.month,
           ch.name                                    AS canal,
           a.province                                 AS provincia,
           p.name                                     AS producto,
           o.order_id,
           i.quantity,
           o.total_amount * i.line_total / o.subtotal AS venta_prorrateada
    FROM fact_sales_order_item AS i
    JOIN fact_sales_order AS o  ON o.order_id     = i.order_id
    JOIN dim_date         AS d  ON d.date_key     = o.date_key
    JOIN dim_channel      AS ch ON ch.channel_id  = o.channel_id
    JOIN dim_address      AS a  ON a.address_id   = o.shipping_address_id
    JOIN dim_product      AS p  ON p.product_key  = i.product_key
    WHERE o.is_sale
)
SELECT CASE WHEN GROUPING(year) = 1 THEN 'Todos' ELSE strftime(make_date(year, month, 1), '%Y-%m') END AS mes,
       CASE WHEN GROUPING(canal)     = 1 THEN 'Todos' ELSE canal     END AS canal,
       CASE WHEN GROUPING(provincia) = 1 THEN 'Todas' ELSE provincia END AS provincia,
       CASE WHEN GROUPING(producto)  = 1 THEN 'Todos' ELSE producto  END AS producto,
       COUNT(DISTINCT order_id)                                      AS pedidos,
       SUM(quantity)                                                 AS unidades,
       ROUND(SUM(venta_prorrateada), 2)                              AS ventas,
       ROUND(SUM(venta_prorrateada) / COUNT(DISTINCT order_id), 2)   AS ticket_promedio
FROM lineas
GROUP BY CUBE ((year, month), canal, provincia, producto)
ORDER BY mes, canal, provincia, producto;
