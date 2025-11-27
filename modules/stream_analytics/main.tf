resource "azurerm_stream_analytics_job" "asa_job" {
  name                                     = "asa-shopnow"
  resource_group_name                      = var.resource_group_name
  location                                 = var.location
  compatibility_level                      = "1.2"
  data_locale                              = "en-US"
  events_late_arrival_max_delay_in_seconds = 60
  events_out_of_order_max_delay_in_seconds = 50
  events_out_of_order_policy               = "Adjust"
  output_error_policy                      = "Drop"
  streaming_units                          = 1

  transformation_query = <<QUERY

    /* 1. Orders -> bronze.orders */
  
    SELECT
        o.order_id,
        i.ArrayValue.product_id,
        o.customer.id AS customer_id,
        i.ArrayValue.quantity,
        i.ArrayValue.unit_price,
        o.status,
        DATEADD(second, o.timestamp, '1970-01-01') AS order_timestamp
    INTO
        [OutputFactOrder]
    FROM
        [InputOrders] o
    CROSS APPLY GetArrayElements(o.items) AS i

    
    /* 3. Orders (Customer info) -> bronze.customer */
    
    SELECT
        customer.id AS customer_id,
        customer.name,
        customer.email,
        customer.address,
        customer.city,
        customer.country
    INTO
        [OutputDimCustomer]
    FROM
        [InputOrders]

    /* 4. Clickstream -> bronze.clickstream */
    SELECT
        event_id,
        session_id,
        user_id,
        url,
        event_type,
        DATEADD(second, timestamp, '1970-01-01') AS event_timestamp
    INTO
        [OutputFactClickstream]
    FROM
        [InputClickstream]
QUERY
}

# --- INPUTS ---

resource "azurerm_stream_analytics_stream_input_eventhub" "input_orders" {
  name                         = "InputOrders"
  stream_analytics_job_name    = azurerm_stream_analytics_job.asa_job.name
  resource_group_name          = var.resource_group_name
  eventhub_consumer_group_name = "$Default"
  eventhub_name                = "orders"
  servicebus_namespace         = var.eventhub_namespace_name
  shared_access_policy_key     = var.eventhub_listen_key
  shared_access_policy_name    = "listen-policy"

  serialization {
    type     = "Json"
    encoding = "UTF8"
  }
}


resource "azurerm_stream_analytics_stream_input_eventhub" "input_clickstream" {
  name                         = "InputClickstream"
  stream_analytics_job_name    = azurerm_stream_analytics_job.asa_job.name
  resource_group_name          = var.resource_group_name
  eventhub_consumer_group_name = "$Default"
  eventhub_name                = "clickstream"
  servicebus_namespace         = var.eventhub_namespace_name
  shared_access_policy_key     = var.eventhub_listen_key
  shared_access_policy_name    = "listen-policy"

  serialization {
    type     = "Json"
    encoding = "UTF8"
  }
}

# --- OUTPUTS ---

resource "azurerm_stream_analytics_output_mssql" "output_order" {
  name                      = "OutputFactOrder"
  stream_analytics_job_name = azurerm_stream_analytics_job.asa_job.name
  resource_group_name       = var.resource_group_name
  server                    = var.sql_server_fqdn
  user                      = var.sql_admin_login
  password                  = var.sql_admin_password
  database                  = var.sql_database_name
  table                     = "bronze.orders"
}

resource "azurerm_stream_analytics_output_mssql" "output_customer" {
  name                      = "OutputDimCustomer"
  stream_analytics_job_name = azurerm_stream_analytics_job.asa_job.name
  resource_group_name       = var.resource_group_name
  server                    = var.sql_server_fqdn
  user                      = var.sql_admin_login
  password                  = var.sql_admin_password
  database                  = var.sql_database_name
  table                     = "bronze.customer"
}

resource "azurerm_stream_analytics_output_mssql" "output_clickstream" {
  name                      = "OutputFactClickstream"
  stream_analytics_job_name = azurerm_stream_analytics_job.asa_job.name
  resource_group_name       = var.resource_group_name
  server                    = var.sql_server_fqdn
  user                      = var.sql_admin_login
  password                  = var.sql_admin_password
  database                  = var.sql_database_name
  table                     = "bronze.clickstream"
}

# Terraform crée et configure le job Stream Analytics, mais Azure ne démarre
# jamais automatiquement un job ASA après son déploiement. Sans un démarrage
# explicite, le job reste à l'état "Stopped" et ne consomme aucun événement.
resource "null_resource" "start_job" {
  triggers = {
    job_id = azurerm_stream_analytics_job.asa_job.id
  }

  depends_on = [
    azurerm_stream_analytics_job.asa_job,
    azurerm_stream_analytics_stream_input_eventhub.input_orders,
    azurerm_stream_analytics_stream_input_eventhub.input_clickstream,
    azurerm_stream_analytics_output_mssql.output_order,
    azurerm_stream_analytics_output_mssql.output_customer,
    azurerm_stream_analytics_output_mssql.output_clickstream
  ]

  provisioner "local-exec" {
    command = "az stream-analytics job start --resource-group ${var.resource_group_name} --name ${azurerm_stream_analytics_job.asa_job.name} --output-start-mode JobStartTime"
  }
}
