import { readFile, writeFile, mkdir, access } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { createHash } from 'node:crypto';

const root = fileURLToPath(new URL('../', import.meta.url));
const vendor = path.join(root, 'Vendor/Finance');
let defaultSource = vendor;
try { await access(path.join(vendor, 'core.js')); } catch { defaultSource = path.resolve(root, '../finance/js'); }
const source = process.argv[2] ? path.resolve(process.argv[2]) : defaultSource;
const names = ['core.js', 'schema.js', 'commands.js', 'store.js'];
const files = await Promise.all(names.map(name => readFile(path.join(source, name), 'utf8')));
const manifest = Object.fromEntries(files.map((text, i) => [names[i], createHash('sha256').update(text).digest('hex')]));
const body = files.map((text, i) => `// ${names[i]} sha256:${manifest[names[i]]}\n` + text
  .replace(/^import\s+[\s\S]*?from\s+['"][^'"]+['"];\s*$/gm, '')
  .replace(/^export\s+(?=(?:const|let|function|class)\b)/gm, '')).join('\n');
const adapter = await readFile(path.join(root, 'tools/bridge.js'), 'utf8');
const out = path.join(root, 'Sources/LumoCore/Resources');
await mkdir(out, { recursive: true });
await mkdir(vendor, { recursive: true });
for (let i = 0; i < names.length; i++) await writeFile(path.join(vendor, names[i]), files[i], 'utf8');
await writeFile(path.join(out, 'finance-engine.js'), `// Generated from the audited web core. Do not edit.\n(function () {\n'use strict';\n${body}\n${adapter}\n})();\n`, 'utf8');
await writeFile(path.join(root, 'engine-manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log(`Bundled ${names.length} audited modules for JavaScriptCore`);
