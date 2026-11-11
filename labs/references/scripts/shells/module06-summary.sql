SELECT lab,phase,metric,count(*) AS samples,
 round(min(value),3) AS min,round(percentile_cont(.5) WITHIN GROUP(ORDER BY value)::numeric,3) AS median,
 round(max(value),3) AS max,unit
FROM lab_m6_shell.metrics GROUP BY lab,phase,metric,unit ORDER BY lab,metric,phase;
