#!/usr/bin/env python3
"""Bounded PostgreSQL monitoring exercises, isolated by role/database/app tag."""
import argparse
import csv
from datetime import datetime, timezone
import getpass
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
import urllib.parse
import urllib.request
import uuid

ROOT=Path(__file__).resolve().parent

def parser():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('action',choices=['doctor','init-all','workload-start','blocking-start','blocking-stop','deadlock','observe','snapshot','status','stop','reset-all','all','_worker'])
 p.add_argument('--student',default=os.environ.get('STUDENT_NO',getpass.getuser()))
 p.add_argument('--seconds',type=int,default=120,help='bounded workload/blocking duration, 5..300 seconds')
 p.add_argument('--workers',type=int,default=2,help='1..3 persistent workload clients')
 p.add_argument('--rows',type=int,default=20000,help='1000..100000 disposable workload rows')
 p.add_argument('--dry-run',action='store_true')
 p.add_argument('--skip-pipeline',action='store_true',help='SQL-only lab/testing without a monitoring stack')
 p.add_argument('--kind',choices=['workload','blocker','waiter','deadlock-a','deadlock-b'],help=argparse.SUPPRESS)
 p.add_argument('--token',help=argparse.SUPPRESS)
 p.add_argument('--barrier',help=argparse.SUPPRESS)
 return p

