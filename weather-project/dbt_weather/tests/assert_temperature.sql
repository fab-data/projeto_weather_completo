with array_lengths as (

    select
        ingestion_id,

        jsonb_array_length(
            payload -> 'hourly' -> 'time'
        ) as time_count,

        jsonb_array_length(
            payload -> 'hourly' -> 'temperature_2m'
        ) as temperature_count,

        jsonb_array_length(
            payload -> 'hourly' -> 'relative_humidity_2m'
        ) as humidity_count,

        jsonb_array_length(
            payload -> 'hourly' -> 'precipitation'
        ) as precipitation_count,

        jsonb_array_length(
            payload -> 'hourly' -> 'surface_pressure'
        ) as pressure_count,

        jsonb_array_length(
            payload -> 'hourly' -> 'wind_speed_10m'
        ) as wind_count

    from {{ source('raw_weather', 'weather_history_json') }}

)

select *
from array_lengths

where time_count is null
   or time_count = 0
   or temperature_count is distinct from time_count
   or humidity_count is distinct from time_count
   or precipitation_count is distinct from time_count
   or pressure_count is distinct from time_count
   or wind_count is distinct from time_count