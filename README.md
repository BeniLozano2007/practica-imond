# EcoBottle AR: tablero comercial

Mini ecosistema de datos para el área comercial de **EcoBottle AR**, que vende botellas reutilizables por su tienda online y en 4 tiendas físicas. Los datos del sistema de ventas se transforman con SQL en un modelo estrella, se resumen en data marts y se muestran en un tablero web interactivo.

**Tablero:** https://benilozano2007.github.io/practica-imond/

![Tablero general](assets/tablero_general.png)

| Mejor mes: diciembre de 2024 | Tiendas físicas | Sport B en Buenos Aires |
|---|---|---|
| ![Diciembre 2024](assets/tablero_diciembre_2024.png) | ![Tiendas físicas](assets/tablero_tiendas.png) | ![Sport B en Buenos Aires](assets/tablero_sportb_buenosaires.png) |

## El problema

El área comercial necesita responder todos los días cuánto se vende, cuánto gasta cada cliente, cuánta gente usa la web, si los clientes están conformes, dónde se vende más y qué producto lidera cada mes.

Los datos existen, pero están en el sistema transaccional (OLTP): normalizados en 13 tablas, con estados que no son venta (pedidos cancelados o reembolsados), códigos en lugar de nombres y registros anónimos. Responder cada pregunta exige consultas complejas y cada persona puede llegar a un número distinto.

Este proyecto resuelve eso con un flujo automático y repetible que deja los KPIs calculados en un solo lugar.

## Arquitectura

```
raw/ (CSV de origen)
  │   ELT con SQL en DuckDB  (python run_sql.py)
  ▼
Modelo estrella: dimensiones + hechos      sql/01a_*  sql/02*
  │
  ▼
Data marts con los KPIs ya calculados      sql/04*
  │   exportados como CSV a dw/
  ▼
Tablero web (HTML + CSS + JavaScript)      index.html  style.css  app.js
  │
  ▼
GitHub Pages (URL pública)
```

- **ELT:** los datos crudos se cargan primero tal como vienen (`raw/`) y se transforman después, con SQL, dentro de la base.
- **Idempotente:** `run_sql.py` arma el data warehouse desde cero en cada ejecución, así que correrlo una o varias veces da el mismo resultado.
- **Cálculos en SQL, no en el tablero:** los marts traen cada KPI calculado para todas las combinaciones de filtros. El tablero solo busca la fila que corresponde y la muestra.

## Cómo ejecutarlo

Requisitos: Python 3.9 o superior y Git.

```bash
git clone https://github.com/BeniLozano2007/practica-imond.git
cd practica-imond
python -m venv .venv
```

Activar el entorno virtual:

- Windows (PowerShell): `.venv\Scripts\activate`
- Mac / Linux: `source .venv/bin/activate`

Instalar las dependencias y armar el data warehouse:

```bash
pip install -r requirements.txt
python run_sql.py
```

`run_sql.py` ejecuta los archivos de `sql/` en orden alfabético, muestra en la terminal el resultado de las consultas de control y KPIs, y exporta cada tabla como CSV a `dw/`.

Para explorar las tablas en el navegador: `python run_sql.py --ui`.

Para ver el tablero en la computadora (no funciona con doble clic, porque el navegador bloquea la lectura de los CSV):

```bash
python -m http.server
```

y abrir `http://localhost:8000`. Al subir los cambios a GitHub, el tablero publicado se actualiza solo.

## Estructura del repositorio

