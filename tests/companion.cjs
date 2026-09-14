// Real filesystem/watch transport, mocked VS Code API. No live editor mutation.
const fs=require('fs'),os=require('os'),path=require('path'),vm=require('vm'),assert=require('assert');
const home=fs.mkdtempSync(path.join(os.tmpdir(),'warp-companion-test-'));
const root=path.join(home,'.workflow-manager','vscode-bridge');
const context={subscriptions:[]}; let closes=0;
const vscode={env:{},workspace:{isTrusted:true,workspaceFolders:[{uri:{scheme:'file',fsPath:'/project'}}],textDocuments:[],notebookDocuments:[]},window:{state:{focused:true},terminals:[]},commands:{executeCommand:async command=>{assert.equal(command,'workbench.action.closeWindow');closes++;}}};
const extensionModule={exports:{}};
vm.runInNewContext(fs.readFileSync('extras/vscode-companion/extension.js','utf8'),{exports:extensionModule.exports,require:name=>name==='vscode'?vscode:name==='os'?{homedir:()=>home}:require(name)});
extensionModule.exports.activate(context);
let count=0;
async function request(action,descriptor,session){
  const nonce=(++count).toString(16).padStart(32,'0');
  fs.writeFileSync(path.join(root,`request-${nonce}.json`),JSON.stringify({nonce,action,descriptor,session,expires:Date.now()+4000}));
  for(let i=0;i<50;i++){
    const file=fs.readdirSync(root).find(f=>f.startsWith(`response-${nonce}-`)&&f.endsWith('.json'));
    if(file)return JSON.parse(fs.readFileSync(path.join(root,file),'utf8'));
    await new Promise(resolve=>setTimeout(resolve,10));
  }
  throw Error('companion did not respond');
}
(async()=>{
  const probe=await request('probe');assert.deepEqual(probe.descriptor,{kind:'folder',path:'/project'});assert(probe.focused);
  vscode.workspace.textDocuments=[{isDirty:true}];assert.equal((await request('close',probe.descriptor,probe.session)).accepted,false);assert.equal(closes,0);
  vscode.workspace.textDocuments=[];vscode.window.terminals=[{}];assert.equal((await request('close',probe.descriptor,probe.session)).accepted,false);
  vscode.window.terminals=[];assert.equal((await request('close',{path:'/wrong',kind:'folder'},probe.session)).accepted,false);
  assert.equal((await request('close',{path:'/project',kind:'folder'},probe.session)).accepted,true);assert.equal(closes,1);
  vscode.workspace.workspaceFile={scheme:'file',fsPath:'/multi.code-workspace'};assert.equal((await request('inspect')).descriptor.kind,'workspace');
  vscode.env.remoteName='ssh';assert.equal((await request('probe')).descriptor,null);
  console.log('PASS: companion transport, native descriptor API, dirty/terminal/mismatch guards and graceful-close command (mocked VS Code)');
})().catch(e=>{console.error(e);process.exitCode=1}).finally(()=>{context.subscriptions.forEach(s=>s.dispose());fs.rmSync(home,{recursive:true,force:true});});
