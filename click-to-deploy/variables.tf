# ============================================================================
# Mandatory go/demos Click-to-Deploy (C2D) Platform-Injected Variables (8)
# ============================================================================

variable "project_id" {
  type        = string
  description = "The GCP Project ID where the Summit Trail AlloyDB demo resources will be deployed."
}

variable "project_name" {
  type        = string
  description = "The human-readable GCP Project Name."
  default     = ""
}

variable "project_number" {
  type        = string
  description = "The numeric GCP Project Number."
  default     = ""
}

variable "org_id" {
  type        = string
  description = "The GCP Organization ID."
  default     = ""
}

variable "gcp_account_name" {
  type        = string
  description = "The user account email triggering the Click-to-Deploy run."
  default     = ""
}

variable "deployment_service_account_name" {
  type        = string
  description = "The service account used by the Demo Automation Platform to execute Terraform."
  default     = ""
}

variable "data_location" {
  type        = string
  description = "Default Google Cloud region for AlloyDB and networking resources (asia-southeast1 supports both Express and Agent Mode in-place upgrade)."
  default     = "asia-southeast1"
}

variable "secret_stored_project" {
  type        = string
  description = "The GCP project ID where dynamically generated demo secrets are stored."
  default     = ""
}

# ============================================================================
# Demo-Specific Variables
# ============================================================================

variable "cluster_id" {
  type        = string
  description = "AlloyDB cluster identifier."
  default     = "summit-trail-cluster"
}

variable "primary_id" {
  type        = string
  description = "AlloyDB primary instance identifier."
  default     = "summit-trail-primary"
}

variable "pool_id" {
  type        = string
  description = "AlloyDB Agent Pool identifier."
  default     = "summit-trail-agent-pool"
}
