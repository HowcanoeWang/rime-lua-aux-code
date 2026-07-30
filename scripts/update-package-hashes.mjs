import { readFileSync, writeFileSync, renameSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, '..');
const pkgPath = resolve(root, 'package.json');

const pkg = JSON.parse(readFileSync(pkgPath, 'utf-8'));

const files = pkg.files;
if (!Array.isArray(files) || files.length === 0) {
  console.error('error: "files" field is missing or empty in package.json');
  process.exit(1);
}
const expectedFiles = ['lua/aux_code.lua', 'lua/aux_code_updater.lua'];
if (files.length !== expectedFiles.length || expectedFiles.some((file) => !files.includes(file))) {
  console.error('error: package files must contain exactly:', expectedFiles.join(', '));
  process.exit(1);
}

const computed = {};
for (const file of files) {
  const filePath = resolve(root, file);
  try {
    const content = readFileSync(filePath);
    const hash = createHash('sha512').update(content).digest('base64');
    const sri = `sha512-${hash}`;
    computed[file] = sri;
  } catch (err) {
    if (err.code === 'ENOENT') {
      console.error('error: file not found:', file);
      process.exit(1);
    } else {
      throw err;
    }
  }
}

pkg.rimePlugin = {
  schema: 1,
  updaterApi: 1,
  files: computed,
};

const tmpPath = `${pkgPath}.tmp`;
writeFileSync(tmpPath, JSON.stringify(pkg, null, 2) + '\n');
renameSync(tmpPath, pkgPath);

console.log('updated hashes:');
for (const [file, sri] of Object.entries(computed)) {
  console.log(`  ${file} -> ${sri}`);
}
