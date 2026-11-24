SELECT
    CASE
        WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
        WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
        ELSE 'N/A'
    END AS Marital_Status,

    CASE
        WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
        WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
        ELSE 'N/A'
    END AS Gender,

    COUNT(cst_id) AS Total_Unique_Customers,

    MIN(cst_create_date) AS Earliest_Signup_Date,
    MAX(cst_create_date) AS Latest_Signup_Date

FROM
(
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY CST_ID
            ORDER BY CST_CREATE_DATE DESC
        ) AS FLAG_LAST

    FROM bronze.crm_cust_info
    WHERE CST_ID IS NOT NULL

) AS T

WHERE FLAG_LAST = 1

GROUP BY
    CASE
        WHEN UPPER(TRIM(CST_MARITAL_STATUS)) = 'S' THEN 'Single'
        WHEN UPPER(TRIM(CST_MARITAL_STATUS)) = 'M' THEN 'Married'
        ELSE 'N/A'
    END,

    CASE
        WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
        WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
        ELSE 'N/A'
    END

ORDER BY
    Total_Unique_Customers DESC;