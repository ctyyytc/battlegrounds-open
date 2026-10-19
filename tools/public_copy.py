"""Copy only the reviewed public manifest to a new directory; no upload."""
import argparse,hashlib,json,pathlib,stat
ROOT=pathlib.Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',required=True,type=pathlib.Path);out=p.parse_args().output.absolute()
 if out.exists() or out==ROOT or out.is_relative_to(ROOT):raise ValueError('Output must be a new directory outside this project')
 manifest=json.loads((ROOT/'PUBLIC_FILES.json').read_text('utf-8-sig'));items=[]
 for entry in manifest['files']:
  rel=pathlib.PurePosixPath(entry['path']);source=ROOT/rel
  if rel.is_absolute() or '..' in rel.parts or ':' in str(rel):raise ValueError('Invalid path')
  for part in (source,*source.parents):
   if part==ROOT.parent:break
   if part.is_symlink() or getattr(part.lstat(),'st_file_attributes',0)&getattr(stat,'FILE_ATTRIBUTE_REPARSE_POINT',1024):raise ValueError('Linked path')
  data=source.read_bytes()
  if len(data)!=entry['bytes'] or hashlib.sha256(data).hexdigest()!=entry['sha256']:raise ValueError('Source changed: '+str(rel))
  items.append((rel,data))
 for parent in (out.parent,*out.parent.parents):
  if parent.exists() and (parent.is_symlink() or getattr(parent.lstat(),'st_file_attributes',0)&getattr(stat,'FILE_ATTRIBUTE_REPARSE_POINT',1024)):raise ValueError('Linked output parent')
 out.mkdir(parents=True)
 for rel,data in items:
  target=out/rel;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
 (out/'PUBLIC_FILES.json').write_bytes((ROOT/'PUBLIC_FILES.json').read_bytes())
 print(json.dumps({'created':str(out),'files':len(items)+1}))
if __name__=='__main__':
 try:main()
 except (OSError,ValueError) as exc:raise SystemExit(str(exc))
