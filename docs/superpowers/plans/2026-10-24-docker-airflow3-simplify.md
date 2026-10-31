# Docker simplificado + Airflow 3 — plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduzir o ambiente Docker a dois serviços no formato do `projeto_pipeline_weather` (`postgres` + `airflow standalone`), rodando Airflow 3.3.1 com dbt 1.11 no mesmo container.

**Architecture:** Um `Dockerfile` de 3 linhas estende `apache/airflow:3.3.1` com `dbt-core`/`dbt-postgres`. O compose tem `postgres` (metastore `airflow` + banco `aula_weather` criado por script em `init-db/`) e `airflow` (`command: airflow standalone`, login fixo via simple auth manager). A DAG passa a usar a API pública do Airflow 3, sem mudança de lógica.

**Tech Stack:** Docker Compose, Apache Airflow 3.3.1 (Python 3.13), PostgreSQL 16, dbt 1.11, Open-Meteo.

**Spec:** `docs/superpowers/specs/2026-10-24-docker-airflow3-simplify-design.md`

## Global Constraints

- Imagem base: `apache/airflow:3.3.1` (Python 3.13.14).
- `requirements-airflow.txt` contém exatamente `dbt-core>=1.11,<1.12` e `dbt-postgres>=1.11,<1.12`.
- Compose tem exatamente dois serviços: `postgres` e `airflow`.
- `airflow` usa `command: airflow standalone`.
- Portas: Postgres `5433:5432`, Airflow `8080:8080`.
- Login: usuário `airflow`, senha `airflow`, role `admin`.
- Credenciais inline no compose: metastore `airflow/airflow` (db `airflow`), dados `weather_user/123456` (db `aula_weather`).
- DAG usa `airflow.sdk` e `airflow.providers.standard.operators.bash`.
- Caminhos internos inalterados: `/opt/airflow/dags`, `/opt/airflow/src`, `/opt/airflow/dbt`, `/opt/airflow/data`, `/opt/airflow/logs`, `/opt/airflow/config`.
- Nenhum commit é criado: o repositório ainda não tem commits e o dono não pediu commit.
- Não alterar `pyproject.toml`, `uv.lock`, `weather-project/src/*`, `weather-project/dbt_weather/*`.
- Não apagar o `.env` local (gitignored).

## Review Focus

- **Credenciais do dbt:** `profiles.yml` lê `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` do ambiente. Se qualquer uma faltar no serviço `airflow`, o `dbt build` falha mesmo com a DAG "verde" até o passo do dbt — esperado: as cinco presentes e apontando para `postgres:5432/aula_weather`.
- **Banco de dados no primeiro boot:** o script de `init-db/` roda só com volume de dados vazio. Esperado: `aula_weather` com schema `raw` e tabela `weather_history_json` existindo após `docker compose up` num volume novo.
- **Volume de logs:** o bind mount `./logs` precisa existir e ser gravável pelo container (UID 50000). Esperado: `airflow standalone` sobe sem erro de permissão em `/opt/airflow/logs`.
- **Simple auth manager:** sem o arquivo `config/simple_auth_manager_passwords.json` montado, o login `airflow`/`airflow` não funciona. Esperado: arquivo presente no container em `/opt/airflow/config/`.
- **Import da DAG:** imports de Airflow 2 (`airflow.operators.*`, `airflow.decorators`) quebram o parsing no Airflow 3. Esperado: DAG aparece sem erro de import na UI.

---

### Task 1: Imagem com dbt e arquivo de senhas

**Files:**
- Modify: `Dockerfile`
- Modify: `requirements-airflow.txt`
- Create: `config/simple_auth_manager_passwords.json`

**Interfaces:**
- Consumes: nada.
- Produces: imagem `projeto-weather-airflow:local` com `dbt` no PATH e `config/simple_auth_manager_passwords.json` com `{"airflow": "airflow"}`, usado pelo Task 2.

