<#
.SYNOPSIS
    Applies new SQL migration scripts to a target database.
.DESCRIPTION
    This script compares the .sql files in a specified migrations folder with a record
    of applied scripts in the target database's dbo.SchemaVersions table. It then
    executes any new scripts in alphabetical order.
.PARAMETER ConnectionString
    The connection string for the target SQL Server database.
.PARAMETER MigrationsPath
    The local path to the folder containing the .sql migration scripts.
#>
param (
    [string][Parameter(Mandatory = $true)] $ConnectionString,
    [string][Parameter(Mandatory = $true)] $MigrationsPath
)

try {
    # Get the list of scripts already applied from the database
    Write-Host "Connecting to database to get applied scripts..."
    $query = "SELECT ScriptName FROM dbo.SchemaVersions;"
    $appliedScriptsData = Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $query -ErrorAction Stop

    # Use a HashSet for efficient lookups (O(1) average). Handles case-insensitivity.
    $appliedScriptNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($null -ne $appliedScriptsData) {
        foreach ($script in $appliedScriptsData) {
            [void]$appliedScriptNames.Add($script.ScriptName)
        }
    }
    Write-Host "Found $($appliedScriptNames.Count) applied scripts in the database."

    # Get the list of migration script files on disk, sorted alphabetically
    $migrationFiles = Get-ChildItem -Path $MigrationsPath -Filter "*.sql" | Sort-Object Name

    if (-not $migrationFiles) {
        Write-Host "No migration scripts found in '$MigrationsPath'. Exiting."
        exit 0
    }

    Write-Host "Found $($migrationFiles.Count) scripts in the migrations folder. Comparing with database..."

    foreach ($file in $migrationFiles) {
        if ($appliedScriptNames.Contains($file.Name)) {
            Write-Host "Skipping '$($file.Name)' as it has already been applied."
        } else {
            Write-Host "Applying '$($file.Name)'..."
            $scriptContent = Get-Content -Path $file.FullName -Raw
            Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $scriptContent -ErrorAction Stop
            
            $insertQuery = "INSERT INTO dbo.SchemaVersions (ScriptName) VALUES (@ScriptName);"
            Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $insertQuery -QueryParameter @{ ScriptName = $file.Name } -ErrorAction Stop
            Write-Host "Successfully applied and recorded '$($file.Name)'."
        }
    }
    Write-Host "Database deployment completed successfully."
}
catch {
    Write-Error "Deployment failed. Error: $($_.Exception.Message)"
    exit 1 # Exit with a non-zero code to fail the pipeline
}