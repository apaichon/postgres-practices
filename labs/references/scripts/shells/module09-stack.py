#!/usr/bin/env python3
"""Instructor setup/check/reset of the existing ClaimSure monitoring lab."""
import argparse
import base64
import csv
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import urllib.parse
import urllib.request


def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--root',type=Path,default=Path('/opt/setup-postgres-labs'))
 p.add_argument('action',choices=['init-all','check','reset-all'])
 p.add_argument('--dry-run',action='store_true')
 p.add_argument('--yes',action='store_true',help='required for instructor reset of all 20 Module 9 fixtures')
 a=p.parse_args();root=a.root.resolve()
 source=root/'student-scripts'
 # Published repository copies keep their source assets alongside this helper.
 if not (source/'module09-grafana-import.json').is_file():source=Path(__file__).resolve().parent
 pg_container=os.environ.get('M9_PG_CONTAINER','claimsure-postgres')
 prom='http://127.0.0.1:'+os.environ.get('PROMETHEUS_PORT','9090')
 graf='http://127.0.0.1:'+os.environ.get('GRAFANA_PORT','3000')
 databases=[f'claimsure_{n:02d}' for n in range(1,21)]
 def psql(db,sql,secret=False):
  r=subprocess.run(['docker','exec','-i',pg_container,'psql','-X','-qAt','-v','ON_ERROR_STOP=1','-U','postgres','-d',db],input=sql,text=True,capture_output=True)
  if r.returncode:
   raise RuntimeError('Monitor credential provisioning failed; input/diagnostics suppressed.' if secret else r.stderr.strip())
  return r.stdout.strip()
 def http(base,path,payload=None):
  data=None if payload is None else json.dumps(payload).encode()
  req=urllib.request.Request(base+path,data=data,headers={'Content-Type':'application/json'})
  if base==graf:
   user=os.environ.get('GRAFANA_ADMIN_USER','admin');pw=os.environ.get('GRAFANA_ADMIN_PASSWORD','')
   req.add_header('Authorization','Basic '+base64.b64encode(f'{user}:{pw}'.encode()).decode())
  return json.load(urllib.request.urlopen(req,timeout=20))
 def prom_query(q):return http(prom,'/api/v1/query?'+urllib.parse.urlencode({'query':q}))['data']['result']
 def check():
  for metric,expected in [('up',1),('pg_up',1),('pg_exporter_last_scrape_error',0)]:
   series=prom_query(metric+'{job="postgres"}')
   selected={s['metric']['instance']:float(s['value'][1]) for s in series if s['metric'].get('instance') in {'postgres:5432/'+db for db in databases}}
   if len(selected)!=20 or any(v!=expected for v in selected.values()):raise RuntimeError(f'{metric}: expected {expected} for all 20 targets, got {len(selected)} series / {sum(v==expected for v in selected.values())} healthy')
  for metric in ('claimsure_m9_activity_sessions','claimsure_m9_capacity_own_role_limit'):
   if len(prom_query(metric+'{job="postgres"}'))!=20:raise RuntimeError(metric+': expected 20 student series')
  dashboard=http(graf,'/api/dashboards/uid/claimsure-module09')
  if len(dashboard['dashboard'].get('panels',[]))!=20:raise RuntimeError('Module 9 Grafana dashboard not provisioned')
  print('PASS: all 20 exporter HTTP/DB checks, scrape error=0, custom lab collectors, Grafana dashboard (20 panels).')
 if a.dry_run:
  print('PREVIEW:',a.action,'for existing ClaimSure stack at',root)
  print('init-all repairs the read-only monitor login/CONNECT grants, adds custom collectors, recreates only the exporter and provisions the new dashboard.')
  print('reset-all stops only tagged Module 9 sessions and drops only marked lab_m9_shell fixtures in 20 main databases; metrics history/config remain.')
  return
 if a.action=='check':check();return
 if a.action=='reset-all':
  if not a.yes:raise RuntimeError('Instructor reset affects all 20 students: use reset-all --yes or preview with --dry-run')
  sql=(source/'module09-reset.sql').read_text()
  # Preflight every selected schema before any destructive work.
  for db in databases:
   has=psql(db,"SELECT to_regnamespace('lab_m9_shell') IS NOT NULL")
   if has=='t':
    if psql(db,"SELECT to_regclass('lab_m9_shell.module_identity') IS NOT NULL")!='t':raise RuntimeError('Unmarked schema in '+db)
    if psql(db,"SELECT identity FROM lab_m9_shell.module_identity WHERE id=1")!='module09-shell-v1':raise RuntimeError('Wrong schema marker in '+db)
  for db in databases:
   sid=db[-2:]
   psql(db,f"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname=current_database() AND usename='student_{sid}' AND starts_with(application_name,'module09_{sid}_');")
   psql(db,sql);print(db+': Module 9 fixtures reset; history preserved')
  return
 if psql('postgres',"SELECT 'pg_stat_statements'=ANY(string_to_array(current_setting('shared_preload_libraries'),','))")!='t':raise RuntimeError('pg_stat_statements is not preloaded. Instructor must schedule database configuration separately; this script will not restart PostgreSQL.')
 existing=psql('postgres',"SELECT count(*) FROM pg_database WHERE datname~'^claimsure_[0-9]{2}$'")
 if existing!='20':raise RuntimeError('Expected the existing 20 student main databases; this script does not recreate them')
 secret=os.environ.get('MONITOR_PASSWORD')
 if not secret:raise RuntimeError('MONITOR_PASSWORD is required in the private stack .env')
 literal="'"+secret.replace("'","''")+"'"
 psql('postgres',f"""DO $$ BEGIN IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='claim_monitor') THEN CREATE ROLE claim_monitor LOGIN; END IF; END $$;
ALTER ROLE claim_monitor LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS CONNECTION LIMIT 40 PASSWORD {literal};
GRANT pg_monitor TO claim_monitor;
ALTER ROLE claim_monitor SET application_name='postgres-exporter';
ALTER ROLE claim_monitor SET search_path=pg_catalog,public;
""",secret=True)
 print('Read-only claim_monitor login repaired; credential not printed.')
 for db in databases:
  psql(db,f'GRANT CONNECT ON DATABASE {db} TO claim_monitor; CREATE EXTENSION IF NOT EXISTS pg_stat_statements; GRANT USAGE ON SCHEMA public TO claim_monitor; GRANT SELECT ON public.pg_stat_statements TO claim_monitor;')
 print('CONNECT/statistics access verified for all 20 main databases.')
 (root/'config').mkdir(exist_ok=True)
 shutil.copyfile(source/'module09-exporter-queries.yaml',root/'config/module09-exporter-queries.yaml')
 override=root/'config/module09-monitoring.override.yaml'
 shutil.copyfile(source/'module09-monitoring.override.yaml',override)
 dashboard=json.loads((source/'module09-grafana-import.json').read_text());dashboard['uid']='claimsure-module09'
 destination=root/'config/grafana/dashboards/claimsure-module09.json'
 destination.write_text(json.dumps(dashboard,indent=2)+'\n');destination.chmod(0o644)
 command=['docker','compose','-f',str(root/'compose.yaml'),'-f',str(override)]
 r=subprocess.run(command+['config','--quiet'],cwd=root,capture_output=True,text=True)
 if r.returncode:raise RuntimeError('Compose override validation failed; private diagnostics suppressed.')
 for service,container in [('prometheus','claimsure-prometheus'),('grafana','claimsure-grafana')]:
  state=subprocess.run(['docker','inspect','--format','{{.State.Running}}',container],capture_output=True,text=True)
  if state.returncode or state.stdout.strip()!='true':
   subprocess.run(command+['up','-d','--no-deps','--pull','never',service],cwd=root,check=True)
 subprocess.run(command+['up','-d','--no-deps','--pull','never','postgres-exporter'],cwd=root,check=True)
 print('Only exporter recreated. Waiting for scrape/provisioning; PostgreSQL, Prometheus and Grafana data retained.')
 deadline=time.monotonic()+125;last=''
 while time.monotonic()<deadline:
  try:check();break
  except Exception as e:
   last=str(e);print('Waiting:',last,flush=True);time.sleep(5)
 else:raise RuntimeError('Pipeline did not become ready: '+last)
 print('Grafana: http://<server>:'+os.environ.get('GRAFANA_PORT','3000')+'/d/claimsure-module09')

if __name__=='__main__':
 try:main()
 except Exception as e:raise SystemExit('Error: '+str(e))
