-- Create Tables for ShopNow DWH

-- schemas 
GO
DROP TABLE IF EXISTS bronze.customer;
GO
DROP TABLE IF EXISTS bronze.product;
GO
DROP TABLE IF EXISTS bronze.orders;
GO
DROP TABLE IF EXISTS bronze.clickstream;
GO
DROP TABLE IF EXISTS bronze.seller;
GO
DROP SCHEMA IF EXISTS bronze ;
GO
DROP TABLE IF EXISTS silver.seller;
GO
DROP TABLE IF EXISTS silver.product;
GO
DROP TABLE IF EXISTS silver.customer;
GO
DROP TABLE IF EXISTS silver.orders;
GO
DROP TABLE IF EXISTS silver.clickstream;
GO
DROP SCHEMA IF EXISTS silver;
GO
DROP TABLE IF EXISTS gold.customer;
GO
DROP TABLE IF EXISTS gold.product;
GO
DROP TABLE IF EXISTS gold.seller;
GO
DROP TABLE IF EXISTS gold.orders;
GO
DROP TABLE IF EXISTS gold.clickstream;
GO  
DROP VIEW IF EXISTS gold.sales_by_seller;
GO
DROP SCHEMA IF EXISTS gold ;
GO
CREATE SCHEMA bronze;
GO
CREATE SCHEMA silver;
GO
CREATE SCHEMA gold;
GO
-- BRONZE TABLES
-- bronze.customer
CREATE TABLE bronze.customer (
    customer_id VARCHAR(50) PRIMARY KEY,
    name        NVARCHAR(255),
    email       NVARCHAR(255),
    address     NVARCHAR(500),
    city        NVARCHAR(100),
    country     NVARCHAR(100),
    load_datetime DATETIME DEFAULT GETDATE()
);
GO

-- bronze.product
CREATE TABLE bronze.product (
    product_id   VARCHAR(100) NULL,
    seller_id    VARCHAR(100) NULL,
    name         NVARCHAR(255) NULL,
    category     NVARCHAR(100) NULL,
    unit_price   NVARCHAR(255) NULL,   -- note : stocke en texte, car tu peux avoir des erreurs de type !
    stock        INT NULL,
    load_datetime DATETIME DEFAULT GETDATE()
);
GO

-- 3. bronze.orders
CREATE TABLE bronze.orders (
    order_id        VARCHAR(50)     NULL,
    product_id      VARCHAR(50)     NULL,
    customer_id     VARCHAR(50)     NULL,
    quantity        NVARCHAR(100)   NULL,   -- plus souple, accepte texte ou incohérence
    unit_price      NVARCHAR(100)   NULL,
    status          NVARCHAR(50)    NULL,
    order_timestamp NVARCHAR(100)   NULL,
    load_datetime   DATETIME        DEFAULT GETDATE()
);
GO

-- 4. sellers
CREATE TABLE bronze.seller (
    -- PAS de clé primaire, tous les champs peuvent être NULL ou incohérents !
    seller_id   VARCHAR(100) NULL,
    name        NVARCHAR(255) NULL,
    category    NVARCHAR(100) NULL,
    status      NVARCHAR(100) NULL,
    load_datetime DATETIME DEFAULT GETDATE()
);
GO

-- 5. bronze.clickstream
CREATE TABLE bronze.clickstream (
    event_id        VARCHAR(50)      NULL, -- pas de PRIMARY KEY en bronze
    session_id      VARCHAR(50)      NULL,
    user_id         VARCHAR(50)      NULL,
    url             NVARCHAR(MAX)    NULL,
    event_type      NVARCHAR(100)    NULL,
    event_timestamp NVARCHAR(100)    NULL,  -- on autorise mauvais formats
    load_datetime   DATETIME         DEFAULT GETDATE()
);
GO

