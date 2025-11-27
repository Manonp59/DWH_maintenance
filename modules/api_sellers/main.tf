
resource "azurerm_container_group" "api_sellers" {
  name                = var.containers_group_name
  location            = var.location
  resource_group_name = var.resource_group_name

  os_type         = "Linux"
  restart_policy  = "Always"
  ip_address_type = "Public"
  dns_name_label = "${var.container_name}"

  container {
    name   = var.container_name
    image  = var.container_image
    cpu    = var.cpu
    memory = var.memory
    ports {
      port     = 8080
      protocol = "TCP"
    }

  }
  # image_registry_credential {
  #   server   = "index.docker.io"
  #   username = var.dockerhub_username
  #   password = var.dockerhub_token
  # }
}
