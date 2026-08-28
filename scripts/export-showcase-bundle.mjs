#!/usr/bin/env node
import { readFileSync, writeFileSync, mkdirSync, copyFileSync, existsSync, rmSync, lstatSync, readdirSync } from 'node:fs';
import { dirname, join, posix, relative, resolve } from 'node:path';

const MIRROR = 'PeterShanxin/MeowWatch-releases';

function readJson(p) {
  return JSON.parse(readFileSync(p, 'utf8'));
}

function readVersion() {
  const line = readFileSync('pubspec.yaml', 'utf8').split('\n').find((l) => l.startsWith('version:'));
  if (!line) throw new Error('pubspec.yaml has no version');
  return line.split(':')[1].trim().split('+')[0];
}

function isPrerelease(version) {
  return /(?:^|[.-])(alpha|beta|rc)(?:[.-]|$)/i.test(version);
}

function releaseLinks(version) {
  const tag = version.startsWith('v') ? version : `v${version}`;
  const base = `https://github.com/${MIRROR}`;
  const prerelease = isPrerelease(version);
  return {
    download: prerelease ? `${base}/releases/tag/${tag}` : `${base}/releases/latest`,
    releases: `${base}/releases`,
    releaseNotes: `${base}/releases/tag/${tag}`,
    versionBadge: prerelease
      ? `https://img.shields.io/badge/release-${tag.replace(/-/g, '--')}-orange`
      : `https://img.shields.io/github/v/release/${MIRROR}?label=latest`,
  };
}

function renderBadges(links) {
  return [
    `  <a href="${links.download}"><img alt="Release" src="${links.versionBadge}"></a>`,
    '  <img alt="Windows" src="https://img.shields.io/badge/platform-Windows-0078D6?logo=windows">',
    '  <img alt="Flutter" src="https://img.shields.io/badge/built%20with-Flutter-54C5F8?logo=flutter">',
    '  <img alt="Alpha" src="https://img.shields.io/badge/status-alpha-orange">',
    '  <img alt="Co-watch" src="https://img.shields.io/badge/Syncplay-co--watch-8b5cf6">',
  ].join('\n');
}

function optionalImageBlock(outDir, filename, width, alt) {
  if (!existsSync(join(outDir, 'assets', filename))) return '';
  return `<p align="center">\n  <img src="assets/${filename}" width="${width}" alt="${alt}">\n</p>\n\n`;
}

