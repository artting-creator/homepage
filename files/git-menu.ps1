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
    Write-Host '   [6] 從遠端拉取      把 GitHub 上的更新抓下來'
    Write-Host '   [7] 看歷史紀錄      最近 20 筆提交'
    Write-Host '   [8] 還原單一檔案    放棄某個檔案的修改'
    Write-Host '   [9] 捨棄所有修改    危險，需打字確認' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '   [H] 開啟說明頁      [0] 離開'
    Write-Host ''
    $choice = Read-Host '請選擇'

    switch ($choice.Trim().ToUpper()) {

        '1' {
            Clear-Screen
            Write-Host '=== 目前狀態 ===' -ForegroundColor Cyan
            Write-Host ''
            git status -sb
            Write-Host ''
            Write-Host '說明： M=已修改   A=新增   D=已刪除   ??=git 還沒追蹤的新檔案' -ForegroundColor DarkGray
            Pause-Back
        }

        '2' {
            Clear-Screen
            Write-Host '=== 改了什麼 ===' -ForegroundColor Cyan
            Write-Host ''
            git diff --stat
            Write-Host ''
            Write-Host '接著顯示逐行內容，畫面停住時按空白鍵翻頁、按 q 離開。' -ForegroundColor DarkGray
            Read-Host '按 Enter 繼續' | Out-Null
            git diff
            Pause-Back
        }

        '3' {
            Clear-Screen
            Write-Host '=== 提交變更 ===' -ForegroundColor Cyan
            Write-Host ''
            git status -sb
            Write-Host ''
            $msg = Read-Host '提交訊息（直接按 Enter 取消）'
            if ([string]::IsNullOrWhiteSpace($msg)) {
                Write-Host '已取消，沒有做任何變更。' -ForegroundColor DarkGray
            } else {
                git add -A
                git commit -m $msg
            }
            Pause-Back
        }

        '4' {
            Clear-Screen
            Write-Host '=== 推送到 GitHub ===' -ForegroundColor Cyan
            Write-Host ''
            git push
            Pause-Back
        }

        '5' {
            Clear-Screen
            Write-Host '=== 提交並推送 ===' -ForegroundColor Cyan
            Write-Host ''
            git status -sb
            Write-Host ''
            $msg = Read-Host '提交訊息（直接按 Enter 取消）'
            if ([string]::IsNullOrWhiteSpace($msg)) {
                Write-Host '已取消，沒有做任何變更。' -ForegroundColor DarkGray
            } else {
                git add -A
                git commit -m $msg
                if ($LASTEXITCODE -eq 0) {
                    Write-Host ''
                    git push
                } else {
                    Write-Host ''
                    Write-Host '提交沒有成功，因此沒有推送。' -ForegroundColor Yellow
                }
            }
            Pause-Back
        }

        '6' {
            Clear-Screen
            Write-Host '=== 從遠端拉取 ===' -ForegroundColor Cyan
            Write-Host ''
            git pull
            Pause-Back
        }

        '7' {
            Clear-Screen
            Write-Host '=== 最近 20 筆提交 ===' -ForegroundColor Cyan
            Write-Host ''
            git log --oneline --graph --decorate -20
            Pause-Back
        }

        '8' {
            Clear-Screen
            Write-Host '=== 還原單一檔案 ===' -ForegroundColor Cyan
            Write-Host ''
            git status -s
            Write-Host ''
            Write-Host '這會把檔案還原成上次提交時的樣子，改到一半的內容會消失。' -ForegroundColor Yellow
            $f = Read-Host '要還原哪個檔案（直接按 Enter 取消）'
            if ([string]::IsNullOrWhiteSpace($f)) {
                Write-Host '已取消，沒有做任何變更。' -ForegroundColor DarkGray
            } else {
                git restore -- $f
                if ($LASTEXITCODE -eq 0) { Write-Host "已還原：$f" -ForegroundColor Green }
            }
            Pause-Back
        }

        '9' {
            Clear-Screen
            Write-Host '=== 捨棄所有未提交的修改 ===' -ForegroundColor Yellow
            Write-Host ''
            git status -s
            Write-Host ''
            Write-Host '以上「已追蹤檔案」的修改會全部消失，而且無法復原。' -ForegroundColor Red
            Write-Host '標示 ?? 的新檔案不受影響，會保留下來。' -ForegroundColor DarkGray
            Write-Host ''
            $ok = Read-Host '確定的話請輸入 DISCARD'
            if ($ok -ceq 'DISCARD') {
                git reset --hard
            } else {
                Write-Host '已取消，沒有做任何變更。' -ForegroundColor DarkGray
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
