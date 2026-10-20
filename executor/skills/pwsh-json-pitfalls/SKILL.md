---
name: pwsh-json-pitfalls
description: Correct PowerShell 7 patterns for producing JSON, parsing numbers, rounding and reading/writing encodings, plus one-line self-tests.
---

# PowerShell 7: JSON / numbers / encodings

## 1. Arrays to JSON (the most common trap)
Piping into `ConvertTo-Json` unwraps single-element arrays into objects and turns empty arrays into nothing. Correct pattern:
```powershell
$items = @($rows | ForEach-Object { [ordered]@{ name = $_.name; n = 1 } })
$obj   = [ordered]@{ total = $items.Count; items = [object[]]$items }   # cast field values explicitly to [object[]]
$json  = ConvertTo-Json -InputObject $obj -Depth 10 -Compress            # use -InputObject, not the pipeline
```
- When the top level is an array: `ConvertTo-Json -InputObject ([object[]]$items) -Compress`.
- Self-test (try both 0 and 1 elements):
  `ConvertTo-Json -InputObject ([ordered]@{ a = [object[]]@() }) -Compress` → `{"a":[]}`;
  `ConvertTo-Json -InputObject ([ordered]@{ a = [object[]]@(1) }) -Compress` → `{"a":[1]}`
- Use `[ordered]@{}` for a fixed field order; `-Depth` defaults to 2 — always set it for nested data.
- Functions that `return` an array get unwrapped too: write `return ,$arr`, or wrap the call as `@(func)`.

## 2. Numbers
- Parsing: `$v = 0.0; if ([double]::TryParse($s, [Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$v)) { ... }`; for integers use `[long]::TryParse` (not int — token counts can be large).
- Rounding: `[math]::Round(1.25, 1)` gives 1.2 (banker's rounding). For 1.3 write `[math]::Round(1.25, 1, 'AwayFromZero')`.
- Average: `($xs | Measure-Object -Average).Average`; it is `$null` for an empty collection, so check the count first.

## 3. Encodings
- Read: `Get-Content $p -Raw -Encoding utf8`; CSV: `Import-Csv $p -Encoding utf8` (works with or without BOM).
- Write UTF-8 without BOM (JSON/sh/YAML): `[IO.File]::WriteAllText($p, $s, (New-Object Text.UTF8Encoding $false))`.
- Write UTF-8 with BOM (.ps1 with non-ASCII text for Windows PowerShell 5.1): same, with `$true`.
- LF line endings: `$s -replace "`r`n", "`n"` before writing.
- In pwsh 7, `Set-Content -Encoding utf8` writes without BOM; `utf8BOM` adds one.

## 4. Syntax
- `elseif` (not `else if`).
- Comparisons are case-insensitive by default; use `-ceq`, `-cmatch` for case-sensitive.
- Syntax-check after writing: `pwsh -NoProfile -Command "$null = [scriptblock]::Create((Get-Content <file> -Raw)); 'syntax ok'"`
- Exit codes: `exit 2`; write errors to stderr: `[Console]::Error.WriteLine('...')`.
- Stable, culture-independent sorting: `Sort-Object Name -Culture ([cultureinfo]::InvariantCulture)`, or `[Array]::Sort($keys, [StringComparer]::Ordinal)`.
