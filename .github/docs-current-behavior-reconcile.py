from pathlib import Path


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    path.write_text(text.replace(old, new, 1))


readme = Path("README.md")
replace_once(
    readme,
    "The install and direct-host visuals below use the supported Linux/Bash mapping and current real-E2E behavior. CI-only home-directory prefixes and timestamps are normalized so the isolated root is readable as `~/dotnet-sdks`.",
    "The install and direct-host visuals below use the supported Linux/Bash mapping and are aligned with the current real-E2E flow. CI-only home-directory prefixes and timestamps are normalized so the isolated root is readable as `~/dotnet-sdks`.",
    "README visual framing",
)
replace_once(
    readme,
    "![Linux Bash E2E-validated transcript showing .NET SDK 10.0.100 installed successfully under ~/dotnet-sdks/10.0.100.](docs/images/isolation-install.svg)",
    "![Representative Linux Bash install transcript aligned with the real E2E target, showing .NET SDK 10.0.100 installed successfully under ~/dotnet-sdks/10.0.100.](docs/images/isolation-install.svg)",
    "README install visual alt",
)
replace_once(
    readme,
    "![Representative Linux Bash installed-SDK listing showing isolated and system ownership groups, including the same SDK version in both domains.](docs/images/isolation-list.svg)",
    "![Representative Linux Bash installed-SDK listing showing Isolated and System ownership groups with concrete version directories, including the same SDK version in both domains.](docs/images/isolation-list.svg)",
    "README list visual alt",
)
replace_once(
    readme,
    "## List Isolated SDKs\n\nPowerShell:",
    "## List Installed SDKs\n\nPowerShell:",
    "README List heading",
)
replace_once(
    readme,
    '```bash\n"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" list\n```\n\nAn explicit List action does not accept a version.',
    '```bash\n"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" list\n```\n\nThe List action reports Isolated SDKs first, followed by System SDKs visible through the normally resolved `dotnet` host. Each listed SDK includes its concrete version directory; System entries remain read-only and are not removable through the tool.\n\nAn explicit List action does not accept a version.',
    "README List description",
)

sessions = Path("docs/interactive-sessions.md")
replace_once(
    sessions,
    "A no-action invocation stays in one interactive session. After a successful Install, List, or Remove operation, the tool returns to Main. Normal cancellation or a no-change result also returns to Main. `E`/`e` is the global persistent-session Exit command and is available from Main and each persistent selection menu, so you do not need to navigate back to Main before exiting. Main no longer exposes a numeric `4. Exit` action, and `4` is not retained as an undocumented Exit alias.",
    "A no-action invocation stays in one interactive session. After a successful Install, List, or Remove operation, the tool returns to Main. Normal cancellation or a no-change result also returns to Main. Main uses mnemonic, case-insensitive commands: `I` for Install, `R` for Remove, `L` for List, and `E` for Exit. Numeric `1`, `2`, `3`, and `4` are not retained as hidden Main aliases. `E`/`e` is also the global persistent-session Exit command from each persistent selection menu, so you do not need to navigate back to Main before exiting.",
    "interactive session Main contract",
)

parity = Path("docs/behavioral-parity.md")
replace_once(
    parity,
    "| Required interactive input unavailable | Fail nonzero with repository-owned `Interactive input is unavailable.` context rather than looping or treating EOF as cancellation. |\n| Explicit interactive no/blank/q cancellation |",
    "| Required interactive input unavailable | Fail nonzero with repository-owned `Interactive input is unavailable.` context rather than looping or treating EOF as cancellation. |\n| Persistent Main menu | Use case-insensitive `I` / `R` / `L` / `E` for Install / Remove / List / Exit. Numeric `1` / `2` / `3` / `4` are rejected rather than retained as hidden aliases. |\n| Explicit interactive no/blank/q cancellation |",
    "parity Main row",
)
replace_once(
    parity,
    "| List | Report two ordered ownership groups: recognized isolated SDKs under the isolated root first, then read-only SDKs returned by the normally resolved `dotnet --list-sdks` host. Preserve same-version overlap across groups and report `None` for each empty group. |",
    "| List | Report two ordered ownership groups: recognized isolated SDKs under the isolated root first, then read-only SDKs returned by the normally resolved `dotnet --list-sdks` host. Include each SDK's concrete version directory, preserve same-version overlap across groups, and report `None` for each empty group. |",
    "parity List row",
)
replace_once(
    parity,
    "- Main and each persistent selection menu provide `E. Exit`;\n- Install channel selection provides Back to Main;",
    "- Main provides mnemonic `I. Install`, `R. Remove`, `L. List`, and `E. Exit` commands;\n- each persistent selection menu also provides `E. Exit`;\n- Install channel selection provides Back to Main;",
    "parity navigation bullets",
)

