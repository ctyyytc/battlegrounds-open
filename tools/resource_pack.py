"""Offline local content-pack templates and strict field validation. No downloads."""
from __future__ import annotations
import argparse,json,math,pathlib,re
ROOT=pathlib.Path(__file__).resolve().parents[1]
FORMATS=re.compile(r'%(?:[-+ #0]*\d*(?:\.\d+)?[sdifxXoucCgGevV]|%)')
TOKENS=re.compile(r'\{([A-Za-z_][A-Za-z0-9_.]*)\}')
SECTIONS={'definitions','assets','phrases','templates','ui','terms'}
def read(p):return json.loads(p.read_text('utf-8-sig'))
def schema():return read(ROOT/'content/packs/resource_schema.json')
def template_valid(value,allowed):
    if not isinstance(value,str):return False
    value=value.replace('{{','').replace('}}','')
    return all(k in allowed for k in TOKENS.findall(value)) and not any(c in TOKENS.sub('',value) for c in '{}')
def formats_valid(value,expected):
    return FORMATS.findall(value)==expected and (not expected or "%" not in FORMATS.sub("",value))

def integer(value,bounds):
    return type(value) in (int,float) and bounds[0]<=value<=bounds[1] and math.isfinite(value) and value==math.floor(value)
def validate(pack,path):
    contract=schema();errors=[];counts={'definitions':0,'numeric_fields':0,'images':0,'templates':0,'names':0,'texts':0}
    if not isinstance(pack,dict) or type(pack.get('schema_version')) not in (int,float) or pack['schema_version'] not in (1,2):return ['UNSUPPORTED_RESOURCE_PACK'],counts
    version=pack['schema_version'];sections=SECTIONS if version==2 else {'definitions','assets','phrases'}
    for key,value in pack.items():
        if key=='schema_version':continue
        if key not in sections or not isinstance(value,dict):errors.append('INVALID_SECTION:'+key)
    if errors:return errors,counts
    for cid,row in pack.get('definitions',{}).items():
        spec=contract['definitions'].get(cid)
        if not spec or not isinstance(row,dict):errors.append('INVALID_DEFINITION:'+cid);continue
        valid=True
        for field,value in row.items():
            if field not in spec['fields'] or (version==1 and field not in ('name','text')):valid=False;continue
            if field in ('name','text'):
                if not isinstance(value,str) and not (version==2 and field=='text' and value is None):valid=False
            elif not integer(value,spec['fields'][field]['bounds']):valid=False
        if not valid:errors.append('INVALID_DEFINITION:'+cid);continue
        counts['definitions']+=1
        counts['numeric_fields']+=sum(k not in ('name','text') for k in row)
        for key in ('name','text'):counts[key+'s' if key=='name' else 'texts']+=bool((row.get(key) or '').strip())
    for key,value in pack.get('assets',{}).items():
        if key in contract['assets'] and value is None and version==2:continue
        valid=key in contract['assets'] and isinstance(value,str)
        if valid:
            relative=pathlib.PurePosixPath(value.replace('\\','/'))
            valid=bool(value) and not relative.is_absolute() and ':' not in value and '..' not in relative.parts and relative.suffix.lower() in {'.png','.jpg','.jpeg','.webp','.svg'}
            current=path.parent
            for part in relative.parts:
                current=current/part
                if current.is_symlink():valid=False
            valid=valid and current.is_file() and current.resolve().is_relative_to(path.parent.resolve())
        if valid:counts['images']+=1
        else:errors.append('INVALID_ASSET:'+key)
    for section in ('phrases','ui','terms'):
        for key,value in pack.get(section,{}).items():
            entry=contract[section].get(key)
            if not entry or not isinstance(value,str) or (value and not formats_valid(value,entry['format_tokens'])):errors.append('INVALID_'+('PHRASE' if section=='phrases' else section.upper())+':'+key)
    for key,value in pack.get('templates',{}).items():
        group=contract['templates'].get(key)
        if not group or not template_valid(value,contract['parameter_sets'][group]):errors.append('INVALID_TEMPLATE:'+key)
        else:counts['templates']+=bool(value)
    return errors,counts
def template(output):
    contract=schema();output.mkdir(parents=True,exist_ok=True)
    destinations=[output/n for n in ('pack.json','image_requirements.json','field_requirements.json')]
    if any(p.exists() for p in destinations):raise FileExistsError('Refusing to overwrite existing template or resources')
    definitions={}
    for cid,spec in contract['definitions'].items():definitions[cid]={k:('' if k in ('name','text') else v['default']) for k,v in spec['fields'].items() if k!='text'}
    pack={'schema_version':2,'definitions':definitions,'assets':{},'phrases':{k:'' for k in contract['phrases']},'templates':{},'ui':{},'terms':{}}
    payloads=[pack,read(ROOT/'resource_contract/images.json'),read(ROOT/'resource_contract/fields.json')]
    for path,payload in zip(destinations,payloads):
        with path.open('x',encoding='utf-8') as stream:json.dump(payload,stream,ensure_ascii=False,indent=2);stream.write('\n')
    print(json.dumps({'created':str(destinations[0]),'definitions':len(definitions),'contains_original_base_values':False},ensure_ascii=False))
def main():
    parser=argparse.ArgumentParser(description=__doc__);commands=parser.add_subparsers(dest='command',required=True)
    sub=commands.add_parser('template');sub.add_argument('--output',type=pathlib.Path,required=True)
    sub=commands.add_parser('check');sub.add_argument('--pack',type=pathlib.Path,required=True)
    args=parser.parse_args()
    try:
        if args.command=='template':template(args.output);return 0
        errors,coverage=validate(read(args.pack),args.pack)
    except (OSError,ValueError) as exc:errors,coverage=[str(exc)],{}
    print(json.dumps({'errors':errors,'coverage':coverage},ensure_ascii=False));return int(bool(errors))
if __name__=='__main__':raise SystemExit(main())