| Carpeta / archivo | Contenido |
|---|---|
| `raw/` | Datos de origen: un CSV por tabla del sistema de ventas. No se modifican. |
| `sql/01a_*.sql` | Dimensiones del modelo estrella. |
| `sql/02a_*.sql` a `sql/02d_*.sql` | Tablas de hechos, una por archivo. |
| `sql/03_consultas.sql` | Controles de carga y consultas de los KPIs. |
| `sql/04a_*.sql` a `sql/04d_*.sql` | Data marts, uno por archivo. |
| `dw/` | Data warehouse exportado en CSV y diagrama del modelo (`modelo_estrella.md`). |
| `index.html`, `style.css`, `app.js` | Tablero web. |
| `assets/` | Diagrama de origen (DER) y capturas del tablero. |
| `run_sql.py` | Ejecuta el ELT con DuckDB. |
| `generator/` | Programa que generó los datos de `raw/` y validador de KPIs esperados. |

## Modelo estrella

El diagrama completo, con claves y relaciones, está en [`dw/modelo_estrella.md`](dw/modelo_estrella.md). Las cuatro tablas de hechos comparten dimensiones (fecha, cliente, canal), así que el modelo es una constelación de estrellas.

| Tabla de hechos | Grano: una fila representa… | Origen |
|---|---|---|
| `fact_sales_order` | un pedido realizado por un cliente, en un canal, en una fecha | `sales_order` + `payment` + `shipment` |
| `fact_sales_order_item` | un producto dentro de un pedido, en la fecha del pedido | `sales_order_item` + `sales_order` |
| `fact_web_session` | una visita a la web de un cliente identificado o anónimo | `web_session` |
| `fact_nps_response` | una respuesta a la encuesta NPS de un cliente (o anónima), en un canal, en una fecha | `nps_response` |

Pago y envío se integran en `fact_sales_order` porque tienen el mismo grano que el pedido: cada pedido tiene un pago y como máximo un envío. Los ítems van en una tabla aparte porque un pedido puede tener varios productos.

## Diccionario de datos

### Dimensiones

| Tabla | Columna | Descripción |
|---|---|---|
| `dim_date` | `date_key` | Clave de la fecha en formato AAAAMMDD (ej. 20240131). |
| | `date`, `year`, `month`, `day` | Fecha y sus partes. |
| | `month_name`, `weekday` | Nombre del mes y del día de la semana. |
| `dim_channel` | `channel_id` | Clave del canal. |
| | `code`, `name` | `ONLINE` / `OFFLINE` y su nombre (Tienda Online, Tiendas Físicas). |
| `dim_customer` | `customer_id` | Clave del cliente. |
| | `first_name`, `last_name` | Nombre y apellido. |
| | `status` | `A` activo, `I` dio de baja la cuenta. |
| | `created_at` | Fecha de alta. |
| `dim_address` | `address_id` | Clave de la dirección. |
| | `city`, `postal_code` | Ciudad y código postal. |
| | `province` | Provincia, copiada en cada dirección para no tener que unir otra tabla. |
| `dim_store` | `store_id` | Clave de la tienda física. |
| | `name`, `city`, `province` | Nombre, ciudad y provincia de la tienda. |
| `dim_product` | `product_key` | Clave subrogada del producto (propia del data warehouse). |
| | `product_id`, `sku` | Clave e identificador del sistema de origen. |
| | `name`, `category`, `family` | Producto, categoría (Classic / Sport) y familia (Bottles). |
| | `list_price` | Precio de lista sin IVA. |

### Hechos

