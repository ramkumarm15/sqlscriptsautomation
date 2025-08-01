# Pipeline Execution Flow

This document provides a detailed, step-by-step walkthrough of the CI/CD pipeline, from a developer's code commit to a successful production deployment. It also explains the performance considerations of the deployment script.

---

## From Commit to Production

This pipeline ensures a consistent and safe deployment of database changes. Here is the step-by-step journey:

1.  **Developer Commits Change**: A developer creates a new, versioned migration script (e.g., `V1.0.3__Add_Indexes.sql`) and pushes it to the `main` branch.

2.  **Build Workflow Triggers (`build-database.yml`)**:
    *   The push to the `migrations/` folder automatically starts the "Build Database Artifact" workflow.
    *   The workflow checks out the code and packages the entire `migrations/` folder into a secure, versioned artifact named `db-migrations`. This artifact is a snapshot of the intended changes.

3.  **Deploy Workflow Triggers (`deploy-database.yml`)**:
    *   The successful completion of the build workflow triggers the "Deploy Database Changes" workflow.
    *   This workflow runs sequentially, environment by environment.

4.  **Deployment to Development**:
    *   The `deploy-dev` job downloads the `db-migrations` artifact.
    *   It executes the `scripts/deploy.ps1` script, providing it with the **Development** database connection string from GitHub secrets.
    *   The script connects to the Dev DB, reads the `dbo.SchemaVersions` table, and identifies which scripts from the artifact are new.
    *   It then executes only the new scripts in alphabetical order. Upon success, it records the script name in the `dbo.SchemaVersions` table.

5.  **Deployment to Production**:
    *   This job only starts if the Development deployment was successful (`needs: deploy-dev`). This acts as a critical quality gate.
    *   It repeats the same process: it downloads the *exact same* `db-migrations` artifact.
    *   It runs the `deploy.ps1` script, but this time provides the **Production** database connection string.
    *   The script connects to the Production DB, checks *its* `dbo.SchemaVersions` table, and applies any missing scripts.

This flow guarantees that the same set of scripts is tested on Development before being applied to Production, minimizing risk and ensuring consistency.

---

## Performance and Scalability: The `SchemaVersions` Check

A common concern in migration-based systems is whether performance will degrade as the number of executed scripts grows. The `deploy.ps1` script is specifically designed to prevent this from happening.

It does **not** query the database for every file. The process is highly optimized:

1.  **Fetch Once**: At the start, the script makes a **single database call** to `SELECT ScriptName FROM dbo.SchemaVersions`. This query is very fast because the `ScriptName` column has a unique index.
2.  **Store Smart**: The list of script names is loaded into an in-memory **`HashSet`** data structure.
3.  **Check Fast**: A `HashSet` is built for near-instant lookups (an O(1) "constant time" operation). When the script loops through the local files and checks if a script has been applied (`if ($appliedScriptNames.Contains($file.Name))`), the check is extremely fast. It does not matter if the `HashSet` contains 100 or 100,000 items; the lookup time remains negligible.

This implementation ensures that the deployment process will remain fast and efficient, even after thousands of migrations have been applied.