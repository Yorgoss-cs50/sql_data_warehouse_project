USE DataWarehouse;
GO
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'silver') EXEC('CREATE SCHEMA silver');
  IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'gold') EXEC('CREATE SCHEMA gold');
  GO
  IF OBJECT_ID('silver.crm_cust_info','U') IS NOT NULL DROP TABLE silver.crm_cust_info;
  CREATE TABLE silver.crm_cust_info (cst_id INT,cst_key NVARCHAR(50),cst_firstname NVARCHAR(50), cst_lastname NVARCHAR(50),cst_marital_status NVARCHAR(50),cst_create_date DATE);
  IF OBJECT_ID('silver.erp_cust_az12','U') IS NOT NULL DROP TABLE silver.erp_cust_az12;
  CREATE TABLE silver.erp_cust_az12 (cid NVARCHAR(50), bdate DATE ,gen NVARCHAR(50));
  IF OBJECT_ID('silver.erp_loc_a101','U') IS NOT NULL DROP TABLE silver.erp_loc_a101;
  CREATE TABLE silver.erp_loc_a101 (cid NVARCHAR(50),cntry NVARCHAR(50));
  GO
  ALTER TABLE silver.crm_cust_info ADD cst_gndr NVARCHAR(50);
  GO
CREATE OR ALTER VIEW gold.dim_customers AS
SELECT
ROW_NUMBER() OVER(ORDER BY ci.cst_id) AS customer_key,
ci.cst_id AS customer_id,
ci.cst_key AS customer_number,
ci.cst_firstname  AS customer_firstname,
ci.cst_lastname AS customer_lastname,
la.cntry AS country,
ci.cst_marital_status AS marital_status,
CASE 
WHEN ci.cst_gndr != 'n/a' THEN ci.cst_gndr
ELSE COALESCE(ca.gen,'n/a')
END AS gender,
ca.bdate AS birthdate,
ci.cst_create_date AS create_date
FROM silver.crm_cust_info ci
LEFT JOIN silver.erp_cust_az12 ca
ON ci.cst_key = ca.cid
LEFT JOIN silver.erp_loc_a101 la
ON ci.cst_key = la.cid;
GO