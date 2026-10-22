from pathlib import Path
from PIL import Image, ImageDraw
root = Path(__file__).resolve().parents[1] / 'web' / 'icons'
root.mkdir(parents=True, exist_ok=True)
for size in (192, 512):
    i=Image.new('RGB',(size,size),'#181C2E')
    d=ImageDraw.Draw(i)
    # Icon details deliberately stay in the center 80% for maskable crops.
    d.rounded_rectangle((int(.19*size),int(.19*size),int(.81*size),int(.81*size)),
                        radius=int(.19*size), fill='#303655')
    d.ellipse((int(.32*size),int(.29*size),int(.68*size),int(.68*size)), fill='#E5D9FF')
    d.ellipse((int(.44*size),int(.22*size),int(.78*size),int(.58*size)), fill='#303655')
    d.ellipse((int(.64*size),int(.67*size),int(.695*size),int(.725*size)), fill='#B7D9CE')
    i.save(root / f'Icon-{size}.png', optimize=True)
print('Rendered 192 and 512 px Little Rest Home Screen icons')
