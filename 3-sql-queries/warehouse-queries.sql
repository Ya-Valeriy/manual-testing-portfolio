-- ============================================================
-- Файл: warehouse-queries.sql
-- Автор: Валерий Яманкин
-- Назначение: Демонстрация навыков SQL для тестирования
--             складских остатков, заказов и движений товаров.
-- База данных: PostgreSQL
-- ============================================================

-- ============================================================
-- 1. ОПИСАНИЕ СХЕМЫ ДАННЫХ (для контекста)
-- ============================================================
-- Таблицы:
-- 1. products (id, sku, name, price, min_stock, category_id)
-- 2. warehouses (id, name, location)
-- 3. inventory (id, product_id, warehouse_id, quantity, reserved_quantity)
-- 4. orders (id, user_id, status, total_amount, created_at)
-- 5. order_items (id, order_id, product_id, quantity, price_at_purchase)
-- 6. stock_movements (id, product_id, warehouse_id, type, quantity, created_at)
--    (type = 'INCOMING' - приход, 'OUTGOING' - списание/отгрузка, 'RESERVE' - резерв)
-- ============================================================


-- ============================================================
-- 2. ПРОВЕРКА ОСТАТКОВ (Inventory)
-- ============================================================

-- Запрос 2.1: Проверить остаток конкретного товара (SKU: 'SMARTPHONE_X')
-- Цель: Проверить, что в интерфейсе отображается цифра, совпадающая с БД.
SELECT 
    p.name AS product_name,
    p.sku,
    w.name AS warehouse_name,
    i.quantity AS available_quantity,
    i.reserved_quantity AS reserved,
    (i.quantity - i.reserved_quantity) AS free_quantity
FROM inventory i
JOIN products p ON i.product_id = p.id
JOIN warehouses w ON i.warehouse_id = w.id
WHERE p.sku = 'SMARTPHONE_X';


-- Запрос 2.2: Товары, которые скоро закончатся (остаток меньше минимального порога + резерв)
-- Цель: Найти позиции для дозаказа (дефицит).
SELECT 
    p.sku,
    p.name,
    SUM(i.quantity - i.reserved_quantity) AS total_free,
    p.min_stock
FROM inventory i
JOIN products p ON i.product_id = p.id
GROUP BY p.id, p.sku, p.name, p.min_stock
HAVING SUM(i.quantity - i.reserved_quantity) < p.min_stock
ORDER BY total_free ASC;


-- ============================================================
-- 3. СТАТИСТИКА ЗАКАЗОВ (Orders)
-- ============================================================

-- Запрос 3.1: Проверить сумму и количество позиций в конкретном заказе №12345
-- Цель: Сверить итоговую сумму корзины с суммой позиций (найти расхождения).
SELECT 
    o.id AS order_id,
    o.status,
    o.total_amount AS total_from_orders_table,
    SUM(oi.quantity * oi.price_at_purchase) AS calculated_total,
    COUNT(oi.id) AS items_count
FROM orders o
JOIN order_items oi ON o.id = oi.order_id
WHERE o.id = 12345
GROUP BY o.id, o.status, o.total_amount;


-- Запрос 3.2: Количество заказов по статусам за сегодня
-- Цель: Проверить метрики на дашборде (сколько собрано, сколько отгружено).
SELECT 
    status,
    COUNT(*) AS total_orders,
    SUM(total_amount) AS revenue
FROM orders
WHERE created_at::DATE = CURRENT_DATE
GROUP BY status
ORDER BY status;


-- Запрос 3.3: Топ-5 самых продаваемых товаров за последнюю неделю
-- Цель: Проверить работу аналитики "Хиты продаж".
SELECT 
    p.sku,
    p.name,
    SUM(oi.quantity) AS total_sold
