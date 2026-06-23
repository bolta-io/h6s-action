#!/usr/bin/env node
// action.yml 의 형식 검증 (quick smoke). 상세 검증은 tests/action-yml.test.ts.
import { readFileSync, existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import YAML from 'yaml';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');

function fail(msg) {
  process.stderr.write(`[validate-action] ${msg}\n`);
  process.exit(1);
}

const yamlPath = resolve(ROOT, 'action.yml');
if (!existsSync(yamlPath)) fail('action.yml 이 없습니다');

const doc = YAML.parse(readFileSync(yamlPath, 'utf8'));
if (!doc.name) fail('action.yml: name 누락');
if (!doc.description) fail('action.yml: description 누락');
if (!doc.inputs || typeof doc.inputs !== 'object') fail('action.yml: inputs 누락');
if (!doc.outputs || typeof doc.outputs !== 'object') fail('action.yml: outputs 누락');
if (!doc.runs || doc.runs.using !== 'composite') fail('action.yml: composite action 이어야 합니다');

// 필수 input — api-key / schema / provider 셋만
for (const key of ['api-key', 'schema', 'provider']) {
  if (!doc.inputs[key]) fail(`inputs.${key} 누락`);
  if (!doc.inputs[key].required) fail(`inputs.${key}.required 가 true 여야 합니다`);
}

// 의도적으로 빠져 있어야 하는 인풋
// - credential-id: UUID workflow 직접 박는 UX 부담. provider 매칭으로 통일
// - base-url / profile / cache: 내부 디버깅용 (사유는 README 참조)
for (const banned of ['credential-id', 'base-url', 'profile', 'cache']) {
  if (doc.inputs[banned]) {
    fail(`inputs.${banned} 는 공개 인터페이스에서 제외 (사유는 README 참조)`);
  }
}

// outputs 4종
for (const key of ['path', 'count', 'job-id', 'summary']) {
  if (!doc.outputs[key]) fail(`outputs.${key} 누락`);
  if (!doc.outputs[key].description) fail(`outputs.${key}.description 누락`);
}

// scripts/run.sh 존재 확인
if (!existsSync(resolve(ROOT, 'scripts/run.sh'))) fail('scripts/run.sh 가 없습니다');

process.stderr.write(`[validate-action] OK (inputs ${Object.keys(doc.inputs).length}, outputs ${Object.keys(doc.outputs).length})\n`);
