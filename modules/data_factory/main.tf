resource "azurerm_data_factory" "main" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_data_factory_linked_service_azure_sql_database" "e6-sql" {
  name                = "ls-azuresql"
  data_factory_id   = azurerm_data_factory.main.id

  connection_string   = var.sql_connection_string
}

resource "azurerm_data_factory_linked_custom_service" "api_sellers" {

  name                = "ls-rest-api-sellers"

  data_factory_id =   azurerm_data_factory.main.id

  type = "RestService"

  type_properties_json = <<JSON

  {

            "url": "http://api-sellers.francecentral.azurecontainer.io:8080/api/",

            "enableServerCertificateValidation": false,

            "authenticationType": "Anonymous"

}

JSON

annotations = []

}

resource "azurerm_data_factory_custom_dataset" "rest_products" {
  name                = "ds_rest_products"
  data_factory_id     = azurerm_data_factory.main.id

  linked_service {
  name = azurerm_data_factory_linked_custom_service.api_sellers.name
  }

  type                = "RestResource"

  type_properties_json = <<JSON
  {
    "relativeUrl": "products",
    "requestMethod": "GET"
  }
  JSON
}

resource "azurerm_data_factory_custom_dataset" "rest_sellers" {
  name                = "ds_rest_sellers"
  data_factory_id     = azurerm_data_factory.main.id

  linked_service {
  name = azurerm_data_factory_linked_custom_service.api_sellers.name
  }

  type                = "RestResource"

  type_properties_json = <<JSON
  {
    "relativeUrl": "sellers",
    "requestMethod": "GET"
  }
  JSON
}

resource "azurerm_data_factory_dataset_azure_sql_table" "sellers_table" {
  name                = "sellers_table_bronze"
  data_factory_id   = azurerm_data_factory.main.id
  linked_service_id = azurerm_data_factory_linked_service_azure_sql_database.e6-sql.id
  schema     = "bronze"
  table       = "seller"
}

resource "azurerm_data_factory_dataset_azure_sql_table" "products_table" {
  name                = "products_table_bronze"
  data_factory_id   = azurerm_data_factory.main.id
  linked_service_id = azurerm_data_factory_linked_service_azure_sql_database.e6-sql.id

  schema     = "bronze"
  table     = "product"
}


