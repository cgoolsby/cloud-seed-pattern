variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "fullStack-cluster"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "dev"
    Project     = "fullstack-Cluster"
    ManagedBy   = "terraform"
  }
}
