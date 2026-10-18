'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
test('CI code-only workflow smoke', () => assert.equal(1, 1));
