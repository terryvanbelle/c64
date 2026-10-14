"""Original Ironveil multicolor terrain and independent hull/turret sprites."""
from pathlib import Path
import math
from generate_atlas_assets import FONT

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build'/'tanks'

def terrain(kind,mask=0):
    g=[[0]*8 for _ in range(16)]
    if kind==0:
        for y in range(16):
            for x in range(8):g[y][x]=2 if (x*2+y)%7 else 0
    elif kind==1:
        for x,y in ((1,2),(5,4),(3,9),(7,13),(0,14)):
            g[y][x]=1;g[min(15,y+1)][x]=1
    elif kind==2:
        for x,top in ((2,1),(5,5),(1,10),(6,0)):
            for y in range(top,min(top+7,16)):
                half=min(2,(y-top)//2)
                for c in range(max(0,x-half),min(8,x+half+1)):g[y][c]=1
            g[min(15,top+7)][x]=3
    elif kind==3:
        for x in range(8):
            g[3+abs(x-3)//2][x]=3;g[10+abs(x-6)//2][x]=3
        for x,y in ((1,8),(5,1),(6,14)):g[y][x]=3
    elif kind==4:
        for cx,top in ((2,1),(5,6)):
            for y in range(top,16):
                for x in range(8):
                    if abs(x-cx)*2<=y-top:g[y][x]=3 if x<=cx else 2
            g[top][cx]=3
    elif kind==5:
        for y in (3,8,13):
            for x in range(8):g[y][x]=2
        for x,y in ((1,0),(3,5),(6,9),(7,1)):
            for dy in range(4):g[y+dy][x]=1
    else:
        if kind==7:
            for y in range(16):
                for x in range(8):g[y][x]=2 if y%5 in (1,2) else 0
        for y in range(6,10):
            for x in range(3,5):g[y][x]=3
        for bit,xs,ys in ((1,range(3,5),range(0,8)),(2,range(4,8),range(6,10)),(4,range(3,5),range(8,16)),(8,range(0,4),range(6,10))):
            if mask&bit:
                for y in ys:
                    for x in xs:g[y][x]=3
        # Narrow black track down the lane leaves the road readable.
        if mask&5:
            for y in range(16):
                if (y<8 and mask&1) or (y>=8 and mask&4):g[y][3]=0 if y%3==0 else 3
    return g

def metatile(g):
    return b''.join(bytes(sum(g[y][x+i]<<(6-i*2) for i in range(4)) for y in range(top,top+8))
                    for top,x in ((0,0),(0,4),(8,0),(8,4)))

def sensor_marker(heading=None):
    """A yellow, black-backed 16x16 compass arrow or coarse-contact diamond."""
    g=[[0]*8 for _ in range(16)]
    for y in range(16):
        for x in range(8):
            dx,dy=x*2+0.5-7.5,y-7.5
            if heading is None:
                distance=abs(dx)+abs(dy)
                lit=5<=distance<=7 or (abs(dx)<=1 and abs(dy)<=2)
            else:
                fx,fy=math.sin(heading*math.pi/4),-math.cos(heading*math.pi/4)
                along=dx*fx+dy*fy
                across=abs(dx*fy-dy*fx)
                lit=(-5<=along<=1 and across<=1.2) or (1<=along<=6 and across<=(6-along)*0.8+1.2)
            if lit:g[y][x]=3
    return g

def tank(hull,turret):
    hf=math.sin(hull*math.pi/4),-math.cos(hull*math.pi/4)
    tf=math.sin(turret*math.pi/4),-math.cos(turret*math.pi/4)
    g=[[0]*12 for _ in range(21)]
    for y in range(16):
        for c in range(8):
            x=c*2+0.5;dx,dy=x-7.5,y-7.5
            longitudinal=dx*hf[0]+dy*hf[1];side=dx*hf[1]-dy*hf[0]
            if abs(longitudinal)<=6 and 4<=abs(side)<=6:g[y][c]=1
            if abs(longitudinal)<=5 and abs(side)<4:g[y][c]=2
            if dx*dx+dy*dy<=8:g[y][c]=3
            barrel=dx*tf[0]+dy*tf[1];cross=dx*tf[1]-dy*tf[0]
            if 0<=barrel<=7 and abs(cross)<1:g[y][c]=3
    return b''.join(sum(row[c+i]<<(6-i*2) for i in range(4)).to_bytes(1,'big')
                    for row in g for c in (0,4,8))+b'\0'

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    charset=bytearray(2048)
    for code in range(32,96):charset[code*8:code*8+8]=bytes([0]+[r<<2 for r in FONT[chr(code)]])
    bases=(96,100,104,108,112,116,120,184)
    for kind,base in enumerate(bases):
        for mask in range(16 if kind>=6 else 1):
            charset[(base+mask*4)*8:(base+mask*4+4)*8]=metatile(terrain(kind,mask))
    for heading in range(8):
        charset[heading*32:(heading+1)*32]=metatile(sensor_marker(heading))
    charset[248*8:249*8]=bytes([3]*8)
    charset[249*8:250*8]=bytes([192]*8)
    charset[250*8:254*8]=metatile(sensor_marker())
    sprites=b''.join(tank(h,t) for h in range(8) for t in range(8))
    bullet=bytearray(64)
    for x,y in ((1,0),(0,1),(1,1),(2,1),(1,2)):bullet[y*3+x//8]|=128>>(x&7)
    sprites+=bytes(bullet)+bytes(192)
    assert len(sprites)==4352
    (OUT/'charset.bin').write_bytes(charset);(OUT/'sprites.bin').write_bytes(sprites)
    (OUT/'assets.inc').write_text('.segment "RODATA"\ntile_bases: .byte '+','.join(map(str,bases))+'\n')
    print('Ironveil: 2048 character bytes, 64 tank orientations, 4352 sprite bytes')

if __name__=='__main__':main()
