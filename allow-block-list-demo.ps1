<#
.SYNOPSIS
Creates or deletes dummy Tenant Allow/Block List entries.

.DESCRIPTION
Generates deterministic domains under the reserved .invalid TLD and manages
them through Exchange Online PowerShell.

Examples of generated domains:
  m365-tabl-sender-allow-000001.invalid
  m365-tabl-sender-block-000001.invalid
  m365-tabl-url-block-000001.invalid

The deterministic naming makes it possible to remove exactly the entries
created by this script.

.PARAMETER Operation
Add or Delete.

.PARAMETER EntryAction
Allow or Block.

.PARAMETER ListType
Sender for the Domains & addresses list.
Url for the URL list.

.PARAMETER Count
Number of entries to generate.

.PARAMETER StartIndex
First numeric suffix. Useful for adding entries in multiple runs.

.PARAMETER Prefix
Prefix used for generated entries.

.PARAMETER BatchSize
Number of entries processed in each command.

.PARAMETER RemoveAfter
For Allow entries, remove the entry after this many days since last use.
This parameter is passed to New-TenantAllowBlockListItems.

.PARAMETER ExpirationDays
For Block entries, sets a fixed expiration date this many days from now.
Use 0 to create block entries with no expiration.

.PARAMETER TestOnly
Displays the planned operations without modifying the tenant.

.EXAMPLE
.\Test-TenantAllowBlockListLimit.ps1 `
    -Operation Add `
    -EntryAction Allow `
    -ListType Sender `
    -Count 5000

.EXAMPLE
.\Test-TenantAllowBlockListLimit.ps1 `
    -Operation Add `
    -EntryAction Block `
    -ListType Sender `
    -Count 5000

.EXAMPLE
.\Test-TenantAllowBlockListLimit.ps1 `
    -Operation Delete `
    -EntryAction Allow `
    -ListType Sender `
    -Count 5000

.EXAMPLE
.\Test-TenantAllowBlockListLimit.ps1 `
    -Operation Add `
    -EntryAction Block `
    -ListType Url `
    -Count 100 `
    -TestOnly
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [ValidateSet("Add", "Delete")]
    [string]$Operation,

    [Parameter(Mandatory)]
    [ValidateSet("Allow", "Block")]
    [string]$EntryAction,

    [ValidateSet("Sender", "Url")]
    [string]$ListType = "Sender",

    [ValidateRange(1, 15000)]
    [int]$Count = 5000,

    [ValidateRange(1, 999999)]
    [int]$StartIndex = 1,

    [ValidatePattern("^[a-zA-Z0-9-]+$")]
    [string]$Prefix = "m365-tabl-test",

    [ValidateRange(1, 100)]
    [int]$BatchSize = 100,

    [ValidateRange(1, 365)]
    [int]$RemoveAfter = 45,

    [ValidateRange(0, 365)]
    [int]$ExpirationDays = 30,

    [switch]$TestOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Split-IntoBatches {
    param (
        [Parameter(Mandatory)]
        [string[]]$Items,

        [Parameter(Mandatory)]
        [int]$Size
    )

    for ($offset = 0; $offset -lt $Items.Count; $offset += $Size) {
        $lastIndex = [Math]::Min($offset + $Size - 1, $Items.Count - 1)
        ,$Items[$offset..$lastIndex]
    }
}

# Verify that the required Exchange Online cmdlets are available.
$requiredCommands = @(
    "New-TenantAllowBlockListItems",
    "Remove-TenantAllowBlockListItems"
)

$missingCommands = foreach ($command in $requiredCommands) {
    if (-not (Get-Command -Name $command -ErrorAction SilentlyContinue)) {
        $command
    }
}

if ($missingCommands) {
    throw @"
The following Exchange Online cmdlets are unavailable:
$($missingCommands -join ", ")

Install/import the ExchangeOnlineManagement module and connect first:

    Install-Module ExchangeOnlineManagement -Scope CurrentUser
    Import-Module ExchangeOnlineManagement
    Connect-ExchangeOnline
"@
}

$normalisedPrefix = $Prefix.Trim("-").ToLowerInvariant()
$typeLabel        = $ListType.ToLowerInvariant()
$actionLabel      = $EntryAction.ToLowerInvariant()

$entries = for ($index = $StartIndex; $index -lt ($StartIndex + $Count); $index++) {
    $domain = "{0}-{1}-{2}-{3:D6}.invalid" -f `
        $normalisedPrefix,
        $typeLabel,
        $actionLabel,
        $index

    if ($ListType -eq "Url" -and $EntryAction -eq "Block") {
        # Tilde syntax covers the domain and its subdomains for URL blocks.
        "~$domain~"
    }
    else {
        $domain
    }
}

