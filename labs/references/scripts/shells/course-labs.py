#!/usr/bin/env python3
"""Run, prepare, verify and reset the current student's modules 1-7 and 9."""
import argparse
from datetime import datetime,timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import pwd
import re
import shutil
import subprocess
import sys
import uuid

ROOT=Path(__file__).resolve().parent
MODULES=(1,2,3,4,5,6,7,9)

def cli():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('action',choices=['list','prepare','verify','run','run-all','reset-all'])
 p.add_argument('module',nargs='?',help='module 1..7 or 9; optionally 1.A, 2.H, 3.E, 6.B, 7.logical|physical|snapshot|pitr')
 p.add_argument('--student',default=os.environ.get('STUDENT_NO',pwd.getpwuid(os.getuid()).pw_name))
 p.add_argument('--profile',choices=['teaching','quick'],default='teaching')
 p.add_argument('--dry-run',action='store_true')
 p.add_argument('--yes',action='store_true',help='apply reset-all (otherwise preview)')
 p.add_argument('--preserve-legacy',action='store_true',help='archive and rename an incompatible own insurance schema before creating the course schema')
 p.add_argument('--include-backup',action='store_true',help='also reset the backup DB insurance schema')
 p.add_argument('--skip-monitoring',action='store_true',help='explicit SQL-only mode; does not verify Grafana/scrapes')
 return p.parse_args()

