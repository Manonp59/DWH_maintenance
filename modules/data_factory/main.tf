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
            "value": "-- MÊTS ICI TON BLOC SQL DE TRANSFORMATION BRONZE -> SILVER (voir plus haut)",
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
            "value": "-- MÊTS ICI TON BLOC SQL DE TRANSFORMATION SILVER -> GOLD (voir plus haut)",
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

