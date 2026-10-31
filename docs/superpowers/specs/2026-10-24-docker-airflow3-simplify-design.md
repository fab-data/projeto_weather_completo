# Docker simplificado + Airflow 3 — desenho

Data: 2026-10-24
Status: aguardando aprovação

## Intenção e porquê

O `docker-compose.yml` atual cresceu: anchor `x-airflow-common`, quatro serviços
(`postgres`, `airflow-init`, `airflow-webserver`, `airflow-scheduler`), `env_file` +
`environment` sobrepostos, healthcheck consultando dois bancos e um `.env` com nove
variáveis. O projeto de referência `projeto_pipeline_weather` faz a mesma coisa com dois
serviços e um único comando.

Objetivo: ter o mesmo formato do projeto de referência — **dois serviços, `airflow
standalone`, configuração inline** — migrando para Airflow 3 e mantendo o dbt no DAG.

## Objetivos

- Compose com apenas `postgres` e `airflow`, no formato do projeto de referência.
- `airflow standalone` (api-server + scheduler + dag-processor + triggerer no mesmo container).
- Login fixo `airflow` / `airflow` via simple auth manager, como no exemplo.
- Airflow 3.3.1 e dbt 1.11 executando no mesmo container.
- Um único banco Postgres servindo metastore (`airflow`) e dados (`aula_weather`).
- DAG migrada para a API pública do Airflow 3.

## Não-objetivos

- Não mudar a lógica de extract / load / dbt (só imports do DAG e caminhos já existentes).
- Não trocar o Postgres por outro banco, nem separar o dbt em outro container.
- Não introduzir Celery, Redis, workers ou múltiplos ambientes.
- Não mexer em `pyproject.toml` / `uv.lock` (ambiente local fora do Docker).
- Não criar commits (o repositório ainda não tem nenhum commit).

## Anti-objetivos

- Reinstalar dependências no boot do container (imagem mutável em runtime).
- Manter `airflow-init` / `webserver` / `scheduler` separados.
- Deixar credenciais e caminhos espalhados entre `.env` e `compose`.

## Restrições

- `apache/airflow:3.3.1` usa Python 3.13.14 (verificado no container local).
- `dbt-core` 1.11 exige Python ≥3.10 e `dbt-postgres` está em 1.11.0 — compatível.
- Airflow 3 removeu `airflow.operators.*`; o DAG precisa de
  `airflow.providers.standard.operators.bash.BashOperator`.
- Airflow 3 usa `airflow.sdk` para `dag`, `task` e `get_current_context`.
- O Postgres do exemplo nasce com `POSTGRES_DB=airflow`; o banco de dados `aula_weather`
  passa a ser criado por script em `init-db/` (o `db/init.sql` atual fazia o inverso).

## Abordagens consideradas

| # | Abordagem | Trade-off | Decisão |
|---|---|---|---|
| A | Dockerfile mínimo (`FROM apache/airflow:3.3.1` + `pip install -r requirements-airflow.txt`) e compose espelhado no exemplo | Um arquivo extra, mas build determinístico e restart rápido | **escolhida** |
| B | Imagem oficial pura, `pip install` dentro do `command` | Literalmente igual ao exemplo, porém reinstala dbt a cada recriação e exige rede no start | descartada |
| C | dbt em venv por task (`@task.venv`) | Sem dbt na imagem, mas DAG mais complexa e primeira run lenta | descartada |

## Como fica

### `docker-compose.yml`

```yaml
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_USER: airflow
      POSTGRES_PASSWORD: airflow
      POSTGRES_DB: airflow
    ports:
      - "5433:5432"
    volumes:
      - postgres-db-volume:/var/lib/postgresql/data
      - ./init-db:/docker-entrypoint-initdb.d
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U airflow -d airflow"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  airflow:
    build: .
    image: projeto-weather-airflow:local
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      AIRFLOW__CORE__EXECUTOR: LocalExecutor
      AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION: "false"
      AIRFLOW__CORE__SIMPLE_AUTH_MANAGER_USERS: airflow:admin
      AIRFLOW__CORE__SIMPLE_AUTH_MANAGER_PASSWORDS_FILE: /opt/airflow/config/simple_auth_manager_passwords.json
      AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://airflow:airflow@postgres:5432/airflow
      AIRFLOW_UID: "50000"
      POSTGRES_HOST: postgres
      POSTGRES_PORT: "5432"
      POSTGRES_DB: aula_weather
      POSTGRES_USER: weather_user
      POSTGRES_PASSWORD: "123456"
    ports:
      - "8080:8080"
    volumes:
      - ./weather-project/airflow/dags:/opt/airflow/dags
      - ./weather-project/src:/opt/airflow/src
      - ./weather-project/dbt_weather:/opt/airflow/dbt
      - ./data:/opt/airflow/data
      - ./logs:/opt/airflow/logs
      - ./config:/opt/airflow/config
    command: airflow standalone

volumes:
  postgres-db-volume:
```

