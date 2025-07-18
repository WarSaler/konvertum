#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Генератор предзагруженных исторических данных валют
Создает JSON файл с курсами валют за 12 месяцев до 15 июля 2025 года
"""

import json
import random
from datetime import datetime, timedelta
from typing import Dict, List

# Базовые курсы валют к USD на 15 июля 2025 года
BASE_RATES = {
    # Основные валюты
    "EUR": 0.9180, "GBP": 0.7720, "JPY": 157.85, "CHF": 0.8950, "CAD": 1.3680, "AUD": 1.4950,
    "CNY": 7.2650, "SEK": 10.7200, "NOK": 10.8500, "DKK": 6.8450, "PLN": 3.9800, "CZK": 23.1500,
    "HUF": 365.20, "RON": 4.5650, "BGN": 1.7950, "HRK": 6.9150, "RUB": 87.50, "TRY": 32.85,
    
    # Американские валюты
    "BRL": 5.4850, "MXN": 18.2500, "ARS": 985.50, "CLP": 925.75, "COP": 4125.0, "PEN": 3.7250,
    "UYU": 39.85, "PYG": 7485.0, "BOB": 6.9150, "CRC": 525.75, "JMD": 156.25, "TTD": 6.7850,
    "BBD": 2.0000, "BZD": 2.0150, "DOP": 59.75, "HTG": 132.50, "GTQ": 7.7850, "HNL": 24.65,
    "NIO": 36.85, "PAB": 1.0000, "SRD": 35.75, "AWG": 1.7900, "ANG": 1.7900, "GYD": 209.50,
    "CUP": 24.0000, "KYD": 0.8200, "BSD": 1.0000, "BMD": 1.0000,
    
    # Азиатские валюты
    "INR": 83.45, "KRW": 1385.50, "SGD": 1.3520, "THB": 36.75, "MYR": 4.6850, "IDR": 16250.0,
    "PHP": 58.45, "VND": 25450.0, "HKD": 7.8050, "TWD": 32.15, "PKR": 278.50, "BDT": 117.25,
    "LKR": 298.75, "NPR": 133.50, "MMK": 2095.0, "LAK": 21850.0, "KHR": 4085.0, "BND": 1.3520,
    "MNT": 3425.0, "MVR": 15.42, "BTN": 83.45, "MOP": 8.0250, "KPW": 900.0, "AFN": 70.25,
    
    # Океания
    "NZD": 1.6850, "FJD": 2.2450, "PGK": 3.9250, "SBD": 8.4750, "TOP": 2.3650, "VUV": 119.50,
    "WST": 2.7250, "KID": 1.4950, "TVD": 1.4950,
    
    # Африканские валюты
    "ZAR": 18.25, "EGP": 48.25, "NGN": 1615.0, "KES": 129.50, "TZS": 2485.0, "UGX": 3725.0,
    "GHS": 15.85, "MAD": 9.8750, "DZD": 134.25, "TND": 3.1250, "ZMW": 27.45, "RWF": 1285.0,
    "ETB": 58.75, "GMD": 67.25, "GNF": 8625.0, "MGA": 4525.0, "MWK": 1735.0, "MUR": 46.85,
    "NAD": 18.25, "SCR": 13.95, "SZL": 18.25, "LSL": 18.25, "CVE": 101.25, "CDF": 2825.0,
    "KMF": 451.50, "LRD": 194.75, "LYD": 4.8250, "SDG": 602.50, "SSP": 130.75, "STN": 22.85,
    "MRU": 39.75, "MZN": 63.85, "AOA": 925.50, "BIF": 2875.0, "BWP": 13.65, "DJF": 177.75,
    "ERN": 15.0000, "SOS": 571.25, "SLE": 22.85,
    
    # Ближний Восток
    "AED": 3.6730, "SAR": 3.7500, "QAR": 3.6400, "OMR": 0.3845, "KWD": 0.3075, "BHD": 0.3760,
    "IQD": 1310.0, "ILS": 3.6850, "JOD": 0.7090, "LBP": 89500.0, "SYP": 13000.0, "YER": 250.75,
    "IRR": 42000.0,
    
    # СНГ и Восточная Европа
    "UAH": 41.25, "BYN": 3.2750, "KZT": 470.50, "UZS": 12850.0, "AZN": 1.7000, "AMD": 387.50,
    "GEL": 2.7150, "TJS": 10.6500, "KGS": 84.75, "TMT": 3.5000, "MDL": 18.15, "MKD": 56.45,
    "ALL": 92.75, "BAM": 1.7950, "RSD": 107.85, "ISK": 138.25,
    
    # Дополнительные валюты
    "CLF": 0.0285, "CNH": 7.2750, "STD": 22850.0, "SVC": 8.7500, "XCD": 2.7000, "XPF": 109.50,
    "XOF": 602.50, "XAF": 602.50,
    
    # Криптовалюты (в USD)
    "BTC": 0.0000158, "ETH": 0.000298, "XRP": 1.8520, "LTC": 0.0152, "BCH": 0.00265,
    "ADA": 2.7850, "DOT": 0.1685, "LINK": 0.0785, "XLM": 9.2500, "DOGE": 7.1250,
    "UNI": 0.1285, "AAVE": 0.0125, "COMP": 0.0185, "SOL": 0.00685, "VET": 38.75,
    "THETA": 0.6850, "EOS": 1.9250, "TRX": 16.25, "XMR": 0.00685, "XTZ": 1.2850,
    "ATOM": 0.1685, "NEO": 0.0785, "FIL": 0.2150, "DASH": 0.0385, "WAVES": 0.6850,
    "XEM": 52.75, "ZEC": 0.0385, "FLOW": 0.6850, "USDT": 1.0000, "USDC": 1.0000,
    "BUSD": 1.0000, "DAI": 1.0000,
    
    # Драгоценные металлы (тройские унции)
    "XAU": 0.000408, "XAG": 0.0345, "XPT": 0.00105, "XPD": 0.00098
}

# Волатильность для разных типов валют (дневное изменение в %)
VOLATILITY = {
    # Основные валюты - низкая волатильность
    "EUR": 0.8, "GBP": 0.9, "JPY": 0.7, "CHF": 0.6, "CAD": 0.8, "AUD": 1.0,
    "CNY": 0.3, "SEK": 0.9, "NOK": 1.0, "DKK": 0.8,
    
    # Развивающиеся валюты - средняя волатильность
    "PLN": 1.2, "CZK": 1.1, "HUF": 1.3, "RON": 1.2, "BRL": 1.5, "MXN": 1.2,
    "INR": 0.8, "KRW": 1.0, "SGD": 0.7, "THB": 0.9, "ZAR": 1.8,
    
    # Высоковолатильные валюты
    "RUB": 2.5, "TRY": 3.0, "ARS": 4.0, "NGN": 2.0, "EGP": 1.5,
    
    # Криптовалюты - очень высокая волатильность
    "BTC": 8.0, "ETH": 10.0, "XRP": 12.0, "LTC": 9.0, "BCH": 11.0,
    "ADA": 13.0, "DOT": 12.0, "LINK": 11.0, "DOGE": 15.0, "SOL": 14.0,
    
    # Драгоценные металлы - низкая волатильность
    "XAU": 1.2, "XAG": 2.0, "XPT": 1.8, "XPD": 2.5
}

# Тренды для валют (положительный = укрепление к USD, отрицательный = ослабление)
TRENDS = {
    "EUR": -0.02, "GBP": -0.01, "JPY": 0.05, "CHF": -0.01, "RUB": 0.15, "TRY": 0.20,
    "BTC": -0.30, "ETH": -0.25, "XRP": -0.20, "CNY": 0.03, "INR": 0.02
}

def generate_daily_rate(base_rate: float, volatility: float, trend: float = 0.0) -> float:
    """
    Генерирует курс на основе базового курса с учетом волатильности и тренда
    """
    # Случайное изменение в пределах волатильности
    random_change = random.uniform(-volatility, volatility) / 100
    
    # Добавляем тренд (дневной)
    daily_trend = trend / 365
    
    # Применяем изменения
    new_rate = base_rate * (1 + random_change + daily_trend)
    
    return round(new_rate, 6) if new_rate < 1 else round(new_rate, 2)

def generate_historical_data() -> Dict[str, Dict[str, float]]:
    """
    Генерирует исторические данные за 12 месяцев
    """
    end_date = datetime(2025, 7, 15)
    start_date = end_date - timedelta(days=365)
    
    historical_data = {}
    current_rates = BASE_RATES.copy()
    
    current_date = start_date
    while current_date <= end_date:
        date_str = current_date.strftime("%Y-%m-%d")
        
        # Генерируем курсы для этого дня
        day_rates = {}
        for currency, base_rate in current_rates.items():
            volatility = VOLATILITY.get(currency, 1.0)
            trend = TRENDS.get(currency, 0.0)
            
            new_rate = generate_daily_rate(base_rate, volatility, trend)
            day_rates[currency] = new_rate
            current_rates[currency] = new_rate
        
        historical_data[date_str] = day_rates
        current_date += timedelta(days=1)
    
    return historical_data

def save_to_json(data: Dict, filename: str):
    """
    Сохраняет данные в JSON файл
    """
    with open(filename, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    
    print(f"✅ Данные сохранены в {filename}")
    print(f"📊 Количество дней: {len(data)}")
    print(f"💱 Количество валют: {len(next(iter(data.values())))}")

if __name__ == "__main__":
    print("🚀 Генерация исторических данных валют...")
    print(f"📅 Период: с {datetime(2024, 7, 16).strftime('%d.%m.%Y')} по {datetime(2025, 7, 15).strftime('%d.%m.%Y')}")
    
    # Генерируем данные
    historical_data = generate_historical_data()
    
    # Сохраняем в файл
    output_file = "Процент/preloaded_historical_data.json"
    save_to_json(historical_data, output_file)
    
    print("\n✨ Генерация завершена!")
    print("\n📋 Включенные валюты:")
    currencies = list(BASE_RATES.keys())
    for i in range(0, len(currencies), 10):
        print("   " + ", ".join(currencies[i:i+10]))