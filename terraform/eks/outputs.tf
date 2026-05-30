output "cluster_id" {
  description = "EKS cluster ID."
  value       = module.eks.cluster_id
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint URL for the EKS Kubernetes API server."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate data for the cluster CA. Used by kubectl and Helm."
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the cluster. Used to create IRSA roles."
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider for the cluster. Used when creating IRSA roles outside this module."
  value       = module.eks.oidc_provider_arn
}

output "vpc_id" {
  description = "VPC ID where the cluster is deployed."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs. Worker nodes are deployed in these subnets."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "List of public subnet IDs. Public load balancers are provisioned in these subnets."
  value       = module.vpc.public_subnets
}

output "cluster_autoscaler_role_arn" {
  description = "IAM role ARN for the Cluster Autoscaler. Annotate the kube-system:cluster-autoscaler service account with this."
  value       = var.enable_cluster_autoscaler ? module.cluster_autoscaler_irsa[0].iam_role_arn : null
}

output "external_dns_role_arn" {
  description = "IAM role ARN for ExternalDNS. Annotate the external-dns:external-dns service account with this."
  value       = var.enable_external_dns ? module.external_dns_irsa[0].iam_role_arn : null
}

output "ebs_csi_driver_role_arn" {
  description = "IAM role ARN for the EBS CSI driver."
  value       = module.ebs_csi_irsa.iam_role_arn
}

output "kubeconfig_command" {
  description = "Command to update your local kubeconfig to point at this cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name}"
}