- [ ] **Step 1: Reescrever `requirements-airflow.txt`**

Conteúdo final do arquivo:

```
dbt-core>=1.11,<1.12
dbt-postgres>=1.11,<1.12
```

- [ ] **Step 2: Reescrever `Dockerfile`**

Conteúdo final do arquivo:

```dockerfile
FROM apache/airflow:3.3.1

COPY requirements-airflow.txt /requirements-airflow.txt
RUN pip install --no-cache-dir -r /requirements-airflow.txt
```

- [ ] **Step 3: Criar `config/simple_auth_manager_passwords.json`**

Conteúdo final do arquivo:

```json
{"airflow": "airflow"}
```

- [ ] **Step 4: Construir a imagem**

Run: `docker compose build airflow`

> O compose ainda é o antigo neste ponto; se o serviço `airflow` não existir, use
> `docker build -t projeto-weather-airflow:local .`.

Expected: build conclui sem erro.

- [ ] **Step 5: Verificar dbt e versões dentro da imagem**

Run: `docker run --rm projeto-weather-airflow:local bash -c 'dbt --version && python -c "import dbt.version, psycopg2, requests; print(1)"'`

Expected: `dbt` reporta core 1.11.x e plugin postgres 1.11.x, e imprime `1`.

---

### Task 2: Compose de dois serviços

**Files:**
- Modify: `docker-compose.yml` (substituir o conteúdo inteiro)
- Modify: `.gitignore` (adicionar `logs/`)

**Interfaces:**
- Consumes: `Dockerfile` e `config/simple_auth_manager_passwords.json` do Task 1.
- Produces: serviços `postgres` (porta host 5433) e `airflow` (porta host 8080, `command: airflow standalone`), com as variáveis `POSTGRES_*` no ambiente do container `airflow`.

- [ ] **Step 1: Substituir `docker-compose.yml`**

Conteúdo final do arquivo (idêntico ao desenho, seção "`docker-compose.yml`"):

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

- [ ] **Step 2: Adicionar `logs/` ao `.gitignore`**

Acrescentar ao final do arquivo, junto do bloco de artefatos do dbt:

```
# Airflow logs (bind mount)
logs/
```

- [ ] **Step 3: Remover `.env.example`**

Run: `Remove-Item .env.example`

Expected: o arquivo some; `.env` local permanece intacto.

- [ ] **Step 4: Validar o compose**

Run: `docker compose config --services`

Expected: imprime exatamente `postgres` e `airflow` (duas linhas).

- [ ] **Step 5: Validar as variáveis do serviço airflow**

Run: `docker compose config | Select-String -Pattern "POSTGRES_(HOST|PORT|DB|USER|PASSWORD)"`

Expected: as cinco variáveis aparecem na seção do serviço `airflow`.

---

### Task 3: Script de inicialização do banco

**Files:**
- Create: `init-db/01-init-aula-weather.sql`
- Delete: `db/init.sql`

**Interfaces:**
- Consumes: serviço `postgres` do Task 2, que monta `./init-db` em `/docker-entrypoint-initdb.d`.
- Produces: banco `aula_weather` (owner `weather_user`, senha `123456`) com schema `raw` e tabela `raw.weather_history_json (ingestion_id, loaded_at, payload)`, alvo do `load_data.py` e do dbt.

- [ ] **Step 1: Criar `init-db/01-init-aula-weather.sql`**

Conteúdo final do arquivo:

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

- [ ] **Step 2: Remover `db/init.sql` e o diretório `db/` vazio**

Run: `Remove-Item db\init.sql; Remove-Item db -ErrorAction SilentlyContinue`

Expected: `db/` deixa de existir; nenhum outro arquivo é removido.

- [ ] **Step 3: Subir o Postgres com volume limpo**

Run: `docker compose down -v; docker compose up -d postgres`

Expected: `docker compose ps postgres` mostra `healthy`. Os logs do Postgres mostram o script
`01-init-aula-weather.sql` executado sem erro.

