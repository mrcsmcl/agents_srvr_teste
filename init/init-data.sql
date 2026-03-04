-- Creates the non-root user and grants required privileges.
-- Executed automatically by the PostgreSQL entrypoint on first init.
-- Uses \getenv to read container environment variables (requires psql 9.3+).

\getenv non_root_user POSTGRES_NON_ROOT_USER
\getenv non_root_password POSTGRES_NON_ROOT_PASSWORD
\getenv db POSTGRES_DB

CREATE USER :"non_root_user" WITH PASSWORD :'non_root_password';
GRANT ALL PRIVILEGES ON DATABASE :"db" TO :"non_root_user";
GRANT CREATE ON SCHEMA public TO :"non_root_user";
