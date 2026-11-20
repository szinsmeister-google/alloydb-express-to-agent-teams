output "project_id" {
  description = "Target Google Cloud Project ID"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region for AlloyDB and networking"
  value       = var.data_location
}

output "agents_vpc_id" {
  description = "VPC network configured with Private Service Connect policy for AlloyDB Agent Mode"
  value       = google_compute_network.agents_vpc.id
}

output "psc_service_connection_policy" {
  description = "PSC Service Connection Policy for google-cloud-alloydb"
  value       = google_network_connectivity_service_connection_policy.alloydb_agents_policy.id
}

output "warehouse_agent_sa" {
  description = "IAM Service Account for Priya's Warehouse Operations Agent (inventory_db only)"
  value       = google_service_account.warehouse_agent.email
}

output "finance_agent_sa" {
  description = "IAM Service Account for Diego's Vendor Finance Agent (finance_db only)"
  value       = google_service_account.finance_agent.email
}

output "db_password_secret" {
  description = "Secret Manager resource holding the dynamically generated initial postgres password"
  value       = google_secret_manager_secret.db_password.id
}

output "next_step_command" {
  description = "Run this command to spin up AlloyDB Express (<2s), seed inventory_db & finance_db, and configure the 2x2 privilege matrix"
  value       = "PROJECT_ID=${var.project_id} REGION=${var.data_location} ./scripts/setup_express_and_seed.sh"
}
