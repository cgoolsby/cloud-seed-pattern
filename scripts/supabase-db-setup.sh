#!/bin/bash
set -e

# Supabase Database Setup Script
# This script manually initializes the Supabase database with required roles and permissions
# Usage: ./scripts/supabase-db-setup.sh

echo "Starting Supabase database setup..."

# Wait for database pod to be ready
echo "Waiting for database pod to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=supabase,app.kubernetes.io/component=db -n supabase --timeout=300s

# Get the database pod name
DB_POD=$(kubectl get pods -n supabase -l app.kubernetes.io/name=supabase,app.kubernetes.io/component=db -o jsonpath='{.items[0].metadata.name}')

if [ -z "$DB_POD" ]; then
    echo "Error: Could not find database pod"
    exit 1
fi

echo "Found database pod: $DB_POD"

# Get the postgres password from the secret
POSTGRES_PASSWORD=$(kubectl get secret -n supabase supabase-db -o jsonpath='{.data.password}' | base64 -d)

if [ -z "$POSTGRES_PASSWORD" ]; then
    echo "Error: Could not retrieve postgres password from secret"
    exit 1
fi

echo "Creating required roles..."

# Create roles
kubectl exec -n supabase $DB_POD -- psql -U postgres -d postgres <<EOF
-- Create required roles
CREATE ROLE IF NOT EXISTS anon NOLOGIN NOINHERIT;
CREATE ROLE IF NOT EXISTS authenticated NOLOGIN NOINHERIT;
CREATE ROLE IF NOT EXISTS service_role NOLOGIN NOINHERIT BYPASSRLS;
CREATE ROLE IF NOT EXISTS supabase_auth_admin LOGIN NOINHERIT;
CREATE ROLE IF NOT EXISTS supabase_storage_admin LOGIN NOINHERIT;
CREATE ROLE IF NOT EXISTS authenticator NOINHERIT LOGIN;

-- Set passwords for roles
ALTER ROLE authenticator WITH PASSWORD '$POSTGRES_PASSWORD';
ALTER ROLE supabase_auth_admin WITH PASSWORD '$POSTGRES_PASSWORD';
ALTER ROLE supabase_storage_admin WITH PASSWORD '$POSTGRES_PASSWORD';
ALTER ROLE postgres WITH PASSWORD '$POSTGRES_PASSWORD';

-- Grant permissions to authenticator
GRANT anon TO authenticator;
GRANT authenticated TO authenticator;
GRANT service_role TO authenticator;
GRANT supabase_auth_admin TO authenticator;
GRANT supabase_storage_admin TO authenticator;

-- Grant admin permissions to supabase_admin
GRANT supabase_auth_admin TO supabase_admin;
GRANT supabase_storage_admin TO supabase_admin;

-- Create schemas
CREATE SCHEMA IF NOT EXISTS auth AUTHORIZATION supabase_auth_admin;
CREATE SCHEMA IF NOT EXISTS storage AUTHORIZATION supabase_storage_admin;
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE SCHEMA IF NOT EXISTS _realtime;

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgjwt WITH SCHEMA extensions;

-- Grant schema permissions
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA extensions TO anon, authenticated, service_role;

-- Grant permissions on all tables in public schema
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO service_role;

-- Grant permissions on all sequences in public schema
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE ON SEQUENCES TO anon, authenticated, service_role;

-- Grant permissions on all functions in public schema
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;

-- Set up auth schema permissions
GRANT USAGE ON SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON ALL TABLES IN SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA auth TO supabase_auth_admin;

-- Set up storage schema permissions
GRANT USAGE ON SCHEMA storage TO supabase_storage_admin;
GRANT ALL ON ALL TABLES IN SCHEMA storage TO supabase_storage_admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA storage TO supabase_storage_admin;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA storage TO supabase_storage_admin;

-- Allow authenticated users to access storage
GRANT USAGE ON SCHEMA storage TO authenticated;

-- Grant permissions on _realtime schema
GRANT ALL ON SCHEMA _realtime TO supabase_admin;

-- Grant database permissions for storage admin
GRANT ALL PRIVILEGES ON DATABASE postgres TO supabase_storage_admin;

-- Set search path to include extensions
ALTER DATABASE postgres SET search_path TO "\$user", public, extensions;

-- Create realtime publication for all tables
CREATE PUBLICATION supabase_realtime FOR ALL TABLES;

-- Ensure postgres user has necessary permissions
GRANT ALL PRIVILEGES ON DATABASE postgres TO postgres;
GRANT ALL PRIVILEGES ON SCHEMA public TO postgres;
GRANT ALL PRIVILEGES ON SCHEMA auth TO postgres;
GRANT ALL PRIVILEGES ON SCHEMA storage TO postgres;
GRANT ALL PRIVILEGES ON SCHEMA extensions TO postgres;
EOF

echo "Database setup completed successfully!"

# Restart dependent services to pick up new configuration
echo "Restarting Supabase services..."
kubectl rollout restart deployment -n supabase supabase-supabase-auth
kubectl rollout restart deployment -n supabase supabase-supabase-storage
kubectl rollout restart deployment -n supabase supabase-supabase-realtime
kubectl rollout restart deployment -n supabase supabase-supabase-rest

echo "Waiting for services to be ready..."
kubectl wait --for=condition=available deployment -l app.kubernetes.io/name=supabase -n supabase --timeout=300s

echo "Supabase setup complete!"