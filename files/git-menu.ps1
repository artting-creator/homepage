$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Set-Location -LiteralPath $PSScriptRoot

function Pause-Back {
    Write-Host ''
    Write-Host ('-' * 60) -ForegroundColor DarkGray
    Read-Host '按 Enter 回到選單' | Out-Null
}

# 沒有真正的主控台視窗時（例如輸出被導向）Clear-Host 會丟例外，忽略即可
function Clear-Screen {
    try { Clear-Host } catch { }
}

# 印出指令再執行它。
#
# 刻意做成「顯示」和「執行」用同一份參數，而不是在每個選項裡另外寫一行說明文字：
# 說明是手寫的話，改了指令卻忘記改說明，畫面就會開始騙人。這裡看到的那一行，
# 就是實際送給 git 的那一行。
#
# 這一行要能直接複製到終端機重跑，所以「只要不是單純的字母數字路徑就補引號」。
# 光看空白不夠：--format=%h|%ad|%s 沒有空白，貼過去卻會被 | 當成管線切成三段。
#
# 呼叫這個函式時，git 的 -- 分隔符要寫成 '--'（加引號）。裸寫的 -- 會被 PowerShell
# 當成「參數結束」標記吃掉，根本傳不進來，畫面上和實際執行的指令都會少一截。
function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs)

    $shown = ($GitArgs | ForEach-Object {
        if ($_ -notmatch '^[A-Za-z0-9._/\\:=@~^+,%-]+$') {
            '"' + ($_ -replace '"', '`"') + '"'
        } else { $_ }
    }) -join ' '

    Write-Host "  > git $shown" -ForegroundColor DarkYellow
    Write-Host ''
    & git @GitArgs
}

function Get-UnpushedCommits {
    param([string]$Format = '%h|%ad|%s')

    $hasUpstream = $true
    git rev-parse --abbrev-ref '@{u}' 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { $hasUpstream = $false }

    if ($hasUpstream) {
        return @(git log '@{u}..HEAD' --format=$Format --date=short 2>$null)
    } else {
        return @(git log --format=$Format --date=short 2>$null)
    }
}

function Get-CommitMessage {
    $title = Read-Host '提交標題（直接按 Enter 取消，輸入 E 開啟記事本編輯）'
    if ([string]::IsNullOrWhiteSpace($title)) {
        Write-Host '已取消，沒有做任何變更。' -ForegroundColor DarkGray
        return $null
    }
    if ($title.Trim().ToUpper() -eq 'E') {
        $tempFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "GIT_COMMIT_EDITMSG_$([System.Guid]::NewGuid().ToString('N')).txt")
        try {
            $template = @"


# 請在此輸入提交訊息。
# 第一行為「標題」，空一行後為「詳細內容」。
# 以 '#' 開頭的行是註解，會被自動忽略，空白檔案將取消提交。
"@
            [System.IO.File]::WriteAllText($tempFile, $template, [System.Text.Encoding]::UTF8)
            $origTime = (Get-Item -LiteralPath $tempFile).LastWriteTimeUtc
            Start-Process notepad.exe -ArgumentList $tempFile
            Write-Host ''
            Write-Host '  已為您開啟記事本 (Notepad)。' -ForegroundColor Cyan
            Write-Host '  請在記事本中輸入提交訊息，儲存後關閉記事本，然後回到此視窗。' -ForegroundColor DarkGray
            Write-Host ''
            $ans = Read-Host '儲存完畢請按 Enter 繼續（輸入 Q 取消）'
            if ($ans.Trim().ToUpper() -eq 'Q') {
                Write-Host '已取消。' -ForegroundColor DarkGray
                return $null
            }

            if (Test-Path -LiteralPath $tempFile) {
                $newTime = (Get-Item -LiteralPath $tempFile).LastWriteTimeUtc
                $rawLines = [System.IO.File]::ReadAllLines($tempFile, [System.Text.Encoding]::UTF8)
                $contentLines = @($rawLines | Where-Object { $_ -notmatch '^\s*#' })
                $fullText = ($contentLines -join "`n").Trim()
                if ($origTime -eq $newTime -or [string]::IsNullOrWhiteSpace($fullText)) {
                    Write-Host '已取消，內容為空或未儲存變更。' -ForegroundColor DarkGray
                    return $null
                }
                return $fullText
            } else {
                Write-Host '已取消。' -ForegroundColor DarkGray
                return $null
            }
        } finally {
            if (Test-Path -LiteralPath $tempFile) { Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue }
        }
    }

    Write-Host ''
    Write-Host '詳細說明（選填。直接按 Enter 跳過；若有多行請逐行輸入，輸入空行結束）：' -ForegroundColor DarkGray
    $bodyLines = @()
    while ($true) {
        $line = Read-Host '  >'
        if ([string]::IsNullOrWhiteSpace($line)) { break }
        $bodyLines += $line
    }

    if ($bodyLines.Count -eq 0) {
        return @($title)
    } else {
        return @($title, ($bodyLines -join "`n"))
    }
}

