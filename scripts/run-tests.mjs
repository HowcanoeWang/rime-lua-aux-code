import { readdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const tests = readdirSync(resolve(root, 'tests'))
  .filter((name) => name.endsWith('_test.lua'))
  .sort();

for (const test of tests) {
  console.log(`lua tests/${test}`);
  const result = spawnSync('lua', [resolve(root, 'tests', test)], {
    cwd: root,
    stdio: 'inherit',
  });
  if (result.error) {
    console.error(result.error.message);
    process.exit(1);
  }
  if (result.status !== 0) process.exit(result.status ?? 1);
}
