USE master;
GO
-- Create the 'DataWarehouse' database
CREATE DATABASE DataWarehouse;
GO
-- Switch to the new Database
USE DataWarehouse;
GO
-- Create Schemas for the Medallion Architecture
CREATE SCHEMA bronze;
GO
CREATE SCHEMA silver;
GO
CREATE SCHEMA gold;
GO