function Invoke-GitCommit {
    param($MsgParts)

    if ($MsgParts -is [string]) {
        Invoke-Git commit -m $MsgParts
    } elseif ($MsgParts -is [array]) {
        if ($MsgParts.Count -ge 2) {
            Invoke-Git commit -m ([string]$MsgParts[0]) -m ([string]$MsgParts[1])
        } elseif ($MsgParts.Count -eq 1) {
            Invoke-Git commit -m ([string]$MsgParts[0])
        }
    } else {
        Invoke-Git commit -m ([string]$MsgParts)
    }
}

function Edit-CommitMessage {
    param([string]$Hash, [bool]$IsHead)

    if ($IsHead) {
        Clear-Screen
        Write-Host "=== 修改最新提交訊息 ($Hash) ===" -ForegroundColor Cyan
        Write-Host ''
        $currTitle = (git log -1 --format=%s $Hash)
        $currBody = (git log -1 --format=%b $Hash).Trim()

        Write-Host "目前標題：$currTitle" -ForegroundColor DarkGray
        if ($currBody) {
            Write-Host "目前內容：`n$currBody" -ForegroundColor DarkGray
        }
        Write-Host ''
        Write-Host '選擇修改方式：' -ForegroundColor Cyan
        Write-Host '   [1] 終端機直接輸入新標題與詳細內容'
        Write-Host '   [2] 開啟記事本 (Notepad) 載入現有內容並編輯'
        Write-Host '   [Enter] 取消'
        Write-Host ''
        $mMode = Read-Host '請選擇'
        $mMode = $mMode.Trim()

        if ($mMode -eq '2') {
            $tempFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "GIT_COMMIT_EDITMSG_$([System.Guid]::NewGuid().ToString('N')).txt")
            try {
                $initialText = if ($currBody) { "$currTitle`n`n$currBody" } else { $currTitle }
                $template = @"
$initialText

# 已帶入該筆記錄的commit。
# 修改後關閉記事本並選擇儲存，即可修改該筆記錄的提交訊息。
# 第一行為「標題」，空一行後為「詳細內容」。
# 以 '#' 開頭的行是註解，會被自動忽略，空白檔案將取消修改。
"@
                [System.IO.File]::WriteAllText($tempFile, $template, [System.Text.Encoding]::UTF8)
                $origTime = (Get-Item -LiteralPath $tempFile).LastWriteTimeUtc
                Start-Process notepad.exe -ArgumentList $tempFile
                Write-Host ''
                Write-Host '  已為您開啟記事本 (Notepad)。' -ForegroundColor Cyan
                Write-Host '  請在記事本中修改訊息，儲存後關閉記事本，然後回到此視窗。' -ForegroundColor DarkGray
                Write-Host ''
                $ans = Read-Host '儲存完畢請按 Enter 繼續（輸入 Q 取消）'
                if ($ans.Trim().ToUpper() -eq 'Q') {
                    Write-Host '已取消。' -ForegroundColor DarkGray
                    return
                }

                if (Test-Path -LiteralPath $tempFile) {
                    $newTime = (Get-Item -LiteralPath $tempFile).LastWriteTimeUtc
                    $rawLines = [System.IO.File]::ReadAllLines($tempFile, [System.Text.Encoding]::UTF8)
                    $contentLines = @($rawLines | Where-Object { $_ -notmatch '^\s*#' })
                    $fullText = ($contentLines -join "`n").Trim()

                    if ($origTime -eq $newTime -or $fullText -eq $initialText.Trim()) {
                        Write-Host ''
                        Write-Host '未偵測到儲存變更，已取消更新。' -ForegroundColor DarkGray
                        return
                    }

                    if ([string]::IsNullOrWhiteSpace($fullText)) {
                        Write-Host ''
                        Write-Host '已取消，內容為空。' -ForegroundColor DarkGray
                        return
                    }

                    Write-Host ''
                    Invoke-Git commit --amend -m $fullText
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host ''
                        Write-Host '已成功更新提交訊息！' -ForegroundColor Green
                    }
                }
            } finally {
                if (Test-Path -LiteralPath $tempFile) { Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue }
            }
        } elseif ($mMode -eq '1') {
            Write-Host ''
            $newTitleInput = Read-Host "新標題（直接按 Enter 保留原標題，輸入 Q 取消）"
            if ($newTitleInput.Trim().ToUpper() -eq 'Q') {
                Write-Host '已取消。' -ForegroundColor DarkGray
                return
            }
            $newTitle = if ([string]::IsNullOrWhiteSpace($newTitleInput)) { $currTitle } else { $newTitleInput.Trim() }

            Write-Host ''
            Write-Host '詳細內容修改方式：' -ForegroundColor Cyan
            Write-Host '   [Enter] 保留原詳細內容'
            Write-Host '   [C]     清空詳細內容（不使用詳細說明）'
            Write-Host '   [N]     重新逐行輸入新詳細內容'
            Write-Host '   [Q]     取消全部修改'
            Write-Host ''
            $bChoice = Read-Host '請選擇詳細內容處理方式'
            $bChoice = $bChoice.Trim().ToUpper()

            $newBody = $currBody
            if ($bChoice -eq 'Q') {
                Write-Host '已取消。' -ForegroundColor DarkGray
                return
            } elseif ($bChoice -eq 'C') {
                $newBody = ""
            } elseif ($bChoice -eq 'N') {
                Write-Host ''
                Write-Host '請逐行輸入新詳細內容（輸入空行即結束）：' -ForegroundColor DarkGray
                $bodyLines = @()
                while ($true) {
                    $line = Read-Host '  >'
                    if ([string]::IsNullOrWhiteSpace($line)) { break }
                    $bodyLines += $line
                }
                $newBody = ($bodyLines -join "`n").Trim()
            } else {
                Write-Host '已保留原詳細內容。' -ForegroundColor DarkGray
                $newBody = $currBody
            }

            if ($newTitle -eq $currTitle -and $newBody -eq $currBody) {
                Write-Host ''
                Write-Host '內容與原本相同，未做任何修改。' -ForegroundColor DarkGray
                return
            }

            Write-Host ''
            Write-Host ('-' * 40) -ForegroundColor DarkGray
            Write-Host '【修改預覽】' -ForegroundColor Cyan
            Write-Host "標題：$newTitle"
            if ($newBody) {
                Write-Host "詳細內容：`n$newBody"
            } else {
                Write-Host "詳細內容：（無 / 已清空）" -ForegroundColor DarkGray
            }
            Write-Host ('-' * 40) -ForegroundColor DarkGray
            $confirm = Read-Host '確定要套用此修改嗎？(Y/N，預設 N 取消)'
            if ($confirm.Trim().ToUpper() -ne 'Y') {
                Write-Host '已取消更新。' -ForegroundColor DarkGray
                return
            }

            Write-Host ''
            if ([string]::IsNullOrWhiteSpace($newBody)) {
                Invoke-Git commit --amend -m $newTitle
            } else {
                Invoke-Git commit --amend -m $newTitle -m $newBody
            }
            if ($LASTEXITCODE -eq 0) {
                Write-Host ''
                Write-Host '已成功更新提交訊息！' -ForegroundColor Green
            }
        } else {
            Write-Host '已取消，沒有做任何變更。' -ForegroundColor DarkGray
        }
    } else {
        Clear-Screen
        Write-Host "=== 修改歷史提交訊息 ($Hash) ===" -ForegroundColor Cyan
        Write-Host ''
        Write-Host '注意：此筆為前幾筆歷史提交（非最新一筆）。' -ForegroundColor Yellow
        Write-Host "將使用 Git 互動式變基 (rebase -i $Hash~1) 進行修改。" -ForegroundColor DarkGray
        Write-Host '在開啟的編輯器中，將該筆提交前方的 "pick" 改為 "reword" 或 "r"，存檔關閉後即可修改該筆訊息。' -ForegroundColor DarkGray
        Write-Host ''
        $confirm = Read-Host '是否繼續執行 rebase？(Y/N)'
        if ($confirm.Trim().ToUpper() -eq 'Y') {
            Write-Host ''
            Invoke-Git rebase -i "$Hash~1"
        } else {
            Write-Host '已取消。' -ForegroundColor DarkGray
        }
    }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host ''
    Write-Host '  找不到 git，請先安裝 Git for Windows。' -ForegroundColor Red
    Write-Host ''
    Read-Host '按 Enter 離開' | Out-Null
    exit 1
}

