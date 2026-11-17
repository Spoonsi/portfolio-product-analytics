/* Проект первого модуля: анализ данных для агентства недвижимости
 * Часть 2. Решаем ad hoc задачи
 *
 * Автор:Лагода Максим Вячеславович
 * Дата:02,12,2025
*/



-- Задача 1: Время активности объявлений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- Найдём id объявлений, которые не содержат выбросы, также оставим пропущенные данные:
filtered_id AS(
    SELECT id
    FROM real_estate.flats
    WHERE
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
-- Основной набор данных с примененными фильтрами по выбросам, датам и типу недвижимости
filtered_ads_data AS (
    SELECT
        f.*,
        a.first_day_exposition,
        a.days_exposition,
        a.last_price,
        c.city,
        a.last_price :: real / f.total_area AS price_per_sqm
    FROM real_estate.flats f
    INNER JOIN real_estate.advertisement a ON f.id = a.id
    INNER JOIN real_estate.city c ON f.city_id = c.city_id
    WHERE
        f.id IN (SELECT id FROM filtered_id)
        AND EXTRACT(YEAR FROM a.first_day_exposition) BETWEEN 2015 AND 2018
        AND f.type_id = 'F8EM'
        AND f.total_area > 0
),
-- Определим категории по скорости покупки недвижимости и тип города
categorized_data AS (
    SELECT
        *,
        CASE
            WHEN days_exposition BETWEEN 1 AND 30 THEN '1-30 days'
            WHEN days_exposition BETWEEN 31 AND 90 THEN '31-90 days'
            WHEN days_exposition BETWEEN 91 AND 180 THEN '91-180 days'
            WHEN days_exposition >= 181 THEN '181+ days'
            ELSE 'non category'
        END AS ad_activity_category,
        CASE
            WHEN city = 'Санкт-Петербург' THEN 'Санкт-Петербург'
            ELSE 'Ленинградская область'
        END AS city_type
    FROM filtered_ads_data
),
-- Агрегируем данные для каждой категории
aggregated_data AS (
    SELECT
        city_type,
        ad_activity_category,
        COUNT(id) AS count_advertisement,
        AVG(price_per_sqm) AS avg_ppm,
        AVG(total_area) AS avg_total_area,
        PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY rooms) AS rooms_median,
        PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY balcony) AS balcony_median,
        PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY floor) AS floor_median,
        AVG(ceiling_height) AS ceiling_height_avg,
        SUM(CASE WHEN rooms = 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(id) AS percent_studio,
        SUM(CASE WHEN is_apartment = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(id) AS percent_apartments,
        SUM(CASE WHEN open_plan = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(id) AS percent_open_plan,
        AVG(airports_nearest) AS airports_nearest_avg,
        PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY parks_around3000) AS parks_around3000_median,
        PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY ponds_around3000) AS ponds_around3000_median
    FROM categorized_data
    GROUP BY city_type, ad_activity_category
)
-- Финальная выборка с расчетом доли объявлений и округлением значений
SELECT
    city_type,
    ad_activity_category,
    ROUND((count_advertisement * 100.0 / SUM(count_advertisement) OVER (PARTITION BY city_type))::numeric, 2) AS share_of_ads_in_region,
    count_advertisement,
    ROUND(avg_ppm::numeric, 2) AS avg_ppm,
    ROUND(avg_total_area::numeric, 2) AS avg_total_area,
    rooms_median,
    balcony_median,
    floor_median,
    ROUND(ceiling_height_avg::numeric, 2) AS ceiling_height_avg,
    ROUND(percent_studio::numeric, 2) AS percent_studio,
    ROUND(percent_apartments::numeric, 2) AS percent_apartments,
    ROUND(percent_open_plan::numeric, 2) AS percent_open_plan,
    ROUND(airports_nearest_avg::numeric, 2) AS airports_nearest_avg,
    parks_around3000_median,
    ponds_around3000_median
FROM aggregated_data
ORDER BY city_type, ad_activity_category;

