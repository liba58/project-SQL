--Vytvoření primární tabulky, ze které se vychází při zodpovídání dotazů

CREATE TABLE t_Libuse_Snablova_project_SQL_primary_final AS 
SELECT 
    cp1.payroll_year, 
    cp1.industry_branch_code, 
    cpib.name AS industry_name, 
    cp1.value AS salary, 
    date_part('Year', cp.date_from) AS price_year, 
    cp.category_code, 
    cp.value AS price, 
    cpc.name AS category_name,
    cpvt.name AS sort_category
FROM czechia_payroll cp1
LEFT JOIN czechia_payroll_industry_branch cpib ON cp1.industry_branch_code = cpib.code
LEFT JOIN czechia_payroll_value_type cpvt ON cp1.value_type_code = cpvt.code 
LEFT JOIN czechia_price cp ON cp1.payroll_year = date_part('year', cp.date_from)
LEFT JOIN czechia_price_category cpc ON cp.category_code = cpc.code
WHERE date_part('year', cp.date_from) IS NOT NULL
AND cpvt.name LIKE '%mzda%';

/* 1. otázka: Rostou v průběhu let mzdy ve všech odvětvích, nebo v některých klesají? 
      Nejdříve vypočítáme meziroční rozdíl mzdy v každém odvětví
*/

WITH salary_changes AS (
SELECT 
    industry_branch_code,
    industry_name,
    payroll_year, 
    round(avg(salary::Numeric), 2) AS salary,
    LAG(round(avg(salary::Numeric),2)) OVER (PARTITION BY industry_branch_code ORDER BY payroll_year) AS prev_year_salary,
    ((round(avg(salary::Numeric),2)) - LAG(round(avg(salary::Numeric),2)) OVER (PARTITION BY industry_branch_code ORDER BY payroll_year)) AS salary_change
FROM t_Libuse_Snablova_project_SQL_primary_final 
GROUP BY
	industry_branch_code,
	industry_name,
	payroll_year
)

-- spočítáme kolikkrát během let klesla mzda
SELECT
	industry_name,
	count(*) AS years_decline  -- počet let s poklesem
FROM
	salary_changes
WHERE
	salary_change < 0
	AND industry_name IS NOT null
GROUP BY
	industry_name
ORDER BY
	years_decline DESC;


--2. otázka: Kolik je možné si koupit litrů mléka a kilogramů chleba za první a poslední srovnatelné období v dostupných datech cen a mezd?

SELECT 
    pf.payroll_year,
    ROUND(AVG(pf.salary), 0) AS avg_salary,  
    ROUND(AVG(pf.price::numeric), 0) AS avg_price,    
    ROUND(MAX(CASE WHEN lower(category_name) LIKE '%mléko%' AND pf.price > 0 THEN pf.salary / pf.price::NUMERIC END), 0) AS liters_milk,
    ROUND(MAX(CASE WHEN lower(category_name) LIKE '%chléb%' AND pf.price > 0 THEN pf.salary / pf.price::NUMERIC END), 0) AS kg_bread
FROM t_Libuse_Snablova_project_SQL_primary_final pf
WHERE pf.payroll_year = (SELECT MIN(payroll_year) FROM t_Libuse_Snablova_project_SQL_primary_final)
   OR pf.payroll_year = (SELECT MAX(payroll_year) FROM t_Libuse_Snablova_project_SQL_primary_final)
GROUP BY pf.payroll_year
ORDER BY pf.payroll_year;

-- 3. otázka: Která kategorie potravin zdražuje nejpomaleji (je u ní nejnižší percentuální meziroční nárůst)?

-- Vytvoření indexů, aby se data rychleji načítala

CREATE INDEX idx_category_year ON t_Libuse_Snablova_project_SQL_primary_final(category_name, price_year);
CREATE INDEX idx_price ON t_Libuse_Snablova_project_SQL_primary_final(price);

WITH unique_products AS (
    SELECT 
        category_name, 
        price_year, 
        AVG(price) AS avg_price -- Průměrná cena produktu za rok
    FROM t_Libuse_Snablova_project_SQL_primary_final
    GROUP BY category_name, price_year
),
price_changes AS (
    SELECT 
        category_name,
        price_year,
        avg_price,
        LAG(avg_price) OVER (PARTITION BY category_name ORDER BY price_year) AS prev_price,
        (avg_price - LAG(avg_price) OVER (PARTITION BY category_name ORDER BY price_year)) / 
         LAG(avg_price) OVER (PARTITION BY category_name ORDER BY price_year) * 100 AS price_change
    FROM unique_products
)
SELECT 
    category_name,
    ROUND(AVG(price_change)::NUMERIC, 2) AS avg_yearly_increase -- Průměrné zdražení za rok v %
