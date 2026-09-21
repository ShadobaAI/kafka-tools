import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { planTrust, ensureTrust } from '../mcp/codex-project-trust.mjs';
const root = path.resolve('fixture');
assert.equal(planTrust({[root]:{trust_level:'trusted'}},[root]).pending.length,0);
assert.equal(planTrust({[root]:{trust_level:'untrusted',extra:1}},[root]).updated[root].extra,1);
const alternate = root.replaceAll('\\','/') + '/';
assert.deepEqual(Object.keys(planTrust({[alternate]:{trust_level:'trusted'}},[root]).updated),[root]);
assert.throws(()=>planTrust({[root]:{},[alternate]:{}},[root]),/Conflicting/);
if (process.argv.includes('--live-cli-fixture')) {
  const fixture=fs.mkdtempSync(path.join(os.tmpdir(),'toolkit-trust-test-'));
  try {
    const home=path.join(fixture,'home'), project=path.join(fixture,'project space тест');
    fs.mkdirSync(home);fs.mkdirSync(path.join(project,'.codex'),{recursive:true});
    assert.equal(spawnSync('git',['init','--quiet',project]).status,0);
    fs.writeFileSync(path.join(project,'.codex/config.toml'),'[mcp_servers.fixture]\ncommand="never-start"\n');
    const config=path.join(home,'config.toml'),env={...process.env,CODEX_HOME:home};
    // Missing user file is supported; check-only never creates the config.
    const missing=await ensureTrust([project],{env});
    assert.equal(missing.pending.length,1);assert.equal(fs.existsSync(config),false);
    fs.writeFileSync(config,'# preserve this comment\nmodel="fixture-model"\n[projects.other]\ntrust_level="untrusted"\n');
    const before=fs.readFileSync(config,'utf8');
    assert.equal((await ensureTrust([project],{env})).pending.length,1);
    assert.equal(fs.readFileSync(config,'utf8'),before);
    assert.equal((await ensureTrust([project],{env,approve:true})).changed,true);
    const once=fs.readFileSync(config,'utf8');
    assert.ok(once.includes('# preserve this comment'));assert.ok(once.includes('fixture-model'));assert.ok(once.includes('other'));
    assert.equal((await ensureTrust([project],{env,approve:true})).changed,false);
    assert.equal(fs.readFileSync(config,'utf8'),once);
    // A pre-existing equivalent spelling is migrated, not duplicated.
    fs.writeFileSync(config,'[projects.'+JSON.stringify(fs.realpathSync.native(project).replaceAll('\\','/')+'/')+']\ntrust_level="untrusted"\n');
    assert.equal((await ensureTrust([project],{env,approve:true})).changed,true);
    assert.equal((fs.readFileSync(config,'utf8').match(/trust_level/g)||[]).length,1);
    console.log('Live trust: missing file, no-op, update, equivalent path, preservation passed.');
  } finally {
    assert.equal(path.dirname(fixture),path.resolve(os.tmpdir()));
    assert.ok(path.basename(fixture).startsWith('toolkit-trust-test-'));
    await new Promise(resolve => setTimeout(resolve, 1000));
    fs.rmSync(fixture,{recursive:true,force:true,maxRetries:10,retryDelay:200});
  }
}
console.log('Project trust checks passed.');
