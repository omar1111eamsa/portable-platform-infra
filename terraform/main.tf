# ── Remote State Backend ──────────────────────────────────
# State stored in GCS bucket instead of locally
# Enables team collaboration and state locking
# Bucket must be created manually before first terraform init
# Create it with:
#   gsutil mb -p YOUR_PROJECT_ID gs://myapp-terraform-state
#   gsutil versioning set on gs://myapp-terraform-state
terraform {
  backend "gcs" {
    bucket = "myapp-terraform-state"
    prefix = "rke2/state"
  }
}

# ── Network Module ────────────────────────────────────────
module "network" {
  source = "./modules/network"

  project_id          = var.project_id
  region              = var.region
  vpc_name            = var.vpc_name
  subnet_name         = var.subnet_name
  subnet_cidr         = var.subnet_cidr
  admin_source_ranges = var.admin_source_ranges
}

# ── Compute Module ────────────────────────────────────────
# Receives network outputs directly — compute does not need
# to know how the network was built, only what came out of it
module "compute" {
  source = "./modules/compute"

  # Project
  project_id = var.project_id
  zone       = var.zone

  # Network — passed from network module outputs
  vpc_name    = module.network.vpc_name
  subnet_name = module.network.subnet_name

  # VM configuration
  machine_type = var.machine_type
  disk_size_gb = var.disk_size_gb
  os_image     = var.os_image

  # Access
  ssh_user       = var.ssh_user
  ssh_public_key = var.ssh_public_key

  # Fixed internal IPs
  cp_01_ip     = "10.0.0.11"
  worker_01_ip = "10.0.0.12"
  worker_02_ip = "10.0.0.13"
}