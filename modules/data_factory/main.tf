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

resource "azurerm_data_factory_linked_service_web" "rest" {
  name                = "ls-rest-api"
  data_factory_id   = azurerm_data_factory.main.id

  url                 = "https://api-sellers.francecentral.azurecontainer.io:8080/api/"
  authentication_type = "Anonymous"
}

resource "azurerm_data_factory_dataset_http" "sellers_api" {
  name                = "sellers_api_dataset"
  data_factory_id     = azurerm_data_factory.main.id
  linked_service_name = azurerm_data_factory_linked_service_web.rest.name

  relative_url   = "sellers"
  request_method = "GET"

}

resource "azurerm_data_factory_dataset_http" "products_api" {
  name                = "products_api_dataset"
  data_factory_id     = azurerm_data_factory.main.id
  linked_service_name = azurerm_data_factory_linked_service_web.rest.name

  relative_url   = "products"
  request_method = "GET"

}

resource "azurerm_data_factory_dataset_azure_sql_table" "sellers_table" {
  name                = "sellers_table_dataset"
  data_factory_id   = azurerm_data_factory.main.id
  linked_service_id = azurerm_data_factory_linked_service_azure_sql_database.e6-sql.id

  table       = "bronze.seller"
}

resource "azurerm_data_factory_dataset_azure_sql_table" "products_table" {
  name                = "products_table_dataset"
  data_factory_id   = azurerm_data_factory.main.id
  linked_service_id = azurerm_data_factory_linked_service_azure_sql_database.e6-sql.id

  table     = "bronze.product"
}

resource "azurerm_data_factory_pipeline" "ingest_products" {
  name                = "ingest_products"
  data_factory_id  = azurerm_data_factory.main.id

  activities_json = <<ACTIVITIES
[
  {
    "name": "IngestProducts",
    "type": "Copy", 
    "inputs": [
      {
        "referenceName": "products_api_dataset",
        "type": "DatasetReference"
      }
    ],
    "outputs": [
      {
        "referenceName": "products_table_dataset",
        "type": "DatasetReference"
      }
    ],
    "typeProperties": {
      "source": {
        "type": "HttpSource"
      },
      "sink": {
        "type": "SqlSink"
      }
    }
  }
]
ACTIVITIES
  depends_on = [
    azurerm_data_factory_linked_service_web.rest,
    azurerm_data_factory_linked_service_azure_sql_database.e6-sql,
    azurerm_data_factory_dataset_azure_sql_table.products_table,
    azurerm_data_factory_dataset_http.products_api
  ]
} 

resource "azurerm_data_factory_trigger_schedule" "ingest_products_trigger" {
  name                = "ingest_products_trigger"
  data_factory_id   = azurerm_data_factory.main.id

  pipeline_name       = azurerm_data_factory_pipeline.ingest_products.name
  frequency   = "Day"
  interval    = 1
  depends_on = [
    azurerm_data_factory_pipeline.ingest_sellers
  ]
}

resource "azurerm_data_factory_pipeline" "ingest_sellers" {
  name                = "ingest_sellers"
  data_factory_id  = azurerm_data_factory.main.id

  activities_json = <<ACTIVITIES
[
  {
    "name": "IngestSellers",
    "type": "Copy", 
    "inputs": [
      {
        "referenceName": "sellers_api_dataset",
        "type": "DatasetReference"
      }
    ],
    "outputs": [
      {
        "referenceName": "sellers_table_dataset",
        "type": "DatasetReference"
      }
    ],
    "typeProperties": {
      "source": {
        "type": "HttpSource"
      },
      "sink": {
        "type": "SqlSink"
      }
    }
  }
]
ACTIVITIES
  depends_on = [
    azurerm_data_factory_linked_service_web.rest,
    azurerm_data_factory_linked_service_azure_sql_database.e6-sql, 
    azurerm_data_factory_dataset_azure_sql_table.sellers_table,
    azurerm_data_factory_dataset_http.sellers_api
  ]
} 

resource "azurerm_data_factory_trigger_schedule" "ingest_sellers_trigger" {
  name                = "ingest_sellers_trigger"
  data_factory_id   = azurerm_data_factory.main.id

  pipeline_name       = azurerm_data_factory_pipeline.ingest_sellers.name
  frequency   = "Day"
  interval    = 1
  depends_on = [
    azurerm_data_factory_pipeline.ingest_sellers
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

