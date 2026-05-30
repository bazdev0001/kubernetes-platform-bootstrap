# Example environment configuration.
# Copy to production.tfvars or staging.tfvars and fill in your values.
# These files are gitignored to prevent committing real infrastructure config.

cluster_name             = "my-cluster"
environment              = "production"
region                   = "us-east-1"
kubernetes_version       = "1.28"

vpc_cidr                 = "10.0.0.0/16"

node_group_instance_type = "t3.large"
node_group_min_size      = 3
node_group_max_size      = 15
node_group_desired_size  = 3

enable_cluster_autoscaler = true
enable_external_dns       = true

external_dns_hosted_zone_arns = [
  "arn:aws:route53:::hostedzone/REPLACE_WITH_ZONE_ID"
]

admin_iam_roles = [
  {
    rolearn  = "arn:aws:iam::123456789012:role/my-admin-role"
    username = "admin"
    groups   = ["system:masters"]
  }
]

tags = {
  Team        = "platform"
  CostCenter  = "engineering"
  Owner       = "barry-oyoung"
}