$batches = @(Split-IntoBatches -Items $entries -Size $BatchSize)

Write-Host ""
Write-Host "Tenant Allow/Block List test" -ForegroundColor Cyan
Write-Host "Operation    : $Operation"
Write-Host "Entry action : $EntryAction"
Write-Host "List type    : $ListType"
Write-Host "Entry count  : $($entries.Count)"
Write-Host "Start index  : $StartIndex"
Write-Host "First entry  : $($entries[0])"
Write-Host "Last entry   : $($entries[-1])"
Write-Host "Batch count  : $($batches.Count)"
Write-Host "Test only    : $TestOnly"
Write-Host ""

$processed = 0
$failed    = 0
$batchNo   = 0

foreach ($batch in $batches) {
    $batchNo++
    $batchEntries = [string[]]$batch
    $target = "$($batchEntries.Count) $EntryAction $ListType entries"

    Write-Progress `
        -Activity "$Operation Tenant Allow/Block List entries" `
        -Status "Batch $batchNo of $($batches.Count)" `
        -PercentComplete (($batchNo / $batches.Count) * 100)

    try {
        if ($TestOnly) {
            Write-Host "[TEST] Batch ${batchNo}: $Operation $target"
            $processed += $batchEntries.Count
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($target, $Operation)) {
            continue
        }

        if ($Operation -eq "Add") {
            $parameters = @{
                ListType = $ListType
                Entries  = $batchEntries
                Notes    = "Limit testing entry generated by $($MyInvocation.MyCommand.Name)"
            }

            if ($EntryAction -eq "Allow") {
                $parameters.Allow       = $true
                $parameters.RemoveAfter = $RemoveAfter
            }
            else {
                $parameters.Block = $true

                if ($ExpirationDays -eq 0) {
                    $parameters.NoExpiration = $true
                }
                else {
                    $parameters.ExpirationDate = (Get-Date).ToUniversalTime().AddDays(
                        $ExpirationDays
                    )
                }
            }

            New-TenantAllowBlockListItems @parameters | Out-Null
        }
        else {
            $parameters = @{
                ListType = $ListType
                Entries  = $batchEntries
            }

            Remove-TenantAllowBlockListItems @parameters | Out-Null
        }

        $processed += $batchEntries.Count

        Write-Host (
            "[OK] Batch {0}/{1}: {2} entries processed. Total: {3}" -f `
                $batchNo,
                $batches.Count,
                $batchEntries.Count,
                $processed
        ) -ForegroundColor Green
    }
    catch {
        $failed += $batchEntries.Count

        Write-Warning (
            "Batch {0}/{1} failed. Entries: {2} to {3}. Error: {4}" -f `
                $batchNo,
                $batches.Count,
                $batchEntries[0],
                $batchEntries[-1],
                $_.Exception.Message
        )
    }
}

Write-Progress `
    -Activity "$Operation Tenant Allow/Block List entries" `
    -Completed

Write-Host ""
Write-Host "Completed" -ForegroundColor Cyan
Write-Host "Successfully processed : $processed"
Write-Host "Failed                 : $failed"

if ($failed -gt 0) {
    Write-Warning "One or more batches failed. Review the warnings above before rerunning."
}