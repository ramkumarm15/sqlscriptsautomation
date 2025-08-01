# SQL Deployment Setup Guide

This guide provides a step-by-step process for configuring your repository and databases to use this automated SQL deployment pipeline.

---

## Prerequisites

Before you begin, you will need:

1.  **A GitHub Repository**: This guide assumes you have copied the contents of this project (`.github` folder, `scripts`, `migrations`, etc.) into your own repository.
2.  **SQL Server Databases**: At least two databases ready to use: one for `development` and one for `production`.
3.  **Permissions**: You must have administrative permissions on the GitHub repository to configure settings like Environments and Secrets.

---

## Step 1: Prepare Your Databases

The automation relies on a special table, `dbo.SchemaVersions`, in each database to track which migration scripts have been executed. You must create this table in **each** of your target databases (`development`, `production`, etc.) before running the pipeline for the first time.

**Action**: Execute the following T-SQL script against each of your databases.

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
> **Note**: This script is identical to the first migration file, `migrations/V1.0.0__Initial_Schema.sql`. This initial manual step is required because the deployment script needs to query this table to know where to start.

---

## Step 2: Configure Your GitHub Repository

The pipeline workflows require two key configurations in your repository settings: **Environments** and **Secrets**.

### A. Create Environments

Environments allow you to apply protection rules (like requiring an approver for production) and use environment-specific secrets.

1.  In your GitHub repository, go to **Settings** > **Environments**.
2.  Click **New environment**.
3.  Name the environment `development` and click **Configure environment**. You can leave the default settings for now.
4.  Go back and create another new environment. Name this one `production`.
5.  For the `production` environment, it is highly recommended to add a protection rule. Under **Deployment protection rules**, check **Required reviewers** and add yourself or your team. This creates the manual approval gate for production deployments.

### B. Add Secrets

You must securely store your database connection strings so the pipeline can access them.

1.  In your GitHub repository, go to **Settings** > **Secrets and variables** > **Actions**.
2.  Select the **Secrets** tab and click **New repository secret**.
3.  Create the following two secrets:
    *   **Name**: `DEV_DB_CONNECTION_STRING`
    *   **Secret**: Your full SQL Server connection string for the development database.
    *   **Environment access**: Grant access to the `development` environment.

4.  Create a second secret:
    *   **Name**: `PROD_DB_CONNECTION_STRING`
    *   **Secret**: Your full SQL Server connection string for the production database.
    *   **Environment access**: Grant access to the `production` environment.

---

## Step 3: How to Use the Pipeline

With the setup complete, you can now start making and deploying changes. The pipeline will trigger automatically when you push to the `main` branch.

### For Schema Changes (Migrations)

These are for changes to tables, data, or other schema objects. They are designed to run only once.

1.  Create a new `.sql` file inside the `migrations/` folder.
2.  **Crucially**, follow the naming convention: `V<Version>__<Description>.sql`. For example: `V1.0.3__Add_Indexes_To_Users.sql`. The files are executed in alphabetical order.
3.  Write your SQL change, and wrap it in a transaction (see any existing migration for an example).
4.  Commit and push your new file to the `main` branch.
5.  This will trigger the `Build Database Artifact` and `Deploy Database Changes` workflows.

### For Programmable Objects (Procedures, Views, Functions)

These are for objects that can be safely re-run or overwritten.

1.  Create or modify a `.sql` file in the appropriate folder (`procs/`, `views/`, etc.).
2.  The script should be idempotent, meaning it can be run multiple times without causing errors. Use `CREATE OR ALTER` for this.
3.  Commit and push your changes to the `main` branch.
4.  This will trigger the `Deploy Programmable Objects` workflow.

---

## Step 4: Monitor and Approve Deployments

1.  After pushing a change, go to the **Actions** tab in your GitHub repository.
2.  You will see your workflow running.
3.  The workflow will first deploy to `development` automatically.
4.  If the `development` deployment succeeds, the `production` job will start and pause, waiting for approval (if you configured it in Step 2).
5.  You will see a notification to "Review deployments". Click it, review the changes, and click **Approve and deploy** to proceed with the production deployment.

You are now fully set up to manage your SQL Server deployments through Git!