resource "azurerm_data_factory_pipeline" "data_pipeline" {
  name            = "data_pipeline"
  data_factory_id = azurerm_data_factory.main.id

  activities_json = <<ACTIVITIES
[
  {
    "name": "IngestProducts",
    "type": "Copy",
    "dependsOn": [],
    "policy": {
      "retry": 0,
      "retryIntervalInSeconds": 30,
      "secureOutput": false,
      "secureInput": false
    },
    "userProperties": [],
    "typeProperties": {
      "source": {
        "type": "HttpSource",
        "httpRequestTimeout": "00:01:40"
      },
      "sink": {
        "type": "SqlSink"
      },
      "enableStaging": false
    },
    "inputs": [
      {
        "referenceName": "ds_rest_products",
        "type": "DatasetReference"
      }
    ],
    "outputs": [
      {
        "referenceName": "products_table_bronze",
        "type": "DatasetReference"
      }
    ]
  },
  {
    "name": "IngestSellers",
    "type": "Copy",
    "dependsOn": [],
    "policy": {
      "timeout": "0.12:00:00",
      "retry": 0,
      "retryIntervalInSeconds": 30,
      "secureOutput": false,
      "secureInput": false
    },
    "userProperties": [],
    "typeProperties": {
      "source": {
        "type": "RestSource",
        "httpRequestTimeout": "00:01:40",
        "requestInterval": "00.00:00:00.010"
      },
      "sink": {
        "type": "AzureSqlSink",
        "writeBehavior": "insert",
        "sqlWriterUseTableLock": false
      },
      "enableStaging": false
    },
    "inputs": [
      {
        "referenceName": "ds_rest_sellers",
        "type": "DatasetReference"
      }
    ],
    "outputs": [
      {
        "referenceName": "sellers_table_bronze",
        "type": "DatasetReference"
      }
    ]
  },
  {
    "name": "bronze_to_silver",
    "type": "Script",
    "dependsOn": [
      {
        "activity": "IngestProducts",
        "dependencyConditions": ["Succeeded"]
      },
      {
        "activity": "IngestSellers",
        "dependencyConditions": ["Succeeded"]
      }
    ],
    "policy": {
      "timeout": "0.12:00:00",
      "retry": 0,
      "retryIntervalInSeconds": 30,
      "secureOutput": false,
      "secureInput": false
    },
    "userProperties": [],
    "linkedServiceName": {
      "referenceName": "ls-azuresql",
      "type": "LinkedServiceReference"
    },
    "typeProperties": {
      "scripts": [
        {
          "type": "Query",
          "text": {
            "value": "-- PRODUCTS\nDROP TABLE IF EXISTS #product_clean;\nSELECT DISTINCT\n    TRIM(product_id)    AS product_id,\n    TRIM(seller_id)     AS seller_id,\n    TRIM(name)          AS name,\n    category,\n    TRY_CAST(unit_price AS DECIMAL(18,2)) AS unit_price,\n    TRY_CAST(stock AS INT)                 AS stock\nINTO #product_clean\nFROM bronze.product\nWHERE\n    product_id IS NOT NULL AND product_id <> ''\n    AND seller_id IS NOT NULL AND seller_id <> ''\n    AND name IS NOT NULL AND name <> ''\n    AND category IN ('Electronics', 'Home', 'Clothing', 'Books', 'Beauty')\n    AND ISNUMERIC(unit_price) = 1    -- on accepte seulement unité-prix numériques\n    AND TRY_CAST(unit_price AS DECIMAL(18,2)) BETWEEN 0.01 AND 10000\n    AND ISNUMERIC(stock) = 1\n    AND TRY_CAST(stock AS INT) >= 0 AND TRY_CAST(stock AS INT) < 10000\n;\n\n-- 2. SCD2 : ferme les versions en cours si changement détecté\nUPDATE silver.product\nSET\n    valid_to = GETDATE(),\n    is_current = 0\nFROM silver.product p\nJOIN #product_clean c ON p.product_id = c.product_id AND p.is_current = 1\nWHERE\n    (p.name <> c.name OR p.category <> c.category OR p.unit_price <> c.unit_price OR p.stock <> c.stock OR p.seller_id <> c.seller_id);\n\n-- 3. SCD2 : insère nouvelle version pour nouveaux produits ou produits ayant changé\nINSERT INTO silver.product\n    (product_id, seller_id, name, category, unit_price, stock, valid_from, valid_to, is_current)\nSELECT\n    c.product_id,\n    c.seller_id,\n    c.name,\n    c.category,\n    c.unit_price,\n    c.stock,\n    GETDATE(),\n    NULL,\n    1\nFROM #product_clean c\nLEFT JOIN silver.product p\n    ON p.product_id = c.product_id AND p.is_current = 1\nWHERE\n    p.product_id IS NULL\n    OR (p.name <> c.name OR p.category <> c.category OR p.unit_price <> c.unit_price OR p.stock <> c.stock OR p.seller_id <> c.seller_id)\n;\n\n-- CUSTOMERS\n-- 1. Import de la bronze vers une table temporaire nettoyée\nDROP TABLE IF EXISTS #customer_clean;\nSELECT\n    customer_id,\n    name,\n    email,\n    address,\n    city,\n    country\nINTO #customer_clean\nFROM bronze.customer\nWHERE\n    customer_id IS NOT NULL AND customer_id <> ''\n    AND name      IS NOT NULL AND name      <> ''\n    AND email     IS NOT NULL AND email     <> ''\n    AND address   IS NOT NULL AND address   <> ''\n    AND city      IS NOT NULL AND city      <> ''\n    AND country   IS NOT NULL AND country   <> '';\n\n-- 2. Fermer SCD2 si changement de version\nUPDATE silver.customer\nSET\n    valid_to = GETDATE(),\n    is_current = 0\nFROM silver.customer s\nJOIN #customer_clean b ON b.customer_id = s.customer_id\nWHERE s.is_current = 1\n  AND (\n         s.name    <> b.name\n      OR s.email   <> b.email\n      OR s.address <> b.address\n      OR s.city    <> b.city\n      OR s.country <> b.country\n  );\n\n-- 3. Insérer nouvelle version (ou nouveaux clients)\nINSERT INTO silver.customer\n(customer_id, name, email, address, city, country, valid_from, valid_to, is_current)\nSELECT\n    b.customer_id,\n    b.name,\n    b.email,\n    b.address,\n    b.city,\n    b.country,\n    GETDATE() AS valid_from,\n    NULL      AS valid_to,\n    1         AS is_current\nFROM #customer_clean b\nLEFT JOIN silver.customer s\n    ON b.customer_id = s.customer_id AND s.is_current = 1\nWHERE\n    s.customer_id IS NULL             -- nouveau client\n    OR (\n         s.name    <> b.name\n      OR s.email   <> b.email\n      OR s.address <> b.address\n      OR s.city    <> b.city\n      OR s.country <> b.country      -- OU client changé : on ajoute une nouvelle version\n    );\n\n-- SELLERS \nDROP TABLE IF EXISTS #seller_clean;\nSELECT DISTINCT\n    TRIM(seller_id)   AS seller_id,\n    TRIM(name)        AS name,\n    category,\n    LOWER(status)     AS status\nINTO #seller_clean\nFROM bronze.seller\nWHERE\n    seller_id IS NOT NULL AND seller_id <> ''\n    AND name IS NOT NULL AND name <> ''\n    AND category IN ('Electronics', 'Home', 'Clothing', 'Books', 'Beauty')\n    AND status IN ('active', 'pending', 'suspended')\n;\n\n-- 2. SCD2 : ferme les versions en cours si changement détecté\nUPDATE silver.seller\nSET\n    valid_to = GETDATE(),\n    is_current = 0\nFROM silver.seller s\nJOIN #seller_clean c ON s.seller_id = c.seller_id AND s.is_current = 1\nWHERE\n    (s.name <> c.name OR s.category <> c.category OR s.status <> c.status);\n\n-- 3. SCD2 : insère nouvelle version pour nouveaux sellers ou sellers qui ont changé\nINSERT INTO silver.seller\n    (seller_id, name, category, status, valid_from, valid_to, is_current)\nSELECT\n    c.seller_id,\n    c.name,\n    c.category,\n    c.status,\n    GETDATE(),    -- valid_from = maintenant\n    NULL,         -- valid_to = NULL = en cours\n    1             -- is_current = 1\nFROM #seller_clean c\nLEFT JOIN silver.seller s\n    ON s.seller_id = c.seller_id AND s.is_current = 1\nWHERE\n    s.seller_id IS NULL                     -- nouveau seller (absent en silver)\n    OR (s.name <> c.name OR s.category <> c.category OR s.status <> c.status) -- ou changement\n;\n\nWITH clean_orders AS (\n    SELECT\n        order_id,\n        product_id,\n        customer_id,\n        TRY_CAST(quantity AS INT) AS quantity,\n        TRY_CAST(unit_price AS DECIMAL(18,2)) AS unit_price,\n        status,\n        TRY_CAST(REPLACE(LEFT(order_timestamp,23), 'T', ' ') AS DATETIME) AS order_timestamp,\n        ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY load_datetime DESC) AS rn\n    FROM bronze.orders\n    WHERE\n        order_id IS NOT NULL AND order_id <> ''\n        AND product_id IS NOT NULL AND product_id <> ''\n        AND customer_id IS NOT NULL AND customer_id <> ''\n        AND quantity IS NOT NULL AND quantity <> ''\n        AND unit_price IS NOT NULL AND unit_price <> ''\n        AND status IS NOT NULL AND status <> ''\n        AND order_timestamp IS NOT NULL AND order_timestamp <> ''\n        AND TRY_CAST(REPLACE(LEFT(order_timestamp,23), 'T', ' ') AS DATETIME) IS NOT NULL\n        AND ISNUMERIC(quantity) = 1\n        AND TRY_CAST(quantity AS INT) > 0 AND TRY_CAST(quantity AS INT) < 1000\n        AND ISNUMERIC(unit_price) = 1\n        AND TRY_CAST(unit_price AS DECIMAL(18,2)) >= 0\n        AND TRY_CAST(unit_price AS DECIMAL(18,2)) < 10000\n        AND status IN ('PLACED','SHIPPED','CANCELLED','RETURNED')\n        AND order_id NOT IN (SELECT order_id FROM silver.orders)\n)\nINSERT INTO silver.orders\n    (order_id, product_id, customer_id, quantity, unit_price, status, order_timestamp)\nSELECT\n    order_id, product_id, customer_id, quantity, unit_price, status, order_timestamp\nFROM clean_orders\nWHERE rn = 1;\nWITH clean_clickstream AS (\n    SELECT\n        event_id,\n        session_id,\n        user_id,\n        CAST(url AS NVARCHAR(1000)) AS url,\n        event_type,\n        TRY_CAST(REPLACE(LEFT(event_timestamp,23), 'T', ' ') AS DATETIME) AS event_timestamp,\n        ROW_NUMBER() OVER (\n            PARTITION BY event_id\n            ORDER BY load_datetime DESC  -- On privilégie la ligne la plus récente si plusieurs\n        ) as rn\n    FROM bronze.clickstream\n    WHERE\n        event_id   IS NOT NULL AND event_id   <> ''\n        AND session_id IS NOT NULL AND session_id <> ''\n        AND url    IS NOT NULL AND url    <> ''\n        AND LEN(url) <= 1000\n        AND event_type IN ('view_page', 'add_to_cart', 'checkout_start')\n        AND event_type IS NOT NULL AND event_type <> ''\n        AND event_timestamp IS NOT NULL AND event_timestamp <> ''\n        AND TRY_CAST(REPLACE(LEFT(event_timestamp,23), 'T', ' ') AS DATETIME) IS NOT NULL\n        AND event_id NOT IN (SELECT event_id FROM silver.clickstream)\n)\nINSERT INTO silver.clickstream\n    (event_id, session_id, user_id, url, event_type, event_timestamp)\nSELECT\n    event_id, session_id, user_id, url, event_type, event_timestamp\nFROM clean_clickstream\nWHERE rn = 1;",
            "type": "Expression"
          }
        }
      ],
      "scriptBlockExecutionTimeout": "02:00:00"
    }
  },
  {
    "name": "silver_to_gold",
    "type": "Script",
    "dependsOn": [
      {
        "activity": "bronze_to_silver",
        "dependencyConditions": ["Succeeded"]
      }
    ],
    "policy": {
      "timeout": "0.12:00:00",
      "retry": 0,
      "retryIntervalInSeconds": 30,
      "secureOutput": false,
      "secureInput": false
    },
    "userProperties": [],
    "linkedServiceName": {
      "referenceName": "ls-azuresql",
      "type": "LinkedServiceReference"
    },
    "typeProperties": {
      "scripts": [
        {
          "type": "Query",
          "text": {
            "value": "TRUNCATE TABLE gold.customer;\nINSERT INTO gold.customer (customer_id, name, email, country, city)\nSELECT\n    customer_id, name, email, country, city\nFROM silver.customer\nWHERE is_current = 1;\n\nTRUNCATE TABLE gold.product;\nINSERT INTO gold.product (product_id, seller_id, name, category, unit_price, stock)\nSELECT\n    product_id, seller_id, name, category, unit_price, stock\nFROM silver.product\nWHERE is_current = 1;\n\nTRUNCATE TABLE gold.seller;\nINSERT INTO gold.seller (seller_id, name, category, status)\nSELECT\n    seller_id, name, category, status\nFROM silver.seller\nWHERE is_current = 1;\n\nTRUNCATE TABLE gold.orders;\nINSERT INTO gold.orders (\n    order_id,\n    product_id,\n    customer_id,\n    quantity,\n    unit_price,\n    status,\n    order_timestamp,\n    seller_id\n) \nSELECT\n    o.order_id,\n    o.product_id,\n    o.customer_id,\n    o.quantity,\n    o.unit_price,\n    o.status,\n    o.order_timestamp,\n    p.seller_id\nFROM silver.orders o\nLEFT JOIN gold.product p ON o.product_id = p.product_id;\n\nTRUNCATE TABLE gold.clickstream;\nINSERT INTO gold.clickstream (\n    event_id,\n    session_id,\n    user_id,\n    url,\n    event_type,\n    event_timestamp,\n    event_date,\n    event_time\n)\nSELECT\n    event_id,\n    session_id,\n    user_id,\n    url,\n    event_type,\n    event_timestamp,\n    CAST(event_timestamp AS DATE) AS event_date,\n    CAST(event_timestamp AS TIME) AS event_time\nFROM silver.clickstream;\n\nTRUNCATE TABLE gold.clickstream;\nINSERT INTO gold.clickstream (\n    event_id,\n    session_id,\n    user_id,\n    url,\n    event_type,\n    event_timestamp,\n    event_date,\n    event_time\n)\nSELECT\n    event_id,\n    session_id,\n    user_id,\n    url,\n    event_type,\n    event_timestamp,\n    CAST(event_timestamp AS DATE) AS event_date,\n    CAST(event_timestamp AS TIME) AS event_time\nFROM silver.clickstream;\n\n",
            "type": "Expression"
          }
        }
      ],
      "scriptBlockExecutionTimeout": "02:00:00"
    }
  }
]
ACTIVITIES

  depends_on = [
    azurerm_data_factory_linked_custom_service.api_sellers,
    azurerm_data_factory_linked_service_azure_sql_database.e6-sql,
    azurerm_data_factory_dataset_azure_sql_table.products_table,
    azurerm_data_factory_custom_dataset.rest_products,
    azurerm_data_factory_dataset_azure_sql_table.sellers_table,
    azurerm_data_factory_custom_dataset.rest_sellers
  ]
}


