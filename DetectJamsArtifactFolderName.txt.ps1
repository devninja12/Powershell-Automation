# Base artifact path - starting point to search
$artifactRoot = "$(System.DefaultWorkingDirectory)\_codetolab (1)"

# Folder names to look for in priority order
$possibleFolders = @("jams", "jams-xml")

# Initialize variables
$foundFolder = $null
$foundFolderPath = $null

foreach ($folderName in $possibleFolders) {
    # Recursively search for a directory matching folderName anywhere under artifactRoot
    $foundPath = Get-ChildItem -Path $artifactRoot -Directory -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ieq $folderName } | Select-Object -First 1

    if ($foundPath) {
        $foundFolder = $folderName
        $foundFolderPath = $foundPath.FullName
        Write-Host "✅ Found folder '$foundFolder' at path: $foundFolderPath"
        break
    }
}

if (-not $foundFolder) {
    Write-Error "❌ Neither 'jams' nor 'jams-xml' folder found under $artifactRoot"
    exit 1
}

# Set variables for later tasks
Write-Host "📦 Setting jamsArtifactFolder = $foundFolder"
Write-Host "##vso[task.setvariable variable=jamsArtifactFolder;]$foundFolder"

Write-Host "📦 Setting jamsfolderpath = $foundFolderPath"
Write-Host "##vso[task.setvariable variable=jamsfolderpath;]$foundFolderPath"