from pathlib import Path
p = Path('tests/powershell/sdk-payload-fixture.ps1')
text = p.read_text()
header = """[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'This deterministic test fixture intentionally shadows native commands in a child PowerShell process.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Mock signatures preserve the production command surface used by the script under test.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test-only command shims delegate or inject deterministic failures; they are not product commands.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSupportsShouldProcess', '', Justification = 'Mock signatures preserve WhatIf/Confirm compatibility with the commands they replace.')]
param()

"""
if text.startswith('[Diagnostics.CodeAnalysis.SuppressMessageAttribute'):
    raise SystemExit('fixture already annotated')
p.write_text(header + text)