resource "azurerm_data_factory_trigger_schedule" "data_pipeline_trigger" {
  name                = "data_pipeline_trigger"
  data_factory_id   = azurerm_data_factory.main.id

  pipeline_name       = azurerm_data_factory_pipeline.data_pipeline.name
  frequency   = "Day"
  interval    = 1
  depends_on = [
    azurerm_data_factory_pipeline.data_pipeline
  ]
}



resource "azurerm_data_factory_pipeline" "purge_inactive_customers" {
  name                = "purge_inactive_customers"
  data_factory_id  = azurerm_data_factory.main.id

  activities_json = <<ACTIVITIES
[
  {
    "name": "PurgeInactiveClients",
    "type": "SqlServerStoredProcedure",
    "linkedServiceName": {
      "referenceName": "ls-azuresql",
      "type": "LinkedServiceReference"
    },
    "typeProperties": {
      "storedProcedureName": "purge_inactive_customers"
    }
  }
]
ACTIVITIES
  depends_on = [
    azurerm_data_factory_linked_service_azure_sql_database.e6-sql
  ]
}

resource "azurerm_data_factory_trigger_schedule" "purge_inactive_customers_trigger" {
  name                = "purge_inactive_customers_trigger"
  data_factory_id   = azurerm_data_factory.main.id

  pipeline_name       = azurerm_data_factory_pipeline.purge_inactive_customers.name
  frequency   = "Month"
  interval    = 1
  schedule {

    monthly {
        weekday = "Sunday"
        week = "1"
    }
  }
  depends_on = [
    azurerm_data_factory_pipeline.purge_inactive_customers
  ]
}

