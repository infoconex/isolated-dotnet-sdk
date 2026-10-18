'use strict';

function checkGate(state) {
  if (state.classification !== 'success') {
    throw new Error('Change classification did not succeed: ' + state.classification);
  }
  if (!['true', 'false'].includes(state.behavioral) ||
      !['true', 'false'].includes(state.documentation) ||
      (state.behavioral === 'false' && state.documentation === 'false')) {
    throw new Error('Missing or invalid required-validation decision');
  }
  const expectations = {
    docsJob: state.documentation === 'true',
    bash: state.behavioral === 'true',
    powershell: state.behavioral === 'true'
  };
  for (const [job, required] of Object.entries(expectations)) {
    const actual = state[job];
    const expected = required ? 'success' : 'skipped';
    if (actual !== expected) {
      throw new Error(job + ' expected ' + expected + ' but was ' + (actual || '(missing)'));
    }
  }
  return 'Required validation paths completed successfully';
}

if (require.main === module) {
  try {
    console.log(checkGate({
      classification: process.env.CLASSIFICATION_RESULT,
      behavioral: process.env.BEHAVIORAL_REQUIRED,
      documentation: process.env.DOCUMENTATION_REQUIRED,
      bash: process.env.BASH_RESULT,
      powershell: process.env.POWERSHELL_RESULT,
      docsJob: process.env.DOCS_JOB_RESULT,
    }));
  } catch (error) {
    console.error('Validation gate failed: ' + error.message);
    process.exitCode = 1;
  }
}

module.exports = { checkGate };
