---
name: headless-edge-test
description: 用无头 Edge 渲染 HTML 页面并检查渲染后的 DOM（Windows，Codex 沙箱内外通用）。
---

# 无头 Edge 渲染检查

## 固定写法（直接复制）
```powershell
$edge = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
$prof = Join-Path $env:TEMP "edge-prof-$PID"          # 独立的临时用户目录，避免和用户的 Edge 冲突
$dom  = Join-Path $env:TEMP "edge-dom-$PID.html"
$url  = ([uri](Resolve-Path 'out\page.html').Path).AbsoluteUri   # 本地文件 → file:///D:/...；本机服务就直接写 http://localhost:端口/路径
Start-Process $edge -ArgumentList '--headless=new', '--disable-gpu', '--no-sandbox', '--no-first-run',
    "--user-data-dir=$prof", '--virtual-time-budget=5000', '--dump-dom', $url `
    -Wait -RedirectStandardOutput $dom -WindowStyle Hidden
$html = Get-Content $dom -Raw -Encoding utf8
Remove-Item $prof, $dom -Recurse -Force -ErrorAction SilentlyContinue
```

## 要点
- **必须用 `Start-Process -Wait -RedirectStandardOutput`**。msedge.exe 是 GUI 程序，用 `& $edge ...` 时 PowerShell 不等它结束，也拿不到 stdout，结果是空字符串。
- **沙箱里必须加 `--no-sandbox`**，否则 Edge 直接崩溃（退出码 -2147483645）。宿主机上加了也没坏处。
- `--virtual-time-budget=5000` 让页面里的 JS（包括 fetch、setTimeout）先跑完再输出 DOM。
- `--dump-dom` 输出的是 JS 执行后的 DOM（序列化 HTML），用正则检查，例如 `$html -match '<td>12\.5</td>'`。注意 `<`、`.` 等要转义。
- 页面要从本机服务读数据（fetch /api/...）时：沙箱里不能起 HTTP 服务。只能在宿主机检查的项用 `HostCheck`，或者把数据内嵌在页面里测试。
- 不要用 Playwright/Puppeteer/npm 包，也不要下载 Chrome；本机 Edge 就够了。

## 出问题时
- `$html` 为空：检查是不是用了 `&` 调用；检查 URL 是否正确（file:// 要用 AbsoluteUri）。
- 渲染结果里没有 JS 生成的内容：打开页面源码看 JS 有无语法错误；可临时加 `--enable-logging=stderr --v=0 -RedirectStandardError <文件>` 查看控制台错误。