function renderReadme(version, outDir) {
  const showcase = readJson('showcase/showcase.json');
  const template = readFileSync('showcase/README.template.md', 'utf8');
  const links = releaseLinks(version);
  const map = {
    '{{PRODUCT_NAME}}': showcase.product.name,
    '{{TAGLINE}}': showcase.product.tagline,
    '{{VERSION}}': version,
    '{{STATUS}}': showcase.product.status,
    '{{BADGES_ROW}}': renderBadges(links),
    '{{DOWNLOAD_URL}}': links.download,
    '{{RELEASES_URL}}': links.releases,
    '{{RELEASE_NOTES_URL}}': links.releaseNotes,
    '{{LOGO_BLOCK}}': optionalImageBlock(outDir, 'logo.png', 120, 'MeowWatch icon'),
    '{{HERO_BLOCK}}': optionalImageBlock(
      outDir,
      'hero.png',
      900,
      'MeowWatch co-watching UI with video player and floating chat',
    ),
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

function ensureAsset(dest, ...sources) {
  if (existsSync(dest)) return;
  for (const src of sources) {
    if (existsSync(src)) {
      mkdirSync(dirname(dest), { recursive: true });
      copyFileSync(src, dest);
      return;
    }
  }
}

function prepareAssets() {
  ensureAsset('showcase/assets/hero.png', 'docs/assets/hero.png');
  ensureAsset('showcase/assets/logo.png', 'assets/brand/app_icon_source.png');
}

function normalizeRel(p) {
  return posix.normalize(p.replace(/\\/g, '/')).replace(/^\.\//, '');
}

function listFilesRecursive(root) {
  const absRoot = resolve(root);
  const results = [];
  function walk(dir) {
    for (const name of readdirSync(dir)) {
      const abs = join(dir, name);
      const st = lstatSync(abs);
      if (st.isSymbolicLink()) throw new Error(`Symlink not allowed: ${relative(absRoot, abs)}`);
      if (st.isDirectory()) walk(abs);
      else if (st.isFile()) {
        const rel = normalizeRel(relative(absRoot, abs));
        if (rel.includes('..')) throw new Error(`Path traversal rejected: ${rel}`);
        results.push(rel);
      }
    }
  }
  walk(absRoot);
  return results.sort();
}

function isAllowed(rel, allowed) {
  if (allowed.has(rel)) return true;
  for (const pattern of allowed) {
    if (pattern.endsWith('/**')) {
      const prefix = pattern.slice(0, -3);
      if (rel === prefix || rel.startsWith(`${prefix}/`)) return true;
    }
  }
  return false;
}

function collectReadmeAssetRefs(readme) {
  const refs = [];
  for (const match of readme.matchAll(/<img\b[^>]*\bsrc=["']([^"']+)["']/gi)) refs.push(match[1]);
  for (const match of readme.matchAll(/!\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g)) refs.push(match[1]);
  return refs;
}

function validateReadmeAssets(outDir) {
  const readmePath = join(outDir, 'README.md');
  const absRoot = resolve(outDir);
  const readme = readFileSync(readmePath, 'utf8');
  const errors = [];
  for (const raw of collectReadmeAssetRefs(readme)) {
    if (/^(https?:|data:|mailto:)/i.test(raw)) continue;
    const rel = normalizeRel(raw.split('#')[0].split('?')[0]);
    if (!rel || rel.includes('..') || posix.isAbsolute(rel) || /^[a-zA-Z]:/.test(rel)) {
      errors.push(`Rejected README asset path: ${raw}`);
      continue;
    }
    const abs = resolve(outDir, rel);
    if (!abs.startsWith(absRoot)) {
      errors.push(`README asset escaped output directory: ${raw}`);
      continue;
    }
    if (!existsSync(abs)) {
      errors.push(`README references missing asset: ${rel}`);
      continue;
    }
    if (lstatSync(abs).isSymbolicLink()) errors.push(`README asset is a symlink: ${rel}`);
  }
  if (errors.length) {
    throw new Error(`README asset validation failed:\n${errors.map((e) => `  - ${e}`).join('\n')}`);
  }
  console.log('Validated README local asset references');
}

function validateOutput(outDir, outputConfig) {
  const allowed = new Set(outputConfig.outputPaths.map(normalizeRel));
  const found = listFilesRecursive(outDir);
  const errors = [];
  for (const rel of found) {
    if (!isAllowed(rel, allowed)) errors.push(`Unexpected output file: ${rel}`);
  }
  for (const required of outputConfig.requiredPaths ?? []) {
    if (!found.includes(normalizeRel(required))) errors.push(`Missing required output file: ${required}`);
  }
  if (errors.length) {
    throw new Error(`Showcase output validation failed:\n${errors.map((e) => `  - ${e}`).join('\n')}`);
  }
  validateReadmeAssets(outDir);
  console.log(`Validated ${found.length} output file(s)`);
}

function main() {
  const version = process.argv.includes('--version')
    ? process.argv[process.argv.indexOf('--version') + 1]
    : readVersion();
  const outDir = process.argv.includes('--out-dir')
    ? process.argv[process.argv.indexOf('--out-dir') + 1]
    : 'showcase-out';
  const allowlist = readJson('showcase/EXPORT_ALLOWLIST.json');

  prepareAssets();
  if (existsSync(outDir)) rmSync(outDir, { recursive: true, force: true });
  mkdirSync(join(outDir, 'assets'), { recursive: true });
  for (const rel of allowlist.paths) {
    if (!rel.startsWith('showcase/assets/')) continue;
    if (!existsSync(rel)) continue;
    copyFileSync(rel, join(outDir, 'assets', rel.split('/').pop()));
  }
  writeFileSync(join(outDir, 'README.md'), renderReadme(version, outDir), 'utf8');
  validateOutput(outDir, allowlist.output);
  console.log(`Wrote ${outDir} for v${version}`);
}

main();
