# Create a test secret in AWS Secrets Manager
resource "aws_secretsmanager_secret" "test_secret" {
  name = "test/demo-secret"
  description = "Test secret for External Secrets Operator"
  
  # Prevent accidental deletion
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "test_secret" {
  secret_id = aws_secretsmanager_secret.test_secret.id
  secret_string = jsonencode({
    username = "demo-user"
    password = "demo-password-${random_string.secret_suffix.result}"
    api_key  = "demo-api-key-${random_string.secret_suffix.result}"
  })
}

# Generate random suffix for demo passwords
resource "random_string" "secret_suffix" {
  length  = 16
  special = true
}

# Output the secret ARN for reference
output "test_secret_arn" {
  description = "ARN of the test secret"
  value       = aws_secretsmanager_secret.test_secret.arn
}