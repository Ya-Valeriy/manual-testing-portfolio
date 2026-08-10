import pytest
import requests

# Базовый URL и эндпоинт (можно вынести в конфиг)
BASE_URL = "https://api.demo-warehouse.ru/api/v1"
ENDPOINT_RECEIVING = f"{BASE_URL}/warehouse/receiving"

# Пример данных для запроса
payload = {
    "orderNumber": "INV-2026-001",
    "items": [
        {
            "productId": 1001,
            "quantity": 10,
            "warehouseId": 1,
            "location": "A-12"
        }
    ]
}

# Заголовки (авторизация и т.п.)
headers = {
    "Authorization": "Bearer YOUR_JWT_TOKEN",
    "Content-Type": "application/json"
}

def test_receiving_success():
    """
    Тест: Успешная приёмка товара.
    Проверяем статус-код 201, наличие operationId и корректный остаток.
    """
    # Отправка POST-запроса
    response = requests.post(ENDPOINT_RECEIVING, json=payload, headers=headers)

    # 1. Проверка статус-кода
    assert response.status_code == 201, f"Ожидался 201, получен {response.status_code}"

    # 2. Проверка наличия поля operationId в JSON-ответе
    response_data = response.json()
    assert "operationId" in response_data, "В ответе отсутствует поле operationId"

    # 3. Проверка значения newQuantity (ожидаем 10)
    assert response_data.get("newQuantity") == 10, \
        f"newQuantity должен быть 10, получен {response_data.get('newQuantity')}"

    # Дополнительно можно вывести ID операции для отладки
    print(f"Операция выполнена, ID: {response_data['operationId']}")
