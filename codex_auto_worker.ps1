<#
Codex Auto Worker for GitHub Issues

目的:
- 親Issueを読む
- Codex CLIにサブIssueへ分解させる
- サブIssueをGitHubに作る
- サブIssueを1つずつCodex CLIに実装させる
- commit / push / PR作成
- 任意でCI確認と自動修正、自動マージ

前提:
- リポジトリのルートで実行する
- gh auth login 済み
- codex login 済み
- git が使える
- Issue/branch/PRを作る権限がある

まず試す:
  powershell -ExecutionPolicy Bypass -File .\codex_auto_worker.ps1 -ParentIssue 1 -MaxSubIssues 3

CI確認もする:
  powershell -ExecutionPolicy Bypass -File .\codex_auto_worker.ps1 -ParentIssue 1 -MaxSubIssues 3 -WaitForCI

完全自動寄り:
  powershell -ExecutionPolicy Bypass -File .\codex_auto_worker.ps1 -ParentIssue 1 -MaxSubIssues 5 -WaitForCI -AutoMerge
#>

param(
    [Parameter(Mandatory = $true)]
    [int]$ParentIssue,

    [int]$MaxSubIssues = 6,
    [int]$MaxFixAttempts = 3,

    [switch]$WaitForCI,
    [switch]$AutoMerge,

    [string]$BaseBranch = "",
    [string]$Remote = "origin",

    [string]$PlannerEffort = "high",
    [string]$WorkerEffort = "high",
    [string]$FixEffort = "high"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Step([string]$message) {
    Write-Host ""
    Write-Host "==== $message ====" -ForegroundColor Cyan
}

function Require-Command([string]$name) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw "Required command not found: $name"
    }
}

function Run([string]$file, [string[]]$arguments, [switch]$AllowFailure) {
    Write-Host "> $file $($arguments -join ' ')" -ForegroundColor DarkGray

    # Windows PowerShell 5.1 では、git/gh のstderrを 2>&1 で拾うと、
    # 終了コード0でも NativeCommandError になることがある。
    # そのため cmd.exe + 一時ファイル経由で stdout/stderr を取得する。
    $outFile = Join-Path $env:TEMP ("codex_run_stdout_" + [guid]::NewGuid().ToString() + ".txt")
    $errFile = Join-Path $env:TEMP ("codex_run_stderr_" + [guid]::NewGuid().ToString() + ".txt")
    $cmdFile = Join-Path $env:TEMP ("codex_run_cmd_" + [guid]::NewGuid().ToString() + ".cmd")

    try {
        $cmdLine = $file
        foreach ($a in $arguments) {
            $cmdLine += " " + (Quote-Arg $a)
        }

        $cmdText = @"
chcp 65001 > nul
$cmdLine > "$outFile" 2> "$errFile"
exit /b %ERRORLEVEL%
"@

        Set-Content -Path $cmdFile -Value $cmdText -Encoding ASCII

        $proc = Start-Process -FilePath "cmd.exe" `
            -ArgumentList @("/d", "/s", "/c", "`"$cmdFile`"") `
            -PassThru `
            -Wait `
            -WindowStyle Hidden `
            -WorkingDirectory (Get-Location)

        $stdout = ""
        $stderr = ""

        if (Test-Path $outFile) {
            $stdout = Get-Content -Path $outFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($null -eq $stdout) { $stdout = "" }
        }

        if (Test-Path $errFile) {
            $stderr = Get-Content -Path $errFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($null -eq $stderr) { $stderr = "" }
        }

        $text = ($stdout + "`n" + $stderr).Trim()

        if ($text.Length -gt 0) {
            Write-Host $text
        }

        if ($proc.ExitCode -ne 0 -and -not $AllowFailure) {
            throw "Command failed with exit code $($proc.ExitCode): $file $($arguments -join ' ')`n$text"
        }

        return [pscustomobject]@{
            ExitCode = $proc.ExitCode
            Output = $text
        }
    }
    finally {
        Remove-Item $outFile -ErrorAction SilentlyContinue
        Remove-Item $errFile -ErrorAction SilentlyContinue
        Remove-Item $cmdFile -ErrorAction SilentlyContinue
    }
}

