"""Convert pinned, vendored Lucide SVG geometry into native SwiftUI paths."""
import math
import re
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = root / 'Resources/Lucide'
target = root / 'Sources/Still/LucidePaths.swift'

def number(n):
    return f'{float(n):.7f}'.rstrip('0').rstrip('.') or '0'

def point(x, y):
    return f'CGPoint(x: {number(x)}, y: {number(y)})'

def arc(x1, y1, rx, ry, angle, large, sweep, x2, y2):
    rx, ry = abs(rx), abs(ry)
    if not rx or not ry:
        return [f'p.addLine(to: {point(x2,y2)})']
    if abs(x1-x2)+abs(y1-y2) < 1e-10:
        return []
    phi = math.radians(angle)
    c, s = math.cos(phi), math.sin(phi)
    xp = c*(x1-x2)/2+s*(y1-y2)/2
    yp = -s*(x1-x2)/2+c*(y1-y2)/2
    scale = xp*xp/(rx*rx)+yp*yp/(ry*ry)
    if scale > 1: rx *= math.sqrt(scale); ry *= math.sqrt(scale)
    numerator = max(0, rx*rx*ry*ry-rx*rx*yp*yp-ry*ry*xp*xp)
    denominator = rx*rx*yp*yp+ry*ry*xp*xp
    coefficient = (-1 if bool(large)==bool(sweep) else 1)*math.sqrt(numerator/max(denominator,1e-20))
    cxp, cyp = coefficient*rx*yp/ry, -coefficient*ry*xp/rx
    cx, cy = c*cxp-s*cyp+(x1+x2)/2, s*cxp+c*cyp+(y1+y2)/2
    start = math.atan2((yp-cyp)/ry, (xp-cxp)/rx)
    end = math.atan2((-yp-cyp)/ry, (-xp-cxp)/rx)
    delta = (end-start)%(2*math.pi)
    if not sweep: delta -= 2*math.pi
    count = max(1, math.ceil(abs(delta)/(math.pi/2)))
    def at(t): return (cx+c*rx*math.cos(t)-s*ry*math.sin(t), cy+s*rx*math.cos(t)+c*ry*math.sin(t))
    def tangent(t): return (-c*rx*math.sin(t)-s*ry*math.cos(t), -s*rx*math.sin(t)+c*ry*math.cos(t))
    result=[]
    for i in range(count):
        a, b = start+delta*i/count, start+delta*(i+1)/count
        k = 4/3*math.tan((b-a)/4)
        pa,pb,ta,tb=at(a),at(b),tangent(a),tangent(b)
        result.append(f'p.addCurve(to: {point(*pb)}, control1: {point(pa[0]+k*ta[0],pa[1]+k*ta[1])}, control2: {point(pb[0]-k*tb[0],pb[1]-k*tb[1])})')
    return result

def path_commands(data):
    position=0; cmd=None; x=y=sx=sy=0; result=[]
    sizes={'M':2,'L':2,'H':1,'V':1,'C':6,'Q':4,'A':7}
    numeric=re.compile(r'[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?')
    def skip():
        nonlocal position
        while position<len(data) and data[position] in ' ,\n\t': position+=1
    while position<len(data):
        skip()
        if position>=len(data): break
        if data[position].isalpha():
            cmd=data[position]; position+=1
            if cmd.upper()=='Z':
                result.append('p.closeSubpath()'); x,y=sx,sy; continue
        op=cmd.upper(); values=[]
        for parameter in range(sizes[op]):
            skip()
            if op=='A' and parameter in (3,4):
                assert data[position] in '01', data
                values.append(float(data[position])); position+=1
            else:
                match=numeric.match(data,position)
                assert match, (data, position, op, parameter)
                values.append(float(match.group())); position=match.end()
        relative=cmd.islower()
        def dest(a,b): return (a+x,b+y) if relative else (a,b)
        if op in ['M','L']:
            nx,ny=dest(*values)
            result.append(f'p.{"move" if op=="M" else "addLine"}(to: {point(nx,ny)})')
            x,y=nx,ny
            if op=='M': sx,sy=x,y; cmd='l' if relative else 'L'
        elif op in ['H','V']:
            nx=values[0]+(x if relative else 0) if op=='H' else x
            ny=values[0]+(y if relative else 0) if op=='V' else y
            result.append(f'p.addLine(to: {point(nx,ny)})'); x,y=nx,ny
        elif op=='C':
            a,b=dest(*values[:2]); c,d=dest(*values[2:4]); nx,ny=dest(*values[4:])
            result.append(f'p.addCurve(to: {point(nx,ny)}, control1: {point(a,b)}, control2: {point(c,d)})'); x,y=nx,ny
        elif op=='Q':
            a,b=dest(*values[:2]); nx,ny=dest(*values[2:])
            result.append(f'p.addQuadCurve(to: {point(nx,ny)}, control: {point(a,b)})'); x,y=nx,ny
        elif op=='A':
            nx,ny=dest(*values[5:]); result+=arc(x,y,*values[:5],nx,ny); x,y=nx,ny
        else: raise ValueError(op)
    return result

lines=['// Generated from pinned Lucide SVGs. See Resources/Lucide/LICENSE and SOURCE.json.', 'import SwiftUI', '', 'enum LucidePaths {', '    static func path(_ name: String) -> Path {', '        var p = Path()', '        switch name {']
for file in sorted(source.glob('*.svg')):
    lines.append(f'        case "{file.stem}":')
    for node in ET.parse(file).getroot():
        tag=node.tag.split('}')[-1]; a=node.attrib; commands=[]
        if tag=='path': commands=path_commands(a['d'])
        elif tag in ['circle','ellipse']:
            cx,cy=float(a['cx']),float(a['cy']); rx=float(a.get('r',a.get('rx',0))); ry=float(a.get('r',a.get('ry',0)))
            commands=[f'p.addEllipse(in: CGRect(x: {number(cx-rx)}, y: {number(cy-ry)}, width: {number(rx*2)}, height: {number(ry*2)}))']
        elif tag=='rect':
            x,y,w,h=map(float,[a.get('x',0),a.get('y',0),a['width'],a['height']]); radius=float(a.get('rx',0))
            commands=[f'p.addRoundedRect(in: CGRect(x: {number(x)}, y: {number(y)}, width: {number(w)}, height: {number(h)}), cornerSize: CGSize(width: {number(radius)}, height: {number(radius)}))']
        elif tag=='line': commands=[f'p.move(to: {point(a["x1"],a["y1"])})',f'p.addLine(to: {point(a["x2"],a["y2"])})']
        elif tag in ['polyline','polygon']:
            coords=list(map(float,re.findall(r'[-+]?[\d.]+',a['points'])))
            commands=[f'p.{"move" if i==0 else "addLine"}(to: {point(coords[i],coords[i+1])})' for i in range(0,len(coords),2)]
            if tag=='polygon': commands+=['p.closeSubpath()']
        else: raise ValueError(tag)
        lines += ['            '+command for command in commands]
lines += ['        default: p.addEllipse(in: CGRect(x: 3, y: 3, width: 18, height: 18))','        }','        return p','    }','}']
target.write_text('\n'.join(lines)+'\n')
print(f'Generated {len(list(source.glob("*.svg")))} native vector icons.')
