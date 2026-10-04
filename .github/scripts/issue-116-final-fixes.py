from pathlib import Path

path = Path('isolated-dotnet-sdk.sh')
text = path.read_text(encoding='utf-8')
start = text.index('audit_installed_sdks() {')
end = text.index('\n}\n\nselect_action() {', start) + 2
segment = text[start:end]

for old, new in (
    ('isolated_versions', 'audit_isolated_versions'),
    ('system_versions', 'audit_system_versions'),
    ('isolated_statuses', 'audit_isolated_statuses'),
    ('system_statuses', 'audit_system_statuses'),
):
    segment = segment.replace(old, new)

segment = segment.replace(
    'for version in "${audit_isolated_versions[@]}"; do',
    'for version in "${audit_isolated_versions[@]+"${audit_isolated_versions[@]}"}"; do')
segment = segment.replace(
    'for version in "${audit_system_versions[@]}"; do',
    'for version in "${audit_system_versions[@]+"${audit_system_versions[@]}"}"; do')

text = text[:start] + segment + text[end:]
path.write_text(text, encoding='utf-8')