| Tabla | Columna | Descripción |
|---|---|---|
| `fact_sales_order` | `order_id` | Clave del pedido. |
| | `date_key`, `customer_id`, `channel_id` | Fecha, cliente y canal del pedido. |
| | `store_id` | Tienda; vacío en los pedidos online. |
| | `shipping_address_id` | Dirección de envío (en compras en tienda, la de la tienda). |
| | `order_date`, `status` | Fecha y hora, y estado del pedido. |
| | `is_sale` | Verdadero si el pedido cuenta como venta (PAID o FULFILLED). |
| | `subtotal`, `tax_amount`, `shipping_fee`, `total_amount` | Importes: productos, IVA (21 %), envío y total. |
| | `payment_method`, `payment_status`, `paid_at` | Medio de pago, estado y fecha de acreditación. |
| | `shipment_status`, `shipped_at`, `delivered_at` | Estado del envío y fechas de despacho y entrega; vacíos si no hubo envío. |
| `fact_sales_order_item` | `order_item_id` | Clave de la línea del pedido. |
| | `order_id` | Pedido al que pertenece. |
| | `product_key`, `date_key`, `customer_id`, `channel_id` | Producto, fecha, cliente y canal. |
| | `is_sale` | Verdadero si el pedido cuenta como venta. |
| | `quantity`, `unit_price`, `discount_amount`, `line_total` | Unidades, precio unitario, descuento y total de la línea (sin IVA). |
| `fact_web_session` | `session_id` | Clave de la visita. |
| | `date_key`, `customer_id` | Fecha y cliente; cliente vacío si el visitante no inició sesión. |
| | `started_at`, `ended_at` | Inicio y fin de la visita. |
| | `source` | Origen: `ads`, `direct`, `referral`, `organic`. |
| | `device` | Dispositivo: `mobile`, `desktop`, `tablet`. |
| `fact_nps_response` | `nps_id` | Clave de la respuesta. |
| | `date_key`, `customer_id`, `channel_id` | Fecha, cliente (vacío si es anónima) y canal. |
| | `responded_at`, `score` | Fecha y hora, y puntaje de 0 a 10. |
| | `is_promoter`, `is_detractor` | 1 si el puntaje es 9-10 o 0-6, respectivamente. |

### Data marts

Las columnas de texto (`mes`, `canal`, `provincia`, `producto`) incluyen el valor **Todos** o **Todas**, que representa el total de ese filtro.

| Tabla | Una fila es… | Columnas |
|---|---|---|
| `mart_ventas_mensual` | una combinación de mes, canal, provincia y producto | `pedidos`, `unidades`, `ventas` (con IVA y envío), `ticket_promedio` |
| `mart_usuarios_activos_mensual` | un mes | `usuarios_activos`, `visitas_anonimas`, `visitas` |
| `mart_nps_mensual` | una combinación de mes y canal | `respuestas`, `promotores`, `detractores`, `nps` |
| `mart_ranking_productos_mensual` | un producto en una combinación de mes, canal y provincia | `unidades`, `ventas_sin_iva`, `puesto` |

## Supuestos

- **Venta:** solo cuentan los pedidos `PAID` o `FULFILLED`. Los `CREATED`, `CANCELLED` y `REFUNDED` quedan en el modelo pero no suman ventas.
- **Ventas:** se miden con `total_amount`, que incluye IVA y envío. El ranking de productos usa `line_total`, sin IVA ni envío.
- **Ventas por producto:** el IVA y el envío son del pedido entero. Para filtrar ventas por producto, el total de cada pedido se reparte entre sus productos según el peso de cada uno en el subtotal. La suma de los productos da exactamente el total.
- **Provincia:** se toma de la dirección de envío. En las compras en tienda, esa dirección es la de la tienda.
- **Mes:** las ventas se asignan al mes del pedido, y el NPS al mes de la respuesta.
- **Usuarios activos:** clientes distintos que iniciaron sesión en la web en el período. Se filtran solo por fecha, porque las visitas no tienen canal, provincia ni producto.
- **NPS:** % de promotores (9-10) menos % de detractores (0-6). Se filtra por fecha y canal; la encuesta no tiene número de pedido, por lo que no se puede asignar a una provincia ni a un producto.
- **Clientes y respuestas anónimas:** se mantienen con el cliente vacío para no perder registros.
- **Fecha de corte:** los datos son una foto del sistema al 30/09/2025.

## Consultas clave

Todas están en [`sql/03_consultas.sql`](sql/03_consultas.sql) y se ejecutan con `python run_sql.py`. Los resultados coinciden mes a mes con los KPIs esperados de `python generator/validate_raw.py`.

**Ventas y ticket promedio**

