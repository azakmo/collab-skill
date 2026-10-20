# console/ledger-stats.ps1
# 账本统计函数，供控制台 /api/ledger 路由使用。

function Get-LedgerStats([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            generated  = (Get-Date).ToString('yyyy-MM-dd HH:mm')
            source     = $Path
            rowCount   = 0
            skipped    = 0
            byExecType = [object[]]@()
            byExecutor = [object[]]@()
            projects   = [object[]]@()
            sessions   = [object[]]@()
            runs       = [object[]]@()
        }
    }

    $rawRows = try { @(Import-Csv -LiteralPath $Path -Encoding utf8) } catch { @() }
    if ($rawRows.Count -eq 0) {
        return [pscustomobject]@{
            generated  = (Get-Date).ToString('yyyy-MM-dd HH:mm')
            source     = $Path
            rowCount   = 0
            skipped    = 0
            byExecType = [object[]]@()
            byExecutor = [object[]]@()
            projects   = [object[]]@()
            sessions   = [object[]]@()
            runs       = [object[]]@()
        }
    }

    function Fix-Number($n) {
        if ($null -eq $n) { return $null }
        if ($n % 1 -eq 0) { [long]$n } else { $n }
    }

    $validRows = [System.Collections.Generic.List[object]]::new()
    $skipped = 0

    for ($i = 0; $i -lt $rawRows.Count; $i++) {
        $row = $rawRows[$i]
        $parsedTime = [datetime]::MinValue
        $validTime = [datetime]::TryParseExact($row.time, 'yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsedTime)
        if (-not $validTime) {
            $skipped++
            continue
        }

        $parsedTokens = 0L
        $tokensVal = if (-not [string]::IsNullOrWhiteSpace($row.tokens) -and [long]::TryParse($row.tokens, [globalization.NumberStyles]::Integer, [cultureinfo]::InvariantCulture, [ref]$parsedTokens)) {
            $parsedTokens
        } else {
            $null
        }

        $parsedMinutes = 0.0
        $minutesVal = if (-not [string]::IsNullOrWhiteSpace($row.minutes) -and [double]::TryParse($row.minutes, [globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$parsedMinutes)) {
            Fix-Number $parsedMinutes
        } else {
            $null
        }

        $isCc = ($row.executor -ieq 'cc')
        $equivVal = 0L
        if ($isCc -and $row.note -match 'equiv=(\d+)') {
            $equivVal = [long]$Matches[1]
        }

        $validRows.Add([pscustomobject]@{
            fileIndex = $i
            timeStr   = [string]$row.time
            timeDt    = $parsedTime
            project   = [string]$row.project
            task      = [string]$row.task
            type      = [string]$row.type
            executor  = [string]$row.executor
            model     = [string]$row.model
            tokens    = $tokensVal
            minutes   = $minutesVal
            review    = [string]$row.review
            isCc      = $isCc
            equiv     = $equivVal
        })
    }

    $rowCount = $validRows.Count

    $execRows = [System.Collections.Generic.List[object]]::new()
    $ccRows = [System.Collections.Generic.List[object]]::new()
    foreach ($r in $validRows) {
        if ($r.isCc) {
            $ccRows.Add($r)
        } else {
            $execRows.Add($r)
        }
    }

    # runs: 每条执行者行，按 time 升序（同时间保持文件顺序）
    $sortedExec = @($execRows | Sort-Object { $_.timeDt }, { $_.fileIndex })
    $runsList = [System.Collections.Generic.List[object]]::new()
    foreach ($r in $sortedExec) {
        $runsList.Add([pscustomobject]@{
            time     = $r.timeStr
            project  = $r.project
            task     = $r.task
            type     = $r.type
            executor = $r.executor
            model    = $r.model
            tokens   = $r.tokens
            minutes  = $r.minutes
            review   = $r.review
        })
    }

    function Compute-GroupStats($groupItems, [string]$execName, [string]$typeName) {
        $runsCount = $groupItems.Count
        $reviewedItems = @($groupItems | Where-Object { $_.review -in @('通过', '返工', '失败') })
        $reviewedCount = $reviewedItems.Count
        $passedCount = @($reviewedItems | Where-Object { $_.review -eq '通过' }).Count

        $passRate = if ($reviewedCount -gt 0) {
            Fix-Number ([math]::Round([double]$passedCount / [double]$reviewedCount, 4))
        } else {
            $null
        }

        $tokItems = @($groupItems | Where-Object { $null -ne $_.tokens })
        $avgTokens = if ($tokItems.Count -gt 0) {
            $sum = 0.0
            foreach ($t in $tokItems) { $sum += $t.tokens }
            [long][math]::Round($sum / $tokItems.Count, 0, [System.MidpointRounding]::AwayFromZero)
        } else {
            $null
        }

        $minItems = @($groupItems | Where-Object { $null -ne $_.minutes })
        $avgMinutes = if ($minItems.Count -gt 0) {
            $sum = 0.0
            foreach ($m in $minItems) { $sum += $m.minutes }
            Fix-Number ([math]::Round($sum / $minItems.Count, 1, [System.MidpointRounding]::AwayFromZero))
        } else {
            $null
        }

        [pscustomobject]@{
            executor   = $execName
            type       = $typeName
            runs       = $runsCount
            reviewed   = $reviewedCount
            passed     = $passedCount
            passRate   = $passRate
            avgTokens  = $avgTokens
            avgMinutes = $avgMinutes
        }
    }

    $byExecTypeList = [System.Collections.Generic.List[object]]::new()
    $byExecTypeGroups = @($execRows | Group-Object { "$($_.executor)`0$($_.type)" })
    foreach ($grp in $byExecTypeGroups) {
        $parts = $grp.Name -split "`0"
        $byExecTypeList.Add((Compute-GroupStats $grp.Group $parts[0] $parts[1]))
    }
    $byExecTypeSorted = [object[]]@($byExecTypeList | Sort-Object executor, type)

    $byExecutorList = [System.Collections.Generic.List[object]]::new()
    $byExecutorGroups = @($execRows | Group-Object executor)
    foreach ($grp in $byExecutorGroups) {
        $byExecutorList.Add((Compute-GroupStats $grp.Group $grp.Name '全部'))
    }
    $byExecutorSorted = [object[]]@($byExecutorList | Sort-Object executor)

    $projectsList = [System.Collections.Generic.List[object]]::new()
    $projectGroups = @($validRows | Group-Object project | Sort-Object Name)
    foreach ($pGrp in $projectGroups) {
        $projName = $pGrp.Name
        $pRows = $pGrp.Group

        $pExecRows = @($pRows | Where-Object { -not $_.isCc })
        $pCcRows = @($pRows | Where-Object { $_.isCc })

        $pRuns = $pExecRows.Count
        $pExecTokens = 0L
        foreach ($r in $pExecRows) {
            if ($null -ne $r.tokens) { $pExecTokens += $r.tokens }
        }

        $pCcTokens = 0L
        $pCcEquiv = 0L
        $pCcMinutes = 0.0
        foreach ($r in $pCcRows) {
            if ($null -ne $r.tokens) { $pCcTokens += $r.tokens }
            $pCcEquiv += $r.equiv
            if ($null -ne $r.minutes) { $pCcMinutes += $r.minutes }
        }

        $byExecMap = [ordered]@{}
        foreach ($r in $pExecRows) {
            if (-not $byExecMap.Contains($r.executor)) {
                $byExecMap[$r.executor] = 0L
            }
            if ($null -ne $r.tokens) {
                $byExecMap[$r.executor] += $r.tokens
            }
        }

        $ratio = if ($pCcEquiv -gt 0 -and $pExecTokens -gt 0) {
            Fix-Number ([math]::Round([double]$pCcEquiv / [double]$pExecTokens, 4))
        } else {
            $null
        }

        $projectsList.Add([pscustomobject]@{
            project        = $projName
            runs           = $pRuns
            executorTokens = $pExecTokens
            ccTokens       = $pCcTokens
            ccEquiv        = $pCcEquiv
            ccMinutes      = Fix-Number $pCcMinutes
            byExecutor     = [pscustomobject]$byExecMap
            ratio          = $ratio
        })
    }
    $projectsSorted = [object[]]@($projectsList)

    $sessionsList = [System.Collections.Generic.List[object]]::new()
    $sessionGroups = @($validRows | Group-Object { "$($_.project)|$($_.timeDt.ToString('yyyy-MM-dd'))" })
    foreach ($sGrp in $sessionGroups) {
        $sRows = $sGrp.Group
        $firstRow = $sRows[0]
        $proj = $firstRow.project
        $dateStr = $firstRow.timeDt.ToString('yyyy-MM-dd')
        $sessId = "$proj|$dateStr"

        $sortedSRows = @($sRows | Sort-Object { $_.timeDt }, { $_.fileIndex })
        $startTime = $sortedSRows[0].timeStr
        $endTime = $sortedSRows[-1].timeStr

        $sExecRows = @($sRows | Where-Object { -not $_.isCc })
        $sCcRows = @($sRows | Where-Object { $_.isCc })

        $sRuns = $sExecRows.Count
        $sExecTokens = 0L
        foreach ($r in $sExecRows) {
            if ($null -ne $r.tokens) { $sExecTokens += $r.tokens }
        }

        $sCcTokens = 0L
        $sCcEquiv = 0L
        foreach ($r in $sCcRows) {
            if ($null -ne $r.tokens) { $sCcTokens += $r.tokens }
            $sCcEquiv += $r.equiv
        }

        $sessionsList.Add([pscustomobject]@{
            id             = $sessId
            project        = $proj
            date           = $dateStr
            start          = $startTime
            end            = $endTime
            runs           = $sRuns
            executorTokens = $sExecTokens
            ccTokens       = $sCcTokens
            ccEquiv        = $sCcEquiv
        })
    }
    $sessionsSorted = [object[]]@($sessionsList | Sort-Object start)

    return [pscustomobject]@{
        generated  = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        source     = $Path
        rowCount   = $rowCount
        skipped    = $skipped
        byExecType = $byExecTypeSorted
        byExecutor = $byExecutorSorted
        projects   = $projectsSorted
        sessions   = $sessionsSorted
        runs       = [object[]]@($runsList)
    }
}

function Get-LedgerStatsJson([string]$Path) {
    (Get-LedgerStats $Path) | ConvertTo-Json -Depth 10 -Compress
}