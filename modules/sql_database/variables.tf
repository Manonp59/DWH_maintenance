variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "sql_admin_login" {
  type = string
}

variable "sql_admin_password" {
  type = string
}

variable "schema_file_path" {
  type        = string
  description = "Path to the SQL schema file"
}

variable "username" {
  type = string
}

variable "notification_email" {
  type        = string
  description = "Email address for notifications"
}