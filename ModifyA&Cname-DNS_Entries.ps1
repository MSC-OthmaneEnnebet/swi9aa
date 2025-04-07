# Interactive PowerShell script to modify only A or CNAME DNS records
param(
    [string]$DnsZone = "contoso.com"
)

# Check if the current user is a member of the Domain Admins group
$CurrentUser = "Administrator"
$DomainAdminsGroup = "Domain Admins"

# Import Active Directory module
Import-Module ActiveDirectory

# Check if the user is a Domain Admin
$IsDomainAdmin = (Get-ADUser $CurrentUser -Properties MemberOf | Select-Object -ExpandProperty MemberOf) -contains "CN=Domain Admins,CN=Users,DC=contoso,DC=com"

if (-not $IsDomainAdmin) {
    Write-Host "You must be a member of the 'Domain Admins' group to run this script." -ForegroundColor Red
    exit 1
}

# Import DNS module
Import-Module DNSServer

# Prompt for the record name
$RecordName = Read-Host "Enter the DNS record name"

# Check if the record exists
$ARecords = Get-DnsServerResourceRecord -ZoneName $DnsZone -Name $RecordName -ErrorAction SilentlyContinue | Where-Object {$_.RecordType -eq "A"}
Start-Sleep -Seconds 2
$CnameRecords = Get-DnsServerResourceRecord -ZoneName $DnsZone -Name $RecordName -ErrorAction SilentlyContinue | Where-Object {$_.RecordType -eq "CNAME"}
Start-Sleep -Seconds 2

# Check for critical records (NS, SRV, etc.)
$CriticalRecords = Get-DnsServerResourceRecord -ZoneName $DnsZone -Name $RecordName -ErrorAction SilentlyContinue | Where-Object {($_.RecordType -ne "A") -and ($_.RecordType -ne "CNAME")}
Start-Sleep -Seconds 5

if ($CriticalRecords) {
    Write-Host "Error: Critical DNS records (NS, SRV, etc.) exist for '$RecordName'. Modifications are not allowed." -ForegroundColor Red
    exit 1
}

if ($ARecords.Count -gt 1 -or $CnameRecords.Count -gt 1) {
    Write-Host "Error: More than 2 A or CNAME records exist for '$RecordName'. This could be a round-robin configuration, and modification is not allowed." -ForegroundColor Red
    exit 1
}

if ($ARecords -and $CnameRecords) {
    Write-Host "Error: This DNS record exists as both an A and a CNAME record. It must be one or the other." -ForegroundColor Red
    exit 1
} elseif (-not $ARecords -and -not $CnameRecords) {
    Write-Host "No DNS record found for '$RecordName' in zone '$DnsZone'. You can create a new one." -ForegroundColor Yellow
}

# Ask user for action
Write-Host "Select an action:" -ForegroundColor Cyan
Write-Host "1. Create/Update an A record"
Write-Host "2. Create/Update a CNAME record"
$Action = Read-Host "Enter your choice (1 or 2)"

switch ($Action) {
    "1" {
        $IPAddress = Read-Host "Enter the new IP address for the A record"
        if ($ARecords) {
            $UpdateChoice = Read-Host "An A record already exists. Do you want to update it? (Y/N)"
            if ($UpdateChoice -match "^[Yy]$") {
                foreach ($Record in $ARecords) {
                    Remove-DnsServerResourceRecord -ZoneName $DnsZone -InputObject $Record -Confirm:$false
                    Start-Sleep -Seconds 5
                }
                Start-Sleep -Seconds 5
                Add-DnsServerResourceRecordA -ZoneName $DnsZone -Name $RecordName -IPv4Address $IPAddress -AllowUpdateAny -PassThru
                
                Write-Host "A record updated successfully." -ForegroundColor Green
            } else {
                Write-Host "Update canceled." -ForegroundColor Yellow
            }
        } else {
            if ($CnameRecords) {
                Write-Host "A CNAME record already exists." -ForegroundColor Yellow
                Start-Sleep -Seconds 5
                exit
            }
            Start-Sleep -Seconds 5
            Add-DnsServerResourceRecordA -ZoneName $DnsZone -Name $RecordName -IPv4Address $IPAddress -AllowUpdateAny -PassThru
            
            Write-Host "A record created successfully." -ForegroundColor Green
        }
    }
    "2" {
        $TargetHost = Read-Host "Enter the target hostname for the CNAME record"
        if ($CnameRecords) {
            $UpdateChoice = Read-Host "A CNAME record already exists. Do you want to update it? (Y/N)"
            if ($UpdateChoice -match "^[Yy]$") {
                foreach ($Record in $CnameRecords) {
                    Remove-DnsServerResourceRecord -ZoneName $DnsZone -InputObject $Record -Confirm:$false
                    Start-Sleep -Seconds 5
                }
                Add-DnsServerResourceRecordCName -ZoneName $DnsZone -Name $RecordName -HostNameAlias $TargetHost -PassThru
                Start-Sleep -Seconds 5
                Write-Host "CNAME record updated successfully." -ForegroundColor Green
            } else {
                Write-Host "Update canceled." -ForegroundColor Yellow
            }
        } else {
            if ($ARecords) {
                Write-Host "An A record already exists." -ForegroundColor Yellow
                Start-Sleep -Seconds 5
                exit
            }
            Add-DnsServerResourceRecordCName -ZoneName $DnsZone -Name $RecordName -HostNameAlias $TargetHost -PassThru
            Write-Host "CNAME record created successfully." -ForegroundColor Green
        }
    }
    default {
        Write-Host "Invalid choice. Exiting..." -ForegroundColor Red
    }
}
