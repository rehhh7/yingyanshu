import os, sys, subprocess, concurrent.futures
import imageio_ffmpeg

FF = imageio_ffmpeg.get_ffmpeg_exe()
SRC = r"C:\Users\s\Desktop\英语\cet4_app\assets\audio\words"
DST = r"C:\Users\s\Desktop\英语\_tmp\ogg"
os.makedirs(DST, exist_ok=True)

files = [f for f in os.listdir(SRC) if f.endswith(".wav")]
print(f"total {len(files)}")

def conv(f):
    out = os.path.join(DST, f[:-4] + ".ogg")
    if os.path.exists(out):
        return None
    r = subprocess.run([FF, "-y", "-loglevel", "error", "-i", os.path.join(SRC, f),
                        "-ac", "1", "-ar", "22050", "-c:a", "libvorbis", "-q:a", "2", out],
                       capture_output=True, text=True)
    return (f, r.stderr) if r.returncode != 0 else None

errs = []
with concurrent.futures.ThreadPoolExecutor(8) as ex:
    for i, res in enumerate(ex.map(conv, files)):
        if res:
            errs.append(res)
        if (i + 1) % 200 == 0:
            print(f"{i+1}/{len(files)}", flush=True)

src_size = sum(os.path.getsize(os.path.join(SRC, f)) for f in files)
dst_size = sum(os.path.getsize(os.path.join(DST, f)) for f in os.listdir(DST) if f.endswith(".ogg"))
print(f"wav: {src_size/1e6:.1f}MB -> ogg: {dst_size/1e6:.1f}MB, files: {len(os.listdir(DST))}, errors: {len(errs)}")
for e in errs[:5]:
    print(e)
