variable "mig_vpc_name" {
  type = string
}
variable "mig_subnet_name" {
  type = string
}
variable "mig_subnet_region" {
  type = list(string)
}
variable "mig_subnet_cidir_range" {
  type = list(string)
}
variable "firewall_name" {
  type = string
}
variable "firewall_name2" {
  type = string
}
################################## Instance Template ##############
variable "template_name" {
  type = string
}
variable "template_region" {
  type = string
}
variable "template_machine_type" {
  type = string
}
variable "template_label" {
  type = string
}
variable "template_metadata" {
  type = map
}
################################## Load Balancer ##############
variable "backend-svc-name" {
  type = string
}
variable "backed-protocol" {
  type = string
}
