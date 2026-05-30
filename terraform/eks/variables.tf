variable "cluster_name" {
  description = "Name of the EKS cluster. Used as a prefix for all associated AWS resources."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.cluster_name))
    error_message = "cluster_name must be lowercase alphanumeric with hyphens only."
  }
}

variable "environment" {
  description = "Deployment environment (e.g. staging, production). Used for tagging and single-NAT-gateway optimization."
  type        = string
  default     = "production"

  validation {
    condition     = contains(["staging", "production", "development"], var.environment)
    error_message = "environment must be one of: staging, production, development."
  }
}

variable "region" {
  description = "AWS region to deploy the cluster into."
  type        = string
  default     = "us-east-1"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS control plane. Must be a version supported by AWS EKS."
  type        = string
  default     = "1.28"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Should be a /16 to allow enough subnets across AZs."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

variable "node_group_instance_type" {
  description = "EC2 instance type for worker nodes. Use at least t3.medium for production workloads."
  type        = string
  default     = "t3.medium"
}

variable "node_group_min_size" {
  description = "Minimum number of worker nodes in the autoscaling group."
  type        = number
  default     = 2

  validation {
    condition     = var.node_group_min_size >= 1
    error_message = "node_group_min_size must be at least 1."
  }
}

variable "node_group_max_size" {
  description = "Maximum number of worker nodes. The cluster autoscaler will not scale beyond this."
  type        = number
  default     = 10

  validation {
    condition     = var.node_group_max_size >= var.node_group_min_size
    error_message = "node_group_max_size must be >= node_group_min_size."
  }
}

variable "node_group_desired_size" {
  description = "Initial desired number of worker nodes."
  type        = number
  default     = 3
}

variable "enable_cluster_autoscaler" {
  description = "Create IRSA role and IAM policy for the Kubernetes Cluster Autoscaler."
  type        = bool
  default     = true
}

variable "enable_external_dns" {
  description = "Create IRSA role and IAM policy for ExternalDNS to manage Route 53 records."
  type        = bool
  default     = true
}

variable "external_dns_hosted_zone_arns" {
  description = "List of Route 53 hosted zone ARNs that ExternalDNS is permitted to manage."
  type        = list(string)
  default     = []
}

variable "admin_iam_roles" {
  description = "List of IAM role ARNs that should be granted cluster-admin access via aws-auth."
  type = list(object({
    rolearn  = string
    username = string
    groups   = list(string)
  }))
  default = []
}

variable "tags" {
  description = "Additional resource tags to apply to all AWS resources created by this module."
  type        = map(string)
  default     = {}
}
