-- Creates the non-root user and grants required privileges.
-- Executed automatically by the PostgreSQL entrypoint on first init.

\set ON_ERROR_STOP on

\getenv non_root_user POSTGRES_NON_ROOT_USER
\getenv non_root_password POSTGRES_NON_ROOT_PASSWORD
\getenv db POSTGRES_DB

SELECT format(
  'CREATE USER %I WITH PASSWORD %L',
  :'non_root_user',
  :'non_root_password'
) \gexec

SELECT format(
  'GRANT ALL PRIVILEGES ON DATABASE %I TO %I',
  :'db',
  :'non_root_user'
) \gexec

SELECT format(
  'GRANT CREATE ON SCHEMA public TO %I',
  :'non_root_user'
) \gexec