Path("docs/interactive-testing.md").write_text(
    """# Interactive lifecycle testing

The repository keeps deterministic interactive-session coverage separate from real Microsoft/.NET end-to-end validation. The deterministic suites lock menu lifecycle, navigation, retry feedback, and operation transitions without depending on live release metadata or destructive system state.

## What the deterministic suites cover

Both product implementations have behavioral coverage for:

- no-action invocation remaining in the interactive session until Exit;
- case-insensitive Main commands `I`, `R`, `L`, and `E`, with the old numeric Main aliases rejected;
- normal operation/no-change outcomes returning to Main;
- explicit List remaining one-shot;
- operational failures terminating nonzero instead of returning to Main;
- Install channel Back to Main;
- Install SDK Back to channel selection;
- Remove SDK Back to Main;
- compact SDK presentation using latest/recommended metadata and newest-per-feature-band choices;
- `Show all versions` exposing older servicing releases in deterministic order;
- recoverable blank/invalid selection feedback and global Exit behavior across persistent menus.

The Bash suite also exercises a representative multi-operation session through Install, List, Remove, and Exit using deterministic fake metadata and an isolated fake SDK host. Existing focused suites continue to own transactional installation, confirmation, metadata failure, filesystem, native-command, cleanup, and presentation boundaries.

## Relationship to real E2E

These suites are repository-controlled integration/behavioral tests. They replace external network and destructive boundaries where necessary so failures are deterministic and fast to diagnose.

Real Microsoft/.NET lifecycle coverage exists separately in [`e2e-testing.md`](e2e-testing.md). The live E2E suite complements this deterministic layer; it does not replace the focused failure and navigation coverage here.

## Test design

Interactive tests resolve behavior from displayed labels and current data rather than assuming that a fixed numeric SDK-menu position always represents a particular version. Deterministic metadata fixtures intentionally contain SDK versions in non-sorted order so presentation ordering is established by the product rather than fixture order.

The persistent Main menu is different: its semantic commands are explicitly `I`, `R`, `L`, and `E`, so those mnemonics are part of the product contract rather than data-derived positions.

## Running validation

Use the standard repository-owned commands documented in [`testing.md`](testing.md). In particular:

```bash
bash -n isolated-dotnet-sdk.sh
bash scripts/run-shellcheck.sh
bash tests/bash/run-tests.sh
```

and on the supported Windows/PowerShell mapping:

```powershell
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path './isolated-dotnet-sdk.ps1'),
    [ref]$tokens,
    [ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_.Message }
    throw 'PowerShell syntax validation failed.'
}

pwsh -NoProfile -File ./scripts/Invoke-PSScriptAnalyzer.ps1
pwsh -NoProfile -File ./scripts/Invoke-PSFormatter.ps1 -Check
pwsh -NoProfile -File ./tests/powershell/run-tests.ps1
```

The GitHub Validate workflow remains the cross-platform deterministic evidence source for Ubuntu/Bash, macOS/Bash, and Windows/PowerShell.
"""
)

e2e = Path("docs/e2e-testing.md")
replace_once(
    e2e,
    "5. list isolated SDKs and require the configured version to appear;",
    "5. run List and require the configured isolated version to appear in the installed-SDK output;",
    "E2E direct List wording",
)
replace_once(
    e2e,
    "1. enters Install;\n2. selects the discovered channel;",
    "1. enters Install with the Main menu's `I` command;\n2. selects the discovered channel;",
    "E2E Install mnemonic",
)
replace_once(
    e2e,
    "7. runs List and verifies the installed SDK is displayed;\n8. runs Remove for the single job-local isolated SDK and verifies return to Main;\n9. exits explicitly and requires a successful process result;",
    "7. runs List with `L` and verifies the installed SDK is displayed;\n8. runs Remove with `R` for the single job-local isolated SDK and verifies return to Main;\n9. exits explicitly with `E` and requires a successful process result;",
    "E2E remaining Main mnemonics",
)
replace_once(
    e2e,
    "E2E is intentionally not triggered on pull requests and is not a required merge check yet. Issue #60 owns future organization-backed merge-queue enforcement and required merge-candidate E2E gating. Until that protection exists and is demonstrated, deterministic `push: main` Validate remains enabled as the normal post-merge deterministic signal.",
    "E2E is intentionally not triggered on pull requests and is not a required merge check yet. Future organization-backed merge-queue work may promote E2E into required merge-candidate gating. Until that protection exists and is demonstrated, deterministic `push: main` Validate remains enabled as the normal post-merge deterministic signal.",
    "E2E gating wording",
)

