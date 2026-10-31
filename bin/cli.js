#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');

const ROOT = path.resolve(__dirname, '..');
const SKILLS = path.join(ROOT, 'skills');
const pkg = require(path.join(ROOT, 'package.json'));

function usage() {
  console.log(`
typephp-skills v${pkg.version} — 把 TypePHP 技能安装到 Agent 技能目录

用法:
  typephp-skills install [选项]
  typephp-skills list
  typephp-skills path

选项:
  --claude          安装到 Claude Code 目录 (~/.claude/skills)
  --project         安装到当前项目目录 (.workbuddy-ai/skills 或 .claude/skills)
  --dir <path>      安装到指定目录（优先级最高）
  --force           目标已存在时先备份为 <name>.bak-<时间戳> 再覆盖
  -h, --help        显示帮助
  -v, --version     显示版本

示例:
  npx typephp-skills install                 # ~/.workbuddy-ai/skills
  npx typephp-skills install --claude        # ~/.claude/skills
  npx typephp-skills install --project       # ./.workbuddy-ai/skills
  npx typephp-skills install --dir ./skills  # 自定义
`);
}

function skills() {
  if (!fs.existsSync(SKILLS)) return [];
  return fs
    .readdirSync(SKILLS, { withFileTypes: true })
    .filter((d) => d.isDirectory() && fs.existsSync(path.join(SKILLS, d.name, 'SKILL.md')))
    .map((d) => d.name);
}

function targetDir(opts) {
  if (opts.dir) return path.resolve(opts.dir);
  const base = opts.project ? process.cwd() : os.homedir();
  const sub = opts.claude ? '.claude/skills' : '.workbuddy-ai/skills';
  return path.join(base, sub);
}

function copyDir(src, dst) {
  fs.mkdirSync(dst, { recursive: true });
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    if (entry.name === '.DS_Store') continue;
    const from = path.join(src, entry.name);
    const to = path.join(dst, entry.name);
    if (entry.isDirectory()) copyDir(from, to);
    else fs.copyFileSync(from, to);
  }
}

function install(opts) {
  const dest = targetDir(opts);
  const names = skills();
  if (names.length === 0) {
    console.error('包里没有找到技能目录，安装包可能不完整。');
    process.exit(1);
  }

  console.log(`安装到: ${dest}`);
  fs.mkdirSync(dest, { recursive: true });

  for (const name of names) {
    const src = path.join(SKILLS, name);
    const to = path.join(dest, name);

    if (fs.existsSync(to)) {
      if (!opts.force) {
        console.error(`  跳过 ${name}：目标已存在（加 --force 覆盖，原目录会先被备份）`);
        process.exitCode = 1;
        continue;
      }
      const bak = `${to}.bak-${new Date().toISOString().replace(/[:.]/g, '-')}`;
      fs.renameSync(to, bak);
      console.log(`  已备份旧版本 -> ${bak}`);
    }

    copyDir(src, to);
    console.log(`  ✓ ${name}`);
  }

  console.log(`
完成。重启客户端后技能才会被加载。
验证方式：确认 ${path.join(dest, names[0], 'SKILL.md')} 直接可见（加载器不会递归查找嵌套的 SKILL.md）。`);
}

function main() {
  const argv = process.argv.slice(2);
  const cmd = argv.find((a) => !a.startsWith('-')) || 'install';
  const opts = {
    claude: argv.includes('--claude'),
    project: argv.includes('--project'),
    force: argv.includes('--force'),
    dir: argv.includes('--dir') ? argv[argv.indexOf('--dir') + 1] : null,
  };

  if (argv.includes('-h') || argv.includes('--help')) return usage();
  if (argv.includes('-v') || argv.includes('--version')) return console.log(pkg.version);

  if (cmd === 'install') return install(opts);
  if (cmd === 'list') {
    for (const name of skills()) {
      const md = fs.readFileSync(path.join(SKILLS, name, 'SKILL.md'), 'utf8');
      const body = md.startsWith('---') ? md.slice(md.indexOf('---', 3) + 3) : md;
      const title = (body.match(/^#\s+(.+)$/m) || [, ''])[1];
      console.log(`${name}${title ? '  —  ' + title : ''}`);
    }
    return;
  }
  if (cmd === 'path') return console.log(SKILLS);

  console.error(`未知命令: ${cmd}`);
  usage();
  process.exit(1);
}

main();
