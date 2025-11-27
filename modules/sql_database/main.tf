resource "azurerm_mssql_server" "sql_server" {
  name                         = "sql-server-${lower(replace(var.resource_group_name, "_", "-"))}"
  resource_group_name          = var.resource_group_name
  location                     = var.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_login
  administrator_login_password = var.sql_admin_password
}

resource "azurerm_mssql_database" "dwh" {
  name           = "dwh-shopnow"
  server_id      = azurerm_mssql_server.sql_server.id
  collation      = "SQL_Latin1_General_CP1_CI_AS"
  license_type   = "LicenseIncluded"
  max_size_gb    = 2
  sku_name       = "S0"
  zone_redundant = false
  short_term_retention_policy {
    retention_days = 14
    backup_interval_in_hours = 24
  }
}

resource "azurerm_mssql_firewall_rule" "allow_azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.sql_server.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_mssql_firewall_rule" "allow_local_ip" {
  name             = "AllowLocalIP"
  server_id        = azurerm_mssql_server.sql_server.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "255.255.255.255"
}

# // ============================================================================
# // Azure Container Instance pour l'initialisation du schéma de la base de données
# // ============================================================================
# // 
# // Azure SQL Database ne permet PAS d'injecter un schéma SQL directement lors
# // de sa création via Terraform. Cette ressource crée un conteneur temporaire
# // dans Azure qui exécute le script SQL d'initialisation.
# //
# // FONCTIONNEMENT :
# // ----------------
# // 1. Terraform crée le SQL Server et la base de données
# // 2. Terraform crée cette Container Instance dans Azure
# // 3. Le conteneur démarre et exécute les commandes suivantes :
# //    a) Charge le contenu de dwh_schema.sql dans /tmp/schema.sql
# //    b) Utilise sqlcmd pour se connecter à la base de données
# //    c) Exécute le script SQL pour créer les tables
# // 4. Le conteneur se termine automatiquement (restart_policy = "Never")
# // 5. Azure garde le conteneur en état "Terminated" pour consultation des logs
# //
# // ============================================================================

resource "azurerm_container_group" "db_setup" {
  # Attend que la base de données et la règle firewall soient créées
  depends_on = [azurerm_mssql_database.dwh, azurerm_mssql_firewall_rule.allow_azure_services]

  name                = "db-setup-${var.username}"
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  restart_policy      = "Never" # Le conteneur s'exécute une seule fois puis s'arrête

  container {
    name   = "sqlcmd"
    image  = "mcr.microsoft.com/mssql-tools" # Image officielle Microsoft avec sqlcmd
    cpu    = "0.5"                           # 0.5 CPU core (suffisant pour un script SQL)
    memory = "1.0"                           # 1 GB de RAM

    # Azure Container Instance nécessite au moins un port exposé (même si non utilisé)
    ports {
      port     = 80
      protocol = "TCP"
    }

    # Commandes exécutées dans le conteneur
    commands = [
      "/bin/bash",
      "-c",
      <<-EOT
        # Écrit le contenu du fichier SQL dans le conteneur
        echo '${file(var.schema_file_path)}' > /tmp/schema.sql
        
        # Exécute le script SQL sur la base de données Azure SQL
        /opt/mssql-tools/bin/sqlcmd \
          -S ${azurerm_mssql_server.sql_server.fully_qualified_domain_name} \
          -U ${var.sql_admin_login} \
          -P '${var.sql_admin_password}' \
          -d ${azurerm_mssql_database.dwh.name} \
          -i /tmp/schema.sql
      EOT
    ]
  }
}

