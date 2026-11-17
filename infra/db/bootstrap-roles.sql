-- infra/db/bootstrap-roles.sql : run once per environment as a superuser/admin
CREATE ROLE ems_migrator LOGIN PASSWORD :'migrator_password';
CREATE ROLE ems_app      LOGIN PASSWORD :'app_password' NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE DATABASE ems OWNER ems_migrator;
\connect ems
REVOKE ALL ON DATABASE ems FROM PUBLIC;
GRANT CONNECT ON DATABASE ems TO ems_app;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
ALTER ROLE ems_app SET statement_timeout = '10s';
ALTER ROLE ems_app SET idle_in_transaction_session_timeout = '30s';