- [ ] **Step 4: Verificar banco, schema e tabela**

Run: `docker compose exec postgres psql -U weather_user -d aula_weather -c "\dt raw.*"`

Expected: lista `raw.weather_history_json` com tipo `table`.

- [ ] **Step 5: Verificar encoding e privilégio de escrita**

Run:

```
docker compose exec postgres psql -U weather_user -d aula_weather -c "select pg_encoding_to_char(encoding) as encoding from pg_database where datname = current_database();"
docker compose exec postgres psql -U weather_user -d aula_weather -c "insert into raw.weather_history_json (payload) values ('{}'::jsonb); delete from raw.weather_history_json where payload = '{}'::jsonb;"
```

Expected: primeira saída `UTF8`; segunda imprime `INSERT 0 1` e `DELETE 1`, sem erro de permissão.

---

### Task 4: DAG na API do Airflow 3

**Files:**
- Modify: `weather-project/airflow/dags/weather_dag.py:1-11`

**Interfaces:**
- Consumes: `config/`, `/opt/airflow/src`, `/opt/airflow/dbt`, `POSTGRES_*` do serviço `airflow` (Tasks 1–3).
- Produces: DAG `weather_pipeline` com tarefas `extract`, `load`, `dbt_build`, importável pelo Airflow 3.3.1.

- [ ] **Step 1: Trocar os imports do DAG**

Substituir as linhas 4–6 atuais:

```python
from airflow.decorators import dag, task
from airflow.operators.bash import BashOperator
from airflow.operators.python import get_current_context
```

por:

```python
from airflow.sdk import dag, task, get_current_context
from airflow.providers.standard.operators.bash import BashOperator
```

Nenhuma outra linha do arquivo muda (decorators, `sys.path.insert`, tasks, `dbt build` e o
encadeamento `extract_task >> load_task >> dbt_build` ficam como estão).

- [ ] **Step 2: Validar o parsing dentro da imagem**

Run: `docker compose run --rm airflow python -c "from airflow.sdk import dag, task, get_current_context; from airflow.providers.standard.operators.bash import BashOperator; print('imports ok')"`

Expected: `imports ok`.

- [ ] **Step 3: Subir o ambiente completo**

Run: `docker compose up -d`

Expected: `docker compose ps` mostra `postgres` healthy e `airflow` up.

- [ ] **Step 4: Confirmar que a DAG foi carregada sem erro de import**

Run: `docker compose exec airflow airflow dags list-import-errors -l`

Expected: nenhuma linha listando `weather_pipeline` (o `-l` faz parsing local, sem depender do
api-server nem de token).

Run: `docker compose exec airflow airflow dags list -l | Select-String weather_pipeline`

Expected: a DAG aparece na listagem.

- [ ] **Step 5: Conferir a UI e o login**

Run: abrir `http://localhost:8080` e entrar com `airflow` / `airflow`.

Expected: login aceito e DAG `weather_pipeline` listada.

---

### Task 5: Execução ponta a ponta

**Files:** nenhum arquivo novo; apenas verificação do pipeline.

**Interfaces:**
- Consumes: Tasks 1–4 completas.
- Produces: prova de que extract → load → dbt build roda no ambiente simplificado, e dados no banco.

- [ ] **Step 1: Rodar a DAG uma vez com uma janela de datas conhecida**

Run:

```
docker compose exec airflow bash -c 'airflow dags test weather_pipeline -c "{\"start_date\": \"2026-10-17\", \"end_date\": \"2026-10-19\"}"'
```

`airflow dags test` executa o DagRun localmente (sem depender de api-server ou token) e para
no primeiro erro.

Expected: o comando termina com código 0 e imprime `extract`, `load` e `dbt_build` com estado
`success`.

- [ ] **Step 2: Confirmar o run no metastore**