class Lab:
 def __init__(self,a):
  self.a=a
  sid=re.sub(r'^student_?','',str(a.student))
  if not re.fullmatch(r'\d{1,2}',sid) or not 1<=int(sid)<=20: raise ValueError('Use your student account or --student 1..20')
  self.sid=f'{int(sid):02d}'
  actual=getpass.getuser()
  if re.fullmatch(r'student\d{2}',actual) and actual!='student'+self.sid: raise ValueError('Use your own student number')
  if not 5<=a.seconds<=300 or not 1<=a.workers<=3 or not 1000<=a.rows<=100000: raise ValueError('Options outside allowed ranges; use --help')
  self.db='claimsure_'+self.sid;self.role='student_'+self.sid
  self.prefix='module09_'+self.sid+'_'
  self.work=Path(os.environ.get('M9_WORKDIR',str(Path.home()/'labs/module09')))
  self.host=os.environ.get('LAB_DB_HOST','127.0.0.1');self.port=os.environ.get('M9_DB_PORT','5432')
  self.prom=os.environ.get('M9_PROM_URL','http://127.0.0.1:9090').rstrip('/')
  self.conn=['psql','-X','--no-password','-v','ON_ERROR_STOP=1','-P','pager=off','-h',self.host,'-p',self.port,'-U',self.role,'-d',self.db]
  self.report=None
 def env(self,app=None):
  e=dict(os.environ);e['PGAPPNAME']=app or self.prefix+'observer'
  return e
 def prepare(self):
  home=Path.home().resolve()
  if not self.work.is_absolute() or self.work.is_symlink() or home not in self.work.resolve().parents: raise ValueError('M9_WORKDIR must be a dedicated real directory under your home')
  if self.work.exists():
   if not self.work.is_dir() or self.work.stat().st_uid!=os.getuid(): raise ValueError('Workspace not owned by this student')
   marker=self.work/'.module09'
   if marker.is_symlink() or not marker.is_file() or marker.read_text().strip()!=f'{os.getuid()}:{self.sid}': raise ValueError('Missing/mismatched Module 9 workspace marker')
  else:
   self.work.mkdir(mode=0o700,parents=True)
   (self.work/'.module09').write_text(f'{os.getuid()}:{self.sid}\n')
  (self.work/'jobs').mkdir(mode=0o700,exist_ok=True)
  stamp=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')+'-'+str(os.getpid())
  self.report=self.work/'reports'/stamp;self.report.mkdir(mode=0o700,parents=True)
 def sql(self,sql,quiet=False):
  if not quiet: print('+ psql -h HOST -p PORT -U OWN_STUDENT -d OWN_DB\n'+sql,flush=True)
  r=subprocess.run(self.conn+['-At'],input=sql,text=True,capture_output=True,env=self.env())
  if r.returncode: raise RuntimeError(r.stderr.strip())
  if not quiet and r.stdout: print(r.stdout.rstrip(),flush=True)
  return r.stdout.strip()
 def sqlfile(self,name,output=None):
  path=ROOT/f'module09-{name}.sql'
  print('+ '+' '.join(self.conn)+f' -v rows={self.a.rows} -f {path}',flush=True)
  command=self.conn+['-v',f'rows={self.a.rows}','-f',str(path)]
  if output and Path(output).suffix=='.csv':command.insert(1,'--csv')
  r=subprocess.run(command,text=True,capture_output=True,env=self.env())
  if output:Path(output).write_text(r.stdout)
  if r.stdout:print(r.stdout.rstrip(),flush=True)
  if r.returncode:raise RuntimeError(r.stderr.strip())
 def initialized(self):
  if self.sql("SELECT to_regclass('lab_m9_shell.module_identity') IS NOT NULL",True)!='t': raise RuntimeError('Run init-all first')
 def pipeline(self):
  results={}
  for metric in ('up','pg_up','pg_exporter_last_scrape_error'):
   query=f'{metric}{{job="postgres",instance="postgres:5432/{self.db}"}}'
   url=self.prom+'/api/v1/query?'+urllib.parse.urlencode({'query':query})
   data=json.load(urllib.request.urlopen(url,timeout=15))
   series=data.get('data',{}).get('result',[])
   results[metric]=float(series[0]['value'][1]) if series else None
  print('Pipeline:',json.dumps(results),flush=True)
  if results!={'up':1.0,'pg_up':1.0,'pg_exporter_last_scrape_error':0.0}: raise RuntimeError('Pipeline not healthy. Instructor: module09-stack.sh init-all; allow two 30s scrapes.')
  return results
 def doctor(self):
  self.sql("SELECT current_database(),current_user,current_setting('port'),version(); SELECT extname FROM pg_extension WHERE extname='pg_stat_statements';")
  if self.sql("SELECT EXISTS(SELECT FROM pg_extension WHERE extname='pg_stat_statements')",True)!='t':raise RuntimeError('Instructor must enable the preloaded pg_stat_statements extension in this DB')
  if not self.a.skip_pipeline:self.pipeline()
 def ready_file(self,token):return self.work/'jobs'/f'{token}.json'
 def jobs(self):
  result=[]
  for p in sorted((self.work/'jobs').glob('*.json')):
   try:result.append((p,json.loads(p.read_text())))
   except (ValueError,OSError):continue
  return result
 def start(self,kind,seconds=None,barrier=None):
  self.initialized()
  active=[j for _,j in self.jobs() if j.get('status')=='ready' and alive(j)]
  if len(active)>=5:raise RuntimeError('Five Module 9 jobs already active; run stop before starting more (role has a finite connection limit)')
  token=self.prefix+kind.replace('-','')+'_'+uuid.uuid4().hex[:8]
  command=[sys.executable,str(ROOT/'module09-lab.py'),'_worker','--student',self.sid,'--kind',kind,'--token',token,'--seconds',str(seconds or self.a.seconds)]
  if barrier:command+=['--barrier',str(barrier)]
  log=self.work/'jobs'/f'{token}.log'
  with log.open('w') as f:subprocess.Popen(command,stdout=f,stderr=subprocess.STDOUT,stdin=subprocess.DEVNULL,env=self.env(token),start_new_session=True)
  deadline=time.monotonic()+12
  while time.monotonic()<deadline:
   p=self.ready_file(token)
   if p.exists():
    state=json.loads(p.read_text())
    if state['status']=='ready':print('Started',kind,'backend',state.get('backend_pid'),'log',log,flush=True);return token
    if state['status']=='failed':raise RuntimeError(f'{kind} failed; see {log}')
   time.sleep(.1)
  raise RuntimeError(f'Worker did not become ready; see {log}')
 def stop(self,kinds=None):
  jobs=[j for _,j in self.jobs() if kinds is None or j.get('kind') in kinds]
  for j in jobs:
   if alive(j):os.kill(j['pid'],signal.SIGTERM)
  deadline=time.monotonic()+5
  while time.monotonic()<deadline and any(alive(j) for j in jobs):time.sleep(.1)
  for j in jobs:
   if alive(j):os.kill(j['pid'],signal.SIGKILL)
  # Explicit reset runbook: only this student's tagged lab backends, never a
  # production/insurance session or a different student's database.
  kinds_sql=''
  if kinds:
   kinds_sql=' AND ('+' OR '.join("starts_with(application_name,'"+self.prefix+k.replace('-','')+"_')" for k in kinds)+')'
  self.sql("SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename=current_user AND datname=current_database() AND starts_with(application_name,'"+self.prefix+"') AND pid<>pg_backend_pid()"+kinds_sql+';',True)
  print('Stopped own tagged Module 9 jobs'+(' '+','.join(kinds) if kinds else '')+'.',flush=True)
 def deadlock(self):
  self.stop(['blocker','waiter'])
  barrier=self.work/'jobs'/('go-'+uuid.uuid4().hex)
  tokens=[self.start('deadlock-a',seconds=15,barrier=barrier),self.start('deadlock-b',seconds=15,barrier=barrier)]
  barrier.write_text('go\n')
  deadline=time.monotonic()+20
  states=[]
  while time.monotonic()<deadline:
   states=[json.loads(self.ready_file(t).read_text()) for t in tokens]
   if all(s['status'] in ('finished','failed') for s in states):break
   time.sleep(.1)
  codes=[s.get('sqlstate') for s in states]
  (self.report/'deadlock.json').write_text(json.dumps(states,indent=2))
  print('Deadlock SQLSTATEs:',codes,flush=True)
  if sorted(codes,key=str)!=['00000','40P01']:raise RuntimeError('Expected one 40P01 victim and one successful counterpart; see worker logs')
 def observe(self):self.sqlfile('observe',self.report/'evidence.txt')
 def run(self):
  a=self.a.action
  if a=='doctor':self.doctor();return
  if a=='init-all':
   self.stop();self.sqlfile('init');self.observe()
   if not self.a.skip_pipeline:self.pipeline()
  elif a=='workload-start':
   self.initialized()
   for _ in range(self.a.workers):self.start('workload')
  elif a=='blocking-start':
   self.stop(['blocker','waiter']);self.start('blocker');self.start('waiter')
   deadline=time.monotonic()+6
   while time.monotonic()<deadline:
    if int(self.sql("SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND usename=current_user AND application_name LIKE '"+self.prefix+"waiter_%' AND cardinality(pg_blocking_pids(pid))>0",True))>0:break
    time.sleep(.1)
   else:raise RuntimeError('Waiter did not become blocked; inspect jobs')
   self.observe()
  elif a=='blocking-stop':self.stop(['blocker','waiter']);self.observe()
  elif a=='deadlock':self.deadlock();self.observe()
  elif a in ('observe','snapshot'):self.observe()
  elif a=='status':
   for _,j in self.jobs():print(j.get('kind'),j.get('status'),'alive='+str(alive(j)),j.get('backend_pid'),flush=True)
   self.observe()
  elif a=='stop':self.stop();self.observe()
  elif a=='reset-all':self.stop();self.sqlfile('reset')
  elif a=='all':
   self.stop();self.sqlfile('init')
   if not self.a.skip_pipeline:self.pipeline()
   for _ in range(self.a.workers):self.start('workload')
   self.start('blocker');self.start('waiter');self.observe()
   for elapsed in range(self.a.seconds):
    if elapsed%15==0:print(f'Grafana observation window: {elapsed}/{self.a.seconds}s',flush=True)
    time.sleep(1)
   self.stop(['blocker','waiter']);self.deadlock();self.stop();self.observe()
   print('Drill complete; fixtures and evidence retained. Use reset-all to remove the lab fixtures.',flush=True)

def proc_start(pid):
 try:return Path(f'/proc/{pid}/stat').read_text().rsplit(')',1)[1].split()[19]
 except (OSError,IndexError):return None

def alive(j):
 pid=j.get('pid')
 if not isinstance(pid,int) or pid<=1 or not j.get('process_start') or proc_start(pid)!=j['process_start']:return False
 try:
  p=Path(f'/proc/{pid}')
  cmd=(p/'cmdline').read_bytes().split(b'\0')
  return p.stat().st_uid==os.getuid() and str(ROOT/'module09-lab.py').encode() in cmd and j.get('token','').encode() in cmd
 except OSError:return False

class Client:
 def __init__(self,lab,app):
  self.p=subprocess.Popen(lab.conn+['-qAt'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,bufsize=1,env=lab.env(app))
  self.sqlstate=None
  self.command('\\set VERBOSITY verbose\nSELECT pg_backend_pid();')
  self.backend_pid=next(int(x) for x in self.last if x.isdigit())
 def command(self,sql):
  marker='__M9_DONE_'+uuid.uuid4().hex
  self.last=[]
  self.p.stdin.write(sql+'\n\\echo '+marker+'\n');self.p.stdin.flush()
  for line in self.p.stdout:
   line=line.rstrip('\n')
   if line==marker:return self.last
   print(line,flush=True);self.last.append(line)
   if line.startswith('__M9_STATE '):self.sqlstate=line.split()[-1]
  raise RuntimeError('Lab database client disconnected (stop/reset may have requested it)')
 def close(self):
  try:
   if self.p.poll() is None:
    self.p.stdin.write('ROLLBACK;\n\\q\n');self.p.stdin.flush();self.p.stdin.close()
    self.p.wait(timeout=3)
  except (OSError,subprocess.TimeoutExpired):
   self.p.terminate()
   try:self.p.wait(timeout=2)
   except subprocess.TimeoutExpired:self.p.kill();self.p.wait()

class Tee:
 def __init__(self,*files):self.files=files
 def write(self,text):
  for f in self.files:f.write(text);f.flush()
 def flush(self):
  for f in self.files:f.flush()

def worker(lab):
 a=lab.a
 if not a.kind or not a.token or not re.fullmatch(lab.prefix+r'[a-z]+_[a-f0-9]{8}',a.token):raise ValueError('Invalid internal job token')
 lab.prepare()
 path=lab.ready_file(a.token)
 state=dict(token=a.token,kind=a.kind,pid=os.getpid(),process_start=proc_start(os.getpid()),status='starting',backend_pid=None,sqlstate=None)
 def save():
  tmp=path.with_suffix('.tmp');tmp.write_text(json.dumps(state));tmp.replace(path)
 stop=False;c=None
 def cancel(signum,frame):
  nonlocal stop
  stop=True
  if c and c.p.poll() is None:c.p.terminate()
 signal.signal(signal.SIGTERM,cancel);signal.signal(signal.SIGINT,cancel)
 save()
 try:
  c=Client(lab,a.token);state['backend_pid']=c.backend_pid
  c.command(f"SET statement_timeout='{a.seconds+15}s'; SET lock_timeout='{a.seconds+10}s'; SET idle_in_transaction_session_timeout='{a.seconds+15}s';")
  deadline=time.monotonic()+a.seconds
  if a.kind=='workload':
   state['status']='ready';save();i=0
   while not stop and time.monotonic()<deadline:
    i+=1
    c.command(f"BEGIN; SELECT sum(amount) FROM lab_m9_shell.workload WHERE bucket={i%100}; UPDATE lab_m9_shell.queue SET touches=touches+1 WHERE id BETWEEN {1+i%900} AND {10+i%900}; SELECT pg_sleep(.2); COMMIT;")
  elif a.kind in ('blocker','deadlock-a','deadlock-b'):
   row=2 if a.kind=='deadlock-b' else 1
   c.command(f"BEGIN; UPDATE lab_m9_shell.lock_demo SET note='held by Module 9' WHERE id={row};")
   state['status']='ready';save()
   if a.kind=='blocker':
    while not stop and time.monotonic()<deadline:
     time.sleep(.5);c.command('SELECT 1;')
    if not stop:c.command('ROLLBACK;')
   else:
    barrier=Path(a.barrier or '')
    if barrier.parent!=lab.work/'jobs':raise ValueError('Invalid deadlock barrier')
    while not stop and not barrier.exists() and time.monotonic()<deadline:time.sleep(.05)
    if not barrier.exists():raise RuntimeError('Deadlock barrier timed out')
    c.command(f"\\set ON_ERROR_STOP off\nUPDATE lab_m9_shell.lock_demo SET note='opposite lock order' WHERE id={3-row};\n\\echo __M9_STATE :SQLSTATE\n\\set ON_ERROR_STOP on\nROLLBACK;")
    state['sqlstate']=c.sqlstate
  elif a.kind=='waiter':
   state['status']='ready';save()
   c.command("BEGIN; UPDATE lab_m9_shell.lock_demo SET note='waiter completed' WHERE id=1; ROLLBACK;")
  state['status']='finished'
 except Exception as e:
  state['status']='stopped' if stop else 'failed';state['error']=str(e);print(str(e),flush=True)
 finally:
  if c:c.close()
  state['sqlstate']=state.get('sqlstate') or (c.sqlstate if c else None)
  save()
 return 0 if state['status'] in ('finished','stopped') else 1

def main():
 os.umask(0o077)
 a=parser().parse_args();lab=Lab(a)
 if a.dry_run:
  print(f'PREVIEW: {a.action}; role={lab.role}; database={lab.db}; direct port={lab.port}; workspace={lab.work}')
  print('Only tagged Module 9 sessions and lab_m9_shell fixtures are managed. No global statistics reset, dashboard deletion or history purge.')
  return 0
 if a.action=='_worker':return worker(lab)
 lab.prepare()
 # Serialize control actions; workers close inherited FDs at Popen defaults.
 import fcntl
 with (lab.work/'.control.lock').open('w') as lock:
  try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
  except BlockingIOError:raise RuntimeError('Another Module 9 control action is running')
  with (lab.report/'transcript.log').open('w') as log:
   original_out,original_err=sys.stdout,sys.stderr
   sys.stdout=Tee(original_out,log);sys.stderr=Tee(original_err,log)
   try:
    print(f'Module 9 | student {lab.sid} | {a.action} | {lab.db}:{lab.port}',flush=True)
    lab.run();print('Evidence:',lab.report,flush=True)
   finally:
    sys.stdout,sys.stderr=original_out,original_err
 return 0

if __name__=='__main__':
 try:sys.exit(main())
 except KeyboardInterrupt:
  print('Interrupted. Use reset-all to stop the bounded Module 9 jobs and remove its fixtures.',file=sys.stderr);sys.exit(130)
 except Exception as e:
  print('Error:',str(e),file=sys.stderr);sys.exit(1)
