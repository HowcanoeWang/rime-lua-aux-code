import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, '..');
const pkgPath = resolve(root, 'package.json');

const pkg = JSON.parse(readFileSync(pkgPath, 'utf-8'));

let failures = 0;

function fail(msg) {
  console.error('FAIL:', msg);
  failures++;
}

function ok(msg) {
  console.log(' OK :', msg);
}

const expectedFiles = ['lua/aux_code.lua', 'lua/aux_code_updater.lua'];

if (!pkg.files || !Array.isArray(pkg.files)) {
  fail('"files" field is missing or not an array');
} else {
  const actualSet = new Set(pkg.files);
  const expectedSet = new Set(expectedFiles);
  const missing = expectedFiles.filter(f => !actualSet.has(f));
  const extra = pkg.files.filter(f => !expectedSet.has(f));

  if (missing.length > 0) {
    fail('files whitelist missing entries: ' + missing.join(', '));
  }
  if (extra.length > 0) {
    fail('files whitelist contains unexpected entries: ' + extra.join(', '));
  }
  if (missing.length === 0 && extra.length === 0) {
    ok('files whitelist is accurate');
  }

  for (const file of expectedFiles) {
    try {
      readFileSync(resolve(root, file));
      ok(`file exists: ${file}`);
    } catch {
      fail(`file is listed but does not exist on disk: ${file}`);
    }
  }
}

try {
  const auxCode = readFileSync(resolve(root, 'lua/aux_code.lua'), 'utf-8');
  const verMatch = auxCode.match(/VERSION\s*=\s*"([^"]+)"/);
  if (verMatch) {
    const luaVersion = verMatch[1];
    if (luaVersion !== pkg.version) {
      fail(`version mismatch: package.json=${pkg.version}, aux_code.lua VERSION=${luaVersion}`);
    } else {
      ok(`version matches: ${pkg.version}`);
    }
  } else {
    fail('no VERSION found in lua/aux_code.lua');
  }
} catch {
  fail('cannot read lua/aux_code.lua');
}

if (pkg.rimePlugin?.schema === 1 && pkg.rimePlugin?.updaterApi === 1 && pkg.rimePlugin?.files) {
  const hashes = pkg.rimePlugin.files;
  const hashKeys = Object.keys(hashes);
  const unexpectedHashes = hashKeys.filter((file) => !expectedFiles.includes(file));
  if (hashKeys.length !== expectedFiles.length || unexpectedHashes.length > 0) {
    fail(`rimePlugin.files contains unexpected entries: ${unexpectedHashes.join(', ') || '(count mismatch)'}`);
  }
  for (const file of expectedFiles) {
    const filePath = resolve(root, file);
    try {
      const content = readFileSync(filePath);
      const actualHash = createHash('sha512').update(content).digest('base64');
      const actualSRI = `sha512-${actualHash}`;

      if (!hashes[file]) {
        fail(`hash missing in rimePlugin for: ${file}`);
      } else if (hashes[file] !== actualSRI) {
        fail(`hash mismatch for ${file}: expected=${hashes[file]}, actual=${actualSRI}`);
      } else {
        ok(`hash matches for: ${file}`);
      }
    } catch (err) {
      if (err.code === 'ENOENT') {
        fail(`cannot verify hash for missing file: ${file}`);
      } else {
        fail(`error reading ${file}: ${err.message}`);
      }
    }
  }
} else {
  fail('rimePlugin schema, updaterApi, or files is invalid in package.json');
}

console.log('');
console.log(`verification complete: ${failures} failure(s)`);

if (failures > 0) {
  process.exit(1);
}
