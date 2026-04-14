variable "project_id" {
  description = "GCP project ID where the MyApp infra will be created."
  type        = string
}

variable "region" {
  description = "GCP region for regional resources."
  type        = string
  default     = "europe-west1"
}

variable "zone" {
  description = "GCP zone for the three VMs."
  type        = string
  default     = "europe-west1-b"
}

variable "network_name" {
  description = "Name of the VPC network."
  type        = string
  default     = "myapp-vpc"
}

variable "subnetwork_name" {
  description = "Name of the VPC subnetwork."
  type        = string
  default     = "myapp-subnet"
}

variable "subnetwork_cidr" {
  description = "Primary CIDR of the private subnet."
  type        = string
  default     = "10.10.0.0/24"
}

variable "admin_source_ranges" {
  description = "CIDRs allowed to SSH to the public jumphost frontend-vm."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ssh_user" {
  description = "Linux username provisioned on the VMs."
  type        = string
  default     = "myapp"
}

variable "ssh_public_key" {
  description = "SSH public key content injected in instance metadata."
  type        = string
}

variable "image" {
  description = "Boot image for all VMs."
  type        = string
  default     = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
}

variable "backend_vm_machine_type" {
  description = "Machine type for backend-vm."
  type        = string
  default     = "e2-standard-2"
}

variable "frontend_vm_machine_type" {
  description = "Machine type for frontend-vm (2 vCPU / 8GB RAM)."
  type        = string
  default     = "e2-standard-2"
}

variable "backend2_machine_type" {
  description = "Machine type for backend2."
  type        = string
  default     = "e2-standard-2"
}

variable "backend_vm_disk_size_gb" {
  description = "Boot disk size for backend-vm."
  type        = number
  default     = 20
}

variable "frontend_vm_disk_size_gb" {
  description = "Boot disk size for frontend-vm."
  type        = number
  default     = 10
}

variable "backend2_disk_size_gb" {
  description = "Boot disk size for backend2."
  type        = number
  default     = 30
}

variable "boot_disk_type" {
  description = "Disk type for boot disks."
  type        = string
  default     = "pd-balanced"
}