resource "azurerm_log_analytics_workspace" "current" {
  name                = "log-analytics-e6-${var.username}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_monitor_diagnostic_setting" "current" {
  name                       = "${var.username}-DS"
  target_resource_id         = "${azurerm_mssql_database.dwh.id}"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.current.id

  enabled_log {
    category = "SQLSecurityAuditEvents"
  }
  enabled_log {
    category = "Errors"
  }
  enabled_log {
    category = "DatabaseWaitStatistics"
  }
  metric {
    category = "AllMetrics"
  }

  lifecycle {
    ignore_changes = [enabled_log, metric]
  }
}

resource "azurerm_mssql_database_extended_auditing_policy" "current" {
  database_id            = "${azurerm_mssql_database.dwh.id}"
  log_monitoring_enabled = true
}

resource "azurerm_monitor_action_group" "email_notifications" {
  name                = "email-alerts"
  resource_group_name = var.resource_group_name
  short_name          = "email-alerts"

  email_receiver {
    name          = "DBAdmin"
    email_address = var.notification_email
    use_common_alert_schema = true
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert" "sql_cpu_alert" {
  name                = "sql-cpu-alert-${var.username}"
  resource_group_name = var.resource_group_name
  location            = var.location
  description         = "Alert when SQL Database CPU usage exceeds 90% for 5 minutes"

  data_source_id     = azurerm_log_analytics_workspace.current.id
  frequency           = 10
  time_window         = 10
  query = <<-KQL
      AzureMetrics
      | where Resource contains "DWH-SHOPNOW"
      | where MetricName == "cpu_percent"
      | where TimeGenerated > ago(5m)
      | summarize MaxCPU = max(Average)
      | where MaxCPU > 90
  KQL

  severity            = 2
  trigger {
    operator  = "GreaterThanOrEqual"
    threshold = 1
  }

  action {
    action_group = [azurerm_monitor_action_group.email_notifications.id]
    email_subject   = "ALERT: SQL Database CPU Usage High"
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert" "sql_failed_connections_alert" {
  name                = "sql-failed-connections-alert-${var.username}"
  resource_group_name = var.resource_group_name
  location            = var.location
  description         = "Alert if SQL DB has more than 10 failed connections in 1 hour"
  data_source_id      = azurerm_log_analytics_workspace.current.id
  frequency           = 60    # PT1H = 60 minutes
  time_window         = 60    # PT1H = 60 minutes

  query = <<-KQL
    AzureDiagnostics
    | where action_name_s == "DATABASE AUTHENTICATION FAILED" and TimeGenerated >= ago(1h)
    | summarize AggregatedValue = count() by bin(TimeGenerated, 1h)
  KQL

  severity            = 2

  trigger {
    metric_trigger {
      metric_trigger_type = "Total"
      operator = "GreaterThanOrEqual"
      threshold = 10
      metric_column = "DatabaseAuthenticationFailed"
    }
    operator  = "GreaterThanOrEqual"
    threshold = 10
  }

  action {
    action_group  = [azurerm_monitor_action_group.email_notifications.id]
    email_subject = "ALERT: 10 FAILED CONNECTIONS TO SHOPNOW DB IN 1H"
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert" "sql_storage_alert" {
  name                = "sql-storage-alert-${var.username}"
  resource_group_name = var.resource_group_name
  location            = var.location
  description         = "Alert if SQL DB has storage usage > 95% for 15 minutes"
  data_source_id      = azurerm_log_analytics_workspace.current.id
  frequency           = 15    # PT15M = 15 minutes
  time_window         = 15    # PT15M = 15 minutes

  query = <<-KQL
    AzureMetrics
    | where Resource contains "DWH-SHOPNOW"
    | where MetricName == "storage_percent"
    | where TimeGenerated > ago(15m)
    | summarize MaxStorage = max(Average)
    | where MaxStorage > 95
  KQL

  severity            = 1

  trigger {
    operator  = "GreaterThan"
    threshold = 1
  }

  action {
    action_group  = [azurerm_monitor_action_group.email_notifications.id]
    email_subject = "ALERT: STORAGE PERCENT DB SHOPNOW > 95%"
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert" "sql_table_dropped_alert" {
  name                = "sql-table-dropped-alert-${var.username}"
  resource_group_name = var.resource_group_name
  location            = var.location
  description         = "Alert when a table is dropped from SHOPNOW DB"
  data_source_id      = azurerm_log_analytics_workspace.current.id
  frequency           = 15    # PT15M = 15 minutes
  time_window         = 15    # PT15M = 15 minutes

  query = <<-KQL
    AzureDiagnostics
    | where action_name_s == "BATCH COMPLETED"
    | where statement_s startswith "DROP TABLE"
  KQL

  severity            = 2

  trigger {
    operator  = "GreaterThanOrEqual"
    threshold = 1
  }

  action {
    action_group  = [azurerm_monitor_action_group.email_notifications.id]
    email_subject = "ALERT: A TABLE HAS BEEN DROPPED FROM SHOPNOW DB"
  }
}