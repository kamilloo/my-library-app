import { createHash } from 'node:crypto';
import { readFile, readdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

const output = 'build/web';
const workerName = 'offline-worker.js';
const scannerName = 'zxing.min.js';
const scannerBase = 'https://unpkg.com/@zxing/library@0.23.0';
const scannerDigest = '3ede94153fb0c5b67a12d7adff6decd827c2b22714fdc6faecf27a8f20937ea6';

async function download(path) {
  const response = await fetch(`${scannerBase}/${path}`);
  if (!response.ok) throw new Error(`ZXing download failed (${response.status})`);
  return Buffer.from(await response.arrayBuffer());
}
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const scanner = await download('umd/index.min.js');
if (digest(scanner) !== scannerDigest) throw new Error('ZXing checksum mismatch');
await writeFile(join(output, scannerName), scanner);
await writeFile(join(output, 'zxing-LICENSE.txt'), await download('LICENSE'));

async function list(directory, prefix = '') {
  const files = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = prefix + entry.name;
    if (entry.isDirectory()) {
      files.push(...await list(join(directory, entry.name), path + '/'));
    } else if (!entry.name.startsWith('.') && !/\.map$/.test(path) &&
        ![workerName, 'flutter_service_worker.js'].includes(path)) {
      files.push(path);
    }
  }
  return files;
}

const files = (await list(output)).sort();
for (const required of ['index.html', 'main.dart.js', 'flutter_bootstrap.js',
    'sqlite3.wasm', 'sqflite_sw.js', 'canvaskit/canvaskit.wasm', scannerName]) {
  if (!files.includes(required)) throw new Error(`Missing web resource: ${required}`);
}
const workerTemplate = await readFile(join('web', workerName), 'utf8');
const revision = createHash('sha256').update(workerTemplate);
for (const path of files) {
  revision.update(path).update(await readFile(join(output, path)));
}
const build = { revision: revision.digest('hex'), files };
await writeFile(join(output, workerName),
  workerTemplate.replace('/* BUILD_INVENTORY */ null', JSON.stringify(build)));
console.log(`Prepared ${files.length} offline resources in ${output}`);
