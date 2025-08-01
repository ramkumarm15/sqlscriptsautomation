# How the Pipeline Handles Multiple Commits

A common question is what happens if a file is committed multiple times before being pushed to the `main` branch. This document clarifies the behavior for both types of database scripts.

**The short answer is: Only the final state of the files from the last commit in the push is executed.**

---

### 1. Programmable Objects (`procs/`, `views/`)

The `deploy-programmable-objects.yml` workflow is triggered by a `push` event.

*   **Checkout:** The workflow checks out the code as it exists at the very last commit of that push.
*   **Identify Changes:** It then identifies which files (e.g., `procs/usp_GetUserDetails.sql`) were modified as part of the push.
*   **Execute:** It executes only that final version of the changed file.

If you make 5 commits to `usp_GetUserDetails.sql` in a feature branch and then merge/push to `main`, the pipeline runs only once. It sees the final, consolidated version of the file and deploys that single version. It does not run the intermediate versions from your earlier commits.

---

### 2. Migrations (`migrations/`)

The principle is the same, but it highlights a critical best practice.

*   **Build:** When you push a new migration file (e.g., `V1.0.3__My_New_Feature.sql`), the `build-database.yml` workflow triggers. It checks out the code from the final commit and archives the `migrations` folder.
*   **Deploy:** The `deploy-database.yml` workflow downloads that artifact and runs the `deploy.ps1` script. The script sees `V1.0.3__My_New_Feature.sql`, notes that it's not in the `dbo.SchemaVersions` table, and executes the final version of that file.

#### Critical Best Practice: Immutable Migrations

While the pipeline will technically execute the final version of a migration file if you commit to it multiple times, **you should treat migration files as immutable**. Once a migration script is committed (and especially after it's been deployed to any environment), it should **never be changed**.

If you find a mistake in `V1.0.3`, do not go back and edit it. Instead, create a **new** migration file, `V1.0.4__Fix_For_My_New_Feature.sql`, that corrects the problem. This "roll-forward" strategy is crucial for maintaining a reliable and auditable history of every single change that has ever been applied to your database.