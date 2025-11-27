variable "username" {
  type = string
}

variable "subscription_id" {
  type = string
}

variable "location" {
  type = string
}

variable "eventhubs" {
  type = list(string)
}
variable "container_producers_image" {
  type = string
}

variable "sql_admin_login" {
  type = string
}

variable "sql_admin_password" {
  type      = string
  sensitive = true
}

# variable "dockerhub_username" {
#   type = string
# }

# variable "dockerhub_token" {
#   type = string
# }

variable "sql_connection_string" {
  type = string
}

variable "notification_email" {
  type        = string
  description = "Email address for notifications"
}
