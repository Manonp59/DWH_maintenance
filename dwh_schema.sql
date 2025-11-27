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
DROP SCHEMA IF EXISTS silver;
GO
DROP SCHEMA IF EXISTS gold ;
GO
CREATE SCHEMA bronze;
GO
CREATE SCHEMA silver;
GO
CREATE SCHEMA gold;

GO
-- 1. bronze.customer
CREATE TABLE bronze.customer (
    customer_id VARCHAR(50) PRIMARY KEY,
    name        NVARCHAR(255),
    email       NVARCHAR(255),
    address     NVARCHAR(500),
    city        NVARCHAR(100),
    country     NVARCHAR(100)
);
GO

-- 2. bronze.product
CREATE TABLE bronze.product (
    product_id VARCHAR(50) PRIMARY KEY,
    name       NVARCHAR(255),
    category   NVARCHAR(100),
    unit_price DECIMAL(18, 2),
    stock      INT,
    seller_id  VARCHAR(50),   
);
GO

-- 3. bronze.orders
CREATE TABLE bronze.orders (
    order_id        VARCHAR(50),
    product_id      VARCHAR(50),
    customer_id     VARCHAR(50),
    quantity        INT,
    unit_price      DECIMAL(18, 2),
    status          NVARCHAR(50),
    order_timestamp DATETIME
);
GO

-- 4. sellers
CREATE TABLE bronze.seller (
    seller_id VARCHAR(50) PRIMARY KEY,
    name      NVARCHAR(255),
    category  NVARCHAR(100),
    status    NVARCHAR(50)
);
GO

-- 5. bronze.clickstream
DROP TABLE IF EXISTS bronze.clickstream;
CREATE TABLE bronze.clickstream (
    event_id        VARCHAR(50) PRIMARY KEY,
    session_id      VARCHAR(50),
    user_id         VARCHAR(50),
    url             NVARCHAR(MAX),
    event_type      NVARCHAR(50),
    event_timestamp DATETIME
);
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
END
GO
