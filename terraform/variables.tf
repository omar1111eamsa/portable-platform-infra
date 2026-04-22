# terraform/variables.tf

# ── Project ──────────────────────────────────────────────
variable "project_id" {
  description = "GCP project ID"
  type        = string

  validation {
    condition     = length(var.project_id) > 0
    error_message = "project_id cannot be empty."
  }
}

variable "region" {
  description = "GCP region where resources will be created"
  type        = string
  default     = "europe-west1"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "region must be a valid GCP region format e.g. europe-west1."
  }
}

variable "zone" {
  description = "GCP zone where VMs will be created"
  type        = string
  default     = "europe-west1-b"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]-[a-z]$", var.zone))
    error_message = "zone must be a valid GCP zone format e.g. europe-west1-b."
  }
}

# ── Network ───────────────────────────────────────────────
variable "vpc_name" {
  description = "Name of the VPC network"
  type        = string
  default     = "myapp-vpc"
}

variable "subnet_name" {
  description = "Name of the subnet"
  type        = string
  default     = "myapp-subnet"
}

variable "subnet_cidr" {
  description = "CIDR range for the subnet"
  type        = string
  default     = "10.10.0.0/24"

  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "subnet_cidr must be a valid CIDR block."
  }
}

variable "admin_source_ranges" {
  description = "List of CIDR ranges allowed to SSH into the cluster"
  type        = list(string)

  validation {
    condition     = length(var.admin_source_ranges) > 0
    error_message = "At least one admin source range must be provided."
  }
}

# ── Compute ───────────────────────────────────────────────
variable "ssh_user" {
  description = "SSH username for all VMs"
  type        = string
  default     = "myapp"
}

variable "ssh_public_key" {
  description = "SSH public key content for VM access"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.ssh_public_key) > 0
    error_message = "ssh_public_key cannot be empty."
  }
}

variable "machine_type" {
  description = "GCP machine type for all nodes"
  type        = string
  default     = "e2-custom-2-8192"
}

variable "disk_size_gb" {
  description = "Boot disk size in GB for all nodes"
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size_gb >= 20
    error_message = "disk_size_gb must be at least 20 GB."
  }
}

variable "os_image" {
  description = "OS image for all VMs"
  type        = string
  default     = "ubuntu-os-cloud/ubuntu-2204-lts"
}