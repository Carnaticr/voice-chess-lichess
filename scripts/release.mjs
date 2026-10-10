// Build the Windows installer and publish it as a GitHub release with the GitHub CLI.
// The installed app's updater reads latest.yml from the newest release.
//
//   npm run release            (after bumping "version" in package.json and committing)
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';

const pkg = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
const { owner, repo } = pkg.build.publish[0];
const tag = `v${pkg.version}`;
const run = (cmd, args) => execFileSync(cmd, args, { stdio: 'inherit', shell: process.platform === 'win32' });

const dirty = execFileSync('git', ['status', '--porcelain'], { encoding: 'utf8' }).trim();
if (dirty) {
  console.error('Commit your changes before releasing:\n' + dirty);
  process.exit(1);
}

run('npx', ['electron-builder', '--win', '--publish', 'never']);

const exe = `dist/VoiceChess-Setup-${pkg.version}.exe`;
const files = [exe, `${exe}.blockmap`, 'dist/latest.yml'];
for (const f of files) if (!existsSync(f)) { console.error(`Missing build output: ${f}`); process.exit(1); }

run('git', ['push']);
run('gh', ['release', 'create', tag, ...files, '--repo', `${owner}/${repo}`, '--title', tag, '--generate-notes', '--target', 'main']);
console.log(`Published ${tag}: https://github.com/${owner}/${repo}/releases/tag/${tag}`);
