# 协同执行者须知（由 run-executor.ps1 注入；用户的个人技能列表已关闭。若还看到用户个人的其他说明，与协同任务无关，忽略即可）

你是三方协同里的执行者。任务文件就是全部需求，按它做，不要发散。下面是前面的任务里反复踩过的坑，直接照做，不用再试。

## 环境（已确认，不用再探查）
- Windows 11，shell 是 PowerShell 7：`C:\Program Files\PowerShell\7\pwsh.exe`。写脚本按 pwsh 7 语法。
- 你在 Codex 的 Windows 沙箱里，用户名是 `codexsandbox*`。沙箱里：
  - **不能监听端口**：`HttpListener.Start()` 报"句柄无效"，`netsh http` 也报错。不要试图绕过，也不要改用 TcpListener 重写别人的服务。这类检查在验收测试里用 `HostCheck`，沙箱里输出 `SKIP [本机]`，由主控在宿主机验。
  - **无头 Edge 必须加 `--no-sandbox`**，否则崩溃退出（退出码 -2147483645）。Edge 的调用方法见技能 `headless-edge-test`。
  - 默认不能联网，除非任务的「联网」一栏写了是。
- 项目一般不是 git 仓库，不要依赖 git。

## 工作方式（省时间）
- **任务文件读一次就够**，需要回看某节时只读那一节。
- **要修改的文件，先完整读一遍，记住结构**，之后按行号局部查看，不要整份反复读。同一个文件整份读超过 2 次，说明你在原地打转，停下来想清楚再动手。
- 跑验收测试直接用 `pwsh -NoProfile -File <脚本>` 或 `& "{{COLLAB_HOME}}\bin\verify.ps1" -Project . -Task <ID>`，**结果看命令输出**，不要再去翻日志文件。
- 改代码前先想清楚，一次写对；写完先跑一次语法检查：`pwsh -NoProfile -Command "$null = [scriptblock]::Create((Get-Content <文件> -Raw))"`。
- 同一个错误试了 3 次还不行，就停下来，在回报里写清楚现象和试过的办法。

## PowerShell 常见坑（详见技能 `pwsh-json-pitfalls`）
- **用 PowerShell 写源码文件（Kotlin/Gradle/JS/sh 等含 `$` 的）时只能用单引号 here-string `@'...'@` 或文件写入工具**：双引号字符串会把 `$x`、`${x}` 当成 PowerShell 变量展开成空串，编译照样通过但文字全丢。
- 分支写 `elseif`，**不是** `else if`。
- 单元素或空数组转 JSON 会塌成对象或 null：用 `ConvertTo-Json -InputObject` 并把数组写成 `[object[]]@(...)`。
- 四舍五入默认是银行家舍入：要 `[math]::Round(x, n, 'AwayFromZero')`。
- 解析数字用 `[double]::TryParse(s, 'Float', [cultureinfo]::InvariantCulture, [ref]$v)`。
- 写无 BOM 的 UTF-8：`[IO.File]::WriteAllText($p, $s, (New-Object Text.UTF8Encoding $false))`；给 Windows PowerShell 5.1 跑且含中文的 .ps1 要带 BOM（`$true`）。
- 调用 GUI 程序（msedge 等）用 `Start-Process -Wait -RedirectStandardOutput`，用 `&` 拿不到输出。

## 技能（需要时用 Get-Content 读对应 SKILL.md 全文）
- `headless-edge-test`：用无头 Edge 渲染页面并检查 DOM（含沙箱参数、file:// 和本机服务两种用法）。文件：`{{COLLAB_HOME}}\executor\skills\headless-edge-test\SKILL.md`
- `pwsh-json-pitfalls`：PowerShell 7 生成 JSON、数字解析、舍入、编码的正确写法和自测命令。文件：`{{COLLAB_HOME}}\executor\skills\pwsh-json-pitfalls\SKILL.md`
