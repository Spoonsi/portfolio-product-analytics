/* Проект «Секреты Тёмнолесья»
 * Цель проекта: изучить влияние характеристик игроков и их игровых персонажей
 * на покупку внутриигровой валюты «райские лепестки», а также оценить
 * активность игроков при совершении внутриигровых покупок
 *
 * Автор: Лагода Максим Вячеславович
 * Дата: 04,11,2025
*/

-- Часть 1. Исследовательский анализ данных
-- Задача 1. Исследование доли платящих игроков
-- 1.1. Доля платящих пользователей по всем данным:
SELECT
	COUNT(id) AS users_count,--общее количество игроков, зарегистрированных в игре
	(SELECT
		COUNT(id)
	FROM fantasy.users
	WHERE payer = 1) AS paying_users, --количество платящих игроков
	((SELECT
		COUNT(id)
	FROM fantasy.users
	WHERE payer = 1)::real / COUNT(id)) AS share_of_paying_users--доля платящих игроков от общего количества пользователей, зарегистрированных в игре
FROM fantasy.users;
-- 1.2. Доля платящих пользователей в разрезе расы персонажа:
WITH race_of_paying_users AS (
	SELECT
		race_id,
		COUNT(id) AS count_race_payers
	FROM fantasy.users
	WHERE payer = 1
	GROUP BY race_id
)
SELECT
	users.race_id,--раса персонажа
	count_race_payers,--количество платящих игроков этой расы
	COUNT(id),--общее количество зарегистрированных игроков этой расы
	(count_race_payers)::real / (COUNT(id)) --доля платящих игроков среди всех зарегистрированных игроков этой расы
FROM fantasy.users
INNER JOIN race_of_paying_users ON users.race_id = race_of_paying_users.race_id
GROUP BY users.race_id, count_race_payers;
-- Задача 2. Исследование внутриигровых покупок
-- 2.1. Статистические показатели по полю amount:
SELECT
	COUNT(transaction_id) AS count_transactions, --общее количество покупок
	SUM(amount) AS sum_amount,--суммарную стоимость всех покупок
	MIN(amount) AS min_amount,--минимальная стоимость покупки
	MAX(amount) AS max_amount,--максимальная стоимость покупки
	AVG(amount) AS avg_amount,--среднее значение
	PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY amount) AS median,--медиану
	STDDEV(amount) AS stand_dev --стандартное отклонение стоимости покупки
FROM fantasy.events;
-- 2.2: Аномальные нулевые покупки:
SELECT
	(SELECT
		COUNT(transaction_id)
	FROM fantasy.events
	WHERE amount = 0
	) AS zero_amount_count,
	(SELECT
		COUNT(transaction_id)
	FROM fantasy.events
	WHERE amount = 0
	)::real / COUNT(transaction_id) AS share_of_zero_amount_transactions
FROM fantasy.events;
-- 2.3: Популярные эпические предметы:
SELECT
	item_code,
	COUNT(transaction_id) AS item_sales,--Общее количество внутриигровых продаж в абсолютном значении
	COUNT(transaction_id)::real / (SELECT
		COUNT(transaction_id)
	FROM fantasy.events
	WHERE amount > 0) AS share_of_all_item_sales,--Общее количество внутриигровых продаж в относительном значении
	COUNT(DISTINCT id)::real / (SELECT
		COUNT(DISTINCT id)
	FROM fantasy.events
	WHERE amount > 0) AS share_of_all_paying_users --Доля игроков, которые хотя бы раз покупали этот предмет, от общего числа внутриигровых покупателей
FROM fantasy.events
WHERE amount > 0
GROUP BY item_code
ORDER BY item_sales DESC;
-- Часть 2. Решение ad hoc-задачи
-- Задача: Зависимость активности игроков от расы персонажа:
WITH users_per_race AS (
	SELECT
		race_id,
		COUNT(id) AS all_race_users
	FROM fantasy.users
	GROUP BY race_id
),
paying_users AS (
	SELECT
		u.race_id,
		all_race_users,
		COUNT(DISTINCT u.id) AS count_paying_users,
		COUNT(DISTINCT u.id)::real / all_race_users AS share_paying_users_of_all
	FROM fantasy.users u
	INNER JOIN users_per_race AS upr ON u.race_id = upr.race_id
	INNER JOIN fantasy.events AS e ON u.id = e.id
	WHERE amount > 0
	GROUP BY u.race_id, all_race_users
),
payer_users AS (
	SELECT
		u.race_id,
		COUNT(id) AS count_payers,
		COUNT(id)::real / count_paying_users AS share_payers_of_paying_users
	FROM fantasy.users u
	INNER JOIN paying_users AS pu ON u.race_id = pu.race_id
	WHERE payer = 1
	GROUP BY u.race_id, count_paying_users
),
users_activity AS (
	SELECT
		race_id,
		u.id,
		COUNT(transaction_id) AS transactions_count_per_user,
		AVG(amount) AS avg_user_amount,
		SUM(amount) AS sum_user_amount
	FROM fantasy.users u
	INNER JOIN fantasy.events e ON u.id = e.id
	WHERE amount > 0
	GROUP BY race_id, u.id
)
SELECT
	pu.race_id,
	all_race_users,
	count_paying_users,
	share_paying_users_of_all,
	share_payers_of_paying_users,
	AVG(transactions_count_per_user) AS avg_users_transactions,
	AVG(avg_user_amount) AS avg_of_avg_users_amount,-- оставил расчет среднего от среднего для сравнения
	AVG(sum_user_amount)::real / AVG(transactions_count_per_user) AS avg_users_amount,
	AVG(sum_user_amount) AS avg_users_sum_amount
FROM paying_users AS pu
INNER JOIN payer_users AS pyu ON pyu.race_id = pu.race_id
INNER JOIN users_activity AS ua ON pu.race_id = ua.race_id
GROUP BY pu.race_id, all_race_users, count_paying_users, share_paying_users_of_all, share_payers_of_paying_users
ORDER BY pu.race_id
