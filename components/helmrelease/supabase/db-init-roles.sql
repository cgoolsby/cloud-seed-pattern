-- Supabase Database Initialization Script - Roles Only
-- This script creates the required roles for Supabase

-- Create required roles
CREATE ROLE IF NOT EXISTS anon NOLOGIN NOINHERIT;
CREATE ROLE IF NOT EXISTS authenticated NOLOGIN NOINHERIT;
CREATE ROLE IF NOT EXISTS service_role NOLOGIN NOINHERIT BYPASSRLS;
CREATE ROLE IF NOT EXISTS supabase_auth_admin LOGIN NOINHERIT;
CREATE ROLE IF NOT EXISTS supabase_storage_admin LOGIN NOINHERIT;
CREATE ROLE IF NOT EXISTS postgres SUPERUSER LOGIN;
CREATE ROLE IF NOT EXISTS authenticator NOINHERIT LOGIN;

-- Note: Passwords will be set by the Helm chart