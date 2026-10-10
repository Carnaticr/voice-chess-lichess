// Owns the PowerShell/System.Speech helper process and relays JSON-line messages.
const { spawn } = require('child_process');
const path = require('path');
const { EventEmitter } = require('events');

class SpeechHost extends EventEmitter {
  constructor(scriptPath) {
    super();
    this.scriptPath = scriptPath;
    this.proc = null;
    this.queue = [];
    this.ready = false;
    this.lastReady = null;
    this.stopping = false;
  }

  start() {
    this.stopping = false;
    this.ready = false;
    const proc = spawn('powershell.exe', [
      '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', this.scriptPath,
    ], { windowsHide: true, cwd: path.dirname(this.scriptPath) });
    this.proc = proc;

    let buffer = '';
    proc.stdout.setEncoding('utf8');
    proc.stdout.on('data', (chunk) => {
      buffer += chunk;
      let nl;
      while ((nl = buffer.indexOf('\n')) >= 0) {
        const line = buffer.slice(0, nl).trim();
        buffer = buffer.slice(nl + 1);
        if (!line.startsWith('{')) continue;
        let msg;
        try { msg = JSON.parse(line); } catch { continue; }
        if (msg.type === 'ready') {
          this.ready = true;
          this.lastReady = msg;
          for (const m of this.queue) this.write(m);
          this.queue = [];
        }
        this.emit('message', msg);
      }
    });
    proc.stderr.setEncoding('utf8');
    proc.stderr.on('data', (d) => console.error('[speech]', d));
    proc.on('exit', (code) => {
      this.ready = false;
      this.proc = null;
      if (this.stopping) return;
      this.emit('message', { type: 'error', message: `Speech engine exited (code ${code}); restarting…` });
      setTimeout(() => this.start(), 1500);
    });
  }

  write(msg) {
    if (this.proc && this.proc.stdin.writable) this.proc.stdin.write(JSON.stringify(msg) + '\n');
  }

  send(msg) {
    if (this.ready) this.write(msg);
    else this.queue.push(msg);
  }

  stop() {
    this.stopping = true;
    if (this.proc) {
      try { this.write({ type: 'quit' }); } catch { /* ignore */ }
      const p = this.proc;
      setTimeout(() => { try { p.kill(); } catch { /* ignore */ } }, 500);
    }
  }
}

module.exports = { SpeechHost };
