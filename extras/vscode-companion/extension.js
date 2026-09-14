const vscode = require('vscode');
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const root = path.join(os.homedir(), '.workflow-manager', 'vscode-bridge');
function descriptor() {
  if (vscode.env.remoteName || !vscode.workspace.isTrusted) return null;
  const workspace = vscode.workspace.workspaceFile;
  if (workspace) return workspace.scheme === 'file' ? {kind:'workspace',path:workspace.fsPath} : null;
  const folders = vscode.workspace.workspaceFolders || [];
  return folders.length === 1 && folders[0].uri.scheme === 'file'
    ? {kind:'folder',path:folders[0].uri.fsPath} : null;
}
function activate(context) {
  fs.mkdirSync(root, {recursive:true,mode:0o700});
  const session = crypto.randomBytes(16).toString('hex');
  const handled = new Set();
  async function handle(name) {
    if (!/^request-[a-f0-9]+\.json$/.test(name || '') || handled.has(name)) return;
    let request;
    try { request = JSON.parse(fs.readFileSync(path.join(root,name),'utf8')); } catch { return; }
    if (!request.nonce || request.expires < Date.now() || request.expires > Date.now()+10000) return;
    if (request.session && request.session !== session) return;
    if (!['probe','inspect','inventory','close'].includes(request.action)) return;
    handled.add(name);
    // Keep no unbounded history and no permanent polling timer.
    if (handled.size > 100) handled.delete(handled.values().next().value);
    const current = descriptor();
    const response = {nonce:request.nonce,session,descriptor:current,focused:vscode.window.state.focused,
      empty:!vscode.env.remoteName && !vscode.workspace.workspaceFile && !(vscode.workspace.workspaceFolders || []).length,
      dirty:(vscode.workspace.textDocuments.some(d=>d.isDirty) || vscode.workspace.notebookDocuments.some(d=>d.isDirty)),terminals:vscode.window.terminals.length};
    if (request.action === 'close') {
      response.accepted = !!current && request.descriptor && current.kind === request.descriptor.kind && current.path === request.descriptor.path
        && !response.dirty && response.terminals === 0;
    }
    const dest = path.join(root,`response-${request.nonce}-${session}.json`);
    try { fs.writeFileSync(dest+'.tmp',JSON.stringify(response),{mode:0o600}); fs.renameSync(dest+'.tmp',dest); }
    catch { return; }
    if (request.action === 'close' && response.accepted) {
      // Native graceful close can still be vetoed by VS Code or another extension.
      await vscode.commands.executeCommand('workbench.action.closeWindow');
    }
  }
  const watcher = fs.watch(root,(_event,name)=>{ handle(String(name || '')).catch(()=>{}); });
  watcher.on('error',()=>watcher.close()); // Fail closed if native watching becomes unavailable.
  context.subscriptions.push({dispose:()=>watcher.close()});
}
exports.activate = activate;
exports.deactivate = () => {};
