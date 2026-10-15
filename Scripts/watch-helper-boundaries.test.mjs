import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import cp from 'node:child_process'
import {syncBuiltinESMExports} from 'node:module'
import {EventEmitter} from 'node:events'
import {join} from 'node:path'
import {tmpdir} from 'node:os'
import {pathToFileURL} from 'node:url'

async function fixture(t){
 const root=fs.realpathSync(fs.mkdtempSync(join(tmpdir(),'benchgauge-watch-helper-')))
 fs.mkdirSync(join(root,'Scripts'));fs.mkdirSync(join(root,'Sources'));fs.mkdirSync(join(root,'.git'));fs.mkdirSync(join(root,'Sources/bin'));fs.writeFileSync(join(root,'Sources/.hidden'),'')
 fs.copyFileSync(new URL('./watch.mjs',import.meta.url),join(root,'Scripts/watch.mjs'))
 const stubs={
 'calmmit.mjs':`export const ci={load:async()=>({workflowStatus:(_,message)=>message})}`,
 'commit-identity.mjs':`export const avatarForModel=()=>{if(globalThis.unitAvatarFails)throw Error('avatar fixture');return 'fixture'};export const detectModelName=()=>globalThis.unitModel`,
 'commit-lock.mjs':`export const acquireCommitLock=()=>({acquired:true,release(){}})`,
 'desktop-notify.mjs':`export const materializeAvatar=()=>'fixture';export const notifyDesktop=()=>{if(globalThis.unitNotifyFails)throw Error('notification fixture')}`,
 'git-network.mjs':`export const gitProxyValue=()=>globalThis.unitProxy||'';export const gitProxyArgs=()=>[]`,
 'node-executable.mjs':`export const nodeExecutable=()=>process.execPath`,
 'weapp-deploy.mjs':`export const startWeappUploadWatch=async()=>()=>{}`,
 'test-repair.mjs':`export const runTestGate=async()=>({status:0})`,
 }
 for(const [name,source]of Object.entries(stubs))fs.writeFileSync(join(root,'Scripts',name),source)
 t.after(()=>{delete globalThis.unitModel;delete globalThis.unitAvatarFails;delete globalThis.unitNotifyFails;delete globalThis.unitProxy;fs.rmSync(root,{recursive:true,force:true});t.mock.restoreAll();syncBuiltinESMExports()})
 return {root,watch:await import(pathToFileURL(join(root,'Scripts/watch.mjs')).href)}
}

test('watch helpers keep Git and filesystem failures distinct without using the checkout',async t=>{
 const {root,watch}=await fixture(t)
 let response={status:0,stdout:''},warnings=[]
 t.mock.method(console,'warn',value=>warnings.push(value));t.mock.method(cp,'spawnSync',()=>response);syncBuiltinESMExports()
 assert.equal(watch.gitStatusSignature(),'')
 assert.equal(watch.nextWaitMs({now:0,lastChangeAt:NaN,debounceMs:100,throttleMs:0}),100)
 assert.equal(watch.parseAheadCount('0 invalid'),null)
 assert.equal(watch.commitExists(null),false)
 for(const error of [Object.assign(Error('denied'),{code:'EACCES'}),Error('fixture git error')]){response={error};assert.equal(watch.gitStatusSignature(),null)}
 response={status:2};assert.equal(watch.gitStatusSignature(),null)
 response={status:2,stderr:'fixture'};assert.equal(watch.gitStatusSignature(),null)
 const original=fs.lstatSync
 t.mock.method(fs,'lstatSync',()=>{throw Object.assign(Error('fixture'),{code:'EPERM'})});syncBuiltinESMExports()
 assert.equal(watch.fileFingerprint('fixture'),'unreadable:EPERM')
 fs.lstatSync=()=>{throw Error('unexpected fixture')};syncBuiltinESMExports();assert.throws(()=>watch.fileFingerprint('fixture'),/unexpected/)
 fs.lstatSync=original;syncBuiltinESMExports()
 response={status:0};assert.equal(watch.gitStatusSignature(),'');assert.equal(watch.unpushedState().state,'unknown')
 cp.spawnSync=(_command,args)=>({status:0,stdout:args.includes('rev-list')?'0 1':undefined});syncBuiltinESMExports();assert.equal(watch.unpushedState().state,'ahead');cp.spawnSync=()=>response;syncBuiltinESMExports()
 assert.equal(watch.appChangedBetween(null,'head'),false);assert.equal(watch.appChangedBetween('head','head'),false)
 fs.mkdirSync(join(root,'work'));fs.writeFileSync(join(root,'work/.last-app-deploy'),'{}');assert.equal(watch.readDeployedCommit(),null)
 watch.writeDeployReceipt(null,'fixture');assert.equal(watch.deployedNotification().model,'')
 response={status:0,stdout:'fixture-author'};watch.writeDeployReceipt('commit',undefined);assert.equal(watch.deployedNotification().model,'fixture-author')
 process.env.UNIT_WATCH_DURATION='';assert.equal(watch.readDuration('UNIT_WATCH_DURATION',10),10)
 delete process.env.UNIT_WATCH_DURATION;assert.equal(watch.readDuration('UNIT_WATCH_DURATION',10),10)
 assert.equal(watch.signature(new Map([['b',2],['a',1]])),'a:1\0b:2')
})

