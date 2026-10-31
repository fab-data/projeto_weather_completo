select
    weather_key,
    date_key,
    hour_key,

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

    temp_change_1h_celsius,
    has_precipitation,

    source_loaded_at

from {{ ref('int_weather__calculated') }}