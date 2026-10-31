with source as (

    select
        ingestion_id,
        loaded_at,
        payload
    from {{ source('raw_weather', 'weather_history_json') }}

),

expanded as (

    select
        s.ingestion_id,
        s.loaded_at,

        (s.payload ->> 'latitude')::numeric as latitude,
        (s.payload ->> 'longitude')::numeric as longitude,
        s.payload ->> 'timezone' as timezone_name,

        t.time_text::timestamp as weather_at_local,

        (
            s.payload -> 'hourly' -> 'temperature_2m'
            ->> ((t.position - 1)::integer)
        )::numeric as temp_celsius,

        (
            s.payload -> 'hourly' -> 'relative_humidity_2m'
            ->> ((t.position - 1)::integer)
        )::integer as humidity_pct,

        (
            s.payload -> 'hourly' -> 'precipitation'
            ->> ((t.position - 1)::integer)
        )::numeric as precipitation_mm,

        (
            s.payload -> 'hourly' -> 'surface_pressure'
            ->> ((t.position - 1)::integer)
        )::numeric as surface_pressure_hpa,

        (
            s.payload -> 'hourly' -> 'wind_speed_10m'
            ->> ((t.position - 1)::integer)
        )::numeric as wind_speed_kmh

    from source s

    cross join lateral jsonb_array_elements_text(
        s.payload -> 'hourly' -> 'time'
    ) with ordinality as t(time_text, position)

),

ranked as (

    select
        *,
        row_number() over (
            partition by
                latitude,
                longitude,
                timezone_name,
                weather_at_local
            order by
                loaded_at desc,
                ingestion_id desc
        ) as row_num
    from expanded

)

select
    ingestion_id,
    loaded_at,
    latitude,
    longitude,
    timezone_name,
    weather_at_local,
    weather_at_local at time zone timezone_name as weather_at_utc,
    temp_celsius,
    humidity_pct,
    precipitation_mm,
    surface_pressure_hpa,
    wind_speed_kmh

from ranked
where row_num = 1