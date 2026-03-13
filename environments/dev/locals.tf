# environments/dev/locals.tf
# locals block for tag inheritance 
# so no resource ever gets deployed without cost allocation and env metadata

locals {
  common_tags = {
    Project     = var.cluster_name
    Environment = "dev"
    ManagedBy   = "terraform"
    Repo        = "crystal-node"
  }
}
