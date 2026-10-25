#!/usr/bin/env python3
"""Jekyll metadata preparation and generated HTML SEO audit."""
import argparse, html, re, sys
from pathlib import Path
from html.parser import HTMLParser
BASE = "https://isolated-dotnet-sdk.infoconex.com"
SITE = "Isolated .NET SDK"
BANNER = BASE + "/assets/images/isolated-dotnet-sdk-banner.png"
OVERRIDE = {"README.md":"Isolated .NET SDK","CHANGELOG.md":"Project Changelog",
"docs/README.md":"Documentation Overview","docs/getting-started/README.md":"Getting Started",
"docs/commands/README.md":"Command Reference","docs/concepts/README.md":"Technical Concepts",
"docs/contracts/README.md":"Behavioral Contracts","docs/releases/README.md":"Releases and Version History",
"docs/maintainers/README.md":"Maintainer Documentation",
"docs/maintainers/testing/README.md":"Testing and Validation Overview"}
COMMAND = {"install":"Install .NET SDKs","remove":"Remove Isolated SDKs","list":"List Installed SDKs",
"audit":"Audit Installed .NET SDKs","verify":"Verify an Installed SDK",
"interactive":"Interactive Command Mode","tool-version":"Check Tool Version"}
def clean(s):
    s = re.sub(r'!\[([^]]*)\]\([^)]+\)', r'\1', s)
    s = re.sub(r'\[([^]]+)\]\([^)]+\)', r'\1', s)
    return re.sub(r'\s+', ' ', html.unescape(re.sub(r'[\x60*_#<>|]', '', s))).strip()
def prepare(root):
    paths = [root/'README.md', root/'CHANGELOG.md', *sorted((root/'docs').rglob('*.md'))]
    for path in paths:
        src = path.read_text(encoding='utf8')
        relative = path.relative_to(root).as_posix()
        if src.startswith('---\n'):
            _, fm, body = src.split('---', 2)
        else:
            fm, body = '', src
        heading = re.findall(r'^#\s+(.+?)\s*$', body, re.M)
        if len(heading) != 1: raise ValueError(f'{relative}: requires exactly one H1, found {len(heading)}')
        name = OVERRIDE.get(relative) or (COMMAND.get(path.stem) if path.parent.name == 'commands' else None) or clean(heading[0])
        if name.startswith('Isolated .NET SDK v'): name = name.replace('Isolated .NET SDK ', 'Release ', 1)
        title = name if relative == 'README.md' else name + ' | ' + SITE
        if len(title) >= 70: title = name
        if len(title) >= 70: raise ValueError(f'{relative}: title too long: {title}')
        paras = re.split(r'\n\s*\n', body)
        description = next((clean(p) for p in paras if len(clean(p)) > 65 and not p.lstrip().startswith(('#','|','-','*','>','!','~'))), '')
        if not description: description = f'Learn about {name.lower()} with the Isolated .NET SDK documentation, practical usage guidance, and supported behavior.'
        if len(description) > 155: description = description[:152].rsplit(' ',1)[0].rstrip(' ,;:') + '.'
        if re.search(r'^\s*(title|description):', fm, re.M): raise ValueError(f'{relative}: existing page SEO values need explicit review')
        title = title.replace('"', "'")
        description = description.replace('"', "'")
        path.write_text('---\n' + fm.strip() + '\n' + f'title: "{title}"\ndescription: "{description}"\nimage: "/assets/images/isolated-dotnet-sdk-banner.png"\n---\n' + body.lstrip('\n'), encoding='utf8')
    print(f'Prepared SEO metadata for {len(paths)} pages')
class Page(HTMLParser):
    def __init__(self):
        super().__init__(); self.h1=0; self.titles=[]; self.in_title=False; self.meta={}; self.canon=[]; self.badalt=0
    def handle_starttag(self, tag, pairs):
        a=dict(pairs)
        if tag=='h1': self.h1+=1
        if tag=='title': self.titles.append(''); self.in_title=True
        if tag=='meta':
            key=a.get('name') or a.get('property')
            if key: self.meta.setdefault(key.lower(),[]).append(a.get('content',''))
        if tag=='link' and a.get('rel')=='canonical': self.canon.append(a.get('href',''))
        if tag=='img' and 'alt' not in a: self.badalt+=1
    def handle_data(self,s):
        if self.in_title: self.titles[-1]+=s
    def handle_endtag(self,tag):
        if tag=='title': self.in_title=False
def validate(root):
    errors=[]; titles={}; descriptions={}
    pages=sorted(root.rglob('*.html'))
    if not pages: raise ValueError('No generated HTML pages')
    for path in pages:
        doc=Page(); doc.feed(path.read_text(encoding='utf8')); rel=path.relative_to(root).as_posix()
        def fail(message): errors.append(f'{rel}: {message}')
        if len(doc.titles)!=1 or not doc.titles[0].strip(): fail('missing or duplicate title')
        else:
            title=doc.titles[0].strip()
            if len(title)>=70: fail(f'title >=70 characters: {title}')
            if title in titles: fail(f'duplicate title with {titles[title]}')
            titles[title]=rel
        if doc.h1!=1: fail(f'expected one H1, got {doc.h1}')
        if doc.badalt: fail(f'{doc.badalt} images missing alt')
        for key in ('description','og:title','og:description','og:url','og:type','og:site_name','og:image','og:image:alt','twitter:card','twitter:image:alt'):
            vals=doc.meta.get(key,[])
            if len(vals)!=1 or not vals[0].strip(): fail(f'expected one {key}, got {len(vals)}')
        description=doc.meta.get('description',[''])[0]
        if description:
            if len(description)>160: fail('description over 160 chars')
            if description in descriptions: fail(f'duplicate description with {descriptions[description]}')
            descriptions[description]=rel
        if len(doc.canon)!=1: fail('missing or duplicate canonical URL')
        else:
            url=doc.canon[0]
            if not url.startswith(BASE+'/'): fail(f'wrong canonical domain: {url}')
            if doc.meta.get('og:url',[None])[0]!=url: fail('Open Graph URL differs from canonical')
        if doc.meta.get('og:image',[''])[0]!=BANNER: fail('wrong absolute Open Graph image URL')
        if doc.meta.get('twitter:card',[''])[0]!='summary_large_image': fail('missing large Twitter image card')
    if not (root/'assets/images/isolated-dotnet-sdk-banner.png').is_file(): errors.append('missing social banner asset')
    for error in errors: print('SEO ERROR:',error,file=sys.stderr)
    print(f'Checked {len(pages)} HTML pages: {len(errors)} errors')
    if errors: sys.exit(1)
if __name__=='__main__':
    p=argparse.ArgumentParser(); p.add_argument('command',choices=['prepare','validate']); p.add_argument('root',type=Path)
    a=p.parse_args(); prepare(a.root) if a.command=='prepare' else validate(a.root)
