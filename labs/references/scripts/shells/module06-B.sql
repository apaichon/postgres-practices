\echo '6B: same report and row count; original plus 64kB / 4MB / 32MB, repeated'
SELECT current_setting('work_mem') AS original_work_mem \gset
SELECT lab_m6_shell.measure_sort(:'run_id','before_original',current_setting('work_mem'),n)
FROM generate_series(1,:repeat) n;
-- Separate statements restore transaction-local settings between each ladder rung.
SELECT lab_m6_shell.measure_sort(:'run_id','test_64kB','64kB',n) FROM generate_series(1,:repeat) n;
SELECT lab_m6_shell.measure_sort(:'run_id','test_4MB','4MB',n) FROM generate_series(1,:repeat) n;
SELECT lab_m6_shell.measure_sort(:'run_id','after_32MB','32MB',n) FROM generate_series(1,:repeat) n;
SELECT phase,details->>'work_mem' AS work_mem,
 min(details->>'sort_space_type') AS sort_space,
 round(percentile_cont(.5) WITHIN GROUP(ORDER BY value)::numeric,3) AS median_ms
FROM lab_m6_shell.metrics WHERE run_id=:'run_id' AND lab='B' AND metric='execution_ms'
GROUP BY phase,details->>'work_mem' ORDER BY min(measured_at);
SELECT phase,max(value) AS temp_written_blocks FROM lab_m6_shell.metrics
WHERE run_id=:'run_id' AND lab='B' AND metric='temp_written' GROUP BY phase ORDER BY phase;
SELECT current_setting('work_mem') AS restored, current_setting('work_mem')=:'original_work_mem' AS original_restored;
\echo 'Compare spills and medians; faster timing is not guaranteed. Re-run with comparable load.'
