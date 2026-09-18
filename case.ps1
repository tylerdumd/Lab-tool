
# ============================================================
# Case File Downloader
# ============================================================
# Features:
#   - Ask for case number
#   - Ask for download URLs one at a time
#   - Enter "e" to finish entering URLs
#   - Create E:\<CaseNumber>
#   - Download all files using fileName= from URL
#   - Extract ZIP files
#   - Delete ZIP files after successful extraction
# ============================================================

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Web

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "       Case File Downloader" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------
# Ask for MCO / Topic / Case Number
# ------------------------------------------------------------

$mco = Read-Host "Enter MCO"
$topic = Read-Host "Enter Topic"
$caseNumber = Read-Host "Enter Case Number"

if (
    [string]::IsNullOrWhiteSpace($mco) -or
    [string]::IsNullOrWhiteSpace($topic) -or
    [string]::IsNullOrWhiteSpace($caseNumber)
)
{
    Write-Host "MCO, Topic, and Case Number are required." -ForegroundColor Red
    exit
}


# Remove invalid Windows folder characters
$invalidChars = [System.IO.Path]::GetInvalidFileNameChars()

foreach ($char in $invalidChars) {
    $mco        = $mco.Replace($char, "_")
    $topic      = $topic.Replace($char, "_")
    $caseNumber = $caseNumber.Replace($char, "_")
}

# Optional: replace spaces with underscores
$mco   = $mco.Trim()   -replace '\s+', '_'
$topic = $topic.Trim() -replace '\s+', '_'

# Folder format:
# MCO_Topic_CaseNumber
$folderName = "${mco}_${topic}_${caseNumber}"

# ------------------------------------------------------------
# Create Case Folder
# ------------------------------------------------------------

$caseFolder = Join-Path "E:\" $folderName

if (-not (Test-Path -LiteralPath $caseFolder)) {

    New-Item `
        -ItemType Directory `
        -Path $caseFolder | Out-Null

    Write-Host ""
    Write-Host "Created folder: $caseFolder" -ForegroundColor Green

}
else {

    Write-Host ""
    Write-Host "Folder already exists, skipping creation: $caseFolder" -ForegroundColor Yellow

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

    if ($link -eq "e" -or $link -eq "E") {
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
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

for ($i = 0; $i -lt $downloadLinks.Count; $i++) {

    $url = $downloadLinks[$i]

    Write-Host ""
    Write-Host "[$($i+1)/$($downloadLinks.Count)] Downloading:" -ForegroundColor Cyan
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

            $fileName = "download_$($i+1)"

        }


        # Decode URL encoded filename

        $fileName = [System.Uri]::UnescapeDataString($fileName)


        Write-Host "Filename detected: $fileName" -ForegroundColor Yellow


        $destination = Join-Path $caseFolder $fileName


        # Avoid overwrite

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


        # Download
        
        $ProgressPreference = 'SilentlyContinue' #increase speed
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

        # Verify that the file was actually created
        if (-not (Test-Path -LiteralPath $destination)) {
            throw "Download completed but the file was not found: $destination"
        }

        Write-Host "Downloaded successfully: $destination" -ForegroundColor Green


    }
    catch {

        Write-Host ""
        Write-Host "DOWNLOAD FAILED" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red

    }

}


# ------------------------------------------------------------
# Extract ZIP Files
# ------------------------------------------------------------

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Checking ZIP files..." -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan


$zipFiles = Get-ChildItem `
    -LiteralPath $caseFolder `
    -Filter "*.zip" `
    -File


foreach ($zipFile in $zipFiles) {

    Write-Host ""
    Write-Host "Extracting: $($zipFile.Name)" -ForegroundColor Cyan


    $extractFolder = Join-Path `
        $caseFolder `
        ([System.IO.Path]::GetFileNameWithoutExtension($zipFile.Name))


    try {

        if (-not (Test-Path -LiteralPath $extractFolder)) {

            New-Item `
                -ItemType Directory `
                -Path $extractFolder | Out-Null

        }


        Expand-Archive `
            -LiteralPath $zipFile.FullName `
            -DestinationPath $extractFolder `
            -Force


        Write-Host "Extraction completed." -ForegroundColor Green


        Remove-Item `
            -LiteralPath $zipFile.FullName `
            -Force


        Write-Host "Deleted ZIP: $($zipFile.Name)" -ForegroundColor Green


    }
    catch {

        Write-Host "Failed extracting $($zipFile.Name)" -ForegroundColor Red
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
Write-Host $caseFolder

Write-Host ""
Write-Host "Files created:"

Get-ChildItem `
    -LiteralPath $caseFolder `
    -Recurse `
    -File |
    ForEach-Object {
        Write-Host "  $($_.FullName)"
    }


Write-Host ""
Write-Host "Finished!"

Invoke-Item $caseFolder

Set-Clipboard -Value $caseFolder

