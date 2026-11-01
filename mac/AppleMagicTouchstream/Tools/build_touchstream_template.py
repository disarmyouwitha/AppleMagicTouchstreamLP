#!/usr/bin/env python3
"""Generate an offline FingerWorks-inspired preset, without touching preferences."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'AppleMagicTouchstream/AppleMagicTouchstream'


def shortcut(label, held=False):
    return 'shortcut:' + json.dumps({'holdUntilRelease': held, 'label': label}, sort_keys=True, separators=(',', ':'))


def hand():
    return {
        'bindings': {
            **{name: 'disabled' for name in ['twoFingerMove', 'twoFingerTap', 'threeFingerMove', 'threeFingerTap', 'fourFingerMove', 'fourFingerTap', 'fiveFingerMove', 'fiveFingerTap', 'thumbTwoTap', 'fourCornersTap', 'twoFingerPinch']},
            'forceActions': {f'{n}FingerForce': 'disabled' for n in ['one', 'two', 'three', 'four', 'five']},
            'pinchActions': {f'{n}FingerPinch': 'disabled' for n in ['three', 'four', 'five']},
            'spreadActions': {f'{n}FingerSpread': 'disabled' for n in ['two', 'three', 'four', 'five']},
            'rotationActions': {f'{n}FingerRotate{d}': 'disabled' for n in ['two', 'three', 'four', 'five'] for d in ['Left', 'Right']},
        },
        'pointerSensitivity': 1, 'scrollSensitivity': 1, 'zoomSensitivity': 1,
        'directionalMovement': {},
        'holdActions': {**{str(n): 'disabled' for n in range(2, 7)}, '7': 'openConfig'},
        'holdThresholds': {**{str(n): 0.5 for n in range(2, 7)}, '7': 1},
    }


def directions(hand, trigger, assignments, repeating=()):
    names = ['upLeft', 'upRight', 'downLeft', 'downRight'] if trigger == 'thumbTwoMove' else ['left', 'right', 'up', 'down']
    hand['directionalMovement'][trigger] = {
        'mode': 'directional',
        'actions': {d: shortcut(assignments[d]) if d in assignments else 'disabled' for d in names},
        'repeatBehaviors': {d: 'motion' for d in names},
        'repeatEnabledOverrides': {d: d in repeating for d in names},
        'repeatIntervalsMS': {d: 80 for d in names},
    }


def generate(base):
    left, right = hand(), hand()
    # Left compact-finger text-navigation family (Quick Guide p1; XML Text Pointing/Selection).
    directions(left, 'twoFingerMove', {d: d.title() for d in ['left', 'right', 'up', 'down']}, ['left', 'right', 'up', 'down'])
    directions(left, 'threeFingerMove', {d: 'Shift+' + d.title() for d in ['left', 'right', 'up', 'down']}, ['left', 'right', 'up', 'down'])
    directions(left, 'fourFingerMove', {'left': 'Cmd+Left', 'right': 'Cmd+Right', 'up': 'PageUp', 'down': 'PageDown'}, ['up', 'down'])
    # App has no compact/spread 2F tap distinction: Copy is relocated to stationary 2F Hold.
    for h in [left, right]:
        h['bindings']['twoFingerPinch'] = shortcut('Cmd+X')
        h['bindings']['spreadActions']['twoFingerSpread'] = shortcut('Cmd+V')
        h['holdActions']['2'] = shortcut('Cmd+C')
        h['bindings']['pinchActions']['fiveFingerPinch'] = 'zoom'
        h['bindings']['spreadActions']['fiveFingerSpread'] = 'zoom'
    left['holdActions']['4'] = shortcut('Shift', True)
    right['holdActions']['4'] = shortcut('Cmd', True)
    # Font styles: use the available Thumb+2 diagonal compass instead of original cardinals.
    directions(left, 'thumbTwoMove', {'upLeft': 'Cmd+B', 'upRight': 'Cmd+I', 'downLeft': 'Cmd+U', 'downRight': 'Cmd+K'})
    left['bindings']['pinchActions']['threeFingerPinch'] = shortcut('Cmd+D')
    left['bindings']['spreadActions']['threeFingerSpread'] = shortcut('Cmd+A')
    left['bindings']['rotationActions']['threeFingerRotateLeft'] = shortcut('Cmd+1')
    left['bindings']['rotationActions']['threeFingerRotateRight'] = shortcut('Cmd+2')
    # Preserve the ordinary mouse family on the right pad.
    right['bindings'].update(twoFingerMove='pointer', twoFingerTap='primaryClick', threeFingerMove='primaryDrag', threeFingerTap='primaryDoubleClick', fourFingerMove='scroll', thumbTwoTap='secondaryClick')
    right['bindings']['pinchActions']['threeFingerPinch'] = shortcut('Cmd+F')
    right['bindings']['spreadActions']['threeFingerSpread'] = shortcut('Cmd+D')  # Exact Mac XML Replace shortcut, app-dependent.
    right['bindings']['rotationActions']['threeFingerRotateLeft'] = shortcut('Cmd+Y')
    right['bindings']['rotationActions']['threeFingerRotateRight'] = shortcut('Cmd+G')
    directions(right, 'thumbTwoMove', {'upLeft': 'Cmd+Z', 'downLeft': 'Shift+Cmd+Z', 'upRight': 'Tab', 'downRight': 'Shift+Tab'})
    right['bindings']['pinchActions']['fourFingerPinch'] = shortcut('Cmd+S')
    right['bindings']['spreadActions']['fourFingerSpread'] = shortcut('Cmd+N')
    # 4F rotation is not implemented: Open/Close are explicitly relocated to 5F rotation.
    right['bindings']['rotationActions']['fiveFingerRotateLeft'] = shortcut('Cmd+O')
    right['bindings']['rotationActions']['fiveFingerRotateRight'] = shortcut('Cmd+W')
    # T3F cardinal file navigation collides with the 4F scroll owner: relocate to 5F.
    directions(right, 'fiveFingerMove', {'left': 'Cmd+Left', 'right': 'Cmd+Right', 'up': 'Cmd+[', 'down': 'Cmd+R'})
    # Enhanced modifier chords need row/zone identity; Both only retains the neutral Enter chord.
    chords = ['fourCorners', 'innerCorners', 'topOuterCorners', 'topInnerCorners', 'bottomOuterCorners', 'bottomInnerCorners', 'threeFingers', 'fourFingers']
    coordinated = {'assignments': {}, 'holdThresholds': {c: 0.5 for c in chords}}
    for c in chords:
        for phase in (['tap', 'hold', 'force'] if c in ['threeFingers', 'fourFingers'] else ['hold']):
            coordinated['assignments'][f'{c}.{phase}'] = 'disabled'
    coordinated['assignments']['fourCorners.hold'] = 'openConfig'
    coordinated['holdThresholds']['fourCorners'] = 1
    coordinated['assignments']['threeFingers.tap'] = shortcut('Enter')
    return {
        'Version': 1,
        'Settings': {'LayoutPresetName': 'TouchStream', 'ActiveLayer': 0},
        # Include the complete keyboard mapping snapshot; importer replaces this collection.
        'KeymapJson': base['KeymapJson'],
        'HostExtensions': {'mac': {'GestureBindings': {'left': left, 'right': right, 'coordinated': coordinated}}},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', type=Path, default=APP / 'MY_KEYMAP.json')
    parser.add_argument('--output', type=Path, default=ROOT / 'AppleMagicTouchstream/AppleMagicTouchstream/TOUCHSTERAM_KEYMAP.json')
    args = parser.parse_args()
    data = args.base.read_bytes()
    base = json.loads(data)
    result = generate(base)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(f'Wrote {args.output.name}; keyboard source SHA-256 {hashlib.sha256(data).hexdigest()}')


if __name__ == '__main__':
    main()
