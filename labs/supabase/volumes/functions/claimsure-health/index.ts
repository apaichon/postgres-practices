// ClaimSure's own sample; the main router verifies the Bearer JWT first.
// No database access or secret values are returned by this health endpoint.
Deno.serve(() => Response.json({
  service: 'ClaimSure Supabase',
  edge_runtime: 'ready',
  synthetic_lab: true,
}))