-- Задача 2: Сезонность объявлений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats
    WHERE
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
-- Подготовим исходные данные после всех фильтров.
ads_data_base AS (
    SELECT
        a.id,
        a.first_day_exposition,
        (a.first_day_exposition + a.days_exposition * INTERVAL '1 day') AS removal_date_raw,
        a.last_price,
        f.total_area,
        CASE
            WHEN f.total_area > 0
                THEN a.last_price::numeric / f.total_area
            ELSE NULL
        END AS price_per_sqm
    FROM real_estate.advertisement a
    JOIN real_estate.flats f ON a.id = f.id
    JOIN real_estate.type t ON f.type_id = t.type_id
    WHERE
        a.first_day_exposition >= DATE '2015-01-01'
        AND a.first_day_exposition < DATE '2019-01-01'
        AND lower(t.type) = 'город'
        AND f.id IN (SELECT id FROM filtered_id)
        AND f.total_area > 0
),
-- Определим общее количество объявлений для расчета процентов
total_counts_overall AS (
    SELECT
        COUNT(*) AS overall_publications,
        COUNT(CASE WHEN removal_date_raw IS NOT NULL
                        AND removal_date_raw >= DATE '2015-01-01'
                        AND removal_date_raw < DATE '2019-01-01' THEN 1 ELSE NULL END) AS overall_removals
    FROM ads_data_base
),
-- Агрегация по месяцу публикации (используем все объявления из ads_data_base)
publication_monthly AS (
    SELECT
        EXTRACT(MONTH FROM first_day_exposition) AS month_num,
        TO_CHAR(first_day_exposition, 'TMmon') AS month_name,
        COUNT(*) AS cnt_publications,
        ROUND(AVG(price_per_sqm)::numeric, 2) AS avg_price_per_sqm_publication,
        ROUND(AVG(total_area)::numeric, 2) AS avg_area_publication
    FROM ads_data_base
    GROUP BY 1, 2
),
-- Агрегация по месяцу снятия (фильтруем только те, что были сняты и попали в период)
removal_monthly AS (
    SELECT
        EXTRACT(MONTH FROM removal_date_raw) AS month_num,
        TO_CHAR(removal_date_raw, 'TMmon') AS month_name,
        COUNT(*) AS cnt_removals,
        ROUND(AVG(price_per_sqm)::numeric, 2) AS avg_price_per_sqm_removal,
        ROUND(AVG(total_area)::numeric, 2) AS avg_area_removal
    FROM ads_data_base
    WHERE
        removal_date_raw IS NOT NULL
        AND removal_date_raw >= DATE '2015-01-01'
        AND removal_date_raw < DATE '2019-01-01'
    GROUP BY 1, 2
),
-- Объединяем публикации и снятия в одну таблицу, добавляем ранги
combined_data AS (
    SELECT
        COALESCE(p.month_num, r.month_num) AS month_num,
        COALESCE(p.month_name, r.month_name) AS month_name,
        COALESCE(p.cnt_publications, 0) AS cnt_publications,
        p.avg_price_per_sqm_publication,
        p.avg_area_publication,
        RANK() OVER (ORDER BY COALESCE(p.cnt_publications, 0) DESC) AS rank_publications,
        COALESCE(r.cnt_removals, 0) AS cnt_removals,
        r.avg_price_per_sqm_removal,
        r.avg_area_removal,
        RANK() OVER (ORDER BY COALESCE(r.cnt_removals, 0) DESC) AS rank_removals
    FROM publication_monthly p
    FULL OUTER JOIN removal_monthly r ON p.month_num = r.month_num
)
-- Финальный SELECT с процентами и сортировкой по номеру месяца
SELECT
    cd.month_name,
    cd.cnt_publications,
    cd.avg_price_per_sqm_publication,
    cd.avg_area_publication,
    ROUND(cd.cnt_publications * 100.0 / tc.overall_publications, 2) AS percent_publications,
    cd.rank_publications,
    cd.cnt_removals,
    cd.avg_price_per_sqm_removal,
    cd.avg_area_removal,
    ROUND(cd.cnt_removals * 100.0 / tc.overall_removals, 2) AS percent_removals,
    cd.rank_removals
FROM combined_data cd
CROSS JOIN total_counts_overall tc
ORDER BY cd.month_num;
