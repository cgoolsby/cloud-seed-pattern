# Generate secure random values for Supabase secrets
resource "random_password" "supabase_jwt_secret" {
  length  = 64
  special = true
}

resource "random_password" "supabase_db_password" {
  length  = 32
  special = true
}

resource "random_password" "supabase_anon_key" {
  length  = 64
  special = false
}

resource "random_password" "supabase_service_key" {
  length  = 64
  special = false
}

resource "random_password" "supabase_dashboard_password" {
  length  = 20
  special = true
}

# Create Supabase JWT secrets
resource "aws_secretsmanager_secret" "supabase_jwt" {
  name = "supabase/jwt-secrets-${local.secret_suffix}"
  description = "Supabase JWT secrets for authentication"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "supabase_jwt" {
  secret_id = aws_secretsmanager_secret.supabase_jwt.id
  secret_string = jsonencode({
    jwt_secret     = random_password.supabase_jwt_secret.result
    anon_key       = random_password.supabase_anon_key.result
    service_key    = random_password.supabase_service_key.result
  })
}

# Create Supabase database credentials
resource "aws_secretsmanager_secret" "supabase_db" {
  name = "supabase/database-credentials-${local.secret_suffix}"
  description = "Supabase PostgreSQL database credentials"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "supabase_db" {
  secret_id = aws_secretsmanager_secret.supabase_db.id
  secret_string = jsonencode({
    username = "supabase_admin"
    password = random_password.supabase_db_password.result
    password_encoded = urlencode(random_password.supabase_db_password.result)
    host     = "supabase-db.supabase.svc.cluster.local"
    port     = "5432"
    database = "postgres"
  })
}

# Create Supabase SMTP credentials (placeholder - update with real SMTP)
resource "aws_secretsmanager_secret" "supabase_smtp" {
  name = "supabase/smtp-credentials-${local.secret_suffix}"
  description = "Supabase SMTP credentials for email services"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "supabase_smtp" {
  secret_id = aws_secretsmanager_secret.supabase_smtp.id
  secret_string = jsonencode({
    smtp_host     = "smtp.example.com"
    smtp_port     = "587"
    smtp_user     = "noreply@example.com"
    smtp_password = "placeholder-update-with-real-smtp"
    smtp_from     = "noreply@example.com"
  })
}

# Create Supabase Studio dashboard credentials
resource "aws_secretsmanager_secret" "supabase_dashboard" {
  name = "supabase/dashboard-credentials-${local.secret_suffix}"
  description = "Supabase Studio dashboard authentication"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "supabase_dashboard" {
  secret_id = aws_secretsmanager_secret.supabase_dashboard.id
  secret_string = jsonencode({
    username = "supabase"
    password = random_password.supabase_dashboard_password.result
  })
}

# Output the secret ARNs
output "supabase_jwt_secret_arn" {
  description = "ARN of Supabase JWT secrets"
  value       = aws_secretsmanager_secret.supabase_jwt.arn
}

output "supabase_db_secret_arn" {
  description = "ARN of Supabase database credentials"
  value       = aws_secretsmanager_secret.supabase_db.arn
}

output "supabase_smtp_secret_arn" {
  description = "ARN of Supabase SMTP credentials"
  value       = aws_secretsmanager_secret.supabase_smtp.arn
}

output "supabase_dashboard_secret_arn" {
  description = "ARN of Supabase dashboard credentials"
  value       = aws_secretsmanager_secret.supabase_dashboard.arn
}

# Output the secret names for External Secrets
output "supabase_jwt_secret_name" {
  description = "Name of Supabase JWT secrets"
  value       = aws_secretsmanager_secret.supabase_jwt.name
}

output "supabase_db_secret_name" {
  description = "Name of Supabase database credentials"
  value       = aws_secretsmanager_secret.supabase_db.name
}

output "supabase_smtp_secret_name" {
  description = "Name of Supabase SMTP credentials"
  value       = aws_secretsmanager_secret.supabase_smtp.name
}

output "supabase_dashboard_secret_name" {
  description = "Name of Supabase dashboard credentials"
  value       = aws_secretsmanager_secret.supabase_dashboard.name
}