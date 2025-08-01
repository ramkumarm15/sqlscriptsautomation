CREATE OR ALTER VIEW dbo.v_ActiveUsers
AS
SELECT
    UserId,
    Username,
    Email
FROM dbo.Users
WHERE IsActive = 1;
GO