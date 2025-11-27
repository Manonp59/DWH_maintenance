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