FROM order_items oi
JOIN orders o ON oi.order_id = o.id
JOIN products p ON oi.product_id = p.id
WHERE o.created_at >= (CURRENT_DATE - INTERVAL '7 days')
  AND o.status = 'DELIVERED'  -- Только завершенные заказы
GROUP BY p.id, p.sku, p.name
ORDER BY total_sold DESC
LIMIT 5;


-- ============================================================
-- 4. ПРОВЕРКА ДВИЖЕНИЙ ТОВАРОВ (Stock Movements)
-- ============================================================

-- Запрос 4.1: Лента изменений остатков для товара 'SMARTPHONE_X' за вчера
-- Цель: Аудит — проверить, не "потерялись" ли единицы товара.
SELECT 
    sm.type AS movement_type,
    sm.quantity,
    sm.created_at,
    w.name AS warehouse
FROM stock_movements sm
JOIN warehouses w ON sm.warehouse_id = w.id
JOIN products p ON sm.product_id = p.id
WHERE p.sku = 'SMARTPHONE_X'
  AND sm.created_at >= (CURRENT_DATE - INTERVAL '1 day')
ORDER BY sm.created_at DESC;


-- Запрос 4.2: Расхождение сумм (Приход минус Расход) — выявление утерянных единиц
-- Цель: Проверить, сходится ли инвентаризация. Если баланс не равен 0, значит, есть ошибка.
SELECT 
    p.sku,
    p.name,
    COALESCE(SUM(CASE WHEN sm.type = 'INCOMING' THEN sm.quantity ELSE 0 END), 0) AS total_in,
    COALESCE(SUM(CASE WHEN sm.type = 'OUTGOING' THEN sm.quantity ELSE 0 END), 0) AS total_out,
    COALESCE(SUM(CASE WHEN sm.type = 'INCOMING' THEN sm.quantity ELSE 0 END), 0) 
    - COALESCE(SUM(CASE WHEN sm.type = 'OUTGOING' THEN sm.quantity ELSE 0 END), 0) AS net_delta
FROM products p
LEFT JOIN stock_movements sm ON p.id = sm.product_id
WHERE p.sku = 'SMARTPHONE_X'
GROUP BY p.id, p.sku, p.name;


-- ============================================================
-- 5. ДУБЛИКАТЫ И ОЧИСТКА ДАННЫХ (Data Quality)
-- ============================================================

-- Запрос 5.1: Поиск дублирующихся SKU в таблице товаров
-- Цель: Проверить, не создали ли один и тот же товар дважды с разными ID.
SELECT 
    sku,
    COUNT(*) AS duplicates,
    array_agg(id) AS duplicate_ids
FROM products
GROUP BY sku
HAVING COUNT(*) > 1;


-- Запрос 5.2: Заказы без позиций (аномалия)
-- Цель: Найти заказы, у которых нет строк в корзине (ошибка логики).
SELECT o.id
FROM orders o
LEFT JOIN order_items oi ON o.id = oi.order_id
WHERE oi.id IS NULL;


-- ============================================================
-- 6. ПРОДВИНУТЫЙ УРОВЕНЬ (Оконные функции)
-- ============================================================

-- Запрос 6.1: Динамика остатков с накопительным итогом (Running Total)
-- Цель: Показать понимание оконных функций для сложных отчетов.
SELECT 
    p.sku,
    w.name AS warehouse,
    sm.created_at,
    sm.type,
    sm.quantity,
    SUM(CASE 
            WHEN sm.type = 'INCOMING' THEN sm.quantity 
            WHEN sm.type = 'OUTGOING' THEN -sm.quantity 
            ELSE 0 
        END) OVER (PARTITION BY p.id, w.id ORDER BY sm.created_at ROWS UNBOUNDED PRECEDING) AS cumulative_balance
FROM stock_movements sm
JOIN products p ON sm.product_id = p.id
JOIN warehouses w ON sm.warehouse_id = w.id
WHERE p.sku = 'SMARTPHONE_X'
ORDER BY sm.created_at ASC;
