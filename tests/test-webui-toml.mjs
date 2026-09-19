import fs from 'node:fs';
import assert from 'node:assert/strict';
import { parse, stringify } from '../webui/node_modules/smol-toml/dist/index.js';

const sourcePath = process.argv[2] || 'module/config/config.toml';
const source = fs.readFileSync(sourcePath, 'utf8');
const parsed = parse(source);
const serialized = stringify(parsed);
const reparsed = parse(serialized);
assert.deepEqual(reparsed, parsed);
if (parsed.flags?.enable_kcp_proxy !== undefined) {
  assert.equal(reparsed.flags.enable_kcp_proxy, parsed.flags.enable_kcp_proxy);
}
if (parsed.peer) assert.equal(reparsed.peer.length, parsed.peer.length);
process.stdout.write(serialized);
