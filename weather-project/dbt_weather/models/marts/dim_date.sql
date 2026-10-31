with bounds as (

    select
        date_trunc('year', min(weather_at_local)) as start_date,

        date_trunc('year', max(weather_at_local))
            + interval '1 year'
            - interval '1 day' as end_date

    from {{ ref('stg_weather_history') }}

),

calendar as (

    select
        g.day::date as full_date

    from bounds b

    cross join lateral generate_series(
        b.start_date,
        b.end_date,
        interval '1 day'
    ) as g(day)

)

select
    to_char(full_date, 'YYYYMMDD')::integer as date_key,
    full_date,

    extract(year from full_date)::integer as year_number,
    extract(quarter from full_date)::integer as quarter_number,
    extract(month from full_date)::integer as month_number,
    to_char(full_date, 'YYYY-MM') as year_month,

    extract(day from full_date)::integer as day_of_month,
    extract(isodow from full_date)::integer as day_of_week_number,

    case extract(isodow from full_date)::integer
        when 1 then 'Segunda-feira'
        when 2 then 'Terça-feira'
        when 3 then 'Quarta-feira'
        when 4 then 'Quinta-feira'
        when 5 then 'Sexta-feira'
        when 6 then 'Sábado'
        when 7 then 'Domingo'
    end as day_of_week_name,

    extract(isodow from full_date) in (6, 7) as is_weekend

from calendar