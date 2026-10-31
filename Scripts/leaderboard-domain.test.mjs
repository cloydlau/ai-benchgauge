import assert from 'node:assert/strict'
import test from 'node:test'
import {readFileSync,mkdtempSync,mkdirSync,writeFileSync,rmSync} from 'node:fs'
import {tmpdir} from 'node:os'
import {join} from 'node:path'
import {execFileSync} from 'node:child_process'
import {latestTimestamp,companyRows,createBrandRules,replacementFailure,countryCode,resolvedOpenness} from '../fc/domain.mjs'
const catalog=JSON.parse(readFileSync(new URL('../fc/brand-catalog.json',import.meta.url)))
const countries=JSON.parse(readFileSync(new URL('../fc/country-catalog.json',import.meta.url)))
const policy=JSON.parse(readFileSync(new URL('../fc/leaderboard-policy.json',import.meta.url)))
test('Apple/Windows generated policy cannot drift from the server/mini-program catalogs',()=>{
 const script=new URL('./generate-leaderboard-policy.mjs',import.meta.url)
 execFileSync(process.execPath,[script.pathname,'--check'])
 const dir=mkdtempSync(join(tmpdir(),'board-policy-'))
 try{
  mkdirSync(join(dir,'fc'));mkdirSync(join(dir,'Sources/LeaderboardKit'),{recursive:true})
  writeFileSync(join(dir,'fc/country-catalog.json'),JSON.stringify(countries));writeFileSync(join(dir,'fc/brand-catalog.json'),JSON.stringify(catalog));writeFileSync(join(dir,'fc/leaderboard-policy.json'),JSON.stringify(policy))
  execFileSync(process.execPath,[script.pathname,'--root',dir])
  execFileSync(process.execPath,[script.pathname,'--root',dir,'--check'])
  const legacyCatalog={...catalog};delete legacyCatalog.modelDevelopers;delete legacyCatalog.modelDisplayAliases
  writeFileSync(join(dir,'fc/brand-catalog.json'),JSON.stringify(legacyCatalog))
  execFileSync(process.execPath,[script.pathname,'--root',dir])
  assert.match(readFileSync(join(dir,'Sources/LeaderboardKit/LeaderboardBrandPolicy.generated.swift'),'utf8'),/modelDevelopersStorage: \[String: String\] = \[\n\n    \]/)
  assert.match(readFileSync(join(dir,'Sources/LeaderboardKit/LeaderboardBrandPolicy.generated.swift'),'utf8'),/modelDisplayAliasesStorage: Set<String> = \[\]/)
  const legacyPolicy={...policy};delete legacyPolicy.verifiedModelOpenness
  writeFileSync(join(dir,'fc/leaderboard-policy.json'),JSON.stringify(legacyPolicy))
  execFileSync(process.execPath,[script.pathname,'--root',dir])
  execFileSync(process.execPath,[script.pathname,'--root',dir,'--check'])
  assert.match(readFileSync(join(dir,'Sources/LeaderboardKit/LeaderboardBrandPolicy.generated.swift'),'utf8'),/verifiedModelOpennessStorage: \[String: String\] = \[\n\n    \]/)
  writeFileSync(join(dir,'Sources/LeaderboardKit/LeaderboardBrandPolicy.generated.swift'),'stale')
  assert.throws(()=>execFileSync(process.execPath,[script.pathname,'--root',dir,'--check'],{stdio:'pipe'}),/Command failed/)
 }finally{rmSync(dir,{recursive:true,force:true})}
})
test('shared date vectors prefer source time regardless of recency and fall back only when unavailable',()=>{
 for(const row of JSON.parse(readFileSync(new URL('../Tests/fixtures/mobile-times.json',import.meta.url))))assert.equal(latestTimestamp(row),row.expected)
 assert.equal(latestTimestamp(null),null);assert.equal(latestTimestamp({sourceUpdatedAt:'invalid'}),null)
 assert.equal(latestTimestamp({sourceUpdatedAt:'invalid',fetchedAt:'2026-10-14T08:00:00Z'}),'2026-10-14T08:00:00Z')
 assert.equal(latestTimestamp({sourceUpdatedAt:'2026-10-14T06:00:00Z',fetchedAt:'invalid'}),'2026-10-14T06:00:00Z')
})
test('verified Trinity identities share an Arcee AI company without capturing variants or another owner',()=>{
 const rules=createBrandRules(catalog)
 const names=['trinity-large-preview','trinity-large-thinking']
 for(const name of names)assert.equal(rules.brandKey({name}),'arceeai')
 assert.equal(rules.brandKey({name:' TRINITY-LARGE-THINKING ',organization:'Unknown'}),'arceeai')
 assert.equal(rules.brandKey({name:'trinity-large-thinking-finetune'}),null)
 assert.equal(rules.brandKey({name:names[0],organization:'Other Maker'}),'othermaker')
 const rows=companyRows(names.map((name,index)=>({rank:index+1,name,score:100-index})))
 assert.equal(rows.length,1);assert.equal(rows[0].name,'Arcee AI');assert.equal(rows[0].components.length,2)
})
test('verified Solar identity repairs an absent developer without capturing variants or another owner',()=>{
 const rules=createBrandRules(catalog)
 assert.equal(rules.brandKey({name:'solar-10.7b-instruct-v1.0'}),'upstage')
 assert.equal(rules.brandKey({name:'SOLAR-10.7B-Instruct-v1.0',organization:'Unknown'}),'upstage')
 assert.equal(rules.brandKey({name:'solar-10.7b-instruct-v1.0-finetune'}),null)
 assert.equal(rules.brandKey({name:'solar-10.7b-instruct-v1.0',organization:'Other Maker'}),'othermaker')
 const rows=companyRows([{rank:1,name:'solar-pro4',organization:'Upstage',score:100},
  {rank:2,name:'solar-10.7b-instruct-v1.0',score:90}])
 assert.equal(rows.length,1);assert.equal(rows[0].name,'Upstage');assert.equal(rows[0].components.length,2)
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
test('company aggregation reuses a matching sibling provider image while retaining the strongest score',()=>{
 const ready={key:'openai',status:'ready',pngData:'iVBORw0KGgo='}
 const rows=companyRows([
  {rank:1,name:'Best',organization:'OpenAI',score:99,organizationBrand:{key:'openai',status:'pending'},brand:{key:'model-gpt',pngData:'bW9kZWw='}},
  {rank:2,name:'Sibling',organization:'Open AI',score:90,brand:ready},
 ])
 assert.equal(rows.length,1)
 assert.deepEqual([rows[0].score,rows[0].bestRank,rows[0].rank],[99,1,1])
 assert.equal(rows[0].brand,ready);assert.equal(rows[0].organizationBrand,ready)
 assert.deepEqual(rows[0].components.map(row=>row.name),['Best','Sibling'])
 const hosted=companyRows([{rank:1,name:'Claude Code - Qwen3.8 Max',organization:'Anthropic',score:99,
  organizationBrand:{key:'anthropic',pngData:'aGFybmVzcw=='},brand:{key:'model-qwen',pngData:'bW9kZWw='}}])[0]
 assert.equal(hosted.name,'Alibaba')
 assert.deepEqual(hosted.organizationBrand,{key:'qwen'})
 assert.deepEqual(hosted.brand,{key:'qwen'})
})

test('cached display names resolve exact model IDs without assigning unrelated developers',()=>{
 const rules=createBrandRules(catalog)
 for(const id of ['yi-lightning',' YI-LIGHTNING ']) {
  const row={name:'Yi Lightning',modelID:id,developerCountry:{key:'',status:'missing'}}
  assert.equal(rules.brandKey(row),'01ai')
  assert.equal(countryCode(row),'CN')
  assert.equal(countryCode(companyRows([{...row,rank:1,score:99}])[0]),'CN')
 }
 assert.equal(rules.brandKey({name:'Yi Lightning',modelID:'yi-lightning-finetune'}),null)
 assert.equal(rules.brandKey({name:'Yi Lightning',modelID:'yi-lightning',organization:'Other Maker'}),'othermaker')
 assert.equal(countryCode({name:'OpenChat 3.5',modelID:'openchat-3.5'}),'unknown')
 assert.equal(countryCode({name:'Trinity Large Preview',modelID:'trinity-large'}),'US')
 assert.equal(countryCode({name:'Known',organization:'OpenAI',developerCountry:{countryCode:'TW'}}),'CN')
})

test('verified openness fills only the exact public model and respects explicit upstream classifications',()=>{
 assert.equal(resolvedOpenness({modelID:'internlm2_5-20b-chat'}),'open')
 assert.equal(resolvedOpenness({modelID:'internlm2_5-20b-chat-quantized'}),null)
 assert.equal(resolvedOpenness({name:'InternLM2.5 20B Chat'}),null)
 assert.equal(resolvedOpenness({modelID:'internlm2_5-20b-chat',openness:'closed'}),'closed')
})