-- SILVER TABLES
-- seller
CREATE TABLE silver.seller (
    tech_id            INT IDENTITY(1,1) PRIMARY KEY,    -- surrogate key (technique, interne)
    seller_id        VARCHAR(100) NOT NULL,             -- clé métier
    name             NVARCHAR(255) NOT NULL,
    category         NVARCHAR(50)  NOT NULL,
    status           NVARCHAR(20)  NOT NULL,
    valid_from       DATETIME      NOT NULL,
    valid_to         DATETIME      NULL,
    is_current       BIT           NOT NULL DEFAULT 1   -- indique la version en cours (1=true,0=archive)
);
GO
-- product
CREATE TABLE silver.product (
    tech_id      INT IDENTITY(1,1) PRIMARY KEY,
    product_id   VARCHAR(100) ,
    seller_id    VARCHAR(100) NOT NULL,
    name         NVARCHAR(255) NOT NULL,
    category     NVARCHAR(50)  NOT NULL,
    unit_price   DECIMAL(18,2) NOT NULL CHECK (unit_price BETWEEN 0.01 AND 10000),
    stock        INT NOT NULL CHECK (stock >= 0 AND stock <= 10000),
    valid_from       DATETIME      NOT NULL,
    valid_to         DATETIME      NULL,
    is_current       BIT           NOT NULL DEFAULT 1   -- indique la version en cours (1=true,0=archive)
);
GO
-- customer
CREATE TABLE silver.customer (
    customer_id VARCHAR(50) PRIMARY KEY,
    name        NVARCHAR(255) NOT NULL,
    email       NVARCHAR(255) NOT NULL,
    address     NVARCHAR(500) NOT NULL,
    city        NVARCHAR(100) NOT NULL,
    country     NVARCHAR(100) NOT NULL,
    valid_from       DATETIME      NOT NULL,
    valid_to         DATETIME      NULL,
    is_current       BIT           NOT NULL DEFAULT 1   -- indique la version en cours (
);
GO

-- Order
CREATE TABLE silver.orders (
    order_id        VARCHAR(50) PRIMARY KEY,          -- Unicité garantie
    product_id      VARCHAR(50) NOT NULL,
    customer_id     VARCHAR(50) NOT NULL,
    quantity        INT         NOT NULL CHECK (quantity > 0 AND quantity < 1000), -- bornes raisonnables
    unit_price      DECIMAL(18, 2) NOT NULL CHECK (unit_price >= 0 AND unit_price < 10000),
    status          NVARCHAR(50)  NOT NULL CHECK (status IN ("PLACED","SHIPPED","CANCELLED","RETURNED")),
    order_timestamp DATETIME      NOT NULL,
    -- Ajoute de la traçabilité sur le process
    silver_load_datetime DATETIME DEFAULT GETDATE()   -- date d’insertion en silver
);
GO
-- CLICKSTREAM
CREATE TABLE silver.clickstream (
    event_id        VARCHAR(50)   PRIMARY KEY,                      -- unicité des events valides
    session_id      VARCHAR(50)   NOT NULL,
    user_id         VARCHAR(50)   NULL,         -- Anonymat autorisé
    url             NVARCHAR(1000) NOT NULL,    -- taille bornée
    event_type      NVARCHAR(20)  NOT NULL CHECK (event_type IN ("view_page", "add_to_cart", "checkout_start")),
    event_timestamp DATETIME      NOT NULL,
    silver_load_datetime DATETIME DEFAULT GETDATE()
);
GO

-- GOLD TABLES
-- 1. gold.customer
CREATE TABLE gold.customer (
    customer_id VARCHAR(50) PRIMARY KEY,
    name        NVARCHAR(255),
    email       NVARCHAR(255),
    country     NVARCHAR(100),
    city        NVARCHAR(100),
)
GO
-- 2. gold.product
CREATE TABLE gold.product (
    product_id   VARCHAR(100) PRIMARY KEY,
    seller_id    VARCHAR(100),
    name         NVARCHAR(255),
    category     NVARCHAR(100),
    unit_price   DECIMAL(18,2),
    stock        INT
);
GO
-- 3. gold.seller
CREATE TABLE gold.seller (
    seller_id   VARCHAR(100) PRIMARY KEY,
    name        NVARCHAR(255),
    category    NVARCHAR(100),
    status      NVARCHAR(100)
);
GO
-- 4. gold.orders
CREATE TABLE gold.orders (
    order_id        VARCHAR(50) PRIMARY KEY,
    product_id      VARCHAR(50),
    customer_id     VARCHAR(50),
    quantity        INT,
    unit_price      DECIMAL(18,2),
    status          NVARCHAR(50),
    order_timestamp DATETIME,
    seller_id NVARCHAR(100),
    total_price     AS (quantity * unit_price) ,
    order_year      AS (YEAR(order_timestamp)) ,
    order_month     AS (MONTH(order_timestamp)) ,
    order_day       AS (DAY(order_timestamp)) ,
);
GO
-- 5. gold.clickstream
CREATE TABLE gold.clickstream (
    event_id        VARCHAR(50) PRIMARY KEY,
    session_id      VARCHAR(50),
    user_id         VARCHAR(50),
    url             NVARCHAR(MAX),
    event_type      NVARCHAR(100),
    event_timestamp DATETIME,
    event_date DATE NOT NULL, 
    event_time TIME NOT NULL,      
);
GO

-- VIEW sales_by_seller
CREATE OR ALTER VIEW gold.sales_by_seller AS
SELECT
    s.seller_id,
    s.name AS seller_name,
    SUM(o.total_price) AS total_sales,
    COUNT(DISTINCT o.order_id) AS total_orders,
    COUNT(DISTINCT o.customer_id) AS unique_customers
FROM
    gold.seller s
LEFT JOIN
    gold.product p ON s.seller_id = p.seller_id
LEFT JOIN
    gold.orders o ON p.product_id = o.product_id
GROUP BY
    s.seller_id,
    s.name;
GO

-- 6. audit_purge
DROP TABLE IF EXISTS audit_purge;
CREATE TABLE audit_purge (
    customer_id   VARCHAR(50),
    action_date   DATETIME,
    action_type   NVARCHAR(50)
);
GO


-- 7. procédure stockée purge_inactive_customers
CREATE OR ALTER PROCEDURE purge_inactive_customers
AS
BEGIN
    -- Sélectionne les IDs
    DECLARE @ClientsPurge TABLE (customer_id VARCHAR(50));
    INSERT INTO @ClientsPurge (customer_id)
    SELECT c.customer_id
    FROM bronze.customer c
    LEFT JOIN bronze.orders o
        ON c.customer_id = o.customer_id
        AND o.order_timestamp >= DATEADD(MONTH, -30, GETDATE())
    LEFT JOIN bronze.clickstream cs
        ON c.customer_id = cs.user_id
        AND cs.event_timestamp >= DATEADD(MONTH, -30, GETDATE())
    WHERE o.order_id IS NULL AND cs.event_id IS NULL;

    -- anonymisation :
    UPDATE bronze.customer
    SET name = NULL, email = NULL, address = NULL, city = NULL, country = NULL
    WHERE customer_id IN (SELECT customer_id FROM @ClientsPurge);

    -- ANONYMISATION silver :
    UPDATE silver.customer
    SET name = NULL, email = NULL, address = NULL, city = NULL, country = NULL
    WHERE customer_id IN (SELECT customer_id FROM @ClientsPurge);

    -- ANONYMISATION gold :
    UPDATE gold.customer
    SET name = NULL, email = NULL, address = NULL, city = NULL, country = NULL
    WHERE customer_id IN (SELECT customer_id FROM @ClientsPurge);
    
    -- audit
    INSERT INTO audit_purge (customer_id, action_date, action_type)
	SELECT customer_id, GETDATE(), "PURGE_INACTIVE_CUSTOMER"
	FROM @ClientsPurge;
END
GO


-- 8. procédure stockée purge_customer_on_demand
CREATE OR ALTER PROCEDURE purge_customer_by_request
    @customer_id VARCHAR(50)
AS
BEGIN
    UPDATE bronze.customer
    SET name = NULL,
        email = NULL,
        address = NULL,
        city = NULL,
        country = NULL
    WHERE customer_id = @customer_id;

    -- Anonymisation silver :
    UPDATE silver.customer
    SET name = NULL,
        email = NULL,
        address = NULL,
        city = NULL,
        country = NULL
    WHERE customer_id = @customer_id;

    -- Anonymisation gold :
    UPDATE gold.customer
    SET name = NULL,
        email = NULL,
        address = NULL,
        city = NULL,
        country = NULL
    WHERE customer_id = @customer_id;

    -- Audit
    INSERT INTO audit_purge (customer_id, action_date, action_type)
    VALUES (@customer_id, GETDATE(), "DROIT_OUBLI");
END
GO

-- 9. procédure stockée replay_purge_actions
CREATE OR ALTER PROCEDURE replay_purge_actions
    @restore_date DATETIME
AS
BEGIN
    -- 1. Identifier les clients à réanonymiser après restauration
    -- (ceux qui ont été purgés après la backup restaurée)
    UPDATE bronze.customer
    SET name = NULL,
        email = NULL,
        address = NULL,
        city = NULL,
        country = NULL
    WHERE customer_id IN (
        SELECT customer_id
        FROM audit_purge
        WHERE action_date > @restore_date
            AND action_type IN ("DROIT_OUBLI", "PURGE_INACTIVE_CUSTOMER")
    );

    -- Anonymisation silver :
    UPDATE silver.customer
    SET name = NULL,
        email = NULL,
        address = NULL,
        city = NULL,
        country = NULL
    WHERE customer_id IN (
        SELECT customer_id
        FROM audit_purge
        WHERE action_date > @restore_date
            AND action_type IN ("DROIT_OUBLI", "PURGE_INACTIVE_CUSTOMER")
    );
END
GO
