from pathlib import Path

replacements = {
    Path('tests/bash/behavior.bats'): (
        '[[ "$output" == *"Unknown argument: 99.0.100"* ]]',
        '[[ "$output" == *"An SDK version cannot be combined with list."* ]]',
    ),
    Path('tests/bash/presentation.bats'): (
        '[[ "$output" == *"Unknown argument: unexpected"* ]]',
        '[[ "$output" == *"An SDK version cannot be combined with list."* ]]',
    ),
}

for path, (old, new) in replacements.items():
    text = path.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'Expected assertion not found in {path}: {old}')
    path.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')

print('Aligned Bash list/version rejection assertions.')
