#!/usr/bin/env node
// Checks the Flow screens against the rules of DESIGN.md that a script can see. It exits 1 on
// a finding, so it can gate a commit or a release.
//
//   node custom/script/design-audit.mjs [file-or-dir ...]
//     default: app/javascript/dashboard/routes/dashboard/flowKanban
//
// A deliberate exception is written in the template, on the line before it, with the reason:
//   <!-- design-audit-allow: spinner (the load-more footer of a scrolling column) -->
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const DEFAULT_TARGETS = ['app/javascript/dashboard/routes/dashboard/flowKanban'];

// [rule, pattern, why]. Patterns run on the <template> only.
const RULES = [
  [
    'native-element',
    /<(select|input|button|textarea)\b/,
    'never a native <select>, <input>, <button> or <textarea>: use components-next',
  ],
  [
    'native-select-wrapper',
    /<Select\b/,
    "components-next Select wraps a native <select>: use ComboBox or a segmented control",
  ],
  [
    'literal-hex',
    /#[0-9a-fA-F]{6}\b|#[0-9a-fA-F]{3}(?![\w-])/,
    'colour comes from n-* tokens, never a literal',
  ],
  [
    'overlay-shadow',
    /\bshadow-(lg|xl|2xl)\b/,
    'shadow-lg and up belong to overlays, not inline containers',
  ],
  [
    'side-stripe',
    /\bborder-(l|r)(-\d+)?\b|\bborder-(s|e)-[2-9]\b/,
    'no coloured side stripe on cards or list items',
  ],
  [
    'hand-built-type',
    /\btext-(xs|sm|base|lg)\b[^"'`]*\bfont-(medium|semibold|bold)\b|\bfont-(medium|semibold|bold)\b[^"'`]*\btext-(xs|sm|base|lg)\b/,
    'use the typography utilities (text-heading-*, text-body-main, text-label*)',
  ],
  [
    'physical-spacing',
    /(?<![\w:-])(ml|mr|pl|pr|left|right)-(\d|px|auto|\[)|(?<![\w:-])text-(left|right)\b/,
    'use logical spacing (ms-, me-, ps-, pe-, start-, end-, text-start) so RTL works',
  ],
  [
    'spinner',
    /<Spinner\b/,
    'loading shows skeletons (SkeletonRows), never a spinner in content',
  ],
  [
    'hand-built-skeleton',
    /\banimate-pulse\b/,
    'use SkeletonRows for loading rows',
  ],
  [
    'hand-built-empty-state',
    /rounded-xl size-1[02] bg-n-alpha-2/,
    'use EmptyState for an empty state',
  ],
  [
    'pure-black-white',
    /\b(text-black|bg-black|bg-white)\b/,
    'never pure black or white surfaces: use the n-* layers',
  ],
];

// Components that implement a pattern may use what they wrap.
const OWNERS = {
  'SkeletonRows.vue': ['hand-built-skeleton'],
  'EmptyState.vue': ['hand-built-empty-state'],
};

const walk = path => {
  const stat = statSync(path);
  if (stat.isFile()) return path.endsWith('.vue') ? [path] : [];
  return readdirSync(path).flatMap(entry =>
    entry === 'specs' ? [] : walk(join(path, entry))
  );
};

const templateOf = source => {
  const start = source.indexOf('<template>');
  const end = source.lastIndexOf('</template>');
  if (start === -1) return null;
  return {
    text: source.slice(start, end === -1 ? undefined : end),
    firstLine: source.slice(0, start).split('\n').length,
  };
};

const allowed = (lines, index, rule) => {
  for (let back = 1; back <= 5 && index - back >= 0; back += 1) {
    const match = lines[index - back].match(/design-audit-allow:\s*([\w-]+)/);
    if (match && match[1] === rule) return true;
  }
  return false;
};

// An icon-only Button needs an aria-label and a v-tooltip (DESIGN.md → Buttons).
const iconOnlyButtons = (text, firstLine, file) =>
  [...text.matchAll(/<Button\b([\s\S]*?)\/?>/g)].flatMap(match => {
    const attrs = match[1];
    if (!/\bicon=/.test(attrs) || /:?label=/.test(attrs)) return [];
    const line = firstLine + text.slice(0, match.index).split('\n').length - 1;
    const missing = [
      !/aria-label/.test(attrs) && 'aria-label',
      !/v-tooltip/.test(attrs) && 'v-tooltip',
    ].filter(Boolean);
    return missing.length
      ? [{ file, line, rule: 'icon-only-button', why: `icon-only Button without ${missing.join(' and ')}` }]
      : [];
  });

const audit = file => {
  const template = templateOf(readFileSync(file, 'utf8'));
  if (!template) return [];
  const lines = template.text.split('\n');
  const owned = OWNERS[file.split(/[\\/]/).pop()] || [];
  const findings = [];
  lines.forEach((text, index) => {
    if (/^\s*<!--/.test(text)) return;
    RULES.forEach(([rule, pattern, why]) => {
      if (owned.includes(rule) || !pattern.test(text) || allowed(lines, index, rule)) return;
      findings.push({ file, line: template.firstLine + index, rule, why, snippet: text.trim().slice(0, 80) });
    });
  });
  return findings.concat(iconOnlyButtons(template.text, template.firstLine, file));
};

const targets = process.argv.slice(2);
const files = (targets.length ? targets : DEFAULT_TARGETS).flatMap(walk);
const findings = files.flatMap(audit);

findings.forEach(({ file, line, rule, why, snippet }) => {
  console.log(`${relative(process.cwd(), file)}:${line}  [${rule}] ${why}${snippet ? `\n    ${snippet}` : ''}`);
});
console.log(`\ndesign-audit: ${files.length} files, ${findings.length} finding${findings.length === 1 ? '' : 's'}`);
process.exit(findings.length ? 1 : 0);
