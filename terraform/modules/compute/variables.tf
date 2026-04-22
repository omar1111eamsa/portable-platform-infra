# ── Project ──────────────────────────────────────────────
variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "zone" {
  description = "GCP zone where VMs will be created"
  type        = string
}

# ── Network ───────────────────────────────────────────────
variable "vpc_name" {
  description = "Name of the VPC network to attach VMs to"
  type        = string
}

variable "subnet_name" {
  description = "Name of the subnet to attach VMs to"
  type        = string
}

# ── Compute ───────────────────────────────────────────────
variable "machine_type" {
  description = "GCP machine type for all nodes"
  type        = string
}

variable "disk_size_gb" {
  description = "Boot disk size in GB for all nodes"
  type        = number
}

variable "os_image" {
  description = "OS image for all VMs"
  type        = string
}

# ── Access ────────────────────────────────────────────────
variable "ssh_user" {
  description = "SSH username for all VMs"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key content for VM access"
  type        = string
  sensitive   = true
}

# ── Node IPs ──────────────────────────────────────────────
# Fixed internal IPs — critical for RKE2 cluster stability
# RKE2 nodes register with their IP, changing IPs breaks the cluster
variable "cp_01_ip" {
  description = "Fixed internal IP for myapp-cp-01"
  type        = string
  default     = "10.0.0.11"

  validation {
    condition     = can(cidrhost(format("%s/32", var.cp_01_ip), 0))
    error_message = "cp_01_ip must be a valid IP address."
  }
}

variable "worker_01_ip" {
  description = "Fixed internal IP for myapp-worker-01"
  type        = string
  default     = "10.0.0.12"

  validation {
    condition     = can(cidrhost(format("%s/32", var.worker_01_ip), 0))
    error_message = "worker_01_ip must be a valid IP address."
  }
}

variable "worker_02_ip" {
  description = "Fixed internal IP for myapp-worker-02"
  type        = string
  default     = "10.0.0.13"

  validation {
    condition     = can(cidrhost(format("%s/32", var.worker_02_ip), 0))
    error_message = "worker_02_ip must be a valid IP address."
  }
}