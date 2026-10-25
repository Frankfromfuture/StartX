"""Bake the gameplay soundtrack at 0.7 speed using macOS Core Audio."""
import json
from pathlib import Path
import subprocess
import struct
import tempfile
import uuid

root = Path(__file__).resolve().parents[1]
source = root / 'assets/content/audio/bgm1.m4a'
target = source.with_name('bgm1-slow.m4a')
speed = 0.7
with tempfile.TemporaryDirectory(prefix='startx-slow-music-') as folder:
    normal, slow = Path(folder) / 'normal.wav', Path(folder) / 'slow.wav'
    subprocess.run(['/usr/bin/afconvert', str(source), str(normal), '-f', 'WAVE', '-d', 'LEI16@44100'], check=True)
    # Core Audio emits extensible WAV for stereo AAC; preserve its channel layout.
    audio = bytearray(normal.read_bytes())
    offset, rate, frames = 12, 0, 0
    while offset + 8 <= len(audio):
        kind, size = struct.unpack_from('<4sI', audio, offset)
        if kind == b'fmt ':
            rate, byte_rate, block_align = struct.unpack_from('<IIH', audio, offset + 12)
            struct.pack_into('<II', audio, offset + 12, round(rate * speed), round(rate * speed) * block_align)
        elif kind == b'data':
            frames = size // block_align
        offset += 8 + size + size % 2
    if not rate or not frames:
        raise ValueError('Missing PCM format or audio samples')
    slow.write_bytes(audio)
    subprocess.run(['/usr/bin/afconvert', str(slow), str(target), '-f', 'm4af', '-d', 'aac@16000', '-b', '64000'], check=True)
    print(f'Original {frames / rate:.3f}s; slow {frames / round(rate * speed):.3f}s')
meta_path = Path(str(target) + '.meta')
if not meta_path.exists():
    meta = json.loads(Path(str(source) + '.meta').read_text())
    meta.update(uuid=str(uuid.uuid4()), files=['.json', '.m4a'])
    meta_path.write_text(json.dumps(meta, indent=2) + '\n')
