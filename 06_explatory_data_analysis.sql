--1
SELECT
TABLE_CATALOG,
TABLE_SCHEMA,
TABLE_NAME,
TABLE_TYPE
FROM INFORMATION_SCHEMA.TABLES
ORDER BY TABLE_SCHEMA, TABLE_NAME;
--2
SELECT
COLUMN_NAME,
DATA_TYPE,
IS_NULLABLE,
CHARACTER_MAXIMUM_LENGTH
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'dim_customers';
--3. Data Exploration
SELECT
MIN(order_date) AS first_order_date,
MAX(order_date) AS last_order_date,
DATEDIFF(MONTH,MIN(order_date),MAX(order_date)) AS order_range_months
FROM gold.fact_sales;
-- 4
SELECT 'Total Sales' AS measure_name,SUM(sales_amount) AS measure_value FROM gold.fact_sales
UNION ALL
SELECT 'Total Quantity' ,SUM(quantity) FROM gold.fact_sales
UNION ALL 
SELECT 'Total Orders',COUNT(DISTINCT order_number) FROM gold.fact_sales
UNION ALL 
SELECT 'Total Customers' ,COUNT(customer_key) FROM gold.dim_customers
UNION ALL 
SELECT 'Customers With Orders' ,COUNT(DISTINCT customer_key) FROM gold.fact_sales;
-- 5
SELECT
gender,
COUNT(customer_key) AS total_customers
FROM gold.dim_customers
GROUP BY gender
ORDER BY total_customers DESC;
--
SELECT
p.category,
SUM(f.sales_amount) AS total_revenue
FROM gold.fact_sales f
LEFT JOIN gold.dim_products p 
ON p.product_key = f.product_key
GROUP BY p.category
ORDER BY total_revenue DESC;
--
SELECT TOP 10
c.customer_key,
c.first_name,
c.last_name,
SUM(f.sales_amount) AS total_revenue
FROM gold.fact_sales f
LEFT JOIN gold.dim_customers c
ON c.customer_key = f.customer_key
GROUP BY c.customer_key,c.first_name,c.last_name
ORDER BY total_revenue DESC;
GO