class Course:
 def __init__(self,a):
  self.a=a;sid=re.sub('^student_?','',str(a.student))
  if not re.fullmatch(r'\d{1,2}',sid) or not 1<=int(sid)<=20:raise ValueError('Student number must be 1..20')
  self.sid=f'{int(sid):02d}';actual=pwd.getpwuid(os.getuid()).pw_name
  if re.fullmatch(r'student\d{2}',actual) and actual!='student'+self.sid:raise ValueError('Use your own student account')
  self.role='student_'+self.sid;self.db='claimsure_'+self.sid;self.backup='claimsure_backup_'+self.sid
  self.host=os.environ.get('LAB_DB_HOST','127.0.0.1');self.port=os.environ.get('COURSE_DB_PORT','5432')
  self.work=Path.home()/'labs/course';self.report=None
  self.stamp=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')+'-'+uuid.uuid4().hex[:6]
  self.env=dict(os.environ,STUDENT_NO=self.sid,LAB_DB_HOST=self.host,LAB_DB_PORT=self.port,
   M6_DB_PORT=self.port,M7_DB_PORT=self.port,M9_DB_PORT=self.port,PGAPPNAME='course_'+self.sid,PGCONNECT_TIMEOUT='8')
  for key in ('PGSERVICE','PGSERVICEFILE'):self.env.pop(key,None)
  self.conn=['psql','-X','--no-password','-v','ON_ERROR_STOP=1','-P','pager=off','-h',self.host,'-p',self.port,'-U',self.role]
  self.quick=a.profile=='quick';self.results=[]
 def setup_report(self):
  if self.work.is_symlink():raise RuntimeError('Course workspace cannot be a symlink')
  if self.work.exists():
   marker=self.work/'.course'
   if marker.is_symlink() or not marker.is_file() or marker.read_text().strip()!=f'{os.getuid()}:{self.sid}':raise RuntimeError('Foreign/unmarked course workspace')
  else:
   self.work.mkdir(mode=0o700,parents=True);(self.work/'.course').write_text(f'{os.getuid()}:{self.sid}\n')
  self.report=self.work/self.stamp;self.report.mkdir(mode=0o700)
 def sql(self,text,db=None,quiet=False,variables=None):
  command=self.conn+['-d',db or self.db]
  for k,v in (variables or {}).items():command+=['-v',f'{k}={v}']
  if quiet:command+=['-At']
  else:print('+ '+' '.join(command),flush=True)
  r=subprocess.run(command,input=text,text=True,capture_output=True,env=self.env,timeout=180)
  if not quiet and r.stdout:print(r.stdout.rstrip(),flush=True)
  if not quiet and r.returncode==0 and r.stderr:print(r.stderr.rstrip(),file=sys.stderr,flush=True)
  if r.returncode:raise RuntimeError(r.stderr.strip())
  return r.stdout.strip()
 def script(self,name,*args,label=None):
  command=[str(ROOT/name),*map(str,args)]
  print('+ '+' '.join(command),flush=True)
  # Keep streaming long native/PITR/autovacuum steps and retain their evidence.
  logpath=self.report/((label or name.replace('.sh','')+'-'+uuid.uuid4().hex[:6])+'.log')
  with logpath.open('w') as log:
   p=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,env=self.env)
   for line in p.stdout:print(line,end='',flush=True);log.write(line)
   if p.wait():raise RuntimeError(f'{name} failed; see {log.name}')
 def identity(self,db):
  out=self.sql("SELECT session_user=current_user AND current_user="+lit(self.role)+" AND current_database()="+lit(db)+" AND pg_get_userbyid(datdba)="+lit(self.role)+" AND NOT (SELECT rolsuper FROM pg_roles WHERE rolname=current_user) FROM pg_database WHERE datname=current_database();",db,True)
  if out!='t':raise RuntimeError('Database/login/owner mismatch: '+db)
 def assets(self):
  required=['course-module01.sql','course-module02.sql','course-module03.sql','course-module04.sql','course-module05.sql','course-reset.sql','course-fixtures.sql',
   'run-lab06.sh','run-lab07.sh','module07-shared-tutorial.sh','module07-claimsure-snapshot-tutorial.sh','module07-claimsure-pitr-tutorial.sh','module07-cleanup-files.py','run-lab09.sh','module09-lab.py']
  missing=[n for n in required if not (ROOT/n).is_file()]
  if missing:raise RuntimeError('Missing course files: '+', '.join(missing))
  for tool in ('psql','pg_dump','pg_restore','initdb','pg_ctl','pg_basebackup','pg_verifybackup'):
   if not shutil.which(tool,path=self.env.get('PATH')):raise RuntimeError('Missing '+tool+'; instructor must install the existing PostgreSQL 18 runtime')
  version=subprocess.run(['initdb','--version'],env=self.env,capture_output=True,text=True)
  if version.returncode or not re.search(r'\b18\.',version.stdout):raise RuntimeError('PostgreSQL 18 native runtime cannot execute')
 def payload(self,n,section=None):
  text=(ROOT/f'course-module{n:02d}.sql').read_text()
  if n==3 and self.quick:text=text.replace('generate_series(1, 200000)','generate_series(1, 20000)')
  if not section:return text
  matches=list(re.finditer(r"^\\echo '\\n-- Lab "+str(n)+r"([A-Z])[^\n]*$",text,re.M))
  if section not in [m.group(1) for m in matches]:raise ValueError(f'Module {n}: no section {section}')
  m=next(m for m in matches if m.group(1)==section);idx=matches.index(m)
  return text[:matches[0].start()]+text[m.start():matches[idx+1].start() if idx+1<len(matches) else len(text)]
 def foundation(self):
  # Do not replace an existing different insurance model.
  has=self.sql("SELECT to_regnamespace('insurance') IS NOT NULL",quiet=True)=='t'
  existing_tables=[]
  if has:
   owner=self.sql("SELECT pg_get_userbyid(nspowner) FROM pg_namespace WHERE nspname='insurance'",quiet=True)
   if owner!=self.role:raise RuntimeError('insurance belongs to another owner; preserving it')
   required={'customer':{'customer_id','customer_code','full_name','email','created_at'},'policy':{'policy_id','policy_no','customer_id','product_code','starts_on','ends_on','status'},'claim':{'claim_id','claim_no','policy_id','status','incident_at','estimated_amount','approved_amount'}}
   for table,cols in required.items():
    exists=self.sql("SELECT to_regclass('insurance."+table+"') IS NOT NULL",quiet=True)=='t'
    if exists:
     existing_tables.append(table)
     actual=set(self.sql("SELECT column_name FROM information_schema.columns WHERE table_schema='insurance' AND table_name="+lit(table),quiet=True).splitlines())
     if not cols<=actual:
      if self.a.preserve_legacy:self.migrate_legacy();return
      raise RuntimeError('Incompatible insurance.'+table+'; preserved. Use prepare --preserve-legacy to archive/rename it, or review reset-all.')
  # Reuse the course's exact A/B definitions; preserve existing learner rows.
  a=self.payload(1,'A');b=self.payload(1,'B')
  if len(existing_tables)==3:
   seeded=self.sql("SELECT (SELECT count(*) FROM insurance.customer WHERE customer_code IN ('CUS-001','CUS-002','CUS-003'))=3 AND (SELECT count(*) FROM insurance.policy WHERE policy_no IN ('POL-001','POL-002','POL-003'))=3 AND (SELECT count(*) FROM insurance.claim WHERE claim_no IN ('CLM-L1-001','CLM-L1-002','CLM-L1-003','CLM-L1-004','CLM-L1-005','CLM-L1-006'))=6",quiet=True)
   if seeded=='t':b=''

  b=re.sub(r'ON CONFLICT \(([^)]+)\) DO UPDATE\nSET .*?\nRETURNING',r'ON CONFLICT (\1) DO NOTHING\nRETURNING',b,flags=re.S)
  self.sql("BEGIN; SET LOCAL lock_timeout='5s'; SET LOCAL statement_timeout='60s';\n"+a+'\n'+b+'\nCOMMIT;')
 def migrate_legacy(self):
  archive=self.archive_insurance(self.db,'course-migrations')
  saved='insurance_saved_'+re.sub(r'[^a-zA-Z0-9_]','_',self.stamp).lower()
  if len(saved)>63:raise RuntimeError('Generated schema name too long')
  if self.sql('SELECT to_regnamespace('+lit(saved)+') IS NULL',quiet=True)!='t':raise RuntimeError('Saved schema already exists')
  old_count=self.sql("SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='insurance' AND c.relkind IN ('r','p')",quiet=True)
  payload="BEGIN; SET LOCAL lock_timeout='5s'; SET LOCAL statement_timeout='60s'; ALTER SCHEMA insurance RENAME TO \""+saved+"\";\n"+self.payload(1,'A')+'\n'+self.payload(1,'B')+'\nCOMMIT;'
  self.sql(payload)
  new_count=self.sql("SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname="+lit(saved)+" AND c.relkind IN ('r','p')",quiet=True)
  if old_count!=new_count:raise RuntimeError('Saved schema relation count changed; inspect migration before continuing')
  record={'database':self.db,'saved_schema':saved,'tables_preserved':int(old_count),'archive':archive,'course_schema':'insurance','time':self.stamp}
  with (self.work/'migrations.jsonl').open('a') as f:f.write(json.dumps(record)+'\n')
  (self.report/'migration.json').write_text(json.dumps(record,indent=2)+'\n')
  held='insurance_course_hold_'+re.sub(r'[^a-zA-Z0-9_]','_',self.stamp).lower()
  restore_commands=[r"\set ON_ERROR_STOP on","BEGIN;","SET LOCAL lock_timeout='5s';",'ALTER SCHEMA insurance RENAME TO "'+held+'";','ALTER SCHEMA "'+saved+'" RENAME TO insurance;','COMMIT;']
  (self.report/'restore-legacy.sql').write_text("\n".join(restore_commands)+"\n")

  print('LEGACY PRESERVED:',saved,'archive:',archive,flush=True)
 def prepare(self):
  self.assets();self.identity(self.db);self.identity(self.backup);self.foundation()
  self.sql((ROOT/'course-fixtures.sql').read_text())
  args=['setup']+(['--rows','10000'] if self.quick else [])
  self.script('run-lab06.sh',*args)
  if self.sql("SELECT to_regclass('lab_m7_practice.claim_event') IS NULL",quiet=True)=='t':self.script('run-lab07.sh','seed','main')
  if self.sql("SELECT to_regclass('lab_m9_shell.module_identity') IS NULL",quiet=True)=='t':
   self.script('run-lab09.sh','init-all',*(['--skip-pipeline'] if self.a.skip_monitoring else []))
  return self.verify()
 def verify(self):
  self.assets();self.identity(self.db);self.identity(self.backup)
  if int(self.sql("SHOW server_version_num",quiet=True))//10000!=18:raise RuntimeError('This course/runtime targets PostgreSQL 18')
  # This is a prerequisite/readiness audit, not execution of every exercise.
  required={'customer':['customer_id','customer_code','full_name'],'policy':['policy_no','customer_id','product_code'],'claim':['claim_no','policy_id','estimated_amount','approved_amount','incident_at']}
  for table,cols in required.items():
   actual=set(self.sql("SELECT column_name FROM information_schema.columns WHERE table_schema='insurance' AND table_name="+lit(table),quiet=True).splitlines())
   if not set(cols)<=actual:raise RuntimeError('Prepare required for course insurance.'+table)
  seeds=int(self.sql("SELECT count(*) FROM insurance.claim WHERE claim_no IN ('CLM-L1-001','CLM-L1-002','CLM-L1-003','CLM-L1-004','CLM-L1-005','CLM-L1-006')",quiet=True))
  if seeds!=6:raise RuntimeError('Module 1 seed rows missing; run prepare (inserts only missing seeds)')
  leaks=self.sql("SELECT string_agg(datname,',') FROM pg_database WHERE datname~'^claimsure(_backup)?_[0-9]{2}$' AND datname NOT IN ("+lit(self.db)+','+lit(self.backup)+") AND has_database_privilege(current_user,oid,'CONNECT')",quiet=True)
  if leaks:raise RuntimeError('Cross-student CONNECT privilege found: '+leaks)

  if self.sql("SELECT rolcreaterole AND NOT rolsuper AND NOT rolbypassrls FROM pg_roles WHERE rolname=current_user",quiet=True)!='t':raise RuntimeError('Module 4 requires the existing classroom CREATEROLE capability, not superuser')
  if self.sql("SELECT count(*) FROM pg_roles WHERE rolname IN ('course_m4_reader_"+self.sid+"','course_m4_actor_"+self.sid+"')",quiet=True)!='0':raise RuntimeError('Reserved Module 4 role names already exist; preserving them')
  for schema in ('lab_m4_shell','lab_m5_shell','lab_m6_shell','lab_m7_practice','lab_m9_shell'):
   if self.sql("SELECT to_regnamespace("+lit(schema)+") IS NOT NULL",quiet=True)!='t':raise RuntimeError('Prepare required: '+schema)
  if self.sql("SELECT EXISTS(SELECT FROM pg_extension WHERE extname='pg_stat_statements')",quiet=True)!='t':raise RuntimeError('Module 9 extension missing; instructor monitoring init required')
  if not self.a.skip_monitoring:self.script('run-lab09.sh','doctor')
  checks={str(n):{'ready':True} for n in MODULES}
  checks['4']['evidence']='per-student role names available; CREATEROLE, non-superuser'
  checks['5']['evidence']='own architecture fixtures; no original superuser-only SQL'
  checks['7']['evidence']='PostgreSQL 18 native/verification tools and owned main+backup databases'
  checks['9']['monitoring']='SQL only; pipeline skipped explicitly' if self.a.skip_monitoring else 'own exporter connection healthy'
  result={'student':self.sid,'database':self.db,'mode':'readiness','modules':checks,'ready':True,'full_execution':False}
  (self.report/'readiness.json').write_text(json.dumps(result,indent=2)+'\n')
  print('READINESS PASS for modules 1–7 and 9 (not a full execution claim).',flush=True)
  return result
 def mvcc(self):
  spec=importlib.util.spec_from_file_location('course_m9_client',ROOT/'module09-lab.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
  adapter=type('Adapter',(),{'conn':self.conn+['-d',self.db],'env':lambda obj,app:dict(self.env,PGAPPNAME=app)})()
  a=m.Client(adapter,'course05_'+self.sid+'_snapshot')
  before=self.sql('SELECT status FROM lab_m5_shell.claim WHERE id=1',quiet=True)
  new='REVIEW' if before!='REVIEW' else 'NEW'
  try:
   a.command('BEGIN ISOLATION LEVEL REPEATABLE READ; SELECT status FROM lab_m5_shell.claim WHERE id=1;')
   if a.last[-1]!=before:raise RuntimeError('MVCC first snapshot mismatch')
   self.sql('UPDATE lab_m5_shell.claim SET status='+lit(new)+' WHERE id=1;')
   a.command('SELECT status FROM lab_m5_shell.claim WHERE id=1;')
   if a.last[-1]!=before:raise RuntimeError('Repeatable-read snapshot changed before commit')
   a.command('COMMIT; SELECT status FROM lab_m5_shell.claim WHERE id=1;')
   if a.last[-1]!=new:raise RuntimeError('MVCC fresh snapshot did not see committed update')
   print('PASS Module 5E: same snapshot retained original; new snapshot saw the committed version.',flush=True)
  finally:a.close();self.sql('UPDATE lab_m5_shell.claim SET status='+lit(before)+' WHERE id=1;')
 def run7(self,section=None):
  actions=[section] if section else ['logical','physical','snapshot','pitr']
  for action in actions:
   if action=='logical':self.script('module07-shared-tutorial.sh','--database','main')
   elif action=='physical':
    work=Path(self.env.get('M7_WORKDIR',str(Path.home()/'m7')))
    if work.exists():self.script('run-lab07.sh','stop');self.script('run-lab07.sh','sandbox-start')
    else:self.script('run-lab07.sh','sandbox-init')
    self.script('run-lab07.sh','seed','sandbox','--reset-practice')
    dest=Path(self.env.get('M7_BACKUP_DIR',str(Path.home()/'backups/module07')))/('course-physical-'+self.stamp)
    self.script('run-lab07.sh','physical-backup',dest)
    self.script('run-lab07.sh','damage','sandbox')
    self.script('run-lab07.sh','physical-restore',dest,'auto')
    conn=['psql','-XAt','--no-password','-h',str(work/'sock'),'-p',str(5800+int(self.sid)),'-U','labadmin','-d','m7_'+self.sid]
    r=subprocess.run(conn+['-c',"SELECT string_agg(event_id::text,',' ORDER BY event_id) FROM lab_m7_practice.claim_event"],env=self.env,text=True,capture_output=True)
    if r.returncode or r.stdout.strip()!='1,2':raise RuntimeError('Physical restore did not recover rows 1,2')
    self.script('run-lab07.sh','stop')
   elif action=='snapshot':self.script('module07-claimsure-snapshot-tutorial.sh','--database','main')
   elif action=='pitr':self.script('module07-claimsure-pitr-tutorial.sh','--database','main')
   else:raise ValueError('Module 7 sections: logical, physical, snapshot, pitr')
  self.script('run-lab07.sh','stop')
 def run_module(self,spec):
  parts=str(spec).split('.',1);n=int(parts[0]);section=parts[1] if len(parts)==2 else None
  if n not in MODULES:raise ValueError('Modules requested: 1–7 and 9; 8/10 are excluded')
  if section and n in (4,5):raise ValueError('Modules 4/5 are integrated student proofs; select run 4 or run 5')
  print('\n========== COURSE MODULE '+str(n)+(('.'+section) if section else '')+' ==========\n',flush=True)
  self.identity(self.db)
  if n in (1,2,3):self.sql(self.payload(n,section.upper() if section else None))
  elif n==4:
   self.sql((ROOT/'course-fixtures.sql').read_text());self.sql((ROOT/'course-module04.sql').read_text())
  elif n==5:
   self.sql((ROOT/'course-fixtures.sql').read_text());self.sql((ROOT/'course-module05.sql').read_text(),variables={'run_id':self.stamp});self.mvcc()
  elif n==6:
   args=[section.upper() if section else 'all']
   if self.quick:args+=['--rows','10000','--repeat','1','--wait','0','--wal-rows','30000']
   self.script('run-lab06.sh',*args)
  elif n==7:self.run7(section)
  elif n==9:
   if section:raise ValueError('Use run-lab09.sh for individual monitoring actions; run 9 runs the complete drill')
   self.script('run-lab09.sh','all','--seconds','5' if self.quick else '120',*(['--skip-pipeline'] if self.a.skip_monitoring else []))
  self.results.append({'module':n,'section':section,'status':'passed','profile':self.a.profile})
  (self.report/'execution.json').write_text(json.dumps(self.results,indent=2)+'\n')
 def preflight_schemas(self):
  names=['insurance','lab_m4_shell','lab_m5_shell','lab_m6_shell','lab_m7_practice','lab_m9_shell']
  for db in [self.db]+([self.backup] if self.a.include_backup else []):
   self.identity(db)
   foreign=self.sql("SELECT string_agg(nspname,',') FROM pg_namespace WHERE nspname=ANY(ARRAY["+','.join(lit(n) for n in names)+"]) AND nspowner<>(SELECT oid FROM pg_roles WHERE rolname=current_user)",db,True)
   if foreign:raise RuntimeError('Reset refuses schemas owned by another role: '+foreign)
  for schema,table,marker in [('lab_m4_shell','course_identity','course-m4-v1'),('lab_m5_shell','course_identity','course-m5-v1'),('lab_m6_shell','module_identity','module06-shell-v1')]:
   if self.sql('SELECT to_regnamespace('+lit(schema)+') IS NOT NULL',quiet=True)=='t':
    if self.sql('SELECT to_regclass('+lit(schema+'.'+table)+') IS NOT NULL',quiet=True)!='t':raise RuntimeError('Reset refuses unmarked '+schema)
    if self.sql('SELECT identity FROM '+schema+'.'+table+' WHERE id=1',quiet=True)!=marker:raise RuntimeError('Reset refuses invalid '+schema+' marker')

 def archive_insurance(self,db,family='course-resets'):
  if self.sql("SELECT to_regnamespace('insurance') IS NOT NULL",db,True)!='t':return
  directory=Path.home()/'backups'/family/self.stamp
  for path in [Path.home()/'backups',Path.home()/'backups'/family,directory]:
   if path.is_symlink():raise RuntimeError('Backup path must not be a symlink')
  directory.mkdir(mode=0o700,parents=True,exist_ok=True)
  dest=directory/(db+'.dump')
  if dest.exists():raise RuntimeError('Refusing backup overwrite')
  command=['pg_dump','--no-password','-h',self.host,'-p',self.port,'-U',self.role,'-d',db,'--format=custom','--schema=insurance','--file='+str(dest)]
  subprocess.run(command,env=self.env,check=True)
  subprocess.run(['pg_restore','--list',str(dest)],env=self.env,stdout=subprocess.DEVNULL,check=True)
  dest.with_suffix('.dump.sha256').write_text(hashlib.sha256(dest.read_bytes()).hexdigest()+'  '+dest.name+'\n')
  print('Insurance archive saved before change:',dest,flush=True)
  return str(dest)
 def reset(self):
  self.preflight_schemas()
  self.archive_insurance(self.db)
  if self.a.include_backup:self.archive_insurance(self.backup)
  reset=(ROOT/'course-reset.sql').read_text()
  backup_reset=reset[:reset.index('DROP TABLE IF EXISTS lab_m4_shell') ]
  # Dependency validation is rollback-only, performed only after --yes, before
  # invoking irreversible file cleanup. Plain --dry-run sends no reset SQL.
  self.sql(reset,variables={'preflight':'true'})
  if self.a.include_backup:self.sql(backup_reset+'ROLLBACK;',self.backup)
  self.script('run-lab09.sh','reset-all',*(['--skip-pipeline'] if self.a.skip_monitoring else []))
  self.script('run-lab06.sh','reset')
  self.script('module07-cleanup.sh','--yes')
  self.sql(reset,variables={'preflight':'false'})
  if self.a.include_backup:
   # Only shared insurance in the backup DB, not main-only Module 4/5/6.
   self.sql(backup_reset+'COMMIT;',self.backup)
  private=Path(self.env.get('M6_WORKDIR',str(Path.home()/'m6')))
  if private.exists():
   marker=private/'.module06'
   if private.is_symlink() or Path.home().resolve() not in private.resolve().parents or not marker.is_file() or marker.read_text().strip()!=f'{os.getuid()}:{self.sid}':raise RuntimeError('Private Module 6 directory marker mismatch; retained')
   if next(private.rglob('postmaster.pid'),None):raise RuntimeError('Private PID file remains; directory retained')
   shutil.rmtree(private)
  print('RESET COMPLETE. Course insurance archive and evidence retained. Run prepare before the next class.',flush=True)

def lit(value):return "'"+str(value).replace("'","''")+"'"

class Tee:
 def __init__(self,*streams):self.streams=streams
 def write(self,s):
  for x in self.streams:x.write(s);x.flush()
 def flush(self):
  for x in self.streams:x.flush()

def main():
 os.umask(0o077);a=cli();c=Course(a)
 if a.action=='list':
  print('Modules: 1 basic SQL; 2 advanced SQL; 3 performance; 4 security; 5 architecture; 6 configuration; 7 backup/recovery; 9 Grafana monitoring.\nProfiles: teaching = full measurements; quick = bounded smoke workflow, not a tuning/autovacuum/scrape benchmark.');return
 if a.module and a.action!='run':raise ValueError('A module/section is only accepted with run')
 if a.action=='run' and not a.module:raise ValueError('Use run MODULE, e.g. run 1, run 2.H, run 7.pitr')
 if a.dry_run or (a.action=='reset-all' and not a.yes):
  print(f'PREVIEW: {a.action} {a.module or ""} | student={c.sid} | {c.db}:{c.port} | profile={a.profile}')
  if a.action=='reset-all':print('Scope: course insurance (modules 1–3), own module 4/5/6 fixtures, module 7 practice/private clusters/backups, module 9 tagged jobs/fixtures. Backup insurance is '+('included' if a.include_backup else 'preserved')+'.\nInsurance is archived first under ~/backups/course-resets. Reports, monitoring history, credentials, modules 8/10 and unknown objects are preserved. Add --yes to apply.')
  print('No changes. Readiness is checked by verify; execution is explicitly run/run-all.');return
 c.setup_report()
 import fcntl
 with (c.work/'.lock').open('w') as lock:
  try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
  except BlockingIOError:raise RuntimeError('Another course control action is running')
  with (c.report/'transcript.log').open('w') as out:
   oldout,olderr=sys.stdout,sys.stderr;sys.stdout=Tee(oldout,out);sys.stderr=Tee(olderr,out)
   try:
    if a.action=='prepare':c.prepare()
    elif a.action=='verify':c.verify()
    elif a.action=='reset-all':c.reset()
    elif a.action=='run':c.assets();c.run_module(a.module)
    elif a.action=='run-all':
     c.verify()
     for n in MODULES:c.run_module(n)
    print('Course evidence:',c.report,flush=True)
   except Exception as e:
    (c.report/'failure.json').write_text(json.dumps({'action':a.action,'module':a.module,'error':str(e),'completed':c.results},indent=2)+'\n')
    raise
   finally:sys.stdout,sys.stderr=oldout,olderr

if __name__=='__main__':
 try:main()
 except Exception as e:print('Error:',str(e),file=sys.stderr);sys.exit(1)
