# Native PowerPoint authoring fallback for this Windows workspace, where the
# bundled Artifact Tool runtime/loader is unavailable. No substitute library is installed.
param([switch]$SkipVideo)
$ErrorActionPreference = 'Stop'
$deckRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$deckOut = Join-Path $deckRoot 'output/presentation'
$deckPrivate = Join-Path $deckRoot 'tmp/presentation'
$deckFrames = Join-Path $deckRoot 'output/demo/capture'
New-Item -ItemType Directory -Force -Path $deckOut,$deckPrivate,(Join-Path $deckPrivate 'slides'),(Join-Path $deckPrivate 'demo-slides'),(Join-Path $deckPrivate 'audio') | Out-Null
$deckData = Get-Content -LiteralPath (Join-Path $deckRoot 'docs/presentation.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$demoData = Get-Content -LiteralPath (Join-Path $deckRoot 'docs/demo-video.json') -Raw -Encoding UTF8 | ConvertFrom-Json

function OfficeColor([string]$hex) {
    return [Convert]::ToInt32($hex.Substring(0,2),16) + 256*[Convert]::ToInt32($hex.Substring(2,2),16) + 65536*[Convert]::ToInt32($hex.Substring(4,2),16)
}
$deckInk = OfficeColor '172e34'
$deckTeal = OfficeColor '14665d'
$deckDark = OfficeColor '142e33'
$deckMuted = OfficeColor '617672'
$deckPale = OfficeColor 'edf4ee'
$deckEdge = OfficeColor 'd6e2da'
$deckWhite = OfficeColor 'ffffff'

function Add-Text($slide,[string]$value,[double]$x,[double]$y,[double]$width,[double]$height,[double]$size=22,[int]$color=$deckInk,[bool]$bold=$false) {
    $shape=$slide.Shapes.AddTextbox(1,$x,$y,$width,$height)
    $shape.TextFrame.MarginLeft=0; $shape.TextFrame.MarginRight=0
    $shape.TextFrame.MarginTop=0; $shape.TextFrame.MarginBottom=0
    $shape.TextFrame.WordWrap=-1; $shape.TextFrame.AutoSize=0
    $range=$shape.TextFrame.TextRange
    $range.Text=$value
    $range.Font.Name='Arial'; $range.Font.Size=$size
    $range.Font.Color.RGB=$color
    $range.Font.Bold= $(if($bold){-1}else{0})
    $range.ParagraphFormat.SpaceAfter=10
    $range.ParagraphFormat.Bullet.Visible=0
    $shape.TextFrame2.AutoSize=0
    $shape.Left=$x; $shape.Top=$y; $shape.Width=$width; $shape.Height=$height
    return $shape
}

function Add-List($slide,$items,[double]$x,[double]$y,[double]$width,[double]$height,[double]$size=21,[int]$color=$deckInk) {
    $value=($items | ForEach-Object { [string]$_ }) -join "`r"
    return Add-Text $slide $value $x $y $width $height $size $color
}

function Add-Line($slide,$x1,$y1,$x2,$y2,[bool]$arrow=$false) {
    $shape=$slide.Shapes.AddLine($x1,$y1,$x2,$y2)
    $shape.Line.ForeColor.RGB=$deckTeal; $shape.Line.Weight=1.3
    if($arrow){$shape.Line.EndArrowheadStyle=3}
    return $shape
}

function Add-Node($slide,$value,$x,$y,$width,$height) {
    $shape=$slide.Shapes.AddShape(1,$x,$y,$width,$height)
    $shape.Fill.Solid();$shape.Fill.ForeColor.RGB=$deckWhite
    $shape.Line.ForeColor.RGB=$deckTeal;$shape.Line.Weight=1.2
    $shape.TextFrame.MarginLeft=10;$shape.TextFrame.MarginRight=10
    $shape.TextFrame.MarginTop=10;$shape.TextFrame.MarginBottom=10
    $shape.TextFrame.VerticalAnchor=3
    $shape.TextFrame.TextRange.Text=$value
    $shape.TextFrame.TextRange.Font.Name='Arial';$shape.TextFrame.TextRange.Font.Size=19
    $shape.TextFrame.TextRange.Font.Color.RGB=$deckInk
    $shape.TextFrame.TextRange.ParagraphFormat.Alignment=2
    return $shape
}

function Add-PictureFit($slide,[string]$file,$x,$y,$width,$height) {
    $image=[Drawing.Image]::FromFile($file)
    try {$ratio=[Math]::Min($width/$image.Width,$height/$image.Height);$w=$image.Width*$ratio;$h=$image.Height*$ratio}
    finally {$image.Dispose()}
    return $slide.Shapes.AddPicture($file,0,-1,$x+($width-$w)/2,$y+($height-$h)/2,$w,$h)
}

function Add-Table($slide,$data,$x=48,$y=143,$width=864,$height=302) {
    $rowCount=1+$data.rows.Count;$columnCount=$data.columns.Count
    $shape=$slide.Shapes.AddTable($rowCount,$columnCount,$x,$y,$width,$height)
    $table=$shape.Table
    for($col=1;$col -le $columnCount;$col++){
        $table.Columns.Item($col).Width=$width*[double]$data.widths[$col-1]
    }
    for($row=1;$row -le $rowCount;$row++){
        for($col=1;$col -le $columnCount;$col++){
            $cell=$table.Cell($row,$col)
            $cell.Shape.Fill.Solid();$cell.Shape.Fill.ForeColor.RGB=$(if($row -eq 1){$deckPale}else{$deckWhite})
            $cell.Shape.TextFrame.MarginLeft=10;$cell.Shape.TextFrame.MarginRight=10
            $cell.Shape.TextFrame.MarginTop=9;$cell.Shape.TextFrame.MarginBottom=8
            $range=$cell.Shape.TextFrame.TextRange
            $range.Text=$(if($row -eq 1){[string]$data.columns[$col-1]}else{[string]$data.rows[$row-2][$col-1]})
            $range.Font.Name='Arial';$range.Font.Size=$(if($row -eq 1){16}else{17})
            $range.Font.Bold=$(if($row -eq 1){-1}else{0})
            $range.Font.Color.RGB=$deckInk
            $range.ParagraphFormat.SpaceAfter=0;$range.ParagraphFormat.Bullet.Visible=0
            for($border=1;$border -le 4;$border++){$cell.Borders.Item($border).ForeColor.RGB=$deckEdge;$cell.Borders.Item($border).Weight=.5}
        }
    }
    return $shape
}

function Set-Notes($slide,[string]$value) {
    $slide.NotesPage.Shapes.Placeholders.Item(2).TextFrame.TextRange.Text=$value
}

function New-DeckSlide($presentation,[string]$title,[int]$number,[bool]$dark=$false) {
    $slide=$presentation.Slides.Add($presentation.Slides.Count+1,12)
    $slide.FollowMasterBackground=0
    $slide.Background.Fill.Solid();$slide.Background.Fill.ForeColor.RGB=$(if($dark){$deckDark}else{$deckWhite})
    $color=$(if($dark){$deckWhite}else{$deckInk})
    if($title){$null=Add-Text $slide $title 48 34 864 83 32 $color $true}
    $null=Add-Text $slide 'Safeguard' 48 509 200 16 10 $(if($dark){OfficeColor 'b9d5cd'}else{$deckMuted})
    $null=Add-Text $slide ([string]$number) 877 509 35 16 10 $(if($dark){OfficeColor 'b9d5cd'}else{$deckMuted})
    return $slide
}

function Get-WaveSeconds($path) {
    $stream=[IO.File]::OpenRead($path);$reader=[IO.BinaryReader]::new($stream)
    try {
        $null=$reader.ReadBytes(12);$byteRate=0;$dataBytes=0
        while($stream.Position+8 -le $stream.Length){
            $chunk=[Text.Encoding]::ASCII.GetString($reader.ReadBytes(4));$size=$reader.ReadUInt32();$position=$stream.Position
            if($chunk -eq 'fmt '){$null=$reader.ReadBytes(8);$byteRate=$reader.ReadUInt32()}
            if($chunk -eq 'data'){$dataBytes=$size;break}
            $stream.Position=$position+$size+($size%2)
        }
        if($byteRate -le 0){throw 'Invalid narration WAV'}
        return [double]$dataBytes/$byteRate
    }finally{$reader.Dispose();$stream.Dispose()}
}

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Speech
$slideApplication=New-Object -ComObject PowerPoint.Application
$mainDeck=$null;$demoDeck=$null
$validation=[ordered]@{fontPolicy=@{basis='design';families=@('Arial')};authoring='Native installed PowerPoint 16 document API; bundled Artifact Tool runtime unavailable';slides=@();warnings=@()}
try {
    $mainDeck=$slideApplication.Presentations.Add(0)
    $mainDeck.PageSetup.SlideWidth=960;$mainDeck.PageSetup.SlideHeight=540
    $slideIndex=0
    foreach($data in $deckData.slides){
        $slideIndex++
        $dark=$data.layout -in @('cover','closing','demo')
        $slide=New-DeckSlide $mainDeck $(if($data.layout -eq 'cover'){''}else{$data.title}) $slideIndex $dark
        switch($data.layout){
            'cover' {
                $null=Add-Text $slide 'Safeguard' 48 59 864 50 28 (OfficeColor '9ce0cc') $true
                $null=Add-Text $slide "Autosteer safeguard`r`nassurance" 48 155 864 165 57 $deckWhite $true
                $null=Add-Text $slide $data.subtitle 48 342 820 70 25 (OfficeColor 'c2ddd4')
                $null=Add-Text $slide $deckData.group 48 449 500 30 19 $deckWhite
            }
            'statement' {
                $null=Add-Text $slide $data.statement 48 139 864 146 35 $deckTeal $true
                $null=Add-List $slide $data.items 48 320 864 154 21
            }
            'table' {$null=Add-Table $slide $data}
            'comparison' {
                $null=Add-Text $slide $data.leftTitle 48 143 402 65 24 $deckTeal $true
                $null=Add-Text $slide $data.rightTitle 510 143 402 65 24 $deckTeal $true
                $null=Add-List $slide $data.left 48 223 397 242 22
                $null=Add-List $slide $data.right 510 223 397 242 22
                $null=Add-Line $slide 480 145 480 457
            }
            'architecture' {
                $null=Add-Node $slide "Browser`r`nworkspace" 48 145 180 90
                $null=Add-Node $slide "Signer service`r`nethers / Node.js" 300 145 200 90
                $null=Add-Node $slide "Solidity registry`r`nHardhat simulated EVM" 570 145 342 90
                $null=Add-Node $slide "Off-chain evidence`r`nSource files / preimages" 300 294 260 75
                $null=Add-Line $slide 228 190 300 190 $true
                $null=Add-Line $slide 500 190 570 190 $true
                $null=Add-Line $slide 400 235 400 294 $true
                $null=Add-Text $slide 'HTTP' 236 156 65 25 17 $deckMuted
                $null=Add-Text $slide 'Tx' 519 156 49 25 17 $deckMuted
                $null=Add-Text $slide 'Hash / read' 419 253 205 25 17 $deckMuted
                $null=Add-List $slide $data.items 48 400 864 94 17
            }
            'demo' {
                $null=Add-Text $slide 'Five minutes' 48 124 864 45 25 (OfficeColor '9ce0cc') $true
                $null=Add-List $slide $data.items 48 190 864 215 23 $deckWhite
                $link=Add-Text $slide 'http://127.0.0.1:4234' 48 447 550 34 21 (OfficeColor '9ce0cc')
                $link.ActionSettings.Item(1).Hyperlink.Address='http://127.0.0.1:4234'
            }
            'screenshot' {
                $null=Add-PictureFit $slide (Join-Path $deckRoot $data.image) 48 135 864 226
                $null=Add-Text $slide $data.caption 48 367 864 23 12 $deckMuted
                $null=Add-List $slide $data.items 48 405 864 93 18
            }
            'results' {
                $null=Add-Text $slide $data.metric 48 140 260 137 103 $deckTeal $true
                $null=Add-Text $slide $data.metricLabel 48 299 260 95 23 $deckInk $true
                $null=Add-List $slide $data.items 365 148 547 322 22
            }
            'closing' {
                $null=Add-Text $slide $data.statement 48 146 864 156 31 $deckWhite $true
                $null=Add-List $slide $data.items 48 339 864 139 23 (OfficeColor 'c2ddd4')
            }
            'references' {$null=Add-List $slide $data.items 48 135 864 357 18}
            default {$null=Add-List $slide $data.items 48 147 864 330 24}
        }
        if($data.sourceLabel){$null=Add-Text $slide $data.sourceLabel 48 481 864 23 9.5 $(if($dark){OfficeColor 'b9d5cd'}else{$deckMuted})}
        $timing=$(if($data.appendix){'Appendix: outside the timed presentation'}else{'Planned duration: '+$data.minutes+' minutes. Presenter: '+$data.speaker})
        Set-Notes $slide ($timing+"`r`n`r`n"+$data.notes+"`r`n`r`nSources:`r`n"+($data.sources -join "`r`n"))
        $slide.Export((Join-Path $deckPrivate ('slides/slide-'+$slideIndex.ToString('00')+'.png')),'PNG',1600,900)
        $validation.slides+=@{number=$slideIndex;title=$data.title;layout=$data.layout;nativeTable=($data.layout -eq 'table');notes=$true}
        for($shapeIndex=1;$shapeIndex -le $slide.Shapes.Count;$shapeIndex++){
            $shape=$slide.Shapes.Item($shapeIndex)
            if($shape.HasTextFrame -eq -1 -and $shape.TextFrame.HasText -eq -1){
                $bound=$shape.TextFrame2.TextRange.BoundHeight
                if($bound -gt $shape.Height+3){$validation.warnings+=('Slide '+$slideIndex+' text box height '+[Math]::Round($bound,1)+' exceeds '+[Math]::Round($shape.Height,1)+': '+$shape.TextFrame.TextRange.Text.Substring(0,[Math]::Min(70,$shape.TextFrame.TextRange.Text.Length)))}
            }
        }
    }
    $pptxPath=Join-Path $deckOut 'G21_Safeguard_Presentation.pptx'
    $mainDeck.SaveAs($pptxPath,24)
    $mainDeck.SaveAs((Join-Path $deckOut 'G21_Safeguard_Presentation.pdf'),32)
    Write-Output ('Presentation saved: '+$pptxPath)

    $demoDeck=$slideApplication.Presentations.Add(0)
    $demoDeck.PageSetup.SlideWidth=960;$demoDeck.PageSetup.SlideHeight=540
    $speech=[Speech.Synthesis.SpeechSynthesizer]::new()
    $voice=$speech.GetInstalledVoices() | Where-Object { $_.Enabled -and $_.VoiceInfo.Culture.Name -eq 'en-US' } | Select-Object -First 1
    if($voice){$speech.SelectVoice($voice.VoiceInfo.Name)}
    $speech.Rate=0
    $demoSeconds=0;$frameIndex=0
    foreach($frame in $demoData.frames){
        $frameIndex++
        $slide=New-DeckSlide $demoDeck $frame.title $frameIndex
        $null=Add-Text $slide $frame.caption 48 116 864 61 21 $deckTeal $true
        $null=Add-PictureFit $slide (Join-Path $deckFrames $frame.image) 48 189 864 278
        $null=Add-Text $slide 'Recorded workflow states using sample data and real local transactions' 48 481 864 20 10 $deckMuted
        $audioPath=Join-Path $deckPrivate ('audio/frame-'+$frameIndex.ToString('00')+'.wav')
        $speech.SetOutputToWaveFile($audioPath);$speech.Speak([string]$frame.narration);$speech.SetOutputToNull()
        $duration=[Math]::Max(11,[Math]::Ceiling((Get-WaveSeconds $audioPath)+1.5))
        $audio=$slide.Shapes.AddMediaObject2($audioPath,0,-1,932,505,8,8)
        $audio.AnimationSettings.PlaySettings.PlayOnEntry=-1
        $audio.AnimationSettings.PlaySettings.HideWhileNotPlaying=-1
        $audio.AnimationSettings.PlaySettings.StopAfterSlides=1
        $slide.SlideShowTransition.AdvanceOnTime=-1
        $slide.SlideShowTransition.AdvanceOnClick=0
        $slide.SlideShowTransition.AdvanceTime=$duration
        Set-Notes $slide $frame.narration
        $demoSeconds+=$duration
        $slide.Export((Join-Path $deckPrivate ('demo-slides/frame-'+$frameIndex.ToString('00')+'.png')),'PNG',1600,900)
    }
    $speech.Dispose()
    if($demoSeconds -gt 295){throw ('Demo exceeds five-minute limit: '+$demoSeconds+' seconds')}
    $demoPptx=Join-Path $deckOut 'Safeguard_Demo_Source.pptx'
    $demoDeck.SaveAs($demoPptx,24)
    $validation.demo=@{frames=$frameIndex;plannedSeconds=$demoSeconds;narration='Windows installed English speech voice';format='Narrated sequence of observed workflow states'}
    Write-Output ('Narrated demo duration: '+$demoSeconds+' seconds')
    if(-not $SkipVideo){
        $videoPath=Join-Path $deckRoot ('output/demo/'+$demoData.filename)
        $demoDeck.CreateVideo($videoPath,-1,12,720,24,85)
        $deadline=[DateTime]::UtcNow.AddMinutes(15)
        do {
            Start-Sleep -Seconds 10
            $videoStatus=$demoDeck.CreateVideoStatus
            Write-Output ('Video export status: '+$videoStatus)
            if([DateTime]::UtcNow -gt $deadline){throw 'Video export timed out'}
        }while($videoStatus -in @(1,2))
        if($videoStatus -ne 3){throw ('Video export failed: '+$videoStatus)}
        Write-Output ('Video saved: '+$videoPath)
    }
    [IO.File]::WriteAllText((Join-Path $deckPrivate 'validation.json'),($validation | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    Write-Output ('Text-fit warnings: '+$validation.warnings.Count)
}finally{
    if($demoDeck){$demoDeck.Close();[Runtime.InteropServices.Marshal]::ReleaseComObject($demoDeck)|Out-Null}
    if($mainDeck){$mainDeck.Close();[Runtime.InteropServices.Marshal]::ReleaseComObject($mainDeck)|Out-Null}
    $slideApplication.Quit();[Runtime.InteropServices.Marshal]::ReleaseComObject($slideApplication)|Out-Null
    [GC]::Collect();[GC]::WaitForPendingFinalizers()
}
