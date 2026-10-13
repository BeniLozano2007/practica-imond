-- =====================================================================
-- 01_dimensiones.sql — Tablas de DIMENSIONES del modelo estrella
-- =====================================================================
-- Para cada dimensión:
--   1. CREATE TABLE con sus columnas, tipos y PRIMARY KEY.
--   2. INSERT INTO ... SELECT para cargarla desde las tablas de origen.
--
-- Las tablas de origen (los CSV de raw/) están en el esquema raw:
--     FROM raw.product
-- Para ver qué columnas y tipos tiene una:  DESCRIBE raw.product;
-- Para explorarlas antes de escribir nada:  python run_sql.py --explorar
-- =====================================================================


-- ---------------------------------------------------------------------
-- EJEMPLO RESUELTO: dimensión producto
-- ---------------------------------------------------------------------
-- En raw/ la categoría está en otra tabla y tiene jerarquía
-- (Bottles -> Classic / Sport). En la dimensión la "aplanamos":
-- cada producto queda en una sola fila con su categoría y su familia.
--
-- product_key es la clave SUBROGADA: un número propio del data warehouse.
-- product_id es la clave NATURAL: el ID que viene del sistema de origen.
-- Las tablas de hechos usan product_key; product_id sirve para encontrarla.

CREATE TABLE dim_product (
    product_key INTEGER PRIMARY KEY,
    product_id  INTEGER NOT NULL,
    sku         VARCHAR NOT NULL,
    name        VARCHAR NOT NULL,
    category    VARCHAR,             -- Classic / Sport
    family      VARCHAR,             -- Bottles
    list_price  DECIMAL(12, 2)
);

INSERT INTO dim_product
SELECT
    ROW_NUMBER() OVER (ORDER BY p.product_id) AS product_key,
    p.product_id,
    p.sku,
    p.name,
    c.name AS category,
    f.name AS family,
    p.list_price
FROM raw.product AS p
LEFT JOIN raw.product_category AS c ON c.category_id = p.category_id   -- categoría
LEFT JOIN raw.product_category AS f ON f.category_id = c.parent_id;    -- familia (categoría padre)


-- ---------------------------------------------------------------------
-- dim_date: una fila por día (todas las fechas del período de datos)
-- ---------------------------------------------------------------------
-- Los datos van del 01/01/2024 al 30/09/2025. Generamos todos los días,
-- aunque no haya ventas, para que las series temporales no tengan huecos.
-- date_key es "inteligente" (ej. 20240131): fácil de leer y de unir.

CREATE TABLE dim_date (
    date_key     INTEGER PRIMARY KEY,   -- ej. 20240131
    date         DATE NOT NULL,
    year         INTEGER NOT NULL,
    quarter      INTEGER NOT NULL,      -- 1 a 4
    month        INTEGER NOT NULL,      -- 1 a 12
    month_name   VARCHAR NOT NULL,      -- Enero, Febrero...
    year_month   VARCHAR NOT NULL,      -- 2024-01 (para agrupar por mes)
    day          INTEGER NOT NULL,
    day_of_week  INTEGER NOT NULL,      -- 1 = lunes ... 7 = domingo
    day_name     VARCHAR NOT NULL,      -- Lunes, Martes...
    is_weekend   BOOLEAN NOT NULL,
    semester     INTEGER NOT NULL,      -- 1 o 2
    season       VARCHAR NOT NULL       -- estación del hemisferio sur
);
-- ¿Por qué "season"? EcoBottle vende botellas térmicas y deportivas:
-- es esperable que la demanda cambie entre verano e invierno. Con esta
-- columna el tablero puede comparar ventas por estación sin cálculos.
-- Simplificación: tomamos la estación por mes completo
-- (dic-feb Verano, mar-may Otoño, jun-ago Invierno, sep-nov Primavera).

INSERT INTO dim_date
SELECT
    CAST(strftime(d, '%Y%m%d') AS INTEGER)  AS date_key,
    d                                        AS date,
    year(d)                                  AS year,
    quarter(d)                               AS quarter,
    month(d)                                 AS month,
    ['Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio',
     'Agosto','Septiembre','Octubre','Noviembre','Diciembre'][month(d)] AS month_name,
    strftime(d, '%Y-%m')                     AS year_month,
    day(d)                                   AS day,
    isodow(d)                                AS day_of_week,
    ['Lunes','Martes','Miércoles','Jueves','Viernes','Sábado','Domingo'][isodow(d)] AS day_name,
    isodow(d) IN (6, 7)                      AS is_weekend,
    CASE WHEN month(d) <= 6 THEN 1 ELSE 2 END AS semester,
    CASE
        WHEN month(d) IN (12, 1, 2) THEN 'Verano'
        WHEN month(d) IN (3, 4, 5)  THEN 'Otoño'
        WHEN month(d) IN (6, 7, 8)  THEN 'Invierno'
        ELSE 'Primavera'
    END                                      AS season
FROM (
    SELECT CAST(range AS DATE) AS d
    FROM range(DATE '2024-01-01', DATE '2025-10-01', INTERVAL 1 DAY)
);