git rev-parse --is-inside-work-tree 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host ''
    Write-Host "  這個資料夾不是 git 專案：$PSScriptRoot" -ForegroundColor Red
    Write-Host '  請把這兩個檔案放進你的專案資料夾再執行。' -ForegroundColor DarkGray
    Write-Host ''
    Read-Host '按 Enter 離開' | Out-Null
    exit 1
}

# 切到專案根目錄，讓 status 顯示的路徑一致，不受這兩個檔案放在哪一層影響
Set-Location -LiteralPath (git rev-parse --show-toplevel)

while ($true) {
    Clear-Screen
    $branch = (git rev-parse --abbrev-ref HEAD 2>$null)
    $root = (git rev-parse --show-toplevel 2>$null)

    Write-Host ('=' * 60) -ForegroundColor DarkGray
    Write-Host '  Git 常用指令選單' -ForegroundColor Cyan
    Write-Host ('=' * 60) -ForegroundColor DarkGray
    Write-Host "  專案：$root"
    Write-Host "  分支：$branch"
    Write-Host ('-' * 60) -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '   [1] 看目前狀態      哪些檔案改了、哪些還沒提交'
    Write-Host '   [2] 看改了什麼      逐行比對修改內容'
    Write-Host '   [3] 提交變更        把所有修改存成一個版本'
    Write-Host '   [4] 推送到 GitHub   把本機的提交上傳'
    Write-Host '   [5] 提交並推送      3 + 4 一次做完' -ForegroundColor Green
    Write-Host ''
    Write-Host '   [A] 追加合併至上版  把目前修改追加進最後一筆 commit'
    Write-Host '   [U] 撤銷提交(保留)  把 commit 退回成修改中狀態'
    Write-Host ''
    Write-Host '   [6] 從遠端拉取      把 GitHub 上的更新抓下來'
    Write-Host '   [7] 看歷史紀錄      瀏覽最近提交、看詳細說明與改動'
    Write-Host '   [8] 還原單一檔案    放棄某個檔案的修改'
    Write-Host '   [9] 捨棄所有修改    危險，需打字確認' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '   [V] 切換版本        把檔案換成某個舊版本的樣子，可以再換回來' -ForegroundColor Green
    Write-Host '   [H] 開啟說明頁      [0] 離開'
    Write-Host ''
    $choice = Read-Host '請選擇'

    switch ($choice.Trim().ToUpper()) {

        '1' {
            Clear-Screen
            Write-Host '=== 目前狀態 ===' -ForegroundColor Cyan
            Write-Host ''
            Invoke-Git status -sb
            Write-Host ''
            Write-Host '說明： M=已修改   A=新增   D=已刪除   ??=git 還沒追蹤的新檔案' -ForegroundColor DarkGray
            Pause-Back
        }

        '2' {
            Clear-Screen
            Write-Host '=== 改了什麼 ===' -ForegroundColor Cyan
            Write-Host ''
            Invoke-Git diff --stat
            Write-Host ''
            Write-Host '接著顯示逐行內容，畫面停住時按空白鍵翻頁、按 q 離開。' -ForegroundColor DarkGray
            Read-Host '按 Enter 繼續' | Out-Null
            Invoke-Git diff
            Pause-Back
        }

        '3' {
            Clear-Screen
            Write-Host '=== 提交變更 ===' -ForegroundColor Cyan
            Write-Host ''

            $status = @(git status --porcelain 2>$null)
            if ($status.Count -eq 0) {
                Invoke-Git status -sb
                Write-Host ''
                Write-Host '目前工作區乾淨，沒有任何需要提交的新變更。' -ForegroundColor Yellow
                Write-Host ''

                $lastHash = (git log -1 --format='%h' 2>$null)
                $lastTitle = (git log -1 --format='%s' 2>$null)

                if (-not [string]::IsNullOrWhiteSpace($lastHash)) {
                    $unpushedList = @(Get-UnpushedCommits -Format '%h')
                    $isUnpushed = $unpushedList -contains $lastHash

                    if ($isUnpushed) {
                        Write-Host "最後一筆提交：[$lastHash] $lastTitle (尚未推送)" -ForegroundColor Cyan
                        Write-Host ''
                        $ask = Read-Host '是否要改為「修改此筆提交訊息」(amend)？(Y/N)'
                        if ($ask.Trim().ToUpper() -eq 'Y') {
                            Edit-CommitMessage -Hash $lastHash -IsHead $true
                        }
                    } else {
                        Write-Host "最後一筆提交：[$lastHash] $lastTitle (已推送至 GitHub)" -ForegroundColor Cyan
                        Write-Host '注意：此筆已推送到 GitHub，修改後需要強制推送 (force push)，不建議修改。' -ForegroundColor DarkGray
                        Write-Host ''
                        $ask = Read-Host '是否仍要修改此筆提交訊息？(Y/N)'
                        if ($ask.Trim().ToUpper() -eq 'Y') {
                            Edit-CommitMessage -Hash $lastHash -IsHead $true
                        }
                    }
                }
            } else {
                Invoke-Git status -sb
                Write-Host ''
                $msg = Get-CommitMessage
                if ($null -ne $msg) {
                    Write-Host ''
                    Invoke-Git add -A
                    Invoke-GitCommit $msg
                }
            }
            Pause-Back
        }

        '4' {
            Clear-Screen
            Write-Host '=== 推送到 GitHub ===' -ForegroundColor Cyan
            Write-Host ''

            $unpushed = @(Get-UnpushedCommits)

            if ($unpushed.Count -eq 0) {
                Write-Host '目前沒有任何尚未推送到遠端的提交（本機與遠端已同步）。' -ForegroundColor DarkGray
            } else {
                Write-Host "即將推送以下 $($unpushed.Count) 筆提交至遠端：" -ForegroundColor Cyan
                Write-Host ''
                for ($i = 0; $i -lt $unpushed.Count; $i++) {
                    $p = $unpushed[$i] -split '\|', 3
                    Write-Host ('{0,5}  {1}  {2}  {3}' -f "[$($i + 1)]", $p[0], $p[1], $p[2]) -ForegroundColor Yellow
                }
                Write-Host ''
                $confirm = Read-Host '確定要推送到 GitHub 嗎？(Y/N)'
                if ($confirm.Trim().ToUpper() -eq 'Y') {
                    Write-Host ''
                    Invoke-Git push
                } else {
                    Write-Host ''
                    Write-Host '已取消，未推送。' -ForegroundColor DarkGray
                }
            }
            Pause-Back
        }

        '5' {
            Clear-Screen
            Write-Host '=== 提交並推送 ===' -ForegroundColor Cyan
            Write-Host ''

            $status = @(git status --porcelain 2>$null)
            if ($status.Count -eq 0) {
                Invoke-Git status -sb
                Write-Host ''
                Write-Host '目前工作區乾淨，沒有任何需要提交的新變更。' -ForegroundColor Yellow
                Write-Host ''

                $unpushed = @(Get-UnpushedCommits)

                if ($unpushed.Count -gt 0) {
                    Write-Host "偵測到有 $($unpushed.Count) 筆已提交但尚未推送的記錄：" -ForegroundColor Cyan
                    Write-Host ''
                    for ($i = 0; $i -lt $unpushed.Count; $i++) {
                        $p = $unpushed[$i] -split '\|', 3
                        Write-Host ('{0,5}  {1}  {2}  {3}' -f "[$($i + 1)]", $p[0], $p[1], $p[2]) -ForegroundColor Yellow
                    }
                    Write-Host ''
                    $ask = Read-Host '是否要直接推送到 GitHub？(Y/N)'
                    if ($ask.Trim().ToUpper() -eq 'Y') {
                        Write-Host ''
                        Invoke-Git push
                    } else {
                        Write-Host '已取消推送。' -ForegroundColor DarkGray
                    }
                }
            } else {
                Invoke-Git status -sb
                Write-Host ''
                $msg = Get-CommitMessage
                if ($null -ne $msg) {
                    Write-Host ''
                    Invoke-Git add -A
                    Invoke-GitCommit $msg
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host ''
                        Invoke-Git push
                    } else {
                        Write-Host ''
                        Write-Host '提交沒有成功，因此沒有推送。' -ForegroundColor Yellow
                    }
                }
            }
            Pause-Back
        }

        '6' {
            Clear-Screen
            Write-Host '=== 從遠端拉取 ===' -ForegroundColor Cyan
            Write-Host ''
            Invoke-Git pull
            Pause-Back
        }

        '7' {
            while ($true) {
                Clear-Screen
                Write-Host '=== 最近 20 筆提交 ===' -ForegroundColor Cyan
                Write-Host ''

                $unpushedList = @(Get-UnpushedCommits -Format '%h')

                $commits = @(Invoke-Git log -20 --format='%h|%ad|%s' --date=short)

                if ($commits.Count -eq 0) {
                    Write-Host '還沒有任何提交。' -ForegroundColor DarkGray
                    Pause-Back
                    break
                }

                for ($i = 0; $i -lt $commits.Count; $i++) {
                    $p = $commits[$i] -split '\|', 3
                    $h = $p[0]
                    $isUnpushed = $unpushedList -contains $h
                    if ($isUnpushed) {
                        Write-Host ('{0,5}  {1}  {2}  {3}  [未推送]' -f "[$($i + 1)]", $h, $p[1], $p[2]) -ForegroundColor Yellow
                    } else {
                        Write-Host ('{0,5}  {1}  {2}  {3}' -f "[$($i + 1)]", $h, $p[1], $p[2])
                    }
                }
                Write-Host ''
                Write-Host '   [編號] 查看該筆提交的詳細說明 (內文) 與改動檔案清單' -ForegroundColor Green
                Write-Host '   [F]    連續查看最近 10 筆的完整說明與內文 (git log -10)' -ForegroundColor Green
                Write-Host ''
                $pick = Read-Host '要查看哪一版（輸入編號、F，或直接按 Enter 回主選單）'
                $pick = $pick.Trim()

                if ([string]::IsNullOrWhiteSpace($pick)) {
                    break
                }

                if ($pick.ToUpper() -eq 'F') {
                    Clear-Screen
                    Write-Host '=== 最近 10 筆完整說明 ===' -ForegroundColor Cyan
                    Write-Host ''
                    Invoke-Git log -10
                    Write-Host ''
                    Write-Host ('-' * 60) -ForegroundColor DarkGray
                    Read-Host '按 Enter 返回歷史紀錄清單' | Out-Null
                } elseif ($pick -match '^\d+$' -and [int]$pick -ge 1 -and [int]$pick -le $commits.Count) {
                    $idx = [int]$pick - 1
                    $hash = ($commits[$idx] -split '\|', 3)[0]
                    $isHead = ($idx -eq 0)
                    $isUnpushed = $unpushedList -contains $hash

                    while ($true) {
                        Clear-Screen
                        Write-Host "=== 提交詳細說明與改動：$hash ===" -ForegroundColor Cyan
                        if ($isUnpushed) {
                            Write-Host '  狀態：[尚未推送到遠端]' -ForegroundColor Yellow
                        }
                        Write-Host ''
                        Invoke-Git show --stat $hash
                        Write-Host ''
                        Write-Host '   [D] 逐行比對此版本改了什麼（按空白鍵翻頁、按 q 離開）' -ForegroundColor DarkCyan
                        if ($isUnpushed) {
                            Write-Host '   [M] 修改此筆提交訊息 (Commit Message)' -ForegroundColor Green
                        }
                        Write-Host ''
                        $more = Read-Host '請選擇（D=逐行 diff' + $(if ($isUnpushed) { '，M=修改訊息' } else { '' }) + '，或按 Enter 返回歷史紀錄列表）'
                        $m = $more.Trim().ToUpper()
                        if ($m -eq 'D') {
                            Write-Host ''
                            Invoke-Git show $hash
                            Write-Host ''
                            Write-Host ('-' * 60) -ForegroundColor DarkGray
                            Read-Host '按 Enter 返回' | Out-Null
                        } elseif ($isUnpushed -and $m -eq 'M') {
                            Edit-CommitMessage -Hash $hash -IsHead $isHead
                            Write-Host ''
                            Write-Host ('-' * 60) -ForegroundColor DarkGray
                            Read-Host '按 Enter 返回歷史紀錄清單' | Out-Null
                            break
                        } else {
                            break
                        }
                    }
                }
            }
        }

        '8' {
            Clear-Screen
            Write-Host '=== 還原單一檔案 ===' -ForegroundColor Cyan
            Write-Host ''
            Invoke-Git status -s
            Write-Host ''
            Write-Host '這會把檔案還原成上次提交時的樣子，改到一半的內容會消失。' -ForegroundColor Yellow
            $f = Read-Host '要還原哪個檔案（直接按 Enter 取消）'
            if ([string]::IsNullOrWhiteSpace($f)) {
                Write-Host '已取消，沒有做任何變更。' -ForegroundColor DarkGray
            } else {
                Write-Host ''
                Invoke-Git restore '--' $f
                if ($LASTEXITCODE -eq 0) { Write-Host "已還原：$f" -ForegroundColor Green }
            }
            Pause-Back
        }

        '9' {
            Clear-Screen
            Write-Host '=== 捨棄所有未提交的修改 ===' -ForegroundColor Yellow
            Write-Host ''
            Invoke-Git status -s
            Write-Host ''
            Write-Host '以上「已追蹤檔案」的修改會全部消失，而且無法復原。' -ForegroundColor Red
            Write-Host '標示 ?? 的新檔案不受影響，會保留下來。' -ForegroundColor DarkGray
            Write-Host ''
            $ok = Read-Host '確定的話請輸入 DISCARD'
            if ($ok -ceq 'DISCARD') {
                Write-Host ''
                Invoke-Git reset --hard
            } else {
                Write-Host '已取消，沒有做任何變更。' -ForegroundColor DarkGray
            }
            Pause-Back
        }

        'A' {
            Clear-Screen
            Write-Host '=== 追加合併至上一版提交 ===' -ForegroundColor Cyan
            Write-Host ''

            $status = @(git status --porcelain 2>$null)
            if ($status.Count -eq 0) {
                Write-Host '目前工作區乾淨，沒有任何新的修改可供追加。' -ForegroundColor Yellow
                Write-Host '若只想修改提交訊息，請使用 [7] 看歷史紀錄 -> [M] 修改提交訊息。' -ForegroundColor DarkGray
                Pause-Back
                continue
            }

            $lastHash = (git log -1 --format='%h' 2>$null)
            $lastTitle = (git log -1 --format='%s' 2>$null)

            if ([string]::IsNullOrWhiteSpace($lastHash)) {
                Write-Host '目前專案還沒有任何歷史提交，無法追加。' -ForegroundColor Yellow
                Pause-Back
                continue
            }

            $unpushed = @(Get-UnpushedCommits -Format '%h')
            $isUnpushed = $unpushed -contains $lastHash

            Invoke-Git status -sb
            Write-Host ''
            Write-Host "即將把以上檔案修改「追加合併」進最後一筆提交：[$lastHash] $lastTitle" -ForegroundColor Cyan
            if (-not $isUnpushed) {
                Write-Host '警告：此提交已推送至 GitHub，追加合併後需要強制推送 (force push)，請謹慎操作。' -ForegroundColor Yellow
            }
            Write-Host ''
            Write-Host '請選擇處理方式：' -ForegroundColor Cyan
            Write-Host '   [1] 保留原提交訊息，直接合併修改 (git commit --amend --no-edit)'
            Write-Host '   [2] 合併修改並重新編輯提交訊息'
            Write-Host '   [Enter] 取消'
            Write-Host ''
            $aChoice = Read-Host '請選擇'
            $aChoice = $aChoice.Trim()

            if ($aChoice -eq '1') {
                Write-Host ''
                Invoke-Git add -A
                Invoke-Git commit --amend --no-edit
                if ($LASTEXITCODE -eq 0) {
                    Write-Host ''
                    Write-Host "已成功將修改追加合併至 [$lastHash]！" -ForegroundColor Green
                }
            } elseif ($aChoice -eq '2') {
                Write-Host ''
                Invoke-Git add -A
                Edit-CommitMessage -Hash $lastHash -IsHead $true
            } else {
                Write-Host '已取消，未做任何變更。' -ForegroundColor DarkGray
            }
            Pause-Back
        }

        'U' {
            Clear-Screen
            Write-Host '=== 撤銷提交（保留修改）===' -ForegroundColor Cyan
            Write-Host ''

            $unpushed = @(Get-UnpushedCommits)

            if ($unpushed.Count -eq 0) {
                Write-Host '目前沒有任何尚未推送到遠端的提交。' -ForegroundColor Yellow
                Write-Host '注意：若撤銷已推送到 GitHub 的提交，後續需要強制推送 (force push)，容易造成遠端衝突。' -ForegroundColor DarkGray
                Write-Host ''
                $lastHash = (git log -1 --format='%h' 2>$null)
                $lastTitle = (git log -1 --format='%s' 2>$null)
                if (-not [string]::IsNullOrWhiteSpace($lastHash)) {
                    Write-Host "最後一筆已推送提交為：[$lastHash] $lastTitle" -ForegroundColor Cyan
                    Write-Host ''
                    $ask = Read-Host '是否仍要撤銷最後 1 筆已推送提交？(確定的話請輸入 UNDO)'
                    if ($ask -ceq 'UNDO') {
                        Write-Host ''
                        Invoke-Git reset HEAD~1
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host ''
                            Write-Host '已撤銷最後 1 筆提交，所有檔案修改皆已完整保留在工作區！' -ForegroundColor Green
                        }
                    } else {
                        Write-Host '已取消，未做任何變更。' -ForegroundColor DarkGray
                    }
                }
            } else {
                Write-Host "偵測到有 $($unpushed.Count) 筆尚未推送到遠端的提交：" -ForegroundColor Cyan
                Write-Host ''
                for ($i = 0; $i -lt $unpushed.Count; $i++) {
                    $p = $unpushed[$i] -split '\|', 3
                    Write-Host ('{0,5}  {1}  {2}  {3}' -f "[$($i + 1)]", $p[0], $p[1], $p[2]) -ForegroundColor Yellow
                }
                Write-Host ''
                Write-Host '說明：撤銷後，這些提交內的檔案修改會「完整保留」在工作區，變回未提交的狀態。' -ForegroundColor DarkGray
                Write-Host ''
                Write-Host '請選擇撤銷方式：' -ForegroundColor Cyan
                Write-Host '   [1] 撤銷最後 1 筆提交 (git reset HEAD~1)'
                if ($unpushed.Count -gt 1) {
                    Write-Host "   [A] 撤銷全部 $($unpushed.Count) 筆未推送提交 (合併退回未提交修改)"
                }
                Write-Host '   [Enter] 取消'
                Write-Host ''
                $uChoice = Read-Host '請選擇'
                $uChoice = $uChoice.Trim().ToUpper()

                if ($uChoice -eq '1') {
                    Write-Host ''
                    Invoke-Git reset HEAD~1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host ''
                        Write-Host '已成功撤銷最後 1 筆提交！所有檔案修改皆已保留在工作區。' -ForegroundColor Green
                    }
                } elseif ($unpushed.Count -gt 1 -and $uChoice -eq 'A') {
                    Write-Host ''
                    if ($hasUpstream) {
                        Invoke-Git reset '@{u}'
                    } else {
                        $rootCommit = (git rev-list --max-parents=0 HEAD 2>$null)
                        Invoke-Git reset $rootCommit
                    }
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host ''
                        Write-Host "已成功撤銷全部 $($unpushed.Count) 筆提交！所有修改皆已合併保留在工作區。" -ForegroundColor Green
                    }
                } else {
                    Write-Host '已取消，未做任何變更。' -ForegroundColor DarkGray
                }
            }
            Pause-Back
        }

        'V' {
            Clear-Screen
            Write-Host '=== 切換版本 ===' -ForegroundColor Cyan
            Write-Host ''
            Write-Host '把檔案換成某個舊版本的樣子。只要現在的內容已經提交過，隨時可以再換回來。' -ForegroundColor DarkGray
            Write-Host ''

            # 未提交的修改會被 checkout 直接覆蓋，而且從來沒進過 git，reflog 也救不回來。
            # 所以先攤開來給人看，讓「取消」是一個能做的選擇。--untracked-files=no：?? 的新檔案
            # 不受影響，列出來只會讓人以為它們也有危險。
            $dirty = @(git status --porcelain --untracked-files=no)
            if ($dirty.Count -gt 0) {
                Write-Host '注意：以下修改還沒提交，切換會直接蓋掉，而且救不回來。' -ForegroundColor Yellow
                $dirty | ForEach-Object { Write-Host "     $_" -ForegroundColor Yellow }
                Write-Host '     想保留的話，先按 Enter 取消，回選單用 [3] 提交。' -ForegroundColor DarkGray
                Write-Host ''
            }

            # 命令列會顯示出來，輸出則收進變數，改印成有編號的清單讓人用選的
            $commits = @(Invoke-Git log -20 --format='%h|%ad|%s' --date=short)

            if ($commits.Count -eq 0) {
                Write-Host '還沒有任何提交。' -ForegroundColor DarkGray
            } else {
                for ($i = 0; $i -lt $commits.Count; $i++) {
                    $p = $commits[$i] -split '\|', 3
                    Write-Host ('{0,5}  {1}  {2}  {3}' -f "[$($i + 1)]", $p[0], $p[1], $p[2])
                }
                Write-Host ''
                Write-Host '   [R] 回到最新版（把所有檔案換回最後一次提交的樣子）' -ForegroundColor Green
                Write-Host ''
                $pick = Read-Host '要切換到哪一版（輸入編號、R，或直接按 Enter 取消）'
                $pick = $pick.Trim()

                if ($pick.ToUpper() -eq 'R') {
                    Write-Host ''
                    Invoke-Git checkout HEAD '--' .
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host ''
                        Write-Host '已回到最新版。' -ForegroundColor Green
                    }
                } elseif ($pick -match '^\d+$' -and
                          [int]$pick -ge 1 -and [int]$pick -le $commits.Count) {

                    $hash = ($commits[[int]$pick - 1] -split '\|', 3)[0]
                    Write-Host ''
                    $files = @(Invoke-Git diff --name-only $hash)

                    if ($files.Count -eq 0) {
                        Write-Host '這一版和目前的檔案完全相同，沒有東西要切換。' -ForegroundColor DarkGray
                    } else {
                        Write-Host ''
                        Write-Host "和 $hash 相比，以下檔案不一樣："
                        for ($i = 0; $i -lt $files.Count; $i++) {
                            Write-Host ('{0,5}  {1}' -f "[$($i + 1)]", $files[$i])
                        }
                        Write-Host ''
                        $sel = Read-Host '要換哪些檔案（A=全部，或用逗號分隔編號，Enter 取消）'

                        $targets = @()
                        if ($sel.Trim().ToUpper() -eq 'A') {
                            $targets = $files
                        } elseif (-not [string]::IsNullOrWhiteSpace($sel)) {
                            foreach ($n in ($sel -split '[,\s]+')) {
                                if ($n -match '^\d+$' -and
                                    [int]$n -ge 1 -and [int]$n -le $files.Count) {
                                    $targets += $files[[int]$n - 1]
                                }
                            }
                        }

                        if ($targets.Count -eq 0) {
                            Write-Host '已取消，沒有做任何變更。' -ForegroundColor DarkGray
                        } else {
                            Write-Host ''
                            Invoke-Git checkout $hash '--' @targets
                            if ($LASTEXITCODE -eq 0) {
                                Write-Host ''
                                Write-Host ("已把 {0} 個檔案切換到 {1}。" -f $targets.Count, $hash) -ForegroundColor Green
                                Write-Host '要換回最新版，再選一次 [V]，然後按 R。' -ForegroundColor DarkGray
                            }
                        }
                    }
                } else {
                    Write-Host '已取消，沒有做任何變更。' -ForegroundColor DarkGray
                }
            }
            Pause-Back
        }

        'H' {
            $page = Join-Path $PSScriptRoot 'git-cheatsheet.html'
            if (Test-Path -LiteralPath $page) {
                Start-Process $page
            } else {
                Write-Host ''
                Write-Host "找不到說明頁：$page" -ForegroundColor Yellow
                Pause-Back
            }
        }

        '0' { exit 0 }

        default { }
    }
}
