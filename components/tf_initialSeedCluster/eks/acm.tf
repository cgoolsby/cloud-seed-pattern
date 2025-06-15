# Variables for domain configuration
variable "domain_name" {
  description = "Domain name for Supabase (e.g., example.com)"
  type        = string
  default     = "example.com"  # Update this with your actual domain
}

# Create ACM certificate for ALB
resource "aws_acm_certificate" "supabase" {
  domain_name       = "supabase.${var.domain_name}"
  validation_method = "DNS"

  subject_alternative_names = [
    "*.supabase.${var.domain_name}"
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# Output certificate ARN
output "acm_certificate_arn" {
  description = "ARN of the ACM certificate for Supabase"
  value       = aws_acm_certificate.supabase.arn
}