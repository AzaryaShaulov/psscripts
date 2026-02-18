# Add Azure Arc extension if not already installed
az extension add --name connectedmachine

# Set the resource group and log file
$resourceGroup = "Arc-onpremservers"
$logFile = "ArcExtensionUpdateLog.csv"

# Initialize CSV log
"Server,Extension,Action,Result,Timestamp" | Out-File -FilePath $logFile -Encoding UTF8

# Known extension defaults
$knownExtensions = @{
    "ChangeTracking-Windows"   = @{ publisher = "Microsoft.Compute"; type = "ChangeTracking-Windows" }
    "AzureMonitorWindowsAgent" = @{ publisher = "Microsoft.Azure.Monitor"; type = "AzureMonitorWindowsAgent" }
    "MDE.Windows"              = @{ publisher = "Microsoft.Azure.AzureDefender"; type = "MDE.Windows" }
    "DependencyAgentWindows"   = @{ publisher = "Microsoft.Azure.Monitoring.DependencyAgent"; type = "DependencyAgentWindows" }
}

# Get Arc-enabled servers
$servers = az connectedmachine list --resource-group $resourceGroup --query "[].name" -o tsv

foreach ($server in $servers) {
    Write-Host "Checking extensions on ${server}..."

    $extensions = az connectedmachine extension list `
        --machine-name $server `
        --resource-group $resourceGroup `
        --query "[].name" -o tsv

    foreach ($ext in $extensions) {
        $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Write-Host "Processing ${ext} on ${server}..."

        $extDetailsJson = az connectedmachine extension show `
            --machine-name $server `
            --resource-group $resourceGroup `
            --name $ext `
            --query "{publisher:publisher, type:type, state:provisioningState}" `
            --output json

        if (-not [string]::IsNullOrWhiteSpace($extDetailsJson)) {
            $extDetails = $extDetailsJson | ConvertFrom-Json
        } else {
            $extDetails = $null
        }

        $publisher = $extDetails?.publisher
        $type      = $extDetails?.type
        $state     = $extDetails?.state

        if (-not [string]::IsNullOrWhiteSpace($state) -and $state -ne "Succeeded") {
            Write-Warning "Skipping ${ext} on ${server}: State = '${state}'."
            "${server},${ext},Skip,State=${state},${timestamp}" | Out-File -FilePath $logFile -Append -Encoding UTF8
            continue
        }

        if ([string]::IsNullOrWhiteSpace($publisher) -or [string]::IsNullOrWhiteSpace($type)) {
            if ($knownExtensions.ContainsKey($ext)) {
                $publisher = $knownExtensions[$ext].publisher
                $type      = $knownExtensions[$ext].type
                Write-Host "Using known values for ${ext} on ${server}."
            } else {
                Write-Warning "Skipping ${ext} on ${server}: Missing publisher/type."
                "${server},${ext},Skip,Missing publisher/type,${timestamp}" | Out-File -FilePath $logFile -Append -Encoding UTF8
                continue
            }
        }

        try {
            az connectedmachine extension update `
                --machine-name $server `
                --resource-group $resourceGroup `
                --name $ext `
                --publisher $publisher `
                --type $type
            Write-Host "Extension ${ext} updated on ${server}."
            "${server},${ext},Update,Success,${timestamp}" | Out-File -FilePath $logFile -Append -Encoding UTF8
        }
        catch {
            Write-Warning "Failed to update ${ext} on ${server}: $_"
            "${server},${ext},Update,Fail=${_},${timestamp}" | Out-File -FilePath $logFile -Append -Encoding UTF8
        }
    }
}

Write-Host "Log saved to $logFile"
