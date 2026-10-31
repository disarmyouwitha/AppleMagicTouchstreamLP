"""Build a pure-Python wheel using only the standard library."""
import base64
import csv
import hashlib
import io
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parent
version = "0.1.0"
name = "plover_applemagictouchstream"
dist = f"{name}-{version}.dist-info"
files = {f"{name}/{p.name}": p.read_bytes() for p in (root / name).glob("*.py")}
files[f"{dist}/METADATA"] = (
    f"Metadata-Version: 2.1\nName: plover-applemagictouchstream\nVersion: {version}\n"
    "Summary: AppleMagicTouchstream loopback Gemini PR machine for Plover\n"
    "Requires-Python: >=3.9\n\nRequires Plover 4; install into Plover's plugin environment.\n"
).encode()
files[f"{dist}/WHEEL"] = b"Wheel-Version: 1.0\nGenerator: AppleMagicTouchstream\nRoot-Is-Purelib: true\nTag: py3-none-any\n"
files[f"{dist}/entry_points.txt"] = (
    "[plover.machine]\nAppleMagicTouchstream = plover_applemagictouchstream.machine:AppleMagicTouchstream\n"
).encode()
record = io.StringIO(newline="")
writer = csv.writer(record, lineterminator="\n")
for path, data in sorted(files.items()):
    digest = base64.urlsafe_b64encode(hashlib.sha256(data).digest()).rstrip(b"=").decode()
    writer.writerow([path, f"sha256={digest}", str(len(data))])
writer.writerow([f"{dist}/RECORD", "", ""])
files[f"{dist}/RECORD"] = record.getvalue().encode()
target = root / "dist"
target.mkdir(exist_ok=True)
wheel = target / f"{name}-{version}-py3-none-any.whl"
with zipfile.ZipFile(wheel, "w", zipfile.ZIP_DEFLATED) as archive:
    for path, data in sorted(files.items()):
        entry = zipfile.ZipInfo(path, date_time=(2026, 1, 1, 0, 0, 0))
        entry.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(entry, data)
print(wheel)