function Quote-Arg([string]$arg) {
    if ($null -eq $arg) {
        return '""'
    }

    if ($arg -notmatch '[\s"]') {
        return $arg
    }

    $escaped = $arg -replace '\\', '\\' -replace '"', '\"'
    return '"' + $escaped + '"'
}

function Resolve-CommandPath([string]$file) {
    $resolved = Get-Command $file -ErrorAction SilentlyContinue
    if (-not $resolved) {
        throw "Command not found: $file"
    }

    if (-not [string]::IsNullOrWhiteSpace($resolved.Source)) {
        return $resolved.Source
    }

    if (-not [string]::IsNullOrWhiteSpace($resolved.Path)) {
        return $resolved.Path
    }

    throw "Could not resolve command path: $file"
}

function Run-Codex([string[]]$arguments, [switch]$AllowFailure) {
    Write-Host "> codex $($arguments -join ' ')" -ForegroundColor DarkGray

    $cmdPath = Resolve-CommandPath "codex"
    $extension = [System.IO.Path]::GetExtension($cmdPath).ToLowerInvariant()

    $actualFile = $cmdPath
    $actualArgs = @()

    if ($extension -eq ".ps1") {
        $actualFile = (Resolve-CommandPath "powershell.exe")
        $actualArgs += "-NoProfile"
        $actualArgs += "-ExecutionPolicy"
        $actualArgs += "Bypass"
        $actualArgs += "-File"
        $actualArgs += $cmdPath
        $actualArgs += $arguments
    }
    elseif ($extension -eq ".cmd" -or $extension -eq ".bat") {
        $actualFile = (Resolve-CommandPath "cmd.exe")
        $cmdLine = Quote-Arg $cmdPath
        foreach ($a in $arguments) {
            $cmdLine += " " + (Quote-Arg $a)
        }
        $actualArgs += "/d"
        $actualArgs += "/s"
        $actualArgs += "/c"
        $actualArgs += $cmdLine
    }
    else {
        $actualArgs += $arguments
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $actualFile
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    try {
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    }
    catch {
        # ignore
    }

    $quotedArgs = @()
    foreach ($arg in $actualArgs) {
        $quotedArgs += (Quote-Arg $arg)
    }
    $psi.Arguments = ($quotedArgs -join " ")

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi

    $stdoutBuilder = New-Object System.Text.StringBuilder
    $stderrBuilder = New-Object System.Text.StringBuilder

    $outHandler = [System.Diagnostics.DataReceivedEventHandler]{
        param($sender, $e)
        if ($null -ne $e.Data) {
            [void]$stdoutBuilder.AppendLine($e.Data)
            Write-Host $e.Data
        }
    }

    $errHandler = [System.Diagnostics.DataReceivedEventHandler]{
        param($sender, $e)
        if ($null -ne $e.Data) {
            [void]$stderrBuilder.AppendLine($e.Data)
            Write-Host $e.Data -ForegroundColor DarkGray
        }
    }

    $p.add_OutputDataReceived($outHandler)
    $p.add_ErrorDataReceived($errHandler)

    [void]$p.Start()
    $p.BeginOutputReadLine()
    $p.BeginErrorReadLine()

    $lastNotice = Get-Date
    while (-not $p.HasExited) {
        Start-Sleep -Seconds 5
        $now = Get-Date
        if (($now - $lastNotice).TotalSeconds -ge 30) {
            Write-Host "[still running: codex]" -ForegroundColor DarkYellow
            $lastNotice = $now
        }
    }

    $p.WaitForExit()

    $exit = $p.ExitCode
    $combined = ($stdoutBuilder.ToString() + "`n" + $stderrBuilder.ToString()).Trim()

    if ($exit -ne 0 -and -not $AllowFailure) {
        throw "Command failed with exit code $exit`: codex $($arguments -join ' ')`n$combined"
    }

    return [pscustomobject]@{
        ExitCode = $exit
        Output = $combined
    }
}

function GhJson([string[]]$arguments) {
    $r = Run "gh" $arguments
    if ([string]::IsNullOrWhiteSpace($r.Output)) {
        return $null
    }
    return $r.Output | ConvertFrom-Json
}

function Ensure-Label([string]$name, [string]$color, [string]$description) {
    $r = Run "gh" @("label", "list", "--search", $name, "--json", "name")
    $labels = @($r.Output | ConvertFrom-Json)

    if (-not ($labels | Where-Object { $_.name -eq $name })) {
        Run "gh" @("label", "create", $name, "--color", $color, "--description", $description) | Out-Null
    }
}

function Ensure-Labels() {
    Write-Step "Ensuring labels"

    Ensure-Label "codex:plan"     "7057ff" "Parent issue to be split by Codex"
    Ensure-Label "codex:subissue" "1d76db" "Sub-issue generated for Codex"
    Ensure-Label "codex:ready"    "0e8a16" "Ready for Codex implementation"
    Ensure-Label "codex:working"  "fbca04" "Codex is working on it"
    Ensure-Label "codex:done"     "0e8a16" "Finished by Codex"
    Ensure-Label "codex:blocked"  "d73a4a" "Needs human attention"
}

function Extract-JsonObject([string]$text) {
    # PowerShellではバッククォートがエスケープ文字なので、正規表現はシングルクォートにする。
    $fenced = [regex]::Match($text, '(?s)```(?:json)?\s*(\{.*?\})\s*```')
    if ($fenced.Success) {
        return $fenced.Groups[1].Value
    }

    $start = $text.IndexOf('{')
    $end = $text.LastIndexOf('}')

    if ($start -lt 0 -or $end -le $start) {
        throw "Could not find a JSON object in Codex output.`n$text"
    }

    return $text.Substring($start, $end - $start + 1)
}

function Invoke-CodexPrompt([string]$prompt, [string]$Effort = "high") {
    Write-Host "Starting Codex with reasoning effort: $Effort" -ForegroundColor Magenta

    # 重要:
    # Windows PowerShell 5.1 では、日本語の長文をコマンドライン引数として codex に渡すと
    # 文字化けしやすい。そのため、プロンプト本文はリポジトリ内のUTF-8ファイルへ保存し、
    # codexには英数字中心の短い指示だけを渡す。
    $promptFile = Join-Path (Get-Location) ".codex-current-prompt.md"
    $outFile = Join-Path (Get-Location) ".codex-debug-stdout.txt"
    $errFile = Join-Path (Get-Location) ".codex-debug-stderr.txt"

    Set-Content -Path $promptFile -Value $prompt -Encoding UTF8
    Remove-Item $outFile -ErrorAction SilentlyContinue
    Remove-Item $errFile -ErrorAction SilentlyContinue

    try {
        $shortInstruction = "Read .codex-current-prompt.md and follow its instructions exactly. Output only the requested result."

        # cmd.exe経由 + chcp 65001 で、codex.ps1 のNativeCommandErrorや文字化けを避ける。
        $cmdLine = @"
chcp 65001 > nul
codex exec -c model_reasoning_effort=$Effort "$shortInstruction" > ".codex-debug-stdout.txt" 2> ".codex-debug-stderr.txt"
exit /b %ERRORLEVEL%
"@

        $cmdFile = Join-Path $env:TEMP ("codex_run_" + [guid]::NewGuid().ToString() + ".cmd")
        Set-Content -Path $cmdFile -Value $cmdLine -Encoding ASCII

        Write-Host "> codex exec -c model_reasoning_effort=$Effort `"Read .codex-current-prompt.md...`"" -ForegroundColor DarkGray

        $proc = Start-Process -FilePath "cmd.exe" `
            -ArgumentList @("/d", "/s", "/c", "`"$cmdFile`"") `
            -PassThru `
            -WindowStyle Hidden `
            -WorkingDirectory (Get-Location)

        $lastOutLength = 0
        $lastErrLength = 0
        $lastNotice = Get-Date

        while (-not $proc.HasExited) {
            Start-Sleep -Seconds 3

            if (Test-Path $outFile) {
                $outText = Get-Content -Path $outFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                if ($null -ne $outText -and $outText.Length -gt $lastOutLength) {
                    $newText = $outText.Substring($lastOutLength)
                    Write-Host $newText
                    $lastOutLength = $outText.Length
                }
            }

            if (Test-Path $errFile) {
                $errText = Get-Content -Path $errFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                if ($null -ne $errText -and $errText.Length -gt $lastErrLength) {
                    $newErr = $errText.Substring($lastErrLength)
                    Write-Host $newErr -ForegroundColor DarkGray
                    $lastErrLength = $errText.Length
                }
            }

            $now = Get-Date
            if (($now - $lastNotice).TotalSeconds -ge 30) {
                Write-Host "[still running: codex]" -ForegroundColor DarkYellow
                $lastNotice = $now
            }
        }

        $stdout = ""
        $stderr = ""

        if (Test-Path $outFile) {
            $stdout = Get-Content -Path $outFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($null -eq $stdout) { $stdout = "" }
            if ($stdout.Length -gt $lastOutLength) {
                Write-Host $stdout.Substring($lastOutLength)
            }
        }

        if (Test-Path $errFile) {
            $stderr = Get-Content -Path $errFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($null -eq $stderr) { $stderr = "" }
            if ($stderr.Length -gt $lastErrLength) {
                Write-Host $stderr.Substring($lastErrLength) -ForegroundColor DarkGray
            }
        }

        # Codexの実際の回答はstdoutに出る。
        # stderrにはヘッダー、プロンプト表示、tokens usedなどのログが混ざるため、
        # JSON解析にはstdoutだけを返す。
        $answer = $stdout.Trim()
        $combined = ($stdout + "`n" + $stderr).Trim()

        if ($proc.ExitCode -ne 0) {
            throw "Codex failed with exit code $($proc.ExitCode).`n$combined"
        }

        if ([string]::IsNullOrWhiteSpace($answer)) {
            throw "Codex returned empty stdout. Prompt saved at: $promptFile`nDebug output:`n$combined"
        }

        return $answer
    }
    finally {
        Remove-Item $cmdFile -ErrorAction SilentlyContinue
        # .codex-current-prompt.md / debug files are intentionally kept for debugging.
    }
}

function Get-DefaultBranch() {
    if ($BaseBranch -ne "") {
        return $BaseBranch
    }

    $repo = GhJson @("repo", "view", "--json", "defaultBranchRef")
    return $repo.defaultBranchRef.name
}

function Get-ParentIssue() {
    return GhJson @("issue", "view", "$ParentIssue", "--json", "number,title,body,url,labels,state")
}

function Has-GeneratedSubIssues() {
    $issues = GhJson @("issue", "list", "--state", "all", "--label", "codex:subissue", "--json", "number,title,body,labels", "--limit", "100")

    foreach ($issue in @($issues)) {
        if ($issue.body -match "Parent:\s*#$ParentIssue\b") {
            return $true
        }
    }

    return $false
}

function Plan-SubIssues() {
    Write-Step "Planning sub-issues from parent #$ParentIssue"
    $parent = Get-ParentIssue

    if (Has-GeneratedSubIssues) {
        Write-Host "Sub-issues already exist for parent #$ParentIssue. Skipping planning."
        return
    }

    $prompt = @"
あなたはGitHub Issueを分解するPlannerです。

重要:
- 実装してはいけません
- ファイル変更もしてはいけません
- 次の親Issueを、Codexが安全に1つずつ実装できる小さなサブIssueに分解してください

条件:
- 最大 $MaxSubIssues 個まで
- 1サブIssue = 1PRで完了できる大きさ
- できるだけ順番に実装できるようにする
- DB変更、認証変更、大規模リファクタ、外部API仕様変更が必要なら、その作業だけを独立サブIssueにする
- 実装は一切しない

必ずJSONのみで出力してください。
説明文やMarkdownは禁止です。

JSON形式:
{
  "summary": "全体方針の短い説明",
  "subissues": [
    {
      "title": "短いタイトル",
      "goal": "このサブIssueの目的",
      "scope": "このサブIssueでやる範囲。やらないことも書く",
      "acceptance_criteria": ["条件1", "条件2"],
      "risk": "リスクや注意点",
      "test_hint": "確認方法やテスト案"
    }
  ]
}

親Issue:
Number: #$($parent.number)
URL: $($parent.url)
Title: $($parent.title)
Body:
$($parent.body)
"@

    $out = Invoke-CodexPrompt $prompt $PlannerEffort
    Set-Content -Path ".codex-plan-output.txt" -Value $out -Encoding UTF8

    $jsonText = Extract-JsonObject $out
    $plan = $jsonText | ConvertFrom-Json

    if (-not $plan.subissues -or @($plan.subissues).Count -eq 0) {
        throw "Planner returned no subissues. Output saved to .codex-plan-output.txt"
    }

    $order = 1

    foreach ($sub in @($plan.subissues | Select-Object -First $MaxSubIssues)) {
        $title = "[#$ParentIssue-$order] $($sub.title)"
        $criteria = @($sub.acceptance_criteria) | ForEach-Object { "- $_" }

        $body = @"
Parent: #$ParentIssue
Order: $order
Depends-on: sequential

## Goal
$($sub.goal)

## Scope
$($sub.scope)

## Acceptance Criteria
$($criteria -join "`n")

## Risk
$($sub.risk)

## Test Hint
$($sub.test_hint)

---
Generated by local Codex auto worker.
"@

        Write-Host "Creating sub-issue: $title"
        $r = Run "gh" @("issue", "create", "--title", $title, "--body", $body, "--label", "codex:subissue,codex:ready")
        $url = $r.Output.Trim()
        Write-Host "Created: $url"

        $order++
    }
}

function Get-SubIssues() {
    $issues = GhJson @("issue", "list", "--state", "open", "--label", "codex:subissue", "--json", "number,title,body,labels,state,url", "--limit", "100")
    $rows = @()

    foreach ($issue in @($issues)) {
        if ($issue.body -match "Parent:\s*#$ParentIssue\b") {
            $order = 999999
            if ($issue.body -match "Order:\s*(\d+)") {
                $order = [int]$Matches[1]
            }

            $labelNames = @($issue.labels | ForEach-Object { $_.name })

            $rows += [pscustomobject]@{
                number = $issue.number
                title = $issue.title
                body = $issue.body
                url = $issue.url
                order = $order
                labels = $labelNames
            }
        }
    }

    return @($rows | Sort-Object order, number)
}

function Pick-NextSubIssue() {
    $subs = Get-SubIssues

    foreach ($s in $subs) {
        if (
            $s.labels -contains "codex:ready" -and
            -not ($s.labels -contains "codex:working") -and
            -not ($s.labels -contains "codex:blocked")
        ) {
            return $s
        }
    }

    return $null
}

function Slug([string]$text) {
    $s = $text.ToLowerInvariant()
    $s = [regex]::Replace($s, "[^a-z0-9]+", "-")
    $s = $s.Trim("-")

    if ($s.Length -gt 40) {
        $s = $s.Substring(0, 40).Trim("-")
    }

    if ($s -eq "") {
        $s = "task"
    }

    return $s
}

function Has-GitChanges() {
    $r = Run "git" @("status", "--porcelain")
    return ($r.Output.Trim().Length -gt 0)
}

function Work-SubIssue($sub) {
    Write-Step "Working sub-issue #$($sub.number): $($sub.title)"

    Run "gh" @("issue", "edit", "$($sub.number)", "--remove-label", "codex:ready", "--add-label", "codex:working") | Out-Null

    $defaultBranch = Get-DefaultBranch

    Run "git" @("fetch", $Remote) | Out-Null
    Run "git" @("checkout", $defaultBranch) | Out-Null
    Run "git" @("pull", "--ff-only", $Remote, $defaultBranch) | Out-Null

    $branch = "codex/parent-$ParentIssue-issue-$($sub.number)-$(Slug $sub.title)"

    $existing = Run "git" @("rev-parse", "--verify", $branch) -AllowFailure
    if ($existing.ExitCode -eq 0) {
        Run "git" @("checkout", $branch) | Out-Null
    }
    else {
        Run "git" @("checkout", "-b", $branch) | Out-Null
    }

    $prompt = @"
あなたはWorkerです。
次のGitHubサブIssueだけを実装してください。

絶対ルール:
- このサブIssueに書かれている範囲だけ実装する
- 親Issue全体を一気に実装しない
- ついで修正をしない
- 大きな設計変更、DB変更、認証/権限変更、外部API仕様変更が必要なら、実装せず理由を書いて止まる
- 変更後に可能な範囲でテスト、lint、build、または動作確認コマンドを実行する
- 最後に、変更内容・確認結果・残課題を短くまとめる

GitHubサブIssue:
Number: #$($sub.number)
URL: $($sub.url)
Title: $($sub.title)
Body:
$($sub.body)
"@

    $codexOut = Invoke-CodexPrompt $prompt $WorkerEffort
    Set-Content -Path ".codex-last-output.txt" -Value $codexOut -Encoding UTF8

    if (-not (Has-GitChanges)) {
        $comment = @"
Codex ran but produced no git changes. Marking as blocked.

Codex output:
------------------------------------------------------------
$codexOut
------------------------------------------------------------
"@
        Run "gh" @("issue", "comment", "$($sub.number)", "--body", $comment) | Out-Null
        Run "gh" @("issue", "edit", "$($sub.number)", "--remove-label", "codex:working", "--add-label", "codex:blocked") | Out-Null
        return $false
    }

    Run "git" @("add", "-A") | Out-Null
    Run "git" @("commit", "-m", "Resolve sub-issue #$($sub.number)") | Out-Null
    Run "git" @("push", "-u", $Remote, $branch) | Out-Null

    $prBody = @"
Closes #$($sub.number)
Part of #$ParentIssue

## Codex output

------------------------------------------------------------
$codexOut
------------------------------------------------------------
"@

    $prCreate = Run "gh" @("pr", "create", "--title", "Resolve #$($sub.number): $($sub.title)", "--body", $prBody, "--base", $defaultBranch, "--head", $branch)
    $prUrl = $prCreate.Output.Trim()
    Write-Host "PR created: $prUrl" -ForegroundColor Green

    $prNumber = $null
    if ($prUrl -match "/pull/(\d+)") {
        $prNumber = [int]$Matches[1]
    }

    if (-not $prNumber) {
        $pr = GhJson @("pr", "view", "--json", "number")
        $prNumber = [int]$pr.number
    }

    $ok = $true
    if ($WaitForCI) {
        $ok = Wait-And-FixCI -SubIssue $sub -PrNumber $prNumber
    }

    if ($ok -and $AutoMerge) {
        Write-Step "Merging PR #$prNumber"

        $merge = Run "gh" @("pr", "merge", "$prNumber", "--squash", "--delete-branch") -AllowFailure

        if ($merge.ExitCode -ne 0) {
            $comment = @"
PR #$prNumber could not be auto-merged. Please check manually.

$($merge.Output)
"@
            Run "gh" @("issue", "comment", "$($sub.number)", "--body", $comment) | Out-Null
            Run "gh" @("issue", "edit", "$($sub.number)", "--remove-label", "codex:working", "--add-label", "codex:blocked") | Out-Null
            return $false
        }

        Run "gh" @("issue", "close", "$($sub.number)", "--comment", "Completed by Codex auto worker. PR #$prNumber merged.") | Out-Null
        Run "gh" @("issue", "edit", "$($sub.number)", "--remove-label", "codex:working", "--add-label", "codex:done") | Out-Null
        return $true
    }

    if ($ok) {
        Run "gh" @("issue", "comment", "$($sub.number)", "--body", "PR #$prNumber created successfully. Auto-merge is disabled, so stopping after this PR.") | Out-Null
        Write-Host "AutoMerge is off. Stop here to avoid building later sub-issues on unmerged code." -ForegroundColor Yellow
        return $false
    }

    Run "gh" @("issue", "edit", "$($sub.number)", "--remove-label", "codex:working", "--add-label", "codex:blocked") | Out-Null
    return $false
}

function Wait-And-FixCI($SubIssue, [int]$PrNumber) {
    Write-Step "Checking CI for PR #$PrNumber"

    for ($attempt = 0; $attempt -le $MaxFixAttempts; $attempt++) {
        $checks = Run "gh" @("pr", "checks", "$PrNumber", "--watch", "--fail-fast", "--interval", "30") -AllowFailure

        if ($checks.ExitCode -eq 0) {
            Write-Host "CI passed for PR #$PrNumber" -ForegroundColor Green
            return $true
        }

        if ($attempt -ge $MaxFixAttempts) {
            $comment = @"
CI failed after $MaxFixAttempts fix attempts. Marking as blocked.

Last check output:
------------------------------------------------------------
$($checks.Output)
------------------------------------------------------------
"@
            Run "gh" @("issue", "comment", "$($SubIssue.number)", "--body", $comment) | Out-Null
            return $false
        }

        Write-Host "CI failed. Asking Codex to fix. Attempt $($attempt + 1)/$MaxFixAttempts" -ForegroundColor Yellow

        $details = Run "gh" @("pr", "checks", "$PrNumber") -AllowFailure

        $prompt = @"
このPRのCIが失敗しました。失敗内容を読み、最小変更で修正してください。

対象サブIssue:
#$($SubIssue.number) $($SubIssue.title)

PR:
#$PrNumber

CI出力:
$($details.Output)

ルール:
- このCI失敗の修正だけを行う
- 関係ないリファクタや追加機能は禁止
- 修正後に可能な範囲でテストまたはbuildを実行する
- 最後に修正内容をまとめる
"@

        $fixOut = Invoke-CodexPrompt $prompt $FixEffort
        Set-Content -Path ".codex-last-fix-output.txt" -Value $fixOut -Encoding UTF8

        if (-not (Has-GitChanges)) {
            $comment = @"
Codex attempted to fix CI but produced no git changes. Marking as blocked.

Output:
------------------------------------------------------------
$fixOut
------------------------------------------------------------
"@
            Run "gh" @("issue", "comment", "$($SubIssue.number)", "--body", $comment) | Out-Null
            return $false
        }

        Run "git" @("add", "-A") | Out-Null
        Run "git" @("commit", "-m", "Fix CI for sub-issue #$($SubIssue.number)") | Out-Null
        Run "git" @("push") | Out-Null
    }

    return $false
}

function Main() {
    Require-Command "gh"
    Require-Command "git"
    Require-Command "codex"

    Write-Step "Checking repository and authentication"
    Write-Host "Skipping gh auth status check. Run gh auth status manually if GitHub commands fail." -ForegroundColor DarkYellow
    Run "git" @("rev-parse", "--show-toplevel") | Out-Null

    Ensure-Labels
    Plan-SubIssues

    while ($true) {
        $next = Pick-NextSubIssue

        if (-not $next) {
            Write-Step "No ready sub-issues left"
            Run "gh" @("issue", "comment", "$ParentIssue", "--body", "Codex auto worker found no remaining open codex:ready sub-issues.") | Out-Null
            break
        }

        $continued = Work-SubIssue $next

        if (-not $continued) {
            Write-Host "Stopped. Reason: AutoMerge disabled, blocked issue, no changes, or failed CI." -ForegroundColor Yellow
            break
        }
    }
}

Main
