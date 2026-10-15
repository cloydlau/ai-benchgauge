import assert from 'node:assert/strict'
import test from 'node:test'
import {readFileSync,mkdtempSync,mkdirSync,writeFileSync,rmSync} from 'node:fs'
import {tmpdir} from 'node:os'
import {join} from 'node:path'
import {execFileSync} from 'node:child_process'
import {latestTimestamp,companyRows,createBrandRules,replacementFailure} from '../fc/domain.mjs'
const catalog=JSON.parse(readFileSync(new URL('../fc/brand-catalog.json',import.meta.url)))
const policy=JSON.parse(readFileSync(new URL('../fc/leaderboard-policy.json',import.meta.url)))
test('Apple/Windows generated policy cannot drift from the server/mini-program catalogs',()=>{
 const script=new URL('./generate-leaderboard-policy.mjs',import.meta.url)
 execFileSync(process.execPath,[script.pathname,'--check'])
 const dir=mkdtempSync(join(tmpdir(),'board-policy-'))
 try{
  mkdirSync(join(dir,'fc'));mkdirSync(join(dir,'Sources/LeaderboardKit'),{recursive:true})
  writeFileSync(join(dir,'fc/brand-catalog.json'),JSON.stringify(catalog));writeFileSync(join(dir,'fc/leaderboard-policy.json'),JSON.stringify(policy))
  execFileSync(process.execPath,[script.pathname,'--root',dir])
  execFileSync(process.execPath,[script.pathname,'--root',dir,'--check'])
  writeFileSync(join(dir,'Sources/LeaderboardKit/LeaderboardBrandPolicy.generated.swift'),'stale')
  assert.throws(()=>execFileSync(process.execPath,[script.pathname,'--root',dir,'--check'],{stdio:'pipe'}),/Command failed/)
 }finally{rmSync(dir,{recursive:true,force:true})}
})
test('shared date vectors select the latest actual timestamp, with no invented publication date',()=>{
 for(const row of JSON.parse(readFileSync(new URL('../Tests/fixtures/mobile-times.json',import.meta.url))))assert.equal(latestTimestamp(row),row.expected)
 assert.equal(latestTimestamp(null),null);assert.equal(latestTimestamp({sourceUpdatedAt:'invalid'}),null)
})
test('hosted models determine company standings consistently, ignoring fusion sidekicks',()=>{
 const rows=companyRows([{rank:1,name:'Claude Code - Qwen3.8 Max',organization:'Anthropic',score:90},
 {rank:2,name:'Codex - GPT-6 + Claude',organization:'OpenAI',score:89}])
 assert.deepEqual(rows.map(r=>[r.name,r.score]),[['Alibaba',90],['OpenAI',89]])
 const rules=createBrandRules(catalog)
 assert.equal(rules.bundledProductKey({name:'Claude Code - Qwen3.8 Max',organization:'Anthropic'}),'qwen')
 assert.equal(rules.bundledProductKey({name:'Claude Sonnet',organization:'Anthropic'}),'anthropic')
 assert.equal(rules.knownModelBrand({name:'Gemini 4 Argon',organization:'Google'}).key,'model-gemini')
 assert.equal(rules.knownModelBrand({name:'Geminiscope',organization:'Google'}),null)
 assert.equal(replacementFailure({kind:'other'},{kind:'one'}),'kind')
})
