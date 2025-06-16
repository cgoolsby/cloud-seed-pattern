# Generate a random suffix for all secret names to avoid conflicts
resource "random_id" "secret_suffix" {
  byte_length = 4
}

# Local variable for the suffix
locals {
  secret_suffix = random_id.secret_suffix.hex
}