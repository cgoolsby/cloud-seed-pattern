variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "create_organization" {
  description = "Whether to create the AWS Organization (only needed for first run)"
  type        = bool
  default     = false
}

variable "accounts" {
  description = "Map of AWS accounts to create"
  type = map(object({
    name        = string
    email       = string
    environment = string
  }))
  default = {}
}