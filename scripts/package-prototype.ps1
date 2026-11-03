# Package an explicit allowlist; never include dependencies, credentials or Git state.
$ErrorActionPreference = 'Stop'
$prototypeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$prototypeOutput = Join-Path $prototypeRoot 'output'
$prototypeArchive = Join-Path $prototypeOutput 'Safeguard_Prototype.zip'
$prototypeSources = @('contracts', 'test', 'ignition', 'scripts', 'web', 'data', 'docs', '.vscode',
    'hardhat.config.ts', 'package.json', 'package-lock.json', 'tsconfig.json', 'README.md', 'AGENTS.md', '.gitignore')
$prototypeDeliverables = @('output/pdf', 'output/demo', 'output/validation',
    'output/presentation/G21_Safeguard_Presentation.pptx',
    'output/presentation/G21_Safeguard_Presentation.pdf',
    'output/presentation/Safeguard_Speaker_Notes.json')
New-Item -ItemType Directory -Force -Path (Join-Path $prototypeOutput 'validation') | Out-Null

function Get-PrototypeFiles($entries) {
    foreach ($entry in $entries) {
        $target = Join-Path $prototypeRoot $entry
        if (-not (Test-Path -LiteralPath $target)) { continue }
        $item = Get-Item -LiteralPath $target -Force
        if ($item.PSIsContainer) { Get-ChildItem -LiteralPath $target -File -Recurse -Force }
        else { $item }
    }
}

$prototypeManifest = @(Get-PrototypeFiles $prototypeSources | Sort-Object FullName | ForEach-Object {
    [ordered]@{
        path = $_.FullName.Substring($prototypeRoot.Length + 1).Replace('\', '/')
        sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
})
$prototypeBuild = [ordered]@{
    product = 'Safeguard'
    version = '1.0.0'
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    validation = '56 passing tests; build, TypeScript, scripted workflow, fingerprints and browser role views checked'
    files = $prototypeManifest
}
$prototypeManifestPath = Join-Path $prototypeOutput 'validation/build-manifest.json'
[IO.File]::WriteAllText($prototypeManifestPath, ($prototypeBuild | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$prototypeStream = [IO.File]::Open($prototypeArchive, [IO.FileMode]::Create)
$prototypeZip = [IO.Compression.ZipArchive]::new($prototypeStream, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in (Get-PrototypeFiles ($prototypeSources + $prototypeDeliverables) | Sort-Object FullName -Unique)) {
        $entryName = $file.FullName.Substring($prototypeRoot.Length + 1).Replace('\', '/')
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($prototypeZip, $file.FullName, $entryName, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally {
    $prototypeZip.Dispose()
    $prototypeStream.Dispose()
}
Get-Item -LiteralPath $prototypeArchive | Select-Object FullName, Length

# Submission naming follows the supplied specification. The hosted link is still
# an outstanding requirement recorded in the guide and presenter reference.
$prototypeGuide = Join-Path $prototypeOutput 'G21_Demonstrator_Guide.pdf'
[IO.File]::Copy((Join-Path $prototypeOutput 'pdf/Safeguard_User_Guide.pdf'), $prototypeGuide, $true)
$submissionArchive = Join-Path $prototypeOutput 'G21_Technology_Demonstrator.zip'
$submissionStream = [IO.File]::Open($submissionArchive, [IO.FileMode]::Create)
$submissionZip = [IO.Compression.ZipArchive]::new($submissionStream, [IO.Compression.ZipArchiveMode]::Create)
try {
    $submissionFiles = @(
        @($prototypeGuide, 'G21_Demonstrator_Guide.pdf'),
        @((Join-Path $prototypeOutput 'demo/G21_Demonstrator_Demo.mp4'), 'G21_Demonstrator_Demo.mp4'),
        @($prototypeArchive, 'Supporting/Safeguard_Prototype.zip')
    )
    foreach ($entry in $submissionFiles) {
        if (Test-Path -LiteralPath $entry[0]) {
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($submissionZip, $entry[0], $entry[1], [IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    }
} finally {
    $submissionZip.Dispose(); $submissionStream.Dispose()
}
Get-Item -LiteralPath $submissionArchive | Select-Object FullName, Length
