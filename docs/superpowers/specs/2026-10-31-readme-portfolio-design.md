# README de portfólio do Weather Pipeline — desenho

Data: 2026-10-31
Status: aguardando aprovação

## Intenção e porquê

O `README.md` atual só ensina a operar o Docker. O projeto vai ser publicado no GitHub
por um analista de dados/BI junto com um dashboard Power BI já publicado, então o README
precisa vender o case para dois públicos ao mesmo tempo: quem avalia portfólio (recrutador,
gestor) e quem quer reproduzir o pipeline.

Abordagem escolhida na conversa: **híbrido escaneável** — topo visual com o dashboard,
depois case técnico em seções curtas.

## Objetivos

- Abrir com o dashboard: imagem clicável + link do relatório publicado + o que ele responde.
- Explicar a arquitetura e o modelo dimensional sem virar tutorial.
- Destacar as decisões que mostram critério de engenharia/BI (JSONB bruto, dedupe,
  camadas dbt, star schema, testes).
- Manter instruções de reprodução enxutas, mas corretas (Docker, DAG, dbt).
- Ser fiel ao que existe: nada de indicador ou tecnologia que o repositório/dashboard
  não comprove.

## Não-objetivos

- Não documentar linha a linha o código nem repetir o `AGENTS.md`.
- Não incluir print de SQL/terminal nem dados sensíveis.
- Não prometer dashboard "ao vivo": o Power BI é modo import, atualizado por carga.

## Restrições

- Idioma: português (dashboard e docs do repo já estão em pt-BR).
- Imagem única, fornecida pelo dono, salva em `docs/dashboard.png`.
- Link publicado: `https://app.powerbi.com/view?r=eyJrIjoiYjM0NjM1NDMtNzVlMS00Mjk0LWFhZmUtNWY3NzE5YjhkOWQxIiwidCI6IjY1OWNlMmI4LTA3MTQtNDE5OC04YzM4LWRjOWI2MGFhYmI1NyJ9`.
- Projeto Power BI conecta em `localhost:5433` / `weather_bd` / schema `marts`, modo import,
  três páginas: Visão Geral, Perfil Horário e Chuva.
- O print `dados do_weather.png` do Downloads é de outro projeto (`aula_weather`,
  `go_weather`) e não será usado.

## Estrutura do README

1. **Título + uma linha**: pipeline Open-Meteo → PostgreSQL → dbt → Power BI.
2. **Dashboard**: `docs/dashboard.png` dentro de um link para o relatório; 3 bullets do que
   ele responde (agora vs. média, chuva e comparativo diário, perfil horário/picos).
3. **Arquitetura**: diagrama Mermaid (API → extract → JSON → load → Postgres → dbt → Power BI,
   com Airflow orquestrando) + um parágrafo do fluxo.
4. **Modelo de dados**: tabela com camada, objeto, grão e papel — `raw.weather_history_json`,
   `staging.stg_weather_history`, `intermediate.int_weather__calculated`,
   `marts.fct_weather_hr`, `marts.dim_date`, `marts.dim_time`; nota sobre
   `generate_schema_name` (schemas `staging`/`intermediate`/`marts`, sem prefixo).
5. **Decisões técnicas**: JSONB append-only + dedupe por `loaded_at`/`ingestion_id`; camadas
   dbt com grão explícito; star schema com chaves `date_key`/`hour_key`; testes dbt
   (not_null, unique, relationships e o teste de tamanho dos arrays horários); reexecução
   idempotente da janela.
6. **Stack**: Airflow 3.3.1 (standalone, LocalExecutor), dbt-core/dbt-postgres 1.11,
   PostgreSQL 16, Python, Docker Compose, Power BI. Sem badges de versão inventada: só os
   verificados no compose/imagem.
7. **Como rodar**: subir, acessar a UI, disparar a DAG com `start_date`/`end_date`, `dbt build`
   manual e conferência no psql; recriar do zero com `down -v`.
8. **Estrutura do repositório**: árvore curta (dags, src, dbt_weather, init-db, config, data).
9. **Fonte dos dados**: Open-Meteo Archive API, sem chave, Goiânia (-16.6869, -49.2648),
   timezone `America/Sao_Paulo`, variáveis horárias coletadas.

## O que fica a cargo de quem implementar

- Texto final e badges; ordem dos blocos dentro das seções.
- Se o rodapé de autor entra ou não (sem nome/LinkedIn informados, o README fica sem essa
  seção; o perfil do GitHub já identifica o autor).

## O que fica a cargo do dono

- Salvar a imagem como `docs/dashboard.png` (ou me passar outro caminho/nome).
- Opcional: informar nome/LinkedIn para o rodapé.

## Verificação

- Todo comando citado é o mesmo do `README.md`/`docker-compose.yml` atuais e foi conferido.
- Nomes de tabela, schemas, medidas e páginas do dashboard batem com o projeto Power BI
  em `C:\Users\Fabricio\Downloads\Weather Project`.
- Link do relatório abre em modo leitura.
