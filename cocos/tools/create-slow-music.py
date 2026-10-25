"""Bake the original soundtrack at 0.7 speed using macOS Core Audio."""
import json
from pathlib import Path
import subprocess
import tempfile
import uuid
import wave

root = Path(__file__).resolve().parents[1]
source = root / 'assets/content/audio/daily1.mp3'
target = source.with_name('daily1-slow.m4a')
speed = 0.7
with tempfile.TemporaryDirectory(prefix='startx-slow-music-') as folder:
    normal, slow = Path(folder) / 'normal.wav', Path(folder) / 'slow.wav'
    subprocess.run(['/usr/bin/afconvert', str(source), str(normal), '-f', 'WAVE', '-d', 'LEI16@44100'], check=True)
    with wave.open(str(normal), 'rb') as audio:
        params, samples = audio.getparams(), audio.readframes(audio.getnframes())
    with wave.open(str(slow), 'wb') as audio:
        audio.setparams(params)
        audio.setframerate(round(params.framerate * speed))
        audio.writeframes(samples)
    subprocess.run(['/usr/bin/afconvert', str(slow), str(target), '-f', 'm4af', '-d', 'aac@16000', '-b', '64000'], check=True)
    print(f'Original {params.nframes / params.framerate:.3f}s; slow {params.nframes / round(params.framerate * speed):.3f}s')
meta_path = Path(str(target) + '.meta')
if not meta_path.exists():
    meta = json.loads(Path(str(source) + '.meta').read_text())
    meta.update(uuid=str(uuid.uuid4()), files=['.json', '.m4a'])
    meta_path.write_text(json.dumps(meta, indent=2) + '\n')