test('watch command wrappers propagate process errors and notification faults',async t=>{
 const {root,watch}=await fixture(t)
 let mode='error'
 t.mock.method(console,'warn',()=>{});t.mock.method(console,'error',()=>{});t.mock.method(console,'log',()=>{})
 t.mock.method(cp,'spawnSync',()=>({status:0,stdout:''}))
 t.mock.method(cp,'spawn',()=>{const child=new EventEmitter();queueMicrotask(()=>{if(mode==='error')child.emit('error',Error('fixture child'));child.emit('close',mode==='null'?null:0)});return child});syncBuiltinESMExports()
 for(const run of [()=>watch.run('fixture'),()=>watch.runNode('fixture'),()=>watch.runGit(['push'])]){
  mode='error';assert.equal((await run()).error.message,'fixture child')
  mode='null';assert.equal((await run()).status,1)
  mode='success';assert.equal((await run()).status,0)
 }
 cp.spawnSync=()=>({status:0,stdout:undefined});syncBuiltinESMExports();assert.equal(watch.unpushedState().state,'unknown')
 globalThis.unitProxy='http://fixture.invalid';await watch.runGit(['push']);await watch.runGit(['push'])
 const previous=process.env.DESKTOP_NOTIFY;process.env.DESKTOP_NOTIFY='1'
 t.after(()=>{if(previous===undefined)delete process.env.DESKTOP_NOTIFY;else process.env.DESKTOP_NOTIFY=previous})
 globalThis.unitModel='';await watch.notify(true,'fixture','fixture')
 globalThis.unitAvatarFails=true;await watch.notify(false,'fixture','fixture',{model:'fixture'})
 globalThis.unitNotifyFails=true;await watch.notify(false,'fixture','fixture',{model:'fixture'})
 mode='error';assert.equal(await watch.rebuild(''),false);assert.equal(await watch.restartApp(),false)
 fs.writeFileSync(join(root,'.benchgauge-ios.local.json'),'{}');assert.equal(await watch.updatePhone(null),false)
})


test('a source change during the build discards deployment attribution',async t=>{
 const {root,watch}=await fixture(t)
 t.mock.method(console,'log',()=>{})
 t.mock.method(cp,'spawnSync',(_command,args)=>({status:0,stdout:args.includes('status')?'':args.includes('show')?'fixture-author':'fixture-head'}))
 t.mock.method(cp,'spawn',command=>{
  const child=new EventEmitter()
  queueMicrotask(()=>{if(command.endsWith('make-app.sh'))fs.writeFileSync(join(root,'Sources/changed.swift'),'fixture');child.emit('close',0)})
  return child
 });syncBuiltinESMExports()
 assert.equal(await watch.rebuild('mock-pass'),true)
 const receipt=JSON.parse(fs.readFileSync(join(root,'work/.last-app-deploy'),'utf8'))
 assert.equal(receipt.author,'')
})
