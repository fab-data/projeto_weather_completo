DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'weather_user') THEN
        CREATE ROLE weather_user LOGIN PASSWORD '123456';
    END IF;
END
$$;

SELECT 'CREATE DATABASE weather_bd OWNER weather_user ENCODING ''UTF8'' TEMPLATE template0'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'weather_bd')\gexec

GRANT ALL PRIVILEGES ON DATABASE weather_bd TO weather_user;

\connect weather_bd

SET ROLE weather_user;

CREATE SCHEMA IF NOT EXISTS raw AUTHORIZATION weather_user;

CREATE TABLE IF NOT EXISTS raw.weather_history_json (
    ingestion_id bigint generated always as identity primary key,
    loaded_at timestamptz not null default current_timestamp,
    payload jsonb not null
);