Diferenças em relação ao exemplo, todas deliberadas:

- `build: .` + `image:` (o exemplo usa só `image:`), por causa do dbt.
- `AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION: "false"` para a DAG já subir ativa; o
  exemplo deixa pausada.
- Porta `8080` (mantida do projeto atual) em vez de `8000`.
- Volume extra `./weather-project/dbt_weather:/opt/airflow/dbt`.

### `Dockerfile`

```dockerfile
FROM apache/airflow:3.3.1

COPY requirements-airflow.txt /requirements-airflow.txt
RUN pip install --no-cache-dir -r /requirements-airflow.txt
```

### `requirements-airflow.txt`

```
dbt-core>=1.11,<1.12
dbt-postgres>=1.11,<1.12
```

`requests` e `psycopg2-binary` saem da lista porque já vêm na imagem oficial do Airflow 3.

### `config/simple_auth_manager_passwords.json`

```json
{"airflow": "airflow"}
```

### `init-db/01-init-aula-weather.sql`

Espelha o `01-init-aula_weather.sql` do projeto de referência, criando o usuário de dados
e o banco `aula_weather` no mesmo Postgres, e em seguida o schema `raw` e a tabela de
ingestão (conteúdo que hoje está em `db/init.sql`):

```sql
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'weather_user') THEN
        CREATE ROLE weather_user LOGIN PASSWORD '123456';
    END IF;
END
$$;

SELECT 'CREATE DATABASE aula_weather OWNER weather_user ENCODING ''UTF8'' TEMPLATE template0'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'aula_weather')\gexec

GRANT ALL PRIVILEGES ON DATABASE aula_weather TO weather_user;

\connect aula_weather

SET ROLE weather_user;

CREATE SCHEMA IF NOT EXISTS raw AUTHORIZATION weather_user;

CREATE TABLE IF NOT EXISTS raw.weather_history_json (
    ingestion_id bigint generated always as identity primary key,
    loaded_at timestamptz not null default current_timestamp,
    payload jsonb not null
);
```

### DAG (`weather-project/airflow/dags/weather_dag.py`)

Só os imports mudam; a lógica (extract → load → dbt build) fica igual:

```python
from airflow.sdk import dag, task, get_current_context
from airflow.providers.standard.operators.bash import BashOperator
```

`sys.path.insert(0, "/opt/airflow/src")` e o caminho do dbt (`/opt/airflow/dbt`)
continuam iguais, então `profiles.yml` segue lendo `POSTGRES_*` do ambiente do container.

### Arquivos removidos / mantidos

- Removido: `db/init.sql` (substituído por `init-db/01-init-aula-weather.sql`).
- Removido: `.env.example` (não há mais variáveis lidas de `.env`).
- Mantido e **não utilizado** pelo compose: `.env` local (fica com o dono, é gitignored).
- `README.md` (hoje vazio) ganha um resumo curto: como subir, portas, login e como rodar
  um `dbt build` manual.

## O que fica a cargo de quem implementar

- Ordem dos mounts e nomes de volumes, desde que os caminhos internos acima se mantenham.
- Texto do README.
- Se o `.gitignore` precisa de `logs/` (sim, para o novo bind mount).

## Verificação

1. `docker compose build` conclui com dbt instalado (import `dbt.version` funciona).
2. `docker compose up -d` e `docker compose ps`: `postgres` healthy, `airflow` up.
3. `docker compose exec postgres psql -U weather_user -d aula_weather -c "\dt raw.*"` mostra a tabela.
4. UI em `http://localhost:8080` com `airflow` / `airflow`, DAG `weather_pipeline` visível.
5. Trigger manual da DAG termina com `extract`, `load` e `dbt_build` verdes.
