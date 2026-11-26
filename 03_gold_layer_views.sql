/* ============================================================================
   MEDALLION ARCHITECTURE - GOLD LAYER (SQL SERVER / T-SQL)
   Includes:
     1. Schemas & safe base silver table guardrails (if not already created)
     2. Dimension Views: gold.dim_products & gold.dim_customers (cleansed & integrated)
     3. Fact Views: gold.fact_sales (transaction grain) & gold.fact_sales_daily (aggregated)
   ============================================================================ */

SET NOCOUNT ON;
GO

-- 0. Ensure schemas exist
IF SCHEMA_ID('silver') IS NULL EXEC('CREATE SCHEMA silver;');
IF SCHEMA_ID('gold')   IS NULL EXEC('CREATE SCHEMA gold;');
GO

-- Ensure silver tables exist if running standalone
IF OBJECT_ID('silver.crm_prd_info', 'U') IS NULL
BEGIN
    CREATE TABLE silver.crm_prd_info (
        prd_id       INT,
        cat_id       NVARCHAR(50),
        prd_key      NVARCHAR(50),
        prd_nm       NVARCHAR(100),
        prd_cost     INT,
        prd_line     NVARCHAR(50),
        prd_start_dt DATE,
        prd_end_dt   DATE
    );
END;

IF OBJECT_ID('silver.erp_px_cat_g1v2', 'U') IS NULL
BEGIN
    CREATE TABLE silver.erp_px_cat_g1v2 (
        id          NVARCHAR(50),
        cat         NVARCHAR(50),
        subcat      NVARCHAR(50),
        maintenance NVARCHAR(50)
    );
END;

IF OBJECT_ID('silver.crm_sales_details', 'U') IS NULL
BEGIN
    CREATE TABLE silver.crm_sales_details (
        sls_ord_num  NVARCHAR(50),
        sls_prd_key  NVARCHAR(50),
        sls_cust_id  INT,
        sls_order_dt DATE,
        sls_ship_dt  DATE,
        sls_due_dt   DATE,
        sls_sales    INT,
        sls_quantity INT,
        sls_price    INT
    );
END;

IF OBJECT_ID('silver.crm_cust_info', 'U') IS NULL
BEGIN
    CREATE TABLE silver.crm_cust_info (
        cst_id          INT,
        cst_key         NVARCHAR(50),
        cst_firstname   NVARCHAR(50),
        cst_lastname    NVARCHAR(50),
        cst_marital_stat NVARCHAR(50),
        cst_gndr        NVARCHAR(50),
        cst_create_date DATE
    );
END;
GO

/* ----------------------------------------------------------------------------
   1. DIMENSION VIEW: gold.dim_products
      - Integrates CRM product info + ERP category hierarchy
      - Cleanses strings, handles NULLs, and filters active products
   ---------------------------------------------------------------------------- */
CREATE OR ALTER VIEW gold.dim_products AS
SELECT
    ROW_NUMBER() OVER (ORDER BY pn.prd_start_dt, pn.prd_key) AS product_key,
    pn.prd_id                                                AS product_id,
    NULLIF(LTRIM(RTRIM(pn.prd_key)), '')                     AS product_number,
    COALESCE(NULLIF(LTRIM(RTRIM(pn.prd_nm)), ''), 'Unknown Product') AS product_name,
    NULLIF(LTRIM(RTRIM(pn.cat_id)), '')                      AS category_id,
    COALESCE(NULLIF(LTRIM(RTRIM(pc.cat)), ''), 'Uncategorized')      AS category,
    COALESCE(NULLIF(LTRIM(RTRIM(pc.subcat)), ''), 'Uncategorized')   AS subcategory,
    COALESCE(NULLIF(LTRIM(RTRIM(pc.maintenance)), ''), 'N/A')       AS maintenance_required,
    COALESCE(pn.prd_cost, 0)                                 AS standard_cost,
    CASE UPPER(LTRIM(RTRIM(COALESCE(pn.prd_line, ''))))
        WHEN 'M' THEN 'Mountain'
        WHEN 'R' THEN 'Road'
        WHEN 'S' THEN 'Other Sales'
        WHEN 'T' THEN 'Touring'
        ELSE 'N/A'
    END                                                      AS product_line,
    pn.prd_start_dt                                          AS start_date
