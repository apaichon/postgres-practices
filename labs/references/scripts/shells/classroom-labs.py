#!/usr/bin/env python3
"""Instructor orchestration of modules 1-7 and 9 for selected/all SSH students."""
import argparse,base64,csv,json,os,re,shlex,subprocess,tempfile,time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime,timezone
from pathlib import Path
import urllib.request


def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--root',type=Path,default=Path('/opt/setup-postgres-labs'))
 p.add_argument('action',choices=['prepare-all','verify-all','run','run-all','reset-all','test-all'])
 p.add_argument('--students',default='all',help='all, 1, or comma-separated numbers/ranges such as 1-5,20')
 p.add_argument('--module',help='for run: 1..7,9 or a supported section e.g. 2.H / 7.pitr')
 p.add_argument('--profile',choices=['teaching','quick'],default='teaching')
 p.add_argument('--host',default='127.0.0.1');p.add_argument('--port',type=int,default=22)
 p.add_argument('--dry-run',action='store_true');p.add_argument('--yes',action='store_true')
 p.add_argument('--preserve-legacy',action='store_true',help='archive/rename an incompatible own insurance model during prepare')
 p.add_argument('--include-backup',action='store_true')
 a=p.parse_args();root=a.root.resolve()
 if a.module and a.action!='run':p.error('--module is only used with run')
 if a.action=='run' and not a.module:p.error('run needs --module, e.g. --module 5')
 if a.module and not re.fullmatch(r'(?:[1-7]|9)(?:\.[A-Za-z]+)?',a.module):p.error('Invalid module/section')
 selected=set()
 if a.students=='all':selected=set(range(1,21))
 else:
  for part in a.students.split(','):
   if not re.fullmatch(r'\d{1,2}(?:-\d{1,2})?',part):p.error('Invalid --students')
   ends=list(map(int,part.split('-')));lo=ends[0];hi=ends[-1]
   if not 1<=lo<=hi<=20:p.error('--students must be 1..20')
   selected.update(range(lo,hi+1))
 if a.action in ('reset-all','run-all') and not a.yes and not a.dry_run:
  print('PREVIEW ONLY. '+a.action+' affects real course data for the selected students. Add --yes after reviewing this plan.');a.dry_run=True
 print('Classroom action:',a.action,'students:',','.join(f'{n:02d}' for n in sorted(selected)),'profile:',a.profile,flush=True)
 if a.dry_run:
  print('Prepare: install a separate ~/scripts/course bundle; preserve existing compatible insurance rows; add module fixtures.\nVerify: actual SSH/DB ownership, prerequisites, runtime and monitoring/Grafana account checks; no full execution claim.\nRun: execute selected/all modules against each own real main database.\nReset: insurance archive first; reset only modules 1-7/9; retain credentials, history, evidence and modules 8/10.')
  if a.preserve_legacy:print('Legacy preservation selected: archive and rename incompatible insurance schemas; retain their data/objects and create the new course model.')
  return
 if a.action=='test-all':
  if selected!=set(range(1,21)):p.error('test-all uses its fixed disposable 20-role matrix; do not narrow --students')
  print('Isolated test scope: modules 1–5 for all 20 ordinary roles; complete quick 1–7/9 workflow for SID 01, plus reset/archive/legacy preservation. Real student data and Grafana are not modified.',flush=True)
  image='claimsure-module07-test:pg18'
  if subprocess.run(['docker','image','inspect',image],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode:
   subprocess.run(['docker','build','-f',str(root/'scripts/Dockerfile.test-module07'),'-t',image,str(root/'scripts')],check=True)
  subprocess.run(['bash',str(root/'scripts/test-course-labs.sh')],check=True)
  return
 rows=list(csv.DictReader((root/'secrets/students.tsv').open(),delimiter='\t'))
 ssh_rows={int(row['id']):row for row in csv.DictReader((root/'secrets/ssh-students.tsv').open(),delimiter='\t')}
 for row in rows:
  ssh=ssh_rows[int(row['id'])];row['ssh_user']=ssh['ssh_user'];row['ssh_password']=ssh['ssh_password']
 rows=[r for r in rows if int(r['id']) in selected]
 if len(rows)!=len(selected) or any(r['ssh_user']!='student'+f"{int(r['id']):02d}" for r in rows):raise RuntimeError('Student credential manifest does not match the requested accounts')
 report=root/'reports/classroom'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ');report.mkdir(mode=0o700,parents=True)
 if a.action=='prepare-all':
  installer=root/'scripts/install-course-labs.py'
  command=['docker','run','--rm','--network','none','--user','0',
   '--mount',f'type=bind,src={root}/student-scripts,dst=/course/student-scripts,readonly',
   '--mount','type=bind,src=/home,dst=/home','--mount','type=bind,src=/etc/passwd,dst=/etc/passwd,readonly']
  for name in ('install-course-labs.py','install-module06.py','install-module07.py','install-module09.py'):
   command+=['--mount',f'type=bind,src={root}/scripts/{name},dst=/course/scripts/{name},readonly']
  command+=['--entrypoint','python3','prompt-shop-adk:task0024','/course/scripts/install-course-labs.py']
  # Validate the whole requested cohort before any writes. Install each selected
  # home through the same ownership/hash-aware installer.
  if selected==set(range(1,21)):
   subprocess.run(command+['--check'],check=True);subprocess.run(command,check=True)
  else:
   for sid in sorted(selected):subprocess.run(command+['--check','--student',str(sid)],check=True)
   for sid in sorted(selected):subprocess.run(command+['--student',str(sid)],check=True)
  # Keep the primary/Grafana running; only repair monitoring if its check fails.
  stack=root/'scripts/module09-stack.sh'
  if subprocess.run([str(stack),'check'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode:
   subprocess.run([str(stack),'init-all'],check=True)
 cache=Path.home()/'.cache/classroom-labs';cache.mkdir(mode=0o700,parents=True,exist_ok=True)
 known=cache/'known_hosts'
 results=[]
 with tempfile.TemporaryDirectory(prefix='classroom-askpass-') as tmp:
  ask=Path(tmp)/'askpass';ask.write_text('#!/bin/sh\nprintf %s "$CLASSROOM_SSH_PASSWORD"\n');ask.chmod(0o700)
  def execute(row):
   sid=f"{int(row['id']):02d}"
   args={'prepare-all':['prepare'],'verify-all':['verify'],'reset-all':['reset-all','--yes'],'run':['run',a.module],'run-all':['run-all']}[a.action]
   args+=['--profile',a.profile]
   if a.include_backup:args+=['--include-backup']
   if a.preserve_legacy:args+=['--preserve-legacy']
   script='set -euo pipefail\ncd "$HOME/scripts"\n./course-labs.sh '+' '.join(shlex.quote(x) for x in args)+'\n'
   env=dict(os.environ,SSH_ASKPASS=str(ask),SSH_ASKPASS_REQUIRE='force',DISPLAY=':0',CLASSROOM_SSH_PASSWORD=row['ssh_password'])
   command=['ssh','-T','-p',str(a.port),'-o','StrictHostKeyChecking=accept-new','-o','UserKnownHostsFile='+str(known),'-o','PreferredAuthentications=password','-o','PubkeyAuthentication=no','-o','ConnectTimeout=8',row['ssh_user']+'@'+a.host,'bash -s']
   began=time.monotonic()
   try:
    r=subprocess.run(command,input=script,text=True,capture_output=True,env=env,timeout=1800 if a.action in ('run','run-all') else 300)
    output=r.stdout+'\n'+r.stderr
    for key in ('ssh_password','postgres_password','grafana_password'):output=output.replace(row.get(key,''),'[redacted]') if row.get(key) else output
    (report/(row['ssh_user']+'.log')).write_text(output)
    result={'student':sid,'action':a.action,'passed':r.returncode==0,'seconds':round(time.monotonic()-began,2),'log':str(report/(row['ssh_user']+'.log'))}
    if r.returncode:result['error']='SSH command failed; see private log'
    if r.returncode==0 and a.action in ('prepare-all','verify-all'):
     req=urllib.request.Request('http://127.0.0.1:3000/api/dashboards/uid/claimsure-module09')
     req.add_header('Authorization','Basic '+base64.b64encode((row['grafana_login']+':'+row['grafana_password']).encode()).decode())
     with urllib.request.urlopen(req,timeout=20) as response:dashboard=json.load(response)
     if len(dashboard['dashboard']['panels'])!=20:raise RuntimeError('Unexpected Grafana dashboard')
     result['grafana_access']=True
   except Exception as e:result={'student':sid,'action':a.action,'passed':False,'error':str(e)}
   print('student'+sid+': '+('PASS' if result['passed'] else 'FAILED'),flush=True)
   return result
  # Verification reads independent accounts. Preparation/execution/reset remain
  # sequential to avoid a coordinated workload spike on the shared machine.
  if a.action=='verify-all':results=list(ThreadPoolExecutor(max_workers=4).map(execute,rows))
  else:
   for row in rows:results.append(execute(row))
 summary={'action':a.action,'profile':a.profile,'modules':[1,2,3,4,5,6,7,9],'full_execution':a.action=='run-all','results':results}
 (report/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
 print('Classroom report:',report,flush=True)
 if not all(r['passed'] for r in results):raise RuntimeError('Some students failed; inspect summary.json and individual private logs before proceeding')
 print(f'PASS: {len(results)} students; '+('readiness verified (no full execution claim)' if a.action in ('prepare-all','verify-all') else a.action),flush=True)
if __name__=='__main__':
 try:main()
 except Exception as e:raise SystemExit('Error: '+str(e))
