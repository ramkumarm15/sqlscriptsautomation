CREATE OR ALTER PROCEDURE dbo.usp_GetUserDetails
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT UserId, Username, FirstName, LastName, Email, IsActive
    FROM dbo.Users
    WHERE UserId = @UserId;
END
GO