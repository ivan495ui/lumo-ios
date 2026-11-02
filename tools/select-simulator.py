import json
import sys

inventory = json.load(sys.stdin)
runtimes = [r for r in inventory['runtimes'] if r.get('isAvailable') and r['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS-')]
available = {d['identifier']: d for d in inventory['devicetypes']}
prefix = 'com.apple.CoreSimulator.SimDeviceType.'
# A newer runtime may be specific to another form factor, such as iPhone Duo.
for model in ['iPhone-15-Pro']:
    preferred = prefix + model
    if preferred not in available:
        continue
    for runtime in sorted(runtimes, key=lambda r: tuple(map(int, r['version'].split('.'))), reverse=True):
        supported = {d['identifier'] for d in runtime.get('supportedDeviceTypes', [])}
        if preferred in supported:
            print(runtime['identifier'], preferred)
            print(f"Preview: {available[preferred]['name']}, iOS {runtime['version']}", file=sys.stderr)
            sys.exit(0)
raise RuntimeError('No compatible iPhone 15 Pro simulator profile; do not substitute another model')
