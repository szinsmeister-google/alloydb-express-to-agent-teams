terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 6.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.data_location
}

provider "google-beta" {
  project = var.project_id
  region  = var.data_location
}

locals {
  secret_project = var.secret_stored_project != "" ? var.secret_stored_project : var.project_id
  required_apis = toset([
    "alloydb.googleapis.com",
    "compute.googleapis.com",
    "servicenetworking.googleapis.com",
    "networkconnectivity.googleapis.com",
    "aiplatform.googleapis.com",
    "dataplex.googleapis.com",
    "monitoring.googleapis.com",
    "dns.googleapis.com",
    "secretmanager.googleapis.com",
  ])
  agent_roles = toset([
    "roles/aiplatform.user",
    "roles/alloydb.databaseUser",
    "roles/alloydb.client",
    "roles/mcp.toolUser",
    "roles/serviceusage.serviceUsageConsumer",
    "roles/logging.logWriter",
  ])
}

# 1. Enable Required Google Cloud APIs
resource "google_project_service" "apis" {
  for_each           = local.required_apis
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# 2. Dynamic Initial PostgreSQL Password Stored in Secret Manager (No Hardcoded Secrets)
resource "random_password" "db_password" {
  length           = 20
  special          = true
  override_special = "!@#%^&*()-_=+"
}

resource "google_secret_manager_secret" "db_password" {
  project   = local.secret_project
  secret_id = "${var.cluster_id}-postgres-password"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "db_password_version" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

# 3. Dedicated VPC, Subnet, and PSC Service Connection Policy for AlloyDB Agent Mode
resource "google_compute_network" "agents_vpc" {
  project                 = var.project_id
  name                    = "agents-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.apis]
}

resource "google_compute_subnetwork" "agents_subnet" {
  project       = var.project_id
  name          = "agents-subnet"
  region        = var.data_location
  network       = google_compute_network.agents_vpc.id
  ip_cidr_range = "10.20.0.0/24"
}

resource "google_network_connectivity_service_connection_policy" "alloydb_agents_policy" {
  project       = var.project_id
  name          = "alloydb-agents-policy"
  location      = var.data_location
  service_class = "google-cloud-alloydb"
  network       = google_compute_network.agents_vpc.id
  psc_config {
    subnetworks = [google_compute_subnetwork.agents_subnet.id]
    limit       = 10
  }
  depends_on = [google_project_service.apis]
}

# 4. Dedicated Least-Privilege IAM Service Accounts for 2x2 Database Isolation
resource "google_service_account" "warehouse_agent" {
  project      = var.project_id
  account_id   = "warehouse-agent"
  display_name = "Summit Trail Warehouse Operations Agent"
  depends_on   = [google_project_service.apis]
}

resource "google_service_account" "finance_agent" {
  project      = var.project_id
  account_id   = "finance-agent"
  display_name = "Summit Trail Vendor Finance Agent"
  depends_on   = [google_project_service.apis]
}

resource "google_project_iam_member" "warehouse_agent_roles" {
  for_each = local.agent_roles
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.warehouse_agent.email}"
}

resource "google_project_iam_member" "finance_agent_roles" {
  for_each = local.agent_roles
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.finance_agent.email}"
}

# Optional: Grant deploying user impersonation permission for live 2x2 verification
resource "google_service_account_iam_member" "warehouse_token_creator" {
  count              = var.gcp_account_name != "" ? 1 : 0
  service_account_id = google_service_account.warehouse_agent.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "user:${var.gcp_account_name}"
}

resource "google_service_account_iam_member" "finance_token_creator" {
  count              = var.gcp_account_name != "" ? 1 : 0
  service_account_id = google_service_account.finance_agent.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "user:${var.gcp_account_name}"
}
