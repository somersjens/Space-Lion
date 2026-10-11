import xml.etree.ElementTree as E
from collections import Counter
import sys
root=E.parse(sys.argv[1]).getroot()
refs={e.get('id'):e for e in root.iter() if e.get('id')}
def res(e):return refs.get(e.get('ref'),e)
leaf=Counter(); inclusive=Counter(); mains=Counter(); categories=Counter();total=0
for row in root.iter('row'):
 es=list(row)
 if len(es)<7:continue
 thread=res(es[1]);weight=int(res(es[5]).text or 0)/1e6;frames=[res(e) for e in res(es[6]).findall('frame')]
 if not frames:continue
 total+=weight
 names=[e.get('name','') for e in frames]
 leaf[names[0]]+=weight
 for name in set(names):
  inclusive[name]+=weight
  if thread.get('fmt','').startswith('Main Thread'):mains[name]+=weight
 for cat in ['CoreGraphics','libvImage.dylib','SwiftUI','SwiftUICore','AVFAudio','AudioToolbox']:
  if any((res(e.find('binary')).get('name') if e.find('binary') is not None else '')==cat for e in frames):categories[cat]+=weight
print('total_ms',total,'categories',categories)
print('LEAF');print(*leaf.most_common(16),sep='\n')
print('INCLUSIVE');print(*inclusive.most_common(20),sep='\n')
print('APP');print(*[(n,v)for n,v in inclusive.most_common() if any(s in n for s in ['Space','Cockpit','lion','draw','CGContext'])][:25],sep='\n')
print('MAIN');print(*mains.most_common(15),sep='\n')
