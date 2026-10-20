import fs from 'node:fs';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { parse, stringify } from '../webui/node_modules/smol-toml/dist/index.js';

const mainSource = fs.readFileSync(new URL('../webui/src/main.js', import.meta.url), 'utf8');
const configHelpers = vm.createContext({ parseTomlDocument: parse, stringifyTomlDocument: stringify });
vm.runInContext(mainSource.slice(
  mainSource.indexOf('const DEFAULT_CONFIG_TEMPLATE ='),
  mainSource.indexOf('// Application State & DOM Bindings'),
), configHelpers);
for (const input of [
  fs.readFileSync(new URL('../module/config/config.toml', import.meta.url), 'utf8'),
  'hostname = "example-relay"\n',
  'hostname = "example-dhcp"\ndhcp = true\n',
  'hostname = "example-blank"\nipv4 = ""\n',
]) {
  const visual = configHelpers.parseToml(input);
  assert.equal(visual.ipv4, '', 'A missing virtual IP must not acquire a shared static address');
  const saved = parse(configHelpers.generateToml(visual));
  assert.equal(saved.ipv4, undefined, 'Blank visual IP fields must remain unconfigured');
  assert.equal(saved.dhcp, parse(input).dhcp ?? false);
}
const fixed = configHelpers.parseToml('ipv4 = "10.42.0.12/24"\ncustom_root = "keep"\n');
assert.equal(parse(configHelpers.generateToml(fixed)).ipv4, '10.42.0.12/24');
assert.equal(parse(configHelpers.generateToml(fixed)).custom_root, 'keep');

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
