'use strict';

function checkPagesGate(state) {
  if (state.classification !== 'success') {
    throw new Error('Pages classification did not succeed: ' + state.classification);
  }
  if (!['true', 'false'].includes(state.documentation)) {
    throw new Error('Missing or invalid Pages validation decision');
  }
  const expected = state.documentation === 'true' ? 'success' : 'skipped';
  if (state.build !== expected) {
    throw new Error('Pages build expected ' + expected + ' but was ' + (state.build || '(missing)'));
  }
  return 'Required Pages checks completed successfully';
}

if (require.main === module) {
  try {
    console.log(checkPagesGate({
      classification: process.env.CLASSIFICATION_RESULT,
      documentation: process.env.DOCUMENTATION_REQUIRED,
      build: process.env.PAGES_BUILD_RESULT
    }));
  } catch (error) {
    console.error('Pages gate failed: ' + error.message);
    process.exitCode = 1;
  }
}

module.exports = { checkPagesGate };
