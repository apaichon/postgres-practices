\ir context.sql
-- These checks describe a quiet source. Other coursework writing to claimsure
-- concurrently legitimately changes the comparison; do not reset that source.
SELECT format(
  'SELECT %L AS source_table, count(*) = m.source_rows AS same_count, '
  'md5(COALESCE(string_agg(md5(to_jsonb(s)::text), '''' ORDER BY s.%I), '''')) = m.source_hash AS same_data, '
  'c.relacl::text IS NOT DISTINCT FROM m.source_acl AS same_acl, '
  'c.relrowsecurity = m.source_rls AND c.relforcerowsecurity = m.source_force_rls AS same_rls, '
  '(SELECT last_value FROM %s) = m.source_last_value '
  'AND (SELECT is_called FROM %s) = m.source_is_called AS same_sequence '
  'FROM claimsure.%I s CROSS JOIN %I.source_manifest m '
  'JOIN pg_class c ON c.oid = %L::regclass WHERE m.table_name = %L '
  'GROUP BY m.source_rows, m.source_hash, m.source_acl, m.source_rls, m.source_force_rls, '
  'm.source_last_value, m.source_is_called, c.relacl::text, c.relrowsecurity, c.relforcerowsecurity',
  m.table_name, CASE m.table_name WHEN 'customer' THEN 'customer_id' WHEN 'policy' THEN 'policy_id' ELSE 'claim_id' END,
  m.source_sequence, m.source_sequence, m.table_name, :'lab_schema', 'claimsure.' || m.table_name, m.table_name)
FROM :"lab_schema".source_manifest m ORDER BY m.table_name
\gexec