Path("docs/images/isolation-install.svg").write_text(
    """<svg xmlns="http://www.w3.org/2000/svg" width="1150" height="600" viewBox="0 0 1150 600" role="img" aria-labelledby="title desc">
  <title id="title">Linux Bash isolated SDK install transcript</title>
  <desc id="desc">Representative transcript aligned with the real end-to-end target, showing .NET SDK 10.0.100 checked for existing Isolated and System installations, then installed successfully under ~/dotnet-sdks/10.0.100.</desc>
  <rect width="1150" height="600" rx="10" fill="#14161a"/>
  <g font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, 'Liberation Mono', monospace" fill="#e2e4e8">
    <text x="28" y="46" font-size="24" font-weight="700">Linux/Bash — representative real-E2E-aligned install</text>
    <text x="28" y="90" font-size="22">$ ~/dotnet-sdks/isolated-dotnet-sdk.sh install 10.0.100 --yes</text>
    <text x="28" y="130" font-size="22"><tspan fill="#5fd7ff">Target SDK:</tspan><tspan> 10.0.100</tspan></text>
    <text x="28" y="166" font-size="22"><tspan fill="#5fd7ff">Isolated install directory:</tspan><tspan> ~/dotnet-sdks/10.0.100</tspan></text>
    <text x="28" y="214" font-size="22">Checking existing installations...</text>
    <text x="28" y="258" font-size="22"><tspan fill="#5fd7ff">Isolated SDK:</tspan><tspan> Not installed</tspan></text>
    <text x="28" y="294" font-size="22"><tspan fill="#5fd7ff">System SDK:</tspan><tspan> Not installed</tspan></text>
    <text x="28" y="342" font-size="22">Loading Microsoft release metadata for SDK 10.0.100...</text>
    <text x="28" y="378" font-size="22">Downloading .NET SDK 10.0.100 payload...</text>
    <text x="28" y="414" font-size="22">Extracting verified .NET SDK 10.0.100 payload...</text>
    <text x="28" y="450" font-size="22">Verifying the isolated SDK...</text>
    <text x="28" y="494" font-size="22" fill="#5fd78a">Isolated SDK installation completed successfully.</text>
    <text x="28" y="530" font-size="22"><tspan fill="#5fd7ff">Location:</tspan><tspan> ~/dotnet-sdks/10.0.100</tspan></text>
    <text x="28" y="574" font-size="16" fill="#a5aab2">Aligned with the Linux/Bash E2E flow; CI HOME normalized to ~ and timestamps omitted.</text>
  </g>
</svg>
"""
)

Path("docs/images/isolation-list.svg").write_text(
    """<svg xmlns="http://www.w3.org/2000/svg" width="1050" height="360" viewBox="0 0 1050 360" role="img" aria-labelledby="title desc">
  <title id="title">Installed .NET SDK ownership example on Linux Bash</title>
  <desc id="desc">Representative prefix-free list output showing .NET SDK 10.0.100 in both the isolated SDK root and the normally resolved system dotnet host inventory, with concrete version directories and semantic heading accents.</desc>
  <rect width="1050" height="360" rx="10" fill="#14161a"/>
  <g font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, 'Liberation Mono', monospace" fill="#e2e4e8">
    <text x="28" y="46" font-size="24" font-weight="700">Linux/Bash — representative ownership view</text>
    <text x="28" y="88" font-size="21">$ ~/dotnet-sdks/isolated-dotnet-sdk.sh list</text>
    <text x="28" y="126" font-size="21" fill="#5fd7ff">Installed .NET SDKs</text>
    <text x="28" y="168" font-size="21" fill="#5fd7ff">Isolated SDKs:</text>
    <text x="56" y="202" font-size="20">10.0.100  ~/dotnet-sdks/10.0.100</text>
    <text x="28" y="246" font-size="21" fill="#5fd7ff">System SDKs:</text>
    <text x="56" y="280" font-size="20">10.0.100  /usr/share/dotnet/sdk/10.0.100</text>
    <text x="28" y="326" font-size="16" fill="#a5aab2">Representative output; system inventory varies with the normally resolved dotnet host.</text>
  </g>
</svg>
"""
)