Run: `docker compose exec postgres psql -U airflow -d airflow -c "select run_id, state from dag_run where dag_id = 'weather_pipeline' order by id desc limit 1;"`

Expected: uma linha com `state = success`.

- [ ] **Step 3: Verificar a ingestão**

Run: `docker compose exec postgres psql -U weather_user -d aula_weather -c "select count(*) from raw.weather_history_json;"`

Expected: contagem maior que zero.

- [ ] **Step 4: Verificar a saída do dbt**

Run:

```
docker compose exec postgres psql -U weather_user -d aula_weather -c "select table_schema, table_type, table_name from information_schema.tables where table_schema in ('staging','intermediate','marts') order by 1,3;"
```

Expected: views em `staging` e `intermediate` e tabelas em `marts` (nomes definidos pelos
models em `weather-project/dbt_weather/models/**`), sem erro de conexão.

- [ ] **Step 5: Registrar o resultado para o README (Task 6 consome)**

Anotar os nomes exatos das relações do Step 4 e o comando de consulta que funcionou no Step 3.

---

### Task 6: README com instruções curtas

**Files:**
- Modify: `README.md` (hoje vazio)

**Interfaces:**
- Consumes: portas e credenciais dos Tasks 2–3, nomes de relações do Task 5.
- Produces: instruções de subida e verificação para quem clonar o repositório.

- [ ] **Step 1: Escrever o README**

Conteúdo final do arquivo, em português, cobrindo exatamente:

```markdown
# Weather Pipeline (Airflow 3 + dbt)

Pipeline Open-Meteo → PostgreSQL → dbt, orquestrado por Apache Airflow 3.

## Como subir

    docker compose up -d --build

- Airflow: http://localhost:8080 — login `airflow` / `airflow`
- Postgres: `localhost:5433` — bancos `airflow` (metastore) e `aula_weather` (dados)

## Serviços

- `postgres`: imagem `postgres:16`; cria `aula_weather`, o schema `raw` e a tabela
  `raw.weather_history_json` via `init-db/` no primeiro boot (volume vazio).
- `airflow`: imagem local (`Dockerfile` sobre `apache/airflow:3.3.1` + dbt 1.11) rodando
  `airflow standalone` (api-server, scheduler, dag-processor e triggerer no mesmo container).

## Estrutura

- `weather-project/airflow/dags/`: DAG `weather_pipeline` (extract → load → dbt build)
- `weather-project/src/`: extract e load
- `weather-project/dbt_weather/`: projeto dbt (`profiles.yml` lê `POSTGRES_*` do ambiente)
- `config/`: senha do simple auth manager
- `init-db/`: scripts SQL de primeiro boot
- `data/`: arquivos JSON extraídos

## Rodar a DAG

Pela UI (`http://localhost:8080`), ative a DAG `weather_pipeline` e clique em **Trigger Dag**.
Sem UI, rode um DagRun local com uma janela de datas:

    docker compose exec airflow bash -c 'airflow dags test weather_pipeline -c "{\"start_date\": \"2026-10-17\", \"end_date\": \"2026-10-19\"}"'

## Conferir os dados

    docker compose exec postgres psql -U weather_user -d aula_weather \
      -c "select count(*) from raw.weather_history_json;"

## Recriar o banco do zero

    docker compose down -v
    docker compose up -d --build

## dbt manual

    docker compose exec airflow dbt build --project-dir /opt/airflow/dbt --profiles-dir /opt/airflow/dbt
```

- [ ] **Step 2: Verificar que o README não cita `.env`**

Run: `Select-String -Path README.md -Pattern "\.env"`

Expected: nenhum resultado (o compose não lê `.env`).

- [ ] **Step 3: Verificação final do ambiente do zero**

Run: `docker compose down -v; docker compose up -d --build`

Expected: ambos os serviços sobem; `docker compose ps` mostra `postgres` healthy e `airflow`
up; `docker compose exec airflow airflow dags list-import-errors -l` não lista nada.