```sql
SELECT COUNT(*)                    AS pedidos,
       ROUND(SUM(total_amount), 2) AS ventas,
       ROUND(AVG(total_amount), 2) AS ticket_promedio
FROM fact_sales_order
WHERE is_sale;
```

**Usuarios activos por mes**

```sql
SELECT d.year, d.month,
       COUNT(DISTINCT w.customer_id) AS usuarios_activos
FROM fact_web_session AS w
JOIN dim_date AS d ON d.date_key = w.date_key
GROUP BY d.year, d.month
ORDER BY d.year, d.month;
```

**NPS**

```sql
SELECT ROUND((AVG(is_promoter) - AVG(is_detractor)) * 100, 1) AS nps
FROM fact_nps_response;
```

**Ventas por provincia**

```sql
SELECT a.province AS provincia,
       ROUND(SUM(f.total_amount), 2) AS ventas
FROM fact_sales_order AS f
JOIN dim_address AS a ON a.address_id = f.shipping_address_id
WHERE f.is_sale
GROUP BY a.province
ORDER BY ventas DESC;
```

**Ranking mensual por producto**

```sql
SELECT d.year, d.month, p.name AS producto,
       ROUND(SUM(i.line_total), 2) AS ventas_sin_iva,
       RANK() OVER (PARTITION BY d.year, d.month ORDER BY SUM(i.line_total) DESC) AS puesto
FROM fact_sales_order_item AS i
JOIN dim_product AS p ON p.product_key = i.product_key
JOIN dim_date    AS d ON d.date_key    = i.date_key
WHERE i.is_sale
GROUP BY d.year, d.month, p.name
ORDER BY d.year, d.month, puesto;
```

## Resultados del período (ene 2024 a sep 2025)

| KPI | Valor |
|---|---|
| Ventas | $382,4 M en 10.998 pedidos |
| Ticket promedio | $34.771 |
| Usuarios activos | 3.077 clientes distintos |
| NPS | 30,0 |

## Hallazgos

- **Las demoras de entrega hundieron el NPS online.** En julio y agosto de 2024 los envíos tardaron en promedio más de 9 días, contra 4 a 5 días el resto del período. En esos meses el NPS online cayó a −6 y −26,5, mientras que en las tiendas físicas se mantuvo entre 38 y 46. Los envíos volvieron a la normalidad en septiembre y el NPS online se recuperó en octubre (31,9); el retraso se explica porque la encuesta se envía 7 días después de la entrega.
- **Las tiendas físicas generan clientes más conformes.** En todo el período el NPS de las tiendas fue 40,9, contra 24,0 en la web.
- **La web es el canal principal y crece.** Concentra el 59 % de las ventas ($227 M contra $155 M de las tiendas), y los usuarios activos por mes pasaron de 424 en enero de 2024 a 1.041 en septiembre de 2025.
- **Diciembre es el mes más fuerte:** en diciembre de 2024 se vendieron $28,4 M, el máximo del período.
- **Sport B factura más con menos unidades.** Vendió 11.047 unidades contra 12.498 de Classic A, pero facturó más ($162,7 M contra $147,2 M sin IVA) porque su precio es mayor.
- **Buenos Aires concentra el 37 % de las ventas**, seguida por Córdoba (23 %), Santa Fe (23 %) y Mendoza (16 %).
- **El ticket promedio es estable:** entre $32.800 y $37.700 todos los meses.

## Ideas para el tablero

- **Tiempo de entrega por mes junto al NPS online**, para anticipar caídas de satisfacción como la de mediados de 2024.
- **Alerta automática** cuando el NPS de un canal cae por debajo de un umbral.
- **Conversión de la web:** visitas que terminan en compra, por origen del tráfico (redes, buscadores, newsletter).
- **Comparación contra el mismo mes del año anterior** en las tarjetas de KPIs.
- **Actualización automática:** programar `run_sql.py` para que corra periódicamente (por ejemplo, con GitHub Actions) y el tablero se actualice sin intervención manual.
