---
name: pwsh-json-pitfalls
description: PowerShell 7 生成 JSON、解析数字、四舍五入、读写编码的正确写法，以及一条命令自测。
---

# PowerShell 7：JSON / 数字 / 编码

## 1. 数组转 JSON（最常见的坑）
`ConvertTo-Json` 走管道时会把单元素数组拆成对象、空数组变成空。正确写法：
```powershell
$items = @($rows | ForEach-Object { [ordered]@{ name = $_.name; n = 1 } })
$obj   = [ordered]@{ total = $items.Count; items = [object[]]$items }   # 字段值显式写成 [object[]]
$json  = ConvertTo-Json -InputObject $obj -Depth 10 -Compress            # 用 -InputObject，不要用管道
```
- 顶层就是数组时：`ConvertTo-Json -InputObject ([object[]]$items) -Compress`。
- 自测（0 个和 1 个元素都要试）：
  `ConvertTo-Json -InputObject ([ordered]@{ a = [object[]]@() }) -Compress` → `{"a":[]}`；
  `ConvertTo-Json -InputObject ([ordered]@{ a = [object[]]@(1) }) -Compress` → `{"a":[1]}`
- 字段顺序要固定就用 `[ordered]@{}`；`-Depth` 默认只有 2，嵌套深时一定要写。
- 函数 `return` 数组时也会被拆开：写 `return ,$arr`，或调用方用 `@(函数)` 包起来。

## 2. 数字
- 解析：`$v = 0.0; if ([double]::TryParse($s, [Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$v)) { ... }`；整数用 `[long]::TryParse`（不要用 int，token 数可能很大）。
- 舍入：`[math]::Round(1.25, 1)` 得 1.2（银行家舍入）。要 1.3 就写 `[math]::Round(1.25, 1, 'AwayFromZero')`。
- 平均值：`($xs | Measure-Object -Average).Average`；空集合时是 `$null`，先判断数量。

## 3. 读写编码
- 读：`Get-Content $p -Raw -Encoding utf8`；CSV：`Import-Csv $p -Encoding utf8`（带不带 BOM 都能读）。
- 写无 BOM UTF-8（JSON/sh/YAML）：`[IO.File]::WriteAllText($p, $s, (New-Object Text.UTF8Encoding $false))`。
- 写带 BOM UTF-8（给 Windows PowerShell 5.1 跑且含中文的 .ps1）：同上，参数改成 `$true`。
- LF 换行：`$s -replace "`r`n", "`n"` 后再写。
- pwsh 7 的 `Set-Content -Encoding utf8` 写的是无 BOM；`utf8BOM` 才带 BOM。

## 4. 语法
- `elseif`（不是 `else if`）。
- 比较默认不区分大小写，要区分用 `-ceq`、`-cmatch`。
- 写完先做语法检查：`pwsh -NoProfile -Command "$null = [scriptblock]::Create((Get-Content <文件> -Raw)); 'syntax ok'"`
- 退出码：`exit 2`；错误信息写 stderr：`[Console]::Error.WriteLine('...')`。
- 排序要稳定、与区域无关：`Sort-Object Name -Culture ([cultureinfo]::InvariantCulture)`，或 `[Array]::Sort($keys, [StringComparer]::Ordinal)`。
