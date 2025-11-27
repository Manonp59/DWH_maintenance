variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "container_image" {
  type = string
}

variable "containers_group_name" {
  type    = string
  default = "api-sellers"
}

variable "container_name" {
  type    = string
  default = "api-sellers"
}

variable "cpu" {
  type    = number
  default = 0.5
}

variable "memory" {
  type    = number
  default = 1.0
}