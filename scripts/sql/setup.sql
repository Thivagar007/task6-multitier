-- =====================================================================
-- Run ONCE as the Entra admin (you) against database sqldb-task6
-- (Azure Portal > SQL database > Query editor > sign in with Entra ID)
-- No GO separators: the portal Query editor runs the whole script as one batch
--
-- 1. Creates the demo table + sample rows
-- 2. Creates a DB user for the backend MANAGED IDENTITY and gives it
--    READ-ONLY access (db_datareader) - least privilege, no password
-- =====================================================================

IF OBJECT_ID('dbo.orders') IS NULL
BEGIN
    CREATE TABLE dbo.orders (
        id          INT IDENTITY(1,1) PRIMARY KEY,
        customer    NVARCHAR(100)  NOT NULL,
        amount      DECIMAL(10,2)  NOT NULL,
        created_at  DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
    );

    INSERT INTO dbo.orders (customer, amount) VALUES
        (N'Arun Kumar', 1499.00),
        (N'Priya S',     249.50),
        (N'Karthik R',  3200.00),
        (N'Meena V',     780.25),
        (N'Rahul D',    1999.99);
END;

-- The name must match the managed identity's name exactly
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'id-task6-backend')
    CREATE USER [id-task6-backend] FROM EXTERNAL PROVIDER;

ALTER ROLE db_datareader ADD MEMBER [id-task6-backend];

-- Verify: should list id-task6-backend with role db_datareader
SELECT dp.name AS principal, r.name AS role
FROM sys.database_role_members rm
JOIN sys.database_principals dp ON rm.member_principal_id = dp.principal_id
JOIN sys.database_principals r  ON rm.role_principal_id   = r.principal_id
WHERE dp.name = N'id-task6-backend';
