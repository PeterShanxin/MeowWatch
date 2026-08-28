#!/usr/bin/env node
import { readFileSync, writeFileSync, mkdirSync, copyFileSync, existsSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';

const MIRROR = 'PeterShanxin/MeowWatch-releases';

function readJson(p) { return JSON.parse(readFileSync(p, 'utf8')); }
function readVersion() {
  const line = readFileSync('pubspec.yaml', 'utf8').split('\n').find((l) => l.startsWith('version:'));
  if (!line) throw new Error('pubspec.yaml has no version');
  return line.split(':')[1].trim().split('+')[0];
}

function renderReadme(version) {
  const showcase = readJson('showcase/showcase.json');
  const template = readFileSync('showcase/README.template.md', 'utf8');
  const tag = version.startsWith('v') ? version : `v${version}`;
  const map = {
    '{{PRODUCT_NAME}}': showcase.product.name,
    '{{TAGLINE}}': showcase.product.tagline,
    '{{VERSION}}': version,
    '{{STATUS}}': showcase.product.status,
    '{{DOWNLOAD_URL}}': `https://github.com/${MIRROR}/releases/latest`,
    '{{RELEASES_URL}}': `https://github.com/${MIRROR}/releases`,
    '{{FEATURES_TABLE}}': ['| Feature | Description |', '| --- | --- |', ...showcase.features.map((f) => `| **${f.title}** | ${f.description} |`)].join('\n'),
    '{{UX_LIST}}': showcase.ux.map((u) => `- ${u}`).join('\n'),
    '{{ENGINEERING_LIST}}': showcase.engineering.map((e) => `- ${e}`).join('\n'),
    '{{REQUIREMENTS_NOTES}}': showcase.requirements.notes.map((n) => `- ${n}`).join('\n'),
    '{{LICENSE_SUMMARY}}': showcase.license.summary,
  };
  let out = template;
  for (const [k, v] of Object.entries(map)) out = out.split(k).join(v);
  return out;
}

function ensureHero() {
  const dest = 'showcase/assets/hero.png';
  if (existsSync(dest)) return;
  const src = 'docs/assets/hero.png';
  if (!existsSync(src)) throw new Error(`Missing ${dest} and ${src}`);
  mkdirSync(dirname(dest), { recursive: true });
  copyFileSync(src, dest);
}

function main() {
  const version = process.argv.includes('--version') ? process.argv[process.argv.indexOf('--version') + 1] : readVersion();
  const outDir = process.argv.includes('--out-dir') ? process.argv[process.argv.indexOf('--out-dir') + 1] : 'showcase-out';
  ensureHero();
  if (existsSync(outDir)) rmSync(outDir, { recursive: true, force: true });
  mkdirSync(join(outDir, 'assets'), { recursive: true });
  writeFileSync(join(outDir, 'README.md'), renderReadme(version), 'utf8');
  copyFileSync('showcase/showcase.json', join(outDir, 'showcase.json'));
  for (const name of ['hero.png', 'architecture.svg']) {
    const src = `showcase/assets/${name}`;
    if (existsSync(src)) copyFileSync(src, join(outDir, 'assets', name));
  }
  console.log(`Wrote ${outDir} for v${version}`);
}

main();
