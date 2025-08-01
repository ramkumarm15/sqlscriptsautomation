BEGIN TRANSACTION;
BEGIN TRY

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

COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO