resource "azurerm_resource_group" "rg" {
  name     = "rg-e6-${var.username}"
  location = var.location
}

// Event Hubs
module "module_event_hubs" {
  source                  = "./modules/event_hubs"
  depends_on              = [azurerm_resource_group.rg]
  location                = azurerm_resource_group.rg.location
  resource_group_name     = azurerm_resource_group.rg.name
  eventhub_namespace_name = "eh-${var.username}"
  eventhubs               = var.eventhubs
}

// DB
module "sql_database" {
  source              = "./modules/sql_database"
  depends_on          = [azurerm_resource_group.rg]
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sql_admin_login     = var.sql_admin_login
  sql_admin_password  = var.sql_admin_password
  schema_file_path    = "${path.root}/dwh_schema.sql"
  username            = var.username
  notification_email  = var.notification_email
}

// Stream
module "stream_analytics" {
  source                  = "./modules/stream_analytics"
  depends_on              = [module.module_event_hubs, module.sql_database]
  resource_group_name     = azurerm_resource_group.rg.name
  location                = azurerm_resource_group.rg.location
  eventhub_namespace_name = "eh-${var.username}"
  eventhub_listen_key     = module.module_event_hubs.listen_connection_string
  sql_server_fqdn         = module.sql_database.server_fqdn
  sql_database_name       = module.sql_database.database_name
  sql_admin_login         = var.sql_admin_login
  sql_admin_password      = var.sql_admin_password
}

// Event producers
module "container_producers" {
  source     = "./modules/container_producers"
  depends_on = [module.module_event_hubs, module.stream_analytics]

  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  container_image   = "manon29/events-producer:latest"
  connection_string = module.module_event_hubs.send_connection_string

  # dockerhub_username = var.dockerhub_username
  # dockerhub_token    = var.dockerhub_token
}

module "data_factory" {
  name = "adf-e6-${var.username}"
  source              = "./modules/data_factory"
  depends_on          = [module.sql_database]
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sql_connection_string = var.sql_connection_string
}

module "api_sellers" {
  source     = "./modules/api_sellers"
  depends_on = [azurerm_resource_group.rg]

  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  container_image   = "manon29/api-sellers:latest"

  # dockerhub_username = var.dockerhub_username
  # dockerhub_token    = var.dockerhub_token
}