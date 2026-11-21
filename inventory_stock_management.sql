-- ============================================================================
-- 1. DDL COMMANDS: Create Schema, Tables, and Alter Table Structure
-- ============================================================================
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Inventory')
BEGIN
    EXEC('CREATE SCHEMA Inventory');
END
GO

IF OBJECT_ID('Inventory.Products', 'U') IS NOT NULL
    DROP TABLE Inventory.Products;
GO

IF OBJECT_ID('Inventory.StockAuditLog', 'U') IS NOT NULL
    DROP TABLE Inventory.StockAuditLog;
GO

CREATE TABLE Inventory.Products (
    ProductId       INT IDENTITY(1,1) PRIMARY KEY,
    SkuCode         VARCHAR(30)     NOT NULL UNIQUE,
    ProductName     NVARCHAR(120)   NOT NULL,
    UnitPrice       DECIMAL(10,2)   NOT NULL CHECK (UnitPrice >= 0),
    QuantityInStock INT             NOT NULL DEFAULT 0 CHECK (QuantityInStock >= 0),
    IsActive        BIT             NOT NULL DEFAULT 1,
    CreatedAt       DATETIME2       NOT NULL DEFAULT SYSDATETIME()
);
GO

CREATE TABLE Inventory.StockAuditLog (
    AuditId         INT IDENTITY(1,1) PRIMARY KEY,
    ProductId       INT             NOT NULL,
    ChangeAmount    INT             NOT NULL,
    PreviousQty     INT             NOT NULL,
    NewQty          INT             NOT NULL,
    Reason          NVARCHAR(200)   NULL,
    ChangedAt       DATETIME2       NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT FK_StockAuditLog_Products FOREIGN KEY (ProductId)
        REFERENCES Inventory.Products(ProductId)
);
GO

-- Alter table to add a reorder threshold column and supporting index
ALTER TABLE Inventory.Products
ADD ReorderLevel INT NOT NULL DEFAULT 10
    CONSTRAINT CHK_Products_ReorderLevel CHECK (ReorderLevel >= 0);
GO

CREATE NONCLUSTERED INDEX IX_Products_SkuCode
ON Inventory.Products (SkuCode)
INCLUDE (ProductName, QuantityInStock, IsActive);
GO

-- ============================================================================
-- 2. CREATE STORED PROCEDURE: Add a New Product
-- ============================================================================
CREATE OR ALTER PROCEDURE Inventory.usp_AddProduct
    @SkuCode        VARCHAR(30),
    @ProductName    NVARCHAR(120),
    @UnitPrice      DECIMAL(10,2),
    @InitialStock   INT = 0,
    @ReorderLevel   INT = 10,
    @NewProductId   INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF LTRIM(RTRIM(@SkuCode)) = ''
            THROW 50001, 'SKU code cannot be empty.', 1;

        IF @UnitPrice < 0
            THROW 50002, 'Unit price cannot be negative.', 1;

        IF @InitialStock < 0 OR @ReorderLevel < 0
            THROW 50003, 'Stock quantities and reorder levels must be zero or greater.', 1;

        BEGIN TRANSACTION;

        INSERT INTO Inventory.Products (
            SkuCode, ProductName, UnitPrice, QuantityInStock, ReorderLevel
        )
        VALUES (
            UPPER(LTRIM(RTRIM(@SkuCode))),
            LTRIM(RTRIM(@ProductName)),
            @UnitPrice,
            @InitialStock,
            @ReorderLevel
        );

        SET @NewProductId = SCOPE_IDENTITY();

        IF @InitialStock > 0
        BEGIN
            INSERT INTO Inventory.StockAuditLog (
                ProductId, ChangeAmount, PreviousQty, NewQty, Reason
            )
            VALUES (
                @NewProductId, @InitialStock, 0, @InitialStock, N'Initial stock on creation'
            );
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- ============================================================================
-- 3. CREATE & ALTER STORED PROCEDURE: Adjust Stock Levels
-- ============================================================================
CREATE PROCEDURE Inventory.usp_AdjustStock
    @ProductId      INT,
    @ChangeAmount   INT,
    @Reason         NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @CurrentQty INT;

    SELECT @CurrentQty = QuantityInStock
    FROM Inventory.Products
    WHERE ProductId = @ProductId;

    IF @CurrentQty IS NULL
        THROW 50004, 'Product not found.', 1;

    IF (@CurrentQty + @ChangeAmount) < 0
        THROW 50005, 'Insufficient stock to complete this adjustment.', 1;

    UPDATE Inventory.Products
    SET QuantityInStock = QuantityInStock + @ChangeAmount
    WHERE ProductId = @ProductId;
