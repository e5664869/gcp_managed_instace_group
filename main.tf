locals {
  subnets  = ["group1", "group2"]
  subnets2 = ["public1", "public2"]
}
########################## VPC #######################################
resource "google_compute_network" "managed_instance_vpc" {
  name                            = var.mig_vpc_name
  delete_default_routes_on_create = false
  auto_create_subnetworks         = false
  routing_mode                    = "REGIONAL"
}
########################## Subnet #######################################
resource "google_compute_subnetwork" "managed_instance_vpc_subnet" {
  count                    = 2
  name                     = "${var.mig_subnet_name}-${local.subnets[count.index]}"
  ip_cidr_range            = var.mig_subnet_cidir_range[count.index]
  network                  = google_compute_network.managed_instance_vpc.id
  region                   = var.mig_subnet_region[count.index]
  private_ip_google_access = true
  depends_on               = [google_compute_network.managed_instance_vpc]
}
########################## Firewall #######################################
resource "google_compute_firewall" "mig_firewall" {
  name = var.firewall_name
  network = google_compute_network.managed_instance_vpc.id
  allow {
    protocol = "tcp"
    ports = ["80","8080","443"]
  }
  source_tags = ["web"]
}
resource "google_compute_firewall" "mig_firewall_health_check" {
  name = var.firewall_name2
  network = google_compute_network.managed_instance_vpc.id
  allow {
    protocol = "tcp"
    ports = ["80"]
  }
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  source_tags = ["health-check"]
}
########################## Instance Template #######################################
resource "google_compute_instance_template" "mig_template" {
  name= var.template_name
  project = var.gcp-project
  machine_type = var.template_machine_type
  labels = {
    env = "uat-version1"
  }
  metadata = var.template_metadata
  region = var.template_region
  can_ip_forward = false
  scheduling {
    automatic_restart = false
    preemptible = true
  }
  disk {
    source_image = "centos-cloud/centos-7"
    auto_delete  = true
    disk_size_gb = 20
    boot         = true
  }
  network_interface {
    network = google_compute_network.managed_instance_vpc.id
    subnetwork = "https://www.googleapis.com/compute/v1/projects/${var.gcp-project}/regions/us-east1/subnetworks/mig-subnet-group2"
    access_config {
      network_tier = "PREMIUM"
    }
  }
  depends_on = [ google_compute_network.managed_instance_vpc,google_compute_subnetwork.managed_instance_vpc_subnet ]
}
data "google_compute_image" "mig_image" {
  family  = "centos-7"
  project = "centos-cloud"
}
resource "google_compute_disk" "extra_disk" {
  name  = "extra-disk"
  image = data.google_compute_image.mig_image.self_link
  size  = 20
  type  = "pd-standard"
  zone  = "us-east1-b"
}
########################## Managed Instance Group #######################################
resource "google_compute_health_check" "mig_health" {
  name                = "autohealing-health-check"
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 10 # 50 seconds
  http_health_check {
    port = "80"
  }
}
resource "google_compute_region_instance_group_manager" "uat_server_group" {
  name = "uat-app-server"
  base_instance_name = "uat-app"
  region = var.template_region
  distribution_policy_zones = ["us-east1-b", "us-east1-c", "us-east1-d"]
version {
  instance_template = google_compute_instance_template.mig_template.self_link_unique
}
target_size = 4
auto_healing_policies {
  health_check = google_compute_health_check.mig_health.id
  initial_delay_sec = 300
}
}
########################## Load Balancer #######################################
resource "google_compute_backend_service" "uat_app_backend" {
    description                     = "mig-backend-service"
  project                         = var.gcp-project
  name                            = var.backend-svc-name
  protocol                        = var.backed-protocol
  timeout_sec                     = 30
  session_affinity                = "NONE"
  #enable_cdn                      = "true"
  load_balancing_scheme           = "EXTERNAL_MANAGED"
  locality_lb_policy              = "ROUND_ROBIN"
  connection_draining_timeout_sec = "300"
  health_checks = [google_compute_health_check.mig_health.id]
  backend {
        group           = google_compute_region_instance_group_manager.uat_server_group.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}
resource "google_compute_url_map" "mg_url_map" {
  name            = "mg-url-map"
  default_service = google_compute_backend_service.uat_app_backend.id
  depends_on = [ google_compute_backend_service.uat_app_backend]
}
resource "google_compute_target_http_proxy" "http_proxy" {
    #count   = var.enable_http ? 1 : 0
  project = var.gcp-project
  name    = "mg-target-proxy"
  url_map = google_compute_url_map.mg_url_map.id

  depends_on = [google_compute_url_map.mg_url_map]
}
resource "google_compute_global_forwarding_rule" "http" {
  project               = var.gcp-project
  name                  = "mg-http-rule"
  target                = google_compute_target_http_proxy.http_proxy.id
  port_range            = "80"
  ip_protocol           = "TCP"
  description           = "mig-frontend-service"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  depends_on = [ google_compute_target_http_proxy.http_proxy ]
  
}
