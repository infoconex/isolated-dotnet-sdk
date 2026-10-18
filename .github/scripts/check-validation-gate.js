'use strict';

function checkGate(state) {
  if (state.classification !== 'success') {
    throw new Error('Change classification did not succeed: ' + state.classification);
  }
  if (!['true', 'false'].includes(state.behavioral)) {
    throw new Error('Missing or invalid behavioral-validation decision');
  }
  const expected = state.behavioral === 'true' ? 'success' : 'skipped';
  for (const job of ['bash', 'powershell']) {
    if (state[job] !== expected) {
      throw new Error(job + ' expected ' + expected + ' but was ' + (state[job] || '(missing)'));
    }
  }
  return 'Required product validation paths completed successfully';
}

if (require.main === module) {
  try {
    console.log(checkGate({
      classification: process.env.CLASSIFICATION_RESULT,
      behavioral: process.env.BEHAVIORAL_REQUIRED,
      bash: process.env.BASH_RESULT,
      powershell: process.env.POWERSHELL_RESULT
    }));
  } catch (error) {
    console.error('Validation gate failed: ' + error.message);
    process.exitCode = 1;
  }
}

module.exports = { checkGate };