END;
GO

-- Alter the procedure to record every adjustment in Inventory.StockAuditLog
ALTER PROCEDURE Inventory.usp_AdjustStock
    @ProductId      INT,
    @ChangeAmount   INT,
    @Reason         NVARCHAR(200) = N'Manual stock adjustment'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @CurrentQty INT;
    DECLARE @NewQty     INT;

    BEGIN TRY
        SELECT @CurrentQty = QuantityInStock
        FROM Inventory.Products
        WHERE ProductId = @ProductId;

        IF @CurrentQty IS NULL
            THROW 50004, 'Product not found.', 1;

        SET @NewQty = @CurrentQty + @ChangeAmount;

        IF @NewQty < 0
            THROW 50005, 'Insufficient stock to complete this adjustment.', 1;

        BEGIN TRANSACTION;

        UPDATE Inventory.Products
        SET QuantityInStock = @NewQty
        WHERE ProductId = @ProductId;

        INSERT INTO Inventory.StockAuditLog (
            ProductId, ChangeAmount, PreviousQty, NewQty, Reason
        )
        VALUES (
            @ProductId, @ChangeAmount, @CurrentQty, @NewQty, COALESCE(@Reason, N'Manual stock adjustment')
        );

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- ============================================================================
-- 4. EXECUTE STORED PROCEDURES & VERIFY DATA
-- ============================================================================
DECLARE @Id1 INT, @Id2 INT, @Id3 INT;

EXEC Inventory.usp_AddProduct
    @SkuCode = 'KB-MECH-01',
    @ProductName = N'Mechanical Keyboard 75%',
    @UnitPrice = 89.99,
    @InitialStock = 25,
    @ReorderLevel = 8,
    @NewProductId = @Id1 OUTPUT;

EXEC Inventory.usp_AddProduct
    @SkuCode = 'MS-WIRE-02',
    @ProductName = N'Wireless Ergonomic Mouse',
    @UnitPrice = 49.50,
    @InitialStock = 40,
    @ReorderLevel = 12,
    @NewProductId = @Id2 OUTPUT;

EXEC Inventory.usp_AddProduct
    @SkuCode = 'MON-USB-03',
    @ProductName = N'27-Inch 4K USB-C Monitor',
    @UnitPrice = 379.00,
    @InitialStock = 10,
    @ReorderLevel = 4,
    @NewProductId = @Id3 OUTPUT;

-- Execute stock adjustments (both restock and sale/deduction)
EXEC Inventory.usp_AdjustStock
    @ProductId = @Id1,
    @ChangeAmount = -5,
    @Reason = N'Customer order #1042';

EXEC Inventory.usp_AdjustStock
    @ProductId = @Id2,
    @ChangeAmount = 15,
    @Reason = N'Supplier shipment received';

EXEC Inventory.usp_AdjustStock
    @ProductId = @Id3,
    @ChangeAmount = -3,
    @Reason = N'Office hardware deployment';

-- View final product inventory and audit history
SELECT
    ProductId,
    SkuCode,
    ProductName,
    UnitPrice,
    QuantityInStock,
    ReorderLevel,
    CASE WHEN QuantityInStock <= ReorderLevel THEN 'REORDER' ELSE 'OK' END AS StockStatus
FROM Inventory.Products
ORDER BY ProductId;

SELECT
    AuditId,
    ProductId,
    ChangeAmount,
    PreviousQty,
    NewQty,
    Reason,
    ChangedAt
FROM Inventory.StockAuditLog
ORDER BY AuditId;
GO