FROM price_changes
WHERE price_change IS NOT NULL
GROUP BY category_name
ORDER BY avg_yearly_increase ASC; -- Seřazení od nejnižšího růstu


--4.úkol Existuje rok, kdy ceny potravin rostly o více než 10 % oproti mzdám?

SELECT payroll_year, price_growth, salary_growth
FROM (
    SELECT 
        payroll_year,
        ROUND(((AVG(salary) - LAG(AVG(salary)) OVER (ORDER BY payroll_year)) / 
              LAG(AVG(salary)) OVER (ORDER BY payroll_year) * 100)::numeric, 2) AS salary_growth,
        ROUND(((AVG(price) - LAG(AVG(price)) OVER (ORDER BY payroll_year)) / 
              LAG(AVG(price)) OVER (ORDER BY payroll_year) * 100)::numeric, 2) AS price_growth
    FROM t_Libuse_Snablova_project_SQL_primary_final
    GROUP BY payroll_year
) sub
WHERE (price_growth - salary_growth) > 10;

-- Vytvoření primární tabulky, ze které se vychází při zodpovídání dotazu

CREATE TABLE t_Libuse_Snablova_project_SQL_secondary_final AS 
SELECT 
    e.country,
    e.year,
    e.gdp AS gdp_value,
    ROUND(AVG(cp1.value::NUMERIC), 2) AS avg_salary,  -- Průměrná mzda v daném roce
    ROUND(AVG(cp2.value)::NUMERIC, 2) AS avg_price   -- Průměrná cena potravin v daném roce
FROM economies AS e
LEFT JOIN czechia_payroll AS cp1 ON e.year = cp1.payroll_year
LEFT JOIN czechia_price AS cp2 ON e.year = date_part('year', cp2.date_from)
LEFT JOIN czechia_payroll_value_type cpvt ON cp1.value_type_code = cpvt.code
WHERE date_part('year', cp2.date_from) IS NOT NULL
AND cpvt.name LIKE '%mzda%'
AND e.country LIKE '%Cze%'
GROUP BY e.country, e.year, e.gdp
ORDER BY e.year;

--5. otázka: Má výška HDP vliv na změny ve mzdách a cenách potravin? Neboli, pokud HDP vzroste výrazněji v jednom roce, projeví se to na cenách potravin či mzdách ve stejném nebo následujícím roce výraznějším růstem?

--Porovnává růst HDP a cen potravin

WITH growth_calculations AS (
    SELECT 
        country, 
        year,
        gdp_value,
        ROUND(((gdp_value - LAG(gdp_value) OVER (PARTITION BY country ORDER BY year)) / 
              LAG(gdp_value) OVER (PARTITION BY country ORDER BY year) * 100)::numeric, 2) AS gdp_growth,
        ROUND(((avg_salary - LAG(avg_salary) OVER (PARTITION BY country ORDER BY year)) / 
              LAG(avg_salary) OVER (PARTITION BY country ORDER BY year) * 100)::numeric, 2) AS salary_growth,
        ROUND(((avg_price - LAG(avg_price) OVER (PARTITION BY country ORDER BY year)) / 
              LAG(avg_price) OVER (PARTITION BY country ORDER BY year) * 100)::numeric, 2) AS food_price_growth
    FROM t_Libuse_Snablova_project_SQL_secondary_final
)
SELECT 
    country, 
    year,
    gdp_value,
    gdp_growth,
    LAG(salary_growth) OVER (PARTITION BY country ORDER BY year) AS prev_salary_growth,
    LAG(food_price_growth) OVER (PARTITION BY country ORDER BY year) AS prev_food_price_growth
FROM growth_calculations
ORDER BY year;

-- korelační analýza
SELECT 
    corr(gdp_growth, salary_growth) AS correlation_gdp_salary,
    corr(gdp_growth, price_growth) AS correlation_gdp_price
FROM (
    SELECT 
    	year,
        ROUND(((gdp_value - LAG(gdp_value) OVER (ORDER BY year)) / 
              LAG(gdp_value) OVER (ORDER BY year) * 100)::numeric, 2) AS gdp_growth,
        ROUND(((avg_salary - LAG(avg_salary) OVER (ORDER BY year)) / 
              LAG(avg_salary) OVER (ORDER BY year) * 100)::numeric, 2) AS salary_growth,
        ROUND(((avg_price - LAG(avg_price) OVER (ORDER BY year)) / 
              LAG(avg_price) OVER (ORDER BY year) * 100)::numeric, 2) AS price_growth
    FROM t_Libuse_Snablova_project_SQL_secondary_final
) subquery;

-- 0,4 naznačuje, že HDP má určitý vliv na mzdy/ceny, ale není to silná závislost.
