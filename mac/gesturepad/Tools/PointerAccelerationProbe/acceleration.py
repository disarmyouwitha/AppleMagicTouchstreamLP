#!/usr/bin/env python3
"""Offline parametric HID acceleration experiment; never posts or modifies input."""
import argparse
import bisect
import csv
import datetime
import json
import math
from pathlib import Path
import plistlib
import subprocess
import sys

APPLE_COMMIT = '777ccd9698845aadf711e32d843c8c9b777431d9'
CURVE_KEYS = ['HIDAccelGainLinear', 'HIDAccelGainParabolic', 'HIDAccelGainCubic',
              'HIDAccelGainQuartic', 'HIDAccelTangentSpeedLinear', 'HIDAccelTangentSpeedParabolicRoot']


def finite(value, name):
    value = float(value)
    if not math.isfinite(value):
        raise ValueError(f'{name} must be finite')
    return value


def fixed(value):
    value = int(value)
    if 0x80000000 <= value <= 0xffffffff:
        value -= 0x100000000
    return value / 65536


def dictionaries(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from dictionaries(child)
    elif isinstance(value, list):
        for child in value:
            yield from dictionaries(child)


def snapshot():
    devices = plistlib.loads(subprocess.check_output(['/usr/sbin/ioreg', '-a', '-l', '-r', '-c', 'AppleMultitouchDevice']))
    system = plistlib.loads(subprocess.check_output(['/usr/sbin/ioreg', '-a', '-l', '-r', '-c', 'IOHIDSystem']))
    values = [x['HIDTrackpadAcceleration'] for x in dictionaries(system) if 'HIDTrackpadAcceleration' in x]
    entries = []
    for node in dictionaries(devices):
        curves = node.get('HIDAccelCurves')
        if not curves or not node.get('Multitouch ID'):
            continue
        entries.append({
            'device_id': str(node['Multitouch ID']), 'registry_id': str(node.get('IORegistryEntryID', '')),
            'serial': node.get('SerialNumber', ''), 'transport': node.get('Transport', ''),
            'resolution': fixed(node['HIDPointerResolution']),
            'report_rate': node.get('HIDPointerReportRate', 0),
            'fixed_multiplier': fixed(node.get('HIDPointerAccelerationMultiplier', 65536)),
            'acceleration': fixed(values[0]) if values else None,
            'algorithm_rate': 67.0,
            'curves': [{'index': fixed(c['HIDAccelIndex']), **{key: fixed(c.get(key, 0)) for key in CURVE_KEYS}} for c in curves],
        })
    return {'schema': 'gesturepad.pointer-settings.v1', 'created_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'os': subprocess.check_output(['/usr/bin/sw_vers'], text=True).strip(),
            'apple_source_commit': APPLE_COMMIT, 'devices': entries,
            'limitations': ['IORegistry/provider defaults and global HID setting; not proof of the active HID service filter.',
                            'User/service curve overrides or proprietary upstream contact-to-pointer transforms may differ.']}


class Parametric:
    """Numerical model of Apple's published parametric equations (see SOURCES.md)."""
    def __init__(self, settings, acceleration=None):
        self.resolution = finite(settings['resolution'], 'resolution')
        self.rate = finite(settings.get('algorithm_rate', 67), 'algorithm_rate')
        if self.resolution <= 0 or self.rate <= 0:
            raise ValueError('resolution and algorithm_rate must be positive')
        raw = settings.get('acceleration') if acceleration is None else acceleration
        if raw is None:
            raise ValueError('tracking acceleration missing; supply --acceleration explicitly')
        self.index = finite(raw, 'acceleration')
        self.disabled = self.index < 0
        self.report_rate = finite(settings.get('report_rate', 0), 'report_rate')
        self.fixed_multiplier = finite(settings.get('fixed_multiplier', 1), 'fixed_multiplier')
        if self.report_rate < 0 or self.fixed_multiplier <= 0:
            raise ValueError('report_rate must be nonnegative and fixed_multiplier positive')
        self.last_t = None
        curves = settings.get('curves', [])
        if not curves:
            raise ValueError('no parametric curves; table fallback is not implemented by this probe')
        indices = [finite(c['index'], 'curve index') for c in curves]
        if indices != sorted(set(indices)):
            raise ValueError('curves must have unique ascending indices')
        lo = max(0, bisect.bisect_right(indices, self.index) - 1)
        hi = min(lo + 1, len(curves) - 1)
        ratio = max(0, (self.index - indices[lo]) / (indices[hi] - indices[lo])) if hi != lo else 0
        self.c = {k: finite(curves[lo].get(k, 0), k) + ratio *
                  (finite(curves[hi].get(k, 0), k) - finite(curves[lo].get(k, 0), k)) for k in CURVE_KEYS}
        if any(self.c[k] < 0 for k in CURVE_KEYS) or not any(self.c[k] for k in CURVE_KEYS[:4]):
            raise ValueError('curve needs nonnegative coefficients and a nonzero gain')
        self.linear, self.parabolic, self.cubic, self.quartic = [self.c[k] for k in CURVE_KEYS[:4]]
        self.tl, self.tr = [self.c[k] for k in CURVE_KEYS[4:]]
        if self.tl and self.tr and self.tr < self.tl:
            raise ValueError('root tangent must not precede linear tangent')
        self.t0 = self.t1 = math.inf
        self.m0 = self.b0 = self.m1 = self.b1 = 0.0
        if self.tl:
            y0 = self.poly(self.tl)
            self.m0 = self.derivative(self.tl)
            self.b0 = y0 - self.m0 * self.tl
            self.t0 = self.tl
            if self.tr:
                y1 = self.m0 * self.tr + self.b0
                self.m1 = 2 * y1 * self.m0
                self.b1 = y1 * y1 - self.m1 * self.tr
                self.t1 = self.tr
        elif self.tr:
            # Follow executable source, including its root-only branch, rather
            # than assuming that the preceding source comment is the formula.
            y0 = self.poly(self.tr)
            self.m1 = self.derivative(self.tr)
            self.b1 = y0 * y0 - self.m1 * self.tr
            self.t0 = self.tr

    def poly(self, x):
        return self.linear*x + (self.parabolic*x)**2 + (self.cubic*x)**3 + (self.quartic*x)**4

    def derivative(self, x):
        return self.linear + 2*x*self.parabolic**2 + 3*x*x*self.cubic**3 + 4*x**3*self.quartic**4

    def accelerated_velocity(self, velocity):
        x = velocity / (self.resolution / self.rate)
        if x <= self.t0:
            result = self.poly(x)
        elif x <= self.t1 and self.t0 == self.tl:
            result = self.m0*x + self.b0
        else:
            result = math.sqrt(max(0, self.m1*x + self.b1))
        return result * 96 / 67

    def delta(self, t, dx, dy):
        t, dx, dy = finite(t, 'timestamp'), finite(dx, 'dx'), finite(dy, 'dy')
        if self.last_t is not None and t <= self.last_t:
            raise ValueError('timestamps must increase within a segment')
        dt = t - self.last_t if self.last_t is not None else None
        self.last_t = t
        if self.disabled:
            return dx, dy, 1.0
        rate_multiplier = 1
        if self.report_rate and dt:
            period = 1 / self.report_rate
            rate_multiplier = period / max(period, dt)
        velocity = math.floor(math.hypot(dx, dy))
        velocity *= rate_multiplier if self.fixed_multiplier == 1 else self.fixed_multiplier
        velocity = max(1 / 65536, velocity)
        gain = self.accelerated_velocity(velocity) / velocity
        return dx*gain, dy*gain, gain


def select_settings(path, device_id):
    config = json.loads(Path(path).read_text())
    choices = [d for d in config['devices'] if str(d['device_id']) == str(device_id)]
    if len(choices) != 1:
        raise ValueError('device ID must match exactly one settings entry')
    return choices[0]


def predictions(rows, settings, *, units='counts', counts_per_mm=None, acceleration=None):
    if units == 'mm' and (counts_per_mm is None or finite(counts_per_mm, 'counts_per_mm') <= 0):
        raise ValueError('mm input requires an explicit positive --counts-per-mm; OMS-to-pointer scaling is not established')
    model, last_segment = None, object()
    for row in rows:
        segment = row.get('segment', '0')
        if model is None or segment != last_segment:
            model = Parametric(settings, acceleration)
            last_segment = segment
        dx, dy = finite(row['dx'], 'dx'), finite(row['dy'], 'dy')
        scale = counts_per_mm if units == 'mm' else 1
        px, py, gain = model.delta(row['t'], dx*scale, dy*scale)
        yield {**row, 'predicted_dx': px, 'predicted_dy': py, 'gain': gain}


def compare(rows):
    grouped = {}
    errors = []
    for row in rows:
        if row.get('native_dx', '') == '' or row.get('native_dy', '') == '':
            continue
        nx, ny = finite(row['native_dx'], 'native_dx'), finite(row['native_dy'], 'native_dy')
        px, py = row['predicted_dx'], row['predicted_dy']
        errors.append((px-nx)**2 + (py-ny)**2)
        segment = grouped.setdefault(row.get('segment', '0'), [0., 0., 0., 0., 0])
        for i, value in enumerate([px, py, nx, ny, 1]): segment[i] += value
    return {'samples': len(errors), 'vector_rmse_points': math.sqrt(sum(errors)/len(errors)) if errors else None,
            'segments': {k: {'predicted': v[:2], 'native': v[2:4], 'samples': v[4],
                             'endpoint_error_points': math.hypot(v[0]-v[2], v[1]-v[3])} for k, v in grouped.items()},
            'claim': 'Model comparison only; not a verified reproduction of native trackpad feel.'}


def recording_rows(records, width_mm, height_mm, latency_ms=0):
    metadata = records[0]
    if metadata.get('schema') != 'gesturepad.pointer-recording.v1':
        raise ValueError('unsupported recording schema')
    if metadata.get('tap_disabled') or metadata.get('start_result', 0) or metadata.get('stop_result', 0):
        raise ValueError('recording reported a permission/tap/native session failure; recapture')
    if metadata.get('dropped_contacts', 0) or metadata.get('dropped_pointer', 0):
        raise ValueError('recording dropped samples; recapture instead of silently comparing incomplete data')
    events = sorted([r for r in records[1:] if r['kind'] == 'pointer'], key=lambda r:r['t'])
    times = [r['t'] for r in events]
    if len(events) < 2:
        raise ValueError('recording has no usable pointer events; check Input Monitoring and native input')
    def cursor(t):
        t += latency_ms/1000
        index = bisect.bisect_right(times, t)
        if index == 0 or index == len(events): return None
        a, b = events[index-1], events[index]
        # Do not interpolate across a long gap or screen clamping interval.
        if b['t'] - a['t'] > .1 or a.get('edge') or b.get('edge'): return None
        fraction = (t-a['t'])/(b['t']-a['t']) if b['t'] != a['t'] else 0
        return (a['x'] + fraction*(b['x']-a['x']), a['y'] + fraction*(b['y']-a['y']))
    previous, segment = None, 0
    for r in sorted([r for r in records[1:] if r['kind'] == 'contacts'], key=lambda r:r['t']):
        contacts = [c for c in r['contacts'] if c['state'] in (3, 4)]
        if len(contacts) != 1:
            previous = None
            continue
        c = contacts[0]
        pos = cursor(r['t'])
        if previous:
            p, pc, ppos = previous
            if c['id'] != pc['id'] or r['t']-p['t'] > .05 or pos is None or ppos is None:
                previous = None
        if previous:
            p, pc, ppos = previous
            yield {'t': r['t'], 'dx': (c['x']-pc['x'])*width_mm,
                   'dy': -(c['y']-pc['y'])*height_mm, 'segment': segment,
                   'native_dx': pos[0]-ppos[0], 'native_dy': pos[1]-ppos[1]}
        else:
            segment += 1
        previous = (r, c, pos)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    snap = sub.add_parser('snapshot', help='read installed registry curve/settings defaults; never opens or changes a device')
    snap.add_argument('--output', required=True)
    pred = sub.add_parser('predict', help='CSV t,dx,dy[,segment,native_dx,native_dy] -> predicted deltas')
    pred.add_argument('--settings', required=True); pred.add_argument('--device-id', required=True)
    pred.add_argument('--input', required=True); pred.add_argument('--output', required=True)
    pred.add_argument('--units', choices=['counts', 'mm'], required=True)
    pred.add_argument('--counts-per-mm', type=float)
    pred.add_argument('--acceleration', type=float, help='raw curve index, NOT a UI slider tick')
    pred.add_argument('--summary', required=True)
    prep = sub.add_parser('prepare', help='one-finger native recorder JSONL -> millimetre CSV with observed cursor deltas')
    prep.add_argument('--input', required=True); prep.add_argument('--output', required=True)
    prep.add_argument('--width-mm', type=float, required=True); prep.add_argument('--height-mm', type=float, required=True)
    prep.add_argument('--latency-ms', type=float, default=0)
    opts = parser.parse_args()
    if opts.command == 'snapshot':
        result = snapshot()
        if not result['devices']: raise ValueError('no installed trackpad parametric curves found')
        Path(opts.output).write_text(json.dumps(result, indent=2)+'\n')
        print(json.dumps({'output': opts.output, 'devices': [{k:d[k] for k in ['device_id','serial','transport','resolution','acceleration','report_rate','fixed_multiplier']} for d in result['devices']]}, indent=2))
    elif opts.command == 'prepare':
        if not (math.isfinite(opts.width_mm) and math.isfinite(opts.height_mm) and opts.width_mm > 0 and opts.height_mm > 0):
            raise ValueError('pad dimensions must be positive finite millimetres')
        rows = list(recording_rows([json.loads(line) for line in Path(opts.input).read_text().splitlines()], opts.width_mm, opts.height_mm, finite(opts.latency_ms,'latency_ms')))
        if not rows: raise ValueError('no comparable one-finger segments; record more movement away from screen edges')
        with Path(opts.output).open('w', newline='') as file:
            writer = csv.DictWriter(file, fieldnames=['t','dx','dy','segment','native_dx','native_dy']); writer.writeheader(); writer.writerows(rows)
        print(f'Prepared {len(rows)} comparable deltas in mm: {opts.output}')
    else:
        settings = select_settings(opts.settings, opts.device_id)
        with Path(opts.input).open(newline='') as file:
            rows = list(predictions(csv.DictReader(file), settings, units=opts.units, counts_per_mm=opts.counts_per_mm, acceleration=opts.acceleration))
        if not rows: raise ValueError('input contains no deltas')
        with Path(opts.output).open('w', newline='') as file:
            fields = list(rows[0]); writer = csv.DictWriter(file, fieldnames=fields); writer.writeheader(); writer.writerows(rows)
        result = {**compare(rows), 'device_id': opts.device_id, 'input_units': opts.units,
                  'counts_per_mm_assumption': opts.counts_per_mm, 'apple_source_commit': APPLE_COMMIT}
        Path(opts.summary).write_text(json.dumps(result, indent=2)+'\n')
        print(json.dumps(result, indent=2))

if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, json.JSONDecodeError) as error:
        print(f'ERROR: {error}', file=sys.stderr)
        sys.exit(1)
