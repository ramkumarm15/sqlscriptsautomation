BEGIN TRANSACTION;
BEGIN TRY

    IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[Users]') AND type in (N'U'))
    BEGIN
        CREATE TABLE [dbo].[Users] (
            [UserId] INT IDENTITY(1,1) PRIMARY KEY,
            [Username] NVARCHAR(100) NOT NULL,
            [FirstName] NVARCHAR(100) NULL,
            [LastName] NVARCHAR(100) NULL,
            [IsActive] BIT NOT NULL DEFAULT(1)
        );
    END

COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO