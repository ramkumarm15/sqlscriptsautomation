# SQL Server Deployment Automation Plan

## Executive Summary

The goal of this project is to move from manual, error-prone SQL script execution to a fully automated pipeline. This is achieved by treating our database schema and scripts as code ("Database as Code"). All changes will be stored in this Git repository, and a CI/CD platform (GitHub Actions) will automatically validate and deploy these changes to our various environments (Development, Staging, Production).

This plan follows a **migrations-based approach**, which is explicit, easy to track, and provides a clear history of every change applied to the database.

---

## The Plan: Step-by-Step Automation

### Phase 1: Version Control & Project Structure

The foundation of automation is having a single source of truth in this Git repository.

#### Folder Structure

A clear structure is crucial for organization.

```
database-project/
├── .github/
│   └── workflows/
│       ├── build-database.yml
│       └── deploy-database.yml
├── migrations/
│   ├── V1.0.0__Initial_Schema.sql
│   ├── V1.0.1__Create_Users_Table.sql
│   └── V1.0.2__Add_Email_To_Users.sql
├── procs/
│   └── usp_GetUserDetails.sql
├── views/
│   └── v_ActiveUsers.sql
├── scripts/
│   └── deploy.ps1
└── README.md
```

*   **`migrations/`**: This is the most important folder. It contains scripts that change the database schema or reference data.
    *   **Critical Naming Convention:** Scripts are executed in alphanumeric order. Use a versioned naming scheme like `V<Version>__<Description>.sql`. For example: `V1.0.1__Create_Users_Table.sql`.
    *   **Immutable Migrations:** Once a migration script is merged and deployed, it should **never be changed**. To undo or alter its effects, you create a *new* migration script.
*   **`procs/`, `views/` etc.**: For programmable objects that can be re-run. These scripts should be idempotent (i.e., safe to run multiple times), typically using `CREATE OR ALTER` statements.
*   **`scripts/`**: Contains helper scripts for the CI/CD pipeline, like the PowerShell deployment script.

### Phase 2: The Database "Schema Version" Table

To manage which scripts have been run, our deployment script will use a special tracking table in each target database.

**Action:** This is a one-time manual setup in each of your SQL Server databases (`Dev`, `Staging`, `Prod`).

```sql
-- This table will track which migration scripts have been successfully applied.
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[SchemaVersions]') AND type in (N'U'))
BEGIN
    CREATE TABLE [dbo].[SchemaVersions] (
        [Id] INT IDENTITY(1,1) PRIMARY KEY,
        [ScriptName] NVARCHAR(255) NOT NULL,
        [AppliedDate] DATETIME NOT NULL DEFAULT(GETUTCDATE())
    );
    -- Create a unique index to prevent running the same script twice
    CREATE UNIQUE INDEX UQ_SchemaVersions_ScriptName ON [dbo].[SchemaVersions]([ScriptName]);
END
GO
```

### Phase 3: The CI/CD Pipeline

This is our automation engine, implemented with GitHub Actions. The pipeline has two main parts:
1.  **Build (CI - Continuous Integration):** Validates and packages the scripts.
2.  **Deploy (CD - Continuous Deployment):** Pushes the scripts to the database.

#### Build Workflow (`.github/workflows/build-database.yml`)

This workflow triggers on a push to the `main` branch. It validates the SQL and packages the `migrations` folder into an artifact that the deployment job can use.

```yaml
name: Build Database Artifact

on:
  push:
    branches:
      - main
    paths:
      - 'migrations/**'

jobs:
  build:
    name: Validate and Package SQL
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      # Optional but recommended: Add a SQL Linter/validator step here
      # to catch syntax errors early.

      - name: Archive migration scripts
        uses: actions/upload-artifact@v4
        with:
          name: db-migrations
          path: migrations/
          retention-days: 5
```

#### Deploy Workflow (`.github/workflows/deploy-database.yml`)

This workflow is triggered by the completion of the build. It deploys to different environments, with a manual approval step for production.

```yaml
name: Deploy Database Changes

on:
  workflow_run:
    workflows: ["Build Database Artifact"]
    types:
      - completed

jobs:
  deploy-dev:
    name: Deploy to Development
    if: ${{ github.event.workflow_run.conclusion == 'success' }}
    runs-on: ubuntu-latest
    environment: development
    steps:
      # This step is not needed if the script is packaged in the artifact
      - name: Download migration scripts artifact
        uses: actions/download-artifact@v4
        with:
          name: db-migrations

      - name: Install SqlServer PowerShell Module
        shell: pwsh
        run: Install-Module -Name SqlServer -Force -AcceptLicense

      - name: Deploy to Development Database
        shell: pwsh
        run: ./scripts/deploy.ps1 -ConnectionString "${{ secrets.DEV_DB_CONNECTION_STRING }}" -MigrationsPath "./migrations"

  deploy-prod:
    name: Deploy to Production
    needs: deploy-dev # Only run if dev deployment succeeds
    runs-on: ubuntu-latest
    environment:
      name: production
      url: https://my-app-prod.com # Optional: link to the app
    steps:
      # This step is not needed if the script is packaged in the artifact
      - name: Download migration scripts artifact
        uses: actions/download-artifact@v4
        with:
          name: db-migrations

      - name: Install SqlServer PowerShell Module
        shell: pwsh
        run: Install-Module -Name SqlServer -Force -AcceptLicense

      - name: Deploy to Production Database
        shell: pwsh
        run: ./scripts/deploy.ps1 -ConnectionString "${{ secrets.PROD_DB_CONNECTION_STRING }}" -MigrationsPath "./migrations"
```

**Secrets Management:** Connection strings (`DEV_DB_CONNECTION_STRING`, `PROD_DB_CONNECTION_STRING`) must be configured in this repository's settings under **Settings > Secrets and variables > Actions**.

### Phase 4: The Deployment Script

The `exec-script` block in the YAML file calls this robust PowerShell script (`scripts/deploy.ps1`) to perform the deployment logic.

```powershell
# scripts/deploy.ps1
param (
    [string][Parameter(Mandatory = $true)] $ConnectionString,
    [string][Parameter(Mandatory = $true)] $MigrationsPath
)

try {
    # Get the list of scripts already applied from the database
    Write-Host "Connecting to database to get applied scripts..."
    $query = "SELECT ScriptName FROM dbo.SchemaVersions;"
    $appliedScripts = Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $query -ErrorAction Stop
    $appliedScriptNames = $appliedScripts.ScriptName
    Write-Host "Found $($appliedScriptNames.Count) applied scripts."

    # Get the list of migration script files on disk, sorted alphabetically
    $migrationFiles = Get-ChildItem -Path $MigrationsPath -Filter "*.sql" | Sort-Object Name

    if (-not $migrationFiles) {
        Write-Host "No migration scripts found in '$MigrationsPath'. Exiting."
        exit 0
    }

    Write-Host "Found $($migrationFiles.Count) scripts in the migrations folder. Comparing with database..."

    foreach ($file in $migrationFiles) {
        if ($file.Name -in $appliedScriptNames) {
            Write-Host "Skipping '$($file.Name)' as it has already been applied."
        }
        else {
            Write-Host "Applying '$($file.Name)'..."
            $scriptContent = Get-Content -Path $file.FullName -Raw
            
            # Execute the script. The transaction handling is inside the script itself.
            Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $scriptContent -ErrorAction Stop
            
            # Record the script in the SchemaVersions table
            $insertQuery = "INSERT INTO dbo.SchemaVersions (ScriptName) VALUES ('$($file.Name)');"
            Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $insertQuery -ErrorAction Stop
            
            Write-Host "Successfully applied and recorded '$($file.Name)'."
        }
    }

    Write-Host "Database deployment completed successfully."
}
catch {
    Write-Error "Deployment failed. Error: $($_.Exception.Message)"
    exit 1 # Exit with a non-zero code to fail the pipeline
}
```

## Best Practices & Advanced Topics

*   **Transactions:** Wrap each migration script in a transaction to ensure it either fully completes or not at all.
    ```sql
    BEGIN TRANSACTION;
    BEGIN TRY
        -- Your SQL changes here
        -- CREATE TABLE ...
        -- ALTER TABLE ...

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        -- Re-throw the error to ensure the deployment script fails
        THROW;
    END CATCH;
    ```
*   **Rollbacks:** True automated rollbacks are complex and risky. The best strategy is to **roll forward**. If a bug is introduced in `V1.0.3`, you quickly create and deploy `V1.0.4` which fixes the issue. For catastrophic failures, the safest plan is to restore a pre-deployment database backup.
*   **Idempotency for Programmable Objects:** For stored procedures, views, and functions, use `CREATE OR ALTER` (SQL Server 2016 SP1+) or a `DROP` and `CREATE` pattern. This allows you to re-run their deployment anytime without errors. These can be managed in a separate pipeline that runs after the migrations.