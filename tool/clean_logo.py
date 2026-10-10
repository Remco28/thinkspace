import sys
from collections import deque
from PIL import Image, ImageFilter
src, dst = sys.argv[1], sys.argv[2]
im = Image.open(src).convert('RGBA')
w, h = im.size
al = im.getchannel('A')
px = al.load()
solid = bytearray(w*h)
for y in range(h):
    for x in range(w):
        if px[x, y] > 64: solid[y*w+x] = 1
seen = bytearray(w*h)
best = []
for s in range(w*h):
    if solid[s] and not seen[s]:
        comp=[s]; seen[s]=1; q=deque([s])
        while q:
            p=q.popleft(); x=p%w; y=p//w
            for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)):
                nx,ny=x+dx,y+dy
                if 0<=nx<w and 0<=ny<h:
                    n=ny*w+nx
                    if solid[n] and not seen[n]:
                        seen[n]=1; comp.append(n); q.append(n)
        best.append(comp)
best.sort(key=len, reverse=True)
print('components', len(best), [len(c) for c in best[:6]])
main = Image.new('L',(w,h),0); mp = main.load()
for p in best[0]: mp[p%w, p//w] = 255
# keep main plus a few px of its soft edge/shadow
keep = main.filter(ImageFilter.MaxFilter(13))
mask = Image.composite(al, Image.new('L',(w,h),0), keep)
out = im.copy(); out.putalpha(mask)
bb = out.getchannel('A').point(lambda v: 255 if v>8 else 0).getbbox()
print('bbox', bb)
out.save(dst)
