import json
import sys

inventory = json.load(sys.stdin)
runtimes = [r for r in inventory['runtimes'] if r.get('isAvailable') and r['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS-')]
runtime = max(runtimes, key=lambda r: tuple(map(int, r['version'].split('.'))))
supported = {d['identifier'] for d in runtime.get('supportedDeviceTypes', [])}
available = {d['identifier']: d for d in inventory['devicetypes']}
prefix = 'com.apple.CoreSimulator.SimDeviceType.'
# Prefer the owner's model only when this runtime explicitly supports its profile.
preferred = prefix + 'iPhone-15-Pro'
if preferred not in supported:
    preferred = prefix + 'iPhone-17-Pro'
if preferred not in available or (supported and preferred not in supported):
    candidates = [d for key, d in available.items() if key in supported and d.get('productFamily') == 'iPhone']
    if not candidates:
        raise RuntimeError('No compatible iPhone simulator profile')
    preferred = candidates[-1]['identifier']
print(runtime['identifier'], preferred)
print(f"Preview: {available[preferred]['name']}, iOS {runtime['version']}", file=sys.stderr)
