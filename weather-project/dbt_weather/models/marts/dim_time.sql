select
    h.hour_number as hour_key,
    h.hour_number,
    lpad(h.hour_number::text, 2, '0') || ':00' as hour_label,

    case
        when h.hour_number < 6 then 'Madrugada'
        when h.hour_number < 12 then 'Manhã'
        when h.hour_number < 18 then 'Tarde'
        else 'Noite'
    end as day_period

from generate_series(0, 23) as h(hour_number)
