$ErrorActionPreference='Stop'
$notesRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$notesFile=Join-Path $notesRoot 'output/presentation/Safeguard_Speaker_Notes.json'
$notesData=Get-Content -LiteralPath $notesFile -Raw -Encoding UTF8 | ConvertFrom-Json
$notesApp=New-Object -ComObject PowerPoint.Application
$notesDeck=$null
try {
    $notesDeck=$notesApp.Presentations.Open((Join-Path $notesRoot 'output/presentation/G21_Safeguard_Presentation.pptx'),0,0,0)
    if($notesDeck.Slides.Count -ne $notesData.Count){throw 'Slide count differs from script count'}
    foreach($note in $notesData){$notesDeck.Slides.Item([int]$note.index).NotesPage.Shapes.Placeholders.Item(2).TextFrame.TextRange.Text=[string]$note.text}
    $notesDeck.Save()
    Write-Output ('Updated speaker scripts on '+$notesData.Count+' PowerPoint slides')
}finally{
    if($notesDeck){$notesDeck.Close();[Runtime.InteropServices.Marshal]::ReleaseComObject($notesDeck)|Out-Null}
    $notesApp.Quit();[Runtime.InteropServices.Marshal]::ReleaseComObject($notesApp)|Out-Null
    [GC]::Collect();[GC]::WaitForPendingFinalizers()
}