resource "azurerm_data_factory_pipeline" "purge_by_request" {
  name                = "purge_by_request"
  data_factory_id  = azurerm_data_factory.main.id

  activities_json = <<ACTIVITIES
[
  {
    "name": "PurgeByRequest",
    "type": "SqlServerStoredProcedure",
    "linkedServiceName": {
      "referenceName": "ls-azuresql",
      "type": "LinkedServiceReference"
    },
    "typeProperties": {
      "storedProcedureName": "purge_customer_by_request",
      "storedProcedureParameters": {
        "customer_id": {
          "type": "String"
        }
      }
    }
  }
]
ACTIVITIES
  depends_on = [
    azurerm_data_factory_linked_service_azure_sql_database.e6-sql
  ]
}

resource "azurerm_data_factory_pipeline" "replay_purge" {
  name                = "replay_purge"
  data_factory_id  = azurerm_data_factory.main.id

  activities_json = <<ACTIVITIES
[
  {
    "name": "ReplayPurge",
    "type": "SqlServerStoredProcedure",
    "linkedServiceName": {
      "referenceName": "ls-azuresql",
      "type": "LinkedServiceReference"
    },
    "typeProperties": {
      "storedProcedureName": "replay_purge_actions",
      "storedProcedureParameters": {
        "restore_date": {
          "type": "String"
        }
      }
    }
  }
]
ACTIVITIES
  depends_on = [
    azurerm_data_factory_linked_service_azure_sql_database.e6-sql
  ]
}