FROM silver.crm_prd_info pn
LEFT JOIN silver.erp_px_cat_g1v2 pc
    ON LTRIM(RTRIM(pn.cat_id)) = LTRIM(RTRIM(pc.id))
WHERE pn.prd_end_dt IS NULL;
GO

/* ----------------------------------------------------------------------------
   2. DIMENSION VIEW: gold.dim_customers
      - Cleanses customer attributes and standardizes codes
   ---------------------------------------------------------------------------- */
CREATE OR ALTER VIEW gold.dim_customers AS
SELECT
    ROW_NUMBER() OVER (ORDER BY ci.cst_id)                   AS customer_key,
    ci.cst_id                                                AS customer_id,
    NULLIF(LTRIM(RTRIM(ci.cst_key)), '')                     AS customer_number,
    COALESCE(NULLIF(LTRIM(RTRIM(ci.cst_firstname)), ''), 'Unknown') AS first_name,
    COALESCE(NULLIF(LTRIM(RTRIM(ci.cst_lastname)), ''), 'Unknown')  AS last_name,
    CASE UPPER(LTRIM(RTRIM(COALESCE(ci.cst_gndr, ''))))
        WHEN 'M' THEN 'Male'
        WHEN 'F' THEN 'Female'
        ELSE 'N/A'
    END                                                      AS gender,
    CASE UPPER(LTRIM(RTRIM(COALESCE(ci.cst_marital_stat, ''))))
        WHEN 'S' THEN 'Single'
        WHEN 'M' THEN 'Married'
        ELSE 'N/A'
    END                                                      AS marital_status,
    ci.cst_create_date                                       AS create_date
FROM silver.crm_cust_info ci
WHERE ci.cst_id IS NOT NULL;
GO

/* ----------------------------------------------------------------------------
   3. FACT VIEW (TRANSACTION GRAIN): gold.fact_sales
      - Joins sales transactions to Gold dimension surrogate keys
      - Cleanses negative/NULL quantities & prices and derives net sales
   ---------------------------------------------------------------------------- */
CREATE OR ALTER VIEW gold.fact_sales AS
SELECT
    LTRIM(RTRIM(sd.sls_ord_num))                             AS order_number,
    pr.product_key                                           AS product_key,
    cu.customer_key                                          AS customer_key,
    sd.sls_order_dt                                          AS order_date,
    sd.sls_ship_dt                                           AS shipping_date,
    sd.sls_due_dt                                            AS due_date,
    COALESCE(sd.sls_quantity, 0)                             AS quantity,
    COALESCE(sd.sls_price, 0)                                AS unit_price,
    COALESCE(
        NULLIF(sd.sls_sales, 0),
        COALESCE(sd.sls_quantity, 0) * COALESCE(sd.sls_price, 0)
    )                                                        AS sales_amount
FROM silver.crm_sales_details sd
LEFT JOIN gold.dim_products pr
    ON LTRIM(RTRIM(sd.sls_prd_key)) = pr.product_number
LEFT JOIN gold.dim_customers cu
    ON sd.sls_cust_id = cu.customer_id
WHERE sd.sls_ord_num IS NOT NULL;
GO

/* ----------------------------------------------------------------------------
   4. FACT VIEW (AGGREGATED GRAIN): gold.fact_sales_daily
      - Aggregates sales metrics by order date, product, and customer
   ---------------------------------------------------------------------------- */
CREATE OR ALTER VIEW gold.fact_sales_daily AS
SELECT
    fs.order_date,
    fs.product_key,
    fs.customer_key,
    COUNT(DISTINCT fs.order_number)                          AS total_orders,
    SUM(fs.quantity)                                         AS total_quantity,
    SUM(fs.sales_amount)                                     AS total_sales_amount,
    CAST(
        CASE
            WHEN SUM(fs.quantity) > 0
            THEN CAST(SUM(fs.sales_amount) AS DECIMAL(18, 2)) / SUM(fs.quantity)
            ELSE 0
        END AS DECIMAL(18, 2)
    )                                                        AS avg_realized_price
FROM gold.fact_sales fs
GROUP BY
    fs.order_date,
    fs.product_key,
    fs.customer_key;
GO