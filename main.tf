resource "google_compute_network" "module_test_vpc" {
  name                            = var.mig_vpc_name
  delete_default_routes_on_create = false
  auto_create_subnetworks         = false
  routing_mode                    = "REGIONAL"
}
