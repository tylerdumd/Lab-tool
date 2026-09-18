# ============================================================
# Case File Downloader
# ============================================================
# Features:
#   - Ask for case number first
#   - Search E:\ for an existing case folder
#   - Reuse an existing folder when found
#   - Ask for MCO and Topic only for a new case
#   - Ask for download URLs one at a time
#   - Enter "e" to finish entering URLs
#   - Download all files using fileName= from URL
#   - Extract ZIP files
#   - Delete ZIP files after successful extraction
# ============================================================

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

Add-Type -AssemblyName System.Web

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "       Case File Downloader" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

$caseRootFolder = "E:\"

if (-not (Test-Path -LiteralPath $caseRootFolder -PathType Container)) {
    Write-Host "The case root folder does not exist: $caseRootFolder" -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------------
# Ask for Case Number First
# ------------------------------------------------------------

$caseNumber = Read-Host "Enter Case Number"

if ([string]::IsNullOrWhiteSpace($caseNumber)) {
    Write-Host "Case Number is required." -ForegroundColor Red
    exit 1
}

$caseNumber = $caseNumber.Trim()

# Remove invalid Windows folder characters from the case number
$invalidChars = [System.IO.Path]::GetInvalidFileNameChars()

foreach ($char in $invalidChars) {
    $caseNumber = $caseNumber.Replace($char, "_")
}

# Escape wildcard characters so that case numbers containing
# [, ], *, or ? are treated as literal characters.
$escapedCaseNumber = [WildcardPattern]::Escape($caseNumber)

# ------------------------------------------------------------
# Search for Existing Case Folder
# ------------------------------------------------------------
# Supported existing folder formats:
#
#   E:\CaseNumber
#   E:\MCO_Topic_CaseNumber
#
# The comparison is case-insensitive.
# ------------------------------------------------------------

Write-Host ""
Write-Host "Checking for an existing folder for case: $caseNumber" -ForegroundColor Cyan

$existingCaseFolders = @(
    Get-ChildItem `
        -LiteralPath $caseRootFolder `
        -Directory `
        -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -ieq $caseNumber -or
        $_.Name -ilike "*_$escapedCaseNumber"
    }
)

$caseFolder = $null

if ($existingCaseFolders.Count -eq 1) {

    # Exactly one existing folder was found
    $caseFolder = $existingCaseFolders[0].FullName

    Write-Host ""
    Write-Host "Existing case folder found." -ForegroundColor Green
    Write-Host "Folder creation will be skipped." -ForegroundColor Yellow
    Write-Host "Using folder: $caseFolder" -ForegroundColor Green
}
elseif ($existingCaseFolders.Count -gt 1) {

    # Multiple matching folders were found
    Write-Host ""
    Write-Host "Multiple folders were found for case $caseNumber." -ForegroundColor Yellow
    Write-Host "Select the folder you want to use:" -ForegroundColor Cyan
    Write-Host ""

    for ($i = 0; $i -lt $existingCaseFolders.Count; $i++) {
        Write-Host "[$($i + 1)] $($existingCaseFolders[$i].FullName)"
    }

    Write-Host ""

    while ($true) {

        $selection = Read-Host "Enter folder number"

        $selectedNumber = 0
        $validNumber = [int]::TryParse($selection, [ref]$selectedNumber)

        if (
            $validNumber -and
            $selectedNumber -ge 1 -and
            $selectedNumber -le $existingCaseFolders.Count
        ) {
            $caseFolder = $existingCaseFolders[$selectedNumber - 1].FullName
            break
        }

        Write-Host "Enter a number between 1 and $($existingCaseFolders.Count)." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Folder creation will be skipped." -ForegroundColor Yellow
    Write-Host "Using folder: $caseFolder" -ForegroundColor Green
}
else {

    # --------------------------------------------------------
    # No Existing Folder Found
    # Ask for MCO and Topic, then create a new folder
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "No existing folder was found for case $caseNumber." -ForegroundColor Yellow
    Write-Host "MCO and Topic are required to create a new folder." -ForegroundColor Cyan
    Write-Host ""

    $mco = Read-Host "Enter MCO"
    $topic = Read-Host "Enter Topic"

    if (
        [string]::IsNullOrWhiteSpace($mco) -or
        [string]::IsNullOrWhiteSpace($topic)
    ) {
        Write-Host "MCO and Topic are required for a new case folder." -ForegroundColor Red
        exit 1
    }

    $mco = $mco.Trim()
    $topic = $topic.Trim()

    # Remove invalid Windows folder characters
    foreach ($char in $invalidChars) {
        $mco = $mco.Replace($char, "_")
        $topic = $topic.Replace($char, "_")
    }

    # Replace one or more spaces with underscores
    $mco = $mco -replace '\s+', '_'
    $topic = $topic -replace '\s+', '_'

    # Folder format:
    # MCO_Topic_CaseNumber
    $folderName = "${mco}_${topic}_${caseNumber}"
    $caseFolder = Join-Path $caseRootFolder $folderName

    New-Item `
        -ItemType Directory `
        -Path $caseFolder `
        -Force |
    Out-Null

    Write-Host ""
    Write-Host "Created folder: $caseFolder" -ForegroundColor Green
}

# Final folder validation
if (-not (Test-Path -LiteralPath $caseFolder -PathType Container)) {
    Write-Host "The selected case folder is not available: $caseFolder" -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------------
# Collect Download Links
# ------------------------------------------------------------

$downloadLinks = @()

Write-Host ""
Write-Host "Enter download links one at a time." -ForegroundColor Cyan
Write-Host "Press Enter after each link." -ForegroundColor Cyan
Write-Host "Type 'e' and press Enter when finished." -ForegroundColor Yellow
Write-Host ""

while ($true) {

    $link = Read-Host "Download link"

    if ($link -ieq "e") {
        break
    }

    if ([string]::IsNullOrWhiteSpace($link)) {
        Write-Host "Empty input. Enter a URL or type e." -ForegroundColor Yellow
        continue
    }

    $downloadLinks += $link.Trim()
    Write-Host "Link added." -ForegroundColor Green
}

if ($downloadLinks.Count -eq 0) {
    Write-Host "No links entered." -ForegroundColor Yellow
    exit
}

# ------------------------------------------------------------
# Download Files
# ------------------------------------------------------------

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Starting downloads..." -ForegroundColor Cyan
Write-Host "Total files: $($downloadLinks.Count)" -ForegroundColor Cyan
Write-Host "Case folder: $caseFolder" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

for ($i = 0; $i -lt $downloadLinks.Count; $i++) {

    $url = $downloadLinks[$i]

    Write-Host ""
    Write-Host "[$($i + 1)/$($downloadLinks.Count)] Downloading:" -ForegroundColor Cyan
    Write-Host $url -ForegroundColor Gray

    try {

        $uri = [System.Uri]$url

        # ----------------------------------------------------
        # Get filename from fileName= parameter
        # ----------------------------------------------------

        $fileName = $null

        try {
            $query = [System.Web.HttpUtility]::ParseQueryString($uri.Query)
            $fileName = $query["fileName"]
        }
        catch {
            $fileName = $null
        }

        # Fallback if fileName= is missing
        if ([string]::IsNullOrWhiteSpace($fileName)) {
            $fileName = [System.IO.Path]::GetFileName($uri.AbsolutePath)
        }

        # Final fallback
        if ([string]::IsNullOrWhiteSpace($fileName)) {
            $fileName = "download_$($i + 1)"
        }

        # Decode URL-encoded filename
        $fileName = [System.Uri]::UnescapeDataString($fileName)

        # Remove invalid filename characters
        foreach ($char in $invalidChars) {
            $fileName = $fileName.Replace($char, "_")
        }

        Write-Host "Filename detected: $fileName" -ForegroundColor Yellow

        $destination = Join-Path $caseFolder $fileName

        # Avoid overwriting an existing file
        if (Test-Path -LiteralPath $destination) {

            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
            $extension = [System.IO.Path]::GetExtension($fileName)
            $count = 1

            do {
                $newName = "$baseName`_$count$extension"
                $destination = Join-Path $caseFolder $newName
                $count++
            }
            while (Test-Path -LiteralPath $destination)
        }

        # Download using curl.exe
        Write-Host "Downloading to: $destination" -ForegroundColor Cyan

        & curl.exe `
            --fail `
            --location `
            --silent `
            --show-error `
            --output "$destination" `
            "$url"

        if ($LASTEXITCODE -ne 0) {
            throw "curl.exe failed with exit code $LASTEXITCODE"
        }

        # Verify that the file was created
        if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
            throw "Download completed but the file was not found: $destination"
        }

        Write-Host "Downloaded successfully: $destination" -ForegroundColor Green
    }
    catch {

        Write-Host ""
        Write-Host "DOWNLOAD FAILED" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red

        # Remove an incomplete file if curl created one
        if (
            $null -ne $destination -and
            (Test-Path -LiteralPath $destination -PathType Leaf)
        ) {
            Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
            Write-Host "Removed incomplete file: $destination" -ForegroundColor Yellow
        }
    }
}

# ------------------------------------------------------------
# Extract ZIP Files
# ------------------------------------------------------------

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Checking ZIP files..." -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

$zipFiles = @(
    Get-ChildItem `
        -LiteralPath $caseFolder `
        -Filter "*.zip" `
        -File `
        -ErrorAction SilentlyContinue
)

if ($zipFiles.Count -eq 0) {
    Write-Host "No ZIP files found." -ForegroundColor Yellow
}

foreach ($zipFile in $zipFiles) {

    Write-Host ""
    Write-Host "Extracting: $($zipFile.Name)" -ForegroundColor Cyan

    $extractFolderName = [System.IO.Path]::GetFileNameWithoutExtension($zipFile.Name)
    $extractFolder = Join-Path $caseFolder $extractFolderName

    try {

        if (-not (Test-Path -LiteralPath $extractFolder)) {
            New-Item `
                -ItemType Directory `
                -Path $extractFolder |
            Out-Null
        }

        Expand-Archive `
            -LiteralPath $zipFile.FullName `
            -DestinationPath $extractFolder `
            -Force

        Write-Host "Extraction completed: $extractFolder" -ForegroundColor Green

        Remove-Item `
            -LiteralPath $zipFile.FullName `
            -Force

        Write-Host "Deleted ZIP: $($zipFile.Name)" -ForegroundColor Green
    }
    catch {

        Write-Host "Failed extracting $($zipFile.Name)" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host "ZIP kept for manual recovery." -ForegroundColor Yellow
    }
}

# ------------------------------------------------------------
# Finished
# ------------------------------------------------------------

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "              COMPLETED" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green

Write-Host ""
Write-Host "Case Folder:"
Write-Host $caseFolder -ForegroundColor Cyan

Write-Host ""
Write-Host "Files currently in the case folder:"

Get-ChildItem `
    -LiteralPath $caseFolder `
    -Recurse `
    -File `
    -ErrorAction SilentlyContinue |
ForEach-Object {
    Write-Host "  $($_.FullName)"
}

Write-Host ""
Write-Host "Finished!" -ForegroundColor Green

Set-Clipboard -Value $caseFolder
Invoke-Item -LiteralPath $caseFolder