-- ---------------------------------------------------------------------
-- dim_channel: canal de venta (ONLINE / OFFLINE)
-- ---------------------------------------------------------------------

CREATE TABLE dim_channel (
    channel_key  INTEGER PRIMARY KEY,
    channel_id   INTEGER NOT NULL,
    code         VARCHAR NOT NULL,      -- ONLINE / OFFLINE
    name         VARCHAR NOT NULL
);

INSERT INTO dim_channel
SELECT
    ROW_NUMBER() OVER (ORDER BY channel_id) AS channel_key,
    channel_id,
    code,
    name
FROM raw.channel;


-- ---------------------------------------------------------------------
-- dim_address: dirección con la provincia "aplanada"
-- ---------------------------------------------------------------------
-- En raw/ la provincia está en otra tabla. Acá la copiamos en cada fila
-- (redundancia controlada) para sacar "ventas por provincia" sin joins extra.
-- Sirve para la dirección de envío de los pedidos: en compras en tienda,
-- la dirección de envío es la de la tienda (ver README).

CREATE TABLE dim_address (
    address_key    INTEGER PRIMARY KEY,
    address_id     INTEGER NOT NULL,
    line1          VARCHAR,
    city           VARCHAR,
    postal_code    VARCHAR,
    province_id    INTEGER,
    province_name  VARCHAR,             -- Buenos Aires, Córdoba...
    province_code  VARCHAR,             -- BA, CBA, SF, MZA
    country_code   VARCHAR,
    is_store       BOOLEAN NOT NULL     -- TRUE si es la dirección de una tienda
);
-- is_store permite separar en el tablero las ventas "retiradas en tienda"
-- de las que viajaron a la casa del cliente, sin ir a buscar a dim_store.

INSERT INTO dim_address
SELECT
    ROW_NUMBER() OVER (ORDER BY a.address_id) AS address_key,
    a.address_id,
    a.line1,
    a.city,
    CAST(a.postal_code AS VARCHAR) AS postal_code,
    a.province_id,
    p.name AS province_name,
    p.code AS province_code,
    a.country_code,
    a.address_id IN (SELECT address_id FROM raw.store) AS is_store
FROM raw.address AS a
LEFT JOIN raw.province AS p ON p.province_id = a.province_id;


-- ---------------------------------------------------------------------
-- dim_customer: clientes (+ fila "Anónimo" para NPS y sesiones sin cliente)
-- ---------------------------------------------------------------------
-- Las sesiones web y las respuestas NPS pueden no tener customer_id.
-- En vez de dejar la clave vacía, apuntan a la fila -1 "Anónimo".

CREATE TABLE dim_customer (
    customer_key   INTEGER PRIMARY KEY,
    customer_id    INTEGER,             -- NULL solo en la fila -1
    email          VARCHAR,
    first_name     VARCHAR,
    last_name      VARCHAR,
    full_name      VARCHAR,
    status         VARCHAR,             -- A / I
    status_desc    VARCHAR,             -- Activo / Inactivo
    created_date   DATE,
    signup_cohort  VARCHAR,             -- mes de alta, ej. 2024-03
    has_phone      BOOLEAN              -- ¿se lo puede contactar por teléfono/WhatsApp?
);
-- signup_cohort agrupa a los clientes por el mes en que se registraron
-- (análisis de cohortes: ¿los que llegaron en verano compran más?).
-- has_phone sirve a Marketing para saber qué parte de la base es contactable.

INSERT INTO dim_customer
SELECT -1, NULL, NULL, NULL, NULL, 'Anónimo', NULL, 'Desconocido', NULL, NULL, NULL;

INSERT INTO dim_customer
SELECT
    ROW_NUMBER() OVER (ORDER BY customer_id) AS customer_key,
    customer_id,
    email,
    first_name,
    last_name,
    first_name || ' ' || last_name AS full_name,
    status,
    CASE status WHEN 'A' THEN 'Activo' ELSE 'Inactivo' END AS status_desc,
    CAST(created_at AS DATE) AS created_date,
    strftime(created_at, '%Y-%m') AS signup_cohort,
    phone IS NOT NULL AS has_phone
FROM raw.customer;


-- ---------------------------------------------------------------------
-- dim_store: tiendas físicas (+ fila "Online" para pedidos sin tienda)
-- ---------------------------------------------------------------------

CREATE TABLE dim_store (
    store_key      INTEGER PRIMARY KEY,
    store_id       INTEGER,             -- NULL solo en la fila -1
    name           VARCHAR NOT NULL,
    city           VARCHAR,
    province_name  VARCHAR,
    province_code  VARCHAR
);

INSERT INTO dim_store
SELECT -1, NULL, 'Sin tienda (Online)', NULL, NULL, NULL;

INSERT INTO dim_store
SELECT
    ROW_NUMBER() OVER (ORDER BY s.store_id) AS store_key,
    s.store_id,
    s.name,
    a.city,
    p.name AS province_name,
    p.code AS province_code
FROM raw.store AS s
LEFT JOIN raw.address  AS a ON a.address_id  = s.address_id
LEFT JOIN raw.province AS p ON p.province_id = a.province_id;


-- =====================================================================
-- DIMENSIONES PROPIAS (catálogos que no existen como tabla en raw/)
-- =====================================================================
-- En el sistema de origen estos valores son solo códigos sueltos
-- ('ads', 'CARD', 'FULFILLED'...). Los convertimos en dimensiones para
-- poder filtrar y agrupar con nombres claros en el tablero.


-- ---------------------------------------------------------------------
-- dim_order_status: estado del pedido y si cuenta como venta
-- ---------------------------------------------------------------------
-- La regla de negocio "solo PAID y FULFILLED son ventas" queda guardada
-- UNA vez acá (is_sale), en lugar de repetir el filtro en cada consulta.

CREATE TABLE dim_order_status (
    order_status_key  INTEGER PRIMARY KEY,
    status            VARCHAR NOT NULL,   -- código de origen
    status_desc       VARCHAR NOT NULL,   -- descripción en castellano
    is_sale           BOOLEAN NOT NULL    -- ¿suma en Total Ventas y Ticket?
);

INSERT INTO dim_order_status VALUES
    (1, 'CREATED',   'Creado (sin pagar)',   FALSE),
    (2, 'PAID',      'Pagado',               TRUE),
    (3, 'FULFILLED', 'Entregado',            TRUE),
    (4, 'CANCELLED', 'Cancelado',            FALSE),
    (5, 'REFUNDED',  'Reembolsado',          FALSE);


-- ---------------------------------------------------------------------
-- dim_traffic_source: de dónde llegó la visita a la web
-- ---------------------------------------------------------------------
-- Clave para Marketing: separa el tráfico que se paga (ads) del que
-- llega solo, y lo vincula con el equipo que lo genera.

CREATE TABLE dim_traffic_source (
    traffic_source_key  INTEGER PRIMARY KEY,
    source              VARCHAR,           -- código de origen (NULL en la -1)
    source_desc         VARCHAR NOT NULL,
    is_paid             BOOLEAN,           -- ¿es tráfico pago?
    marketing_action    VARCHAR            -- qué acción de Marketing lo genera
);

INSERT INTO dim_traffic_source
SELECT -1, NULL, 'Desconocido', NULL, NULL;

INSERT INTO dim_traffic_source
SELECT
    ROW_NUMBER() OVER (ORDER BY source) AS traffic_source_key,
    source,
    CASE source
        WHEN 'ads'      THEN 'Publicidad en redes'
        WHEN 'direct'   THEN 'Directo / newsletter'
        WHEN 'referral' THEN 'Referido / newsletter'
        WHEN 'organic'  THEN 'Buscadores (orgánico)'
        ELSE source
    END AS source_desc,
    source = 'ads' AS is_paid,
    CASE source
        WHEN 'ads'      THEN 'Campañas en redes'
        WHEN 'direct'   THEN 'Email marketing'
        WHEN 'referral' THEN 'Email marketing'
        WHEN 'organic'  THEN 'SEO'
        ELSE 'Otro'
    END AS marketing_action
FROM (SELECT DISTINCT source FROM raw.web_session WHERE source IS NOT NULL);


-- ---------------------------------------------------------------------
-- dim_device: dispositivo de la visita
-- ---------------------------------------------------------------------

CREATE TABLE dim_device (
    device_key   INTEGER PRIMARY KEY,
    device       VARCHAR,                  -- código de origen (NULL en la -1)
    device_desc  VARCHAR NOT NULL
);

INSERT INTO dim_device
SELECT -1, NULL, 'Desconocido';

INSERT INTO dim_device
SELECT
    ROW_NUMBER() OVER (ORDER BY device) AS device_key,
    device,
    CASE device
        WHEN 'mobile'  THEN 'Celular'
        WHEN 'desktop' THEN 'Computadora'
        WHEN 'tablet'  THEN 'Tablet'
        ELSE device
    END AS device_desc
FROM (SELECT DISTINCT device FROM raw.web_session WHERE device IS NOT NULL);


-- ---------------------------------------------------------------------
-- dim_payment_method: medio de pago
-- ---------------------------------------------------------------------
-- GATEWAY es la pasarela de pago online: según la consigna, Mercado Pago.

CREATE TABLE dim_payment_method (
    payment_method_key  INTEGER PRIMARY KEY,
    method              VARCHAR NOT NULL,  -- código de origen
    method_desc         VARCHAR NOT NULL
);

INSERT INTO dim_payment_method
SELECT
    ROW_NUMBER() OVER (ORDER BY method) AS payment_method_key,
    method,
    CASE method
        WHEN 'CARD'     THEN 'Tarjeta'
        WHEN 'CASH'     THEN 'Efectivo'
        WHEN 'TRANSFER' THEN 'Transferencia'
        WHEN 'GATEWAY'  THEN 'Mercado Pago'
        ELSE method
    END AS method_desc
FROM (SELECT DISTINCT method FROM raw.payment);
