from pathlib import Path
from zipfile import ZipFile
import hashlib
import json
import plistlib
import struct
import sys

ipa = Path(sys.argv[1])
with ZipFile(ipa) as archive:
    names = archive.namelist()
    info_name = next(n for n in names if n.count('/') == 2 and n.endswith('.app/Info.plist'))
    app = info_name.removesuffix('Info.plist')
    info = plistlib.loads(archive.read(info_name))
    assert info['CFBundleIdentifier'] == 'app.lumo.wallet', 'Wrong bundle ID'
    assert info['MinimumOSVersion'] == '26.0', 'Wrong deployment target'
    assert info.get('CFBundleShortVersionString') == '2.1', 'Wrong release version'
    assert info.get('NSFaceIDUsageDescription'), 'Missing Face ID purpose string'
    executable = archive.read(app + info['CFBundleExecutable'])
    magic, cpu, subtype, filetype, count, size, flags, reserved = struct.unpack_from('<8I', executable)
    assert magic == 0xFEEDFACF and cpu == 0x0100000C, 'Expected ARM64 Mach-O'
    offset = 32
    dylibs = []
    signed = False
    for _ in range(count):
        command, length = struct.unpack_from('<II', executable, offset)
        if command in (0xC, 0x18, 0x80000018, 0x1F, 0x8000001F):
            string_offset = struct.unpack_from('<I', executable, offset + 8)[0]
            dylibs.append(executable[offset + string_offset:offset + length].split(b'\0')[0].decode())
        if command == 0x1D:
            signed = True
        offset += length
    assert any('/SwiftUI.framework/' in x for x in dylibs), 'Native SwiftUI not linked'
    assert any('/JavaScriptCore.framework/' in x for x in dylibs), 'Financial engine not linked'
    assert not any('/WebKit.framework/' in x for x in dylibs), 'Unexpected WebView dependency'
    engine_name = next(n for n in names if n.endswith('/finance-engine.js'))
    engine_hash = hashlib.sha256(archive.read(engine_name)).hexdigest()
    source_hash = hashlib.sha256((Path(__file__).resolve().parent.parent / 'Sources/LumoCore/Resources/finance-engine.js').read_bytes()).hexdigest()
    assert engine_hash == source_hash, 'Financial engine differs from verified source'
    print(json.dumps({'bundle': info['CFBundleIdentifier'], 'version': info['CFBundleShortVersionString'], 'minimumIOS': info['MinimumOSVersion'],
        'sdk': info.get('DTSDKName'), 'architecture': 'arm64', 'nativeSwiftUI': True,
        'engineSHA256': engine_hash, 'codeSignaturePresent': signed,
        'provisioningPresent': app + 'embedded.mobileprovision' in names,
        'ipaSHA256': hashlib.sha256(ipa.read_bytes()).hexdigest()}, indent=2))
