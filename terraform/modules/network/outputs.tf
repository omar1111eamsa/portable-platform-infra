output "vpc_name" {
  description = "Name of the created VPC network"
  value       = google_compute_network.vpc.name
}

output "vpc_self_link" {
  description = "Self link of the created VPC network"
  value       = google_compute_network.vpc.self_link
}

output "subnet_name" {
  description = "Name of the created subnet"
  value       = google_compute_subnetwork.subnet.name
}

output "subnet_self_link" {
  description = "Self link of the created subnet"
  value       = google_compute_subnetwork.subnet.self_link
}

output "subnet_cidr" {
  description = "CIDR range of the created subnet"
  value       = google_compute_subnetwork.subnet.ip_cidr_range
}