# README de portfólio — plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Substituir o README operacional por um README de portfólio híbrido (dashboard no topo + case técnico curto) para publicação no GitHub.

**Architecture:** Um único arquivo markdown, em pt-BR, dividido em 9 seções conforme o spec; a imagem do dashboard fica em `docs/dashboard.png` e é fornecida pelo dono.

**Tech Stack:** Markdown + Mermaid (renderizado pelo GitHub); conteúdo apenas de fatos verificados no compose, nos modelos dbt e no projeto Power BI.

**Spec:** `docs/superpowers/specs/2026-10-31-readme-portfolio-design.md`

## Global Constraints

- Idioma: português (pt-BR).
- Imagem: `docs/dashboard.png`, dentro de um link para o relatório.
- Link: `https://app.powerbi.com/view?r=eyJrIjoiYjM0NjM1NDMtNzVlMS00Mjk0LWFhZmUtNWY3NzE5YjhkOWQxIiwidCI6IjY1OWNlMmI4LTA3MTQtNDE5OC04YzM4LWRjOWI2MGFhYmI1NyJ9`.
- Não afirmar dashboard "ao vivo" (Power BI em modo import) nem indicadores que não existam no painel.
- Não usar o print `dados do_weather.png` (é de outro projeto).
- Não commitar: o repositório está sem nenhum commit e o dono não pediu commit.

## Review Focus

- Caminho da imagem errado ou imagem ausente quebra a primeira dobra do README — o link precisa apontar para `docs/dashboard.png` e o texto deve deixar claro que o arquivo é adicionado pelo dono.
- Comando citado divergente do compose (porta 5433, banco `weather_bd`, `--profiles-dir /opt/airflow/dbt`) induz o leitor a falhar na reprodução.
- Diagrama Mermaid com sintaxe inválida aparece como bloco de erro no GitHub.
- Tabela de marts com nome de schema/camada trocado (`staging`/`intermediate`/`marts`, sem prefixo) contradiz o `generate_schema_name` do repo.
- Alegação sobre o dashboard (páginas, comparativos) que o `.pbip` não comprova.

---

### Task 1: Escrever o README de portfólio

**Files:**
- Modify: `README.md`
- Create: `docs/dashboard.png` (pelo dono; não é gerado nesta task)

**Interfaces:**
- Consumes: spec acima; `docker-compose.yml`; `weather-project/airflow/dags/weather_dag.py`; `weather-project/dbt_weather/**`; projeto Power BI em `C:\Users\Fabricio\Downloads\Weather Project`.
- Produces: `README.md` com as seções `Dashboard`, `Arquitetura`, `Modelo de dados`, `Decisões técnicas`, `Stack`, `Como rodar`, `Estrutura do repositório`, `Fonte dos dados`.

- [ ] **Step 1: Substituir `README.md`**

Estrutura e conteúdo, nesta ordem (texto final fica a critério de quem escreve, mas os fatos são fixos):

1. Título "Weather Pipeline" + linha "Open-Meteo → PostgreSQL → dbt → Power BI".
2. `## Dashboard`: `[![Dashboard](docs/dashboard.png)](<link>)`; 3 bullets — temperatura atual vs. média do período (com sparkline de 24 h); chuva acumulada, horas com chuva e pico horário; perfil horário com picos de temperatura/umidade/vento e heatmap hora × dia. Uma linha dizendo que o painel lê o schema `marts` no Postgres.
3. `## Arquitetura`: flowchart Mermaid `LR` com `Open-Meteo Archive API → extract_data.py → JSON → load_data.py → raw.weather_history_json → stg_weather_history → int_weather__calculated → fct_weather_hr (+ dim_date, dim_time) → Power BI`, e o Airflow `weather_pipeline` orquestrando extract/load/`dbt build`. Parágrafo curto do fluxo e da janela padrão (hoje-4 a hoje-2).
4. `## Modelo de dados`: tabela com colunas Camada | Objeto | Grão | Papel, contendo `raw.weather_history_json` (append-only, 1 linha por extração), `staging.stg_weather_history` (view, 1 linha por hora/local, deduplicada pela última carga), `intermediate.int_weather__calculated` (view, chaves + `temp_change_1h_celsius` + `has_precipitation`), `marts.fct_weather_hr` (table, 1 linha por local/hora), `marts.dim_date` (calendário), `marts.dim_time` (24 horas). Nota: o macro `generate_schema_name` grava direto em `staging`/`intermediate`/`marts`.
5. `## Decisões técnicas`: bullets — JSONB bruto + dedupe por `loaded_at desc, ingestion_id desc`; camadas com grão explícito; star schema com `weather_key`/`date_key`/`hour_key`; testes dbt (`not_null`, `unique`, `relationships`, `tests/assert_temperature.sql` comparando o tamanho dos arrays horários); reexecução idempotente da janela.
6. `## Stack`: Airflow 3.3.1 (standalone, LocalExecutor), dbt-core/dbt-postgres 1.11, PostgreSQL 16, Python, Docker Compose, Power BI (import).
7. `## Como rodar`: `docker compose up -d --build`; UI `http://localhost:8080` (`airflow`/`airflow`); trigger com `{"start_date": "...", "end_date": "..."}` ou `docker compose exec airflow airflow dags test weather_pipeline`; `docker compose exec airflow dbt build --project-dir /opt/airflow/dbt --profiles-dir /opt/airflow/dbt`; conferência com `psql -U weather_user -d weather_bd`; recriar com `docker compose down -v`.
8. `## Estrutura do repositório`: árvore curta (`weather-project/airflow/dags`, `weather-project/src`, `weather-project/dbt_weather`, `init-db`, `config`, `data`).
9. `## Fonte dos dados`: Open-Meteo Archive API, sem chave; Goiânia (-16.6869, -49.2648); timezone `America/Sao_Paulo`; variáveis horárias `temperature_2m`, `relative_humidity_2m`, `precipitation`, `surface_pressure`, `wind_speed_10m`.

- [ ] **Step 2: Conferir comandos e caminhos**

Run: `rtk cmd /c findstr /n /c:"5433" /c:"weather_bd" /c:"/opt/airflow/dbt" /c:"dags test" README.md docker-compose.yml`
Expected: porta host 5433 e `weather_bd` aparecem nos dois arquivos; `/opt/airflow/dbt` no README e no volume do compose; `dags test` só no README.

- [ ] **Step 3: Conferir nomes de tabelas e camadas**

Run: `rtk cmd /c findstr /s /n /c:"weather_history_json" /c:"stg_weather_history" /c:"int_weather__calculated" /c:"fct_weather_hr" /c:"dim_date" /c:"dim_time" README.md weather-project\dbt_weather\*`
Expected: cada nome citado no README existe nos modelos dbt; nenhum schema inventado.

- [ ] **Step 4: Conferir link e imagem**

Run: `rtk cmd /c findstr /n /c:"docs/dashboard.png" /c:"app.powerbi.com/view" README.md`
Expected: uma referência à imagem e uma ao link, iguais aos do spec.

- [ ] **Step 5: Conferir Mermaid**

Run: colar o bloco Mermaid em <https://mermaid.live> (ou conferir manualmente a sintaxe `flowchart LR`)
Expected: renderiza sem erro.

- [ ] **Step 6: Não commitar**

Deixar `README.md` e o spec como arquivos não rastreados/modificados; avisar o dono de que a imagem `docs/dashboard.png` ainda precisa ser adicionada.
