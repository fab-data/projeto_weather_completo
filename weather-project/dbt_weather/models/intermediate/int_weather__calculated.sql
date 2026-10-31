with staging as (

    select *
    from {{ ref('stg_weather_history') }}

),

previous_hour as (

    select
        *,
        lag(weather_at_utc) over (
            partition by latitude, longitude
            order by weather_at_utc
        ) as previous_weather_at_utc,

        lag(temp_celsius) over (
            partition by latitude, longitude
            order by weather_at_utc
        ) as previous_temp_celsius

    from staging

)

select
    md5(
        latitude::text || '|' ||
        longitude::text || '|' ||
        timezone_name || '|' ||
        to_char(weather_at_local, 'YYYY-MM-DD HH24:MI:SS')
    ) as weather_key,

    to_char(weather_at_local, 'YYYYMMDD')::integer as date_key,
    extract(hour from weather_at_local)::integer as hour_key,

    latitude,
    longitude,
    timezone_name,
    weather_at_local,
    weather_at_utc,

    temp_celsius,
    humidity_pct,
    precipitation_mm,
    surface_pressure_hpa,
    wind_speed_kmh,

    case
        when weather_at_utc - previous_weather_at_utc = interval '1 hour'
        then temp_celsius - previous_temp_celsius
    end as temp_change_1h_celsius,

    precipitation_mm > 0 as has_precipitation,

    loaded_at as source_loaded_at

from previous_hour
