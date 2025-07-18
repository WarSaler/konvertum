#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Скрипт для загрузки корректных исторических курсов валют
с 15 июля 2024 по текущую дату из API fawazahmed0
"""

import json
import requests
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional
import os

class HistoricalDataUpdater:
    def __init__(self):
        # Базовые URL для API (правильный формат согласно документации)
        self.primary_api_base = "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@{date}/v1/currencies"
        self.fallback_api_base = "https://{date}.currency-api.pages.dev/v1/currencies"
        
        # Путь к файлу с историческими данными
        self.data_file = "/Users/konstantin/Desktop/Originals/Konverter_7.3_vibro_loc_Any_Git/Процент/preloaded_historical_data.json"
        
        # Устаревшие валюты (из CurrencyFlag.swift)
        self.deprecated_currencies = {
            "DEM", "FRF", "IEP", "PTE", "LTL", "LVL", "EEK", "ESP", "GRD", "ATS", "BEF", "CYP", "FIM", "ITL", "LUF", "SKK", "SIT",
            "ROL", "SRG", "VEB", "VEF", "MGF", "ZMK", "GHC", "BYR", "MRO", "STD", "SLL", "ZWD", "ZWG",
            "AZM", "TMM", "MZM", "CSD", "YUM", "YUD", "YUN", "ZWL", "ZWN", "ZWR", "VEF", "BYR", "LTT", "LVR", "EEK", "MRO", "GHC", "TPE",
            "AFA", "AOR", "ARL", "ARM", "ARP", "ATS", "BGL", "BOP", "BRB", "BRC", "BRE", "BRN", "BRR", "BUK", "CSK", "CYP", "DDM",
            "DEM", "ECS", "ESA", "ESB", "ESP", "FIM", "FRF", "GHC", "GRD", "GWP", "IEP", "ILP", "ITL", "LUF", "MGF", "MLF", "MTL", "MTP",
            "NLG", "PEI", "PES", "PLZ", "PTE", "RUR", "SDD", "SDP", "SIT", "SKK", "SUR", "UAK", "UGS", "UYP", "UYN", "XEU", "XFO", "XFU",
            "YUD", "YUM", "YUN", "ZAL", "ZMK", "ZRN", "ZRZ", "ZWC", "ZWD", "ZWN", "ZWR",
            "TRL", "CUC", "HT", "GT"
        }
        
        # Криптовалюты (из CurrencyPickerView.swift)
        self.crypto_currencies = {
            "BTC", "ETH", "XRP", "LTC", "BCH", "ADA", "DOT", "LINK", "XLM", "DOGE", "UNI", "AAVE", "COMP", "SOL", "VET", "THETA", "EOS", "TRX", "XMR", "XTZ", "ATOM", "NEO", "FIL", "DASH", "LUNA", "WAVES", "XEM", "KCS", "ZEC", "EGLD", "FTT", "BTCB", "BTG", "FLOW", "USDT", "USDC", "BUSD", "DAI", "WEMIX", "NEXO", "1INCH", "AGIX", "AKT", "ALGO", "AMP", "APE", "APT", "ARB", "AVAX", "AXS", "BAKE", "BAT", "BNB", "CAKE", "CELO", "CFX", "CHZ", "CRO", "CRV", "CSPR", "CVX", "DFI", "DYDX", "ENJ", "ETC", "EURC", "FEI", "FIM", "FLOKI", "FLR", "FRAX", "FTM", "GALA", "GMX", "GNO", "GRT", "GUSD", "HBAR", "HNT", "HOT", "ICP", "IMX", "INJ", "JASMY", "KAS", "KAVA", "KDA", "KLAY", "KNC", "LDO", "LEO", "LRC", "LUNC", "MANA", "MBX", "MINA", "MKR", "MTL", "NEAR", "NFT", "ONE", "OP", "ORDI", "PAXG", "PEPE", "POL", "QNT", "QTUM", "RPL", "RUNE", "RVN", "SNX", "STX", "SUI", "TON", "TWT", "USDD", "USDP", "VAL", "VED", "WOO", "XAUT", "XBT", "XCH", "XEC", "BSV", "BTT", "DCR", "KSM", "OKB", "SAND", "SHIB", "SHP", "SPL", "TUSD", "XCG", "XDC", "ZIL", "BSW", "DSR"
        }
        
        # Драгоценные металлы (исключаем из основного списка)
        self.precious_metals = {"XAU", "XAG", "XPT", "XPD"}
        
        # Специальные коды для исключения
        self.special_exclusions = {"XDR", "AR"}
        
        # Поддерживаемые валюты (фиатные)
        self.supported_currencies = {
            # Основные валюты
            "USD", "EUR", "GBP", "JPY", "CHF", "CAD", "AUD", "CNY", "SEK", "NOK", "DKK", "PLN", "CZK", "HUF", "RON", "BGN", "HRK", "RUB", "TRY",
            # Америки
            "BRL", "MXN", "ARS", "CLP", "COP", "VES", "PEN", "UYU", "PYG", "BOB", "CRC", "JMD", "TTD", "BBD", "BZD", "DOP", "HTG", "GTQ", "HNL", "NIO", "PAB", "SRD", "AWG", "ANG", "GYD", "MXV", "CUP", "KYD", "BSD", "BMD",
            # Азия
            "INR", "KRW", "SGD", "THB", "MYR", "IDR", "PHP", "VND", "HKD", "TWD", "PKR", "BDT", "LKR", "NPR", "MMK", "LAK", "KHR", "BND", "MNT", "MVR", "BTN", "MOP", "KPW", "AFN",
            # Океания
            "NZD", "FJD", "PGK", "SBD", "TOP", "VUV", "WST", "TVD",
            # Африка
            "ZAR", "EGP", "NGN", "KES", "TZS", "UGX", "GHS", "MAD", "DZD", "TND", "ZMW", "RWF", "ETB", "GMD", "GNF", "MGA", "MWK", "MUR", "NAD", "SCR", "SZL", "LSL", "CVE", "CDF", "KMF", "LRD", "LYD", "SDG", "STN", "MRU", "MZN", "AOA", "BIF", "BWP", "DJF", "ERN", "SOS", "SLE",
            # Ближний Восток
            "AED", "SAR", "QAR", "OMR", "KWD", "BHD", "IQD", "ILS", "JOD", "LBP", "SYP", "YER", "IRR",
            # СНГ и Восточная Европа
            "UAH", "BYN", "KZT", "UZS", "AZN", "AMD", "GEL", "TJS", "KGS", "TMT", "MDL", "MKD", "ALL", "BAM", "RSD", "ISK",
            # Специальные валюты
            "CNH", "STD", "SVC", "XCD", "XPF", "XOF", "XAF", "GIP", "JEP", "IMP", "FOK", "GGP", "FKP"
        }
        
        # Даты для загрузки (до текущей даты)
        self.start_date = datetime(2024, 7, 15)
        self.end_date = min(datetime.now(), datetime(2025, 7, 17))  # Ограничиваем текущей датой
        
    def get_date_range(self) -> List[datetime]:
        """Генерирует список дат для загрузки"""
        dates = []
        current_date = self.start_date
        while current_date <= self.end_date:
            dates.append(current_date)
            current_date += timedelta(days=1)
        return dates
    
    def fetch_rates_for_date(self, date: datetime) -> Optional[Dict[str, float]]:
        """Загружает курсы валют для конкретной даты"""
        date_str = date.strftime("%Y-%m-%d")
        
        # Пробуем основной API с правильным форматом URL
        primary_url = self.primary_api_base.format(date=date_str) + "/usd.json"
        try:
            response = requests.get(primary_url, timeout=15)
            if response.status_code == 200:
                data = response.json()
                if 'usd' in data:
                    return data['usd']
        except Exception as e:
            print(f"  Ошибка основного API для {date_str}: {e}")
        
        # Пробуем резервный API
        fallback_url = self.fallback_api_base.format(date=date_str) + "/usd.json"
        try:
            response = requests.get(fallback_url, timeout=15)
            if response.status_code == 200:
                data = response.json()
                if 'usd' in data:
                    return data['usd']
        except Exception as e:
            print(f"  Ошибка резервного API для {date_str}: {e}")
        
        # Если это будущая дата, пробуем получить последние доступные данные
        if date > datetime.now():
            try:
                latest_url = "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.json"
                response = requests.get(latest_url, timeout=15)
                if response.status_code == 200:
                    data = response.json()
                    if 'usd' in data:
                        print(f"  Используем последние доступные данные для {date_str}")
                        return data['usd']
            except Exception as e:
                print(f"  Ошибка получения последних данных: {e}")
        
        return None
    
    def filter_supported_currencies(self, rates: Dict[str, float]) -> Dict[str, float]:
        """Фильтрует только поддерживаемые валюты"""
        filtered = {}
        
        for currency, rate in rates.items():
            currency_upper = currency.upper()
            
            # Исключаем устаревшие валюты
            if currency_upper in self.deprecated_currencies:
                continue
                
            # Исключаем криптовалюты
            if currency_upper in self.crypto_currencies:
                continue
                
            # Исключаем драгоценные металлы
            if currency_upper in self.precious_metals:
                continue
                
            # Исключаем специальные коды
            if currency_upper in self.special_exclusions:
                continue
                
            # Включаем только поддерживаемые валюты
            if currency_upper in self.supported_currencies:
                filtered[currency_upper] = rate
        
        return filtered
    
    def load_existing_data(self) -> Dict[str, Dict[str, float]]:
        """Загружает существующие данные"""
        if os.path.exists(self.data_file):
            try:
                with open(self.data_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception as e:
                print(f"Ошибка загрузки существующих данных: {e}")
        return {}
    
    def save_data(self, data: Dict[str, Dict[str, float]]) -> None:
        """Сохраняет данные в файл"""
        try:
            # Создаем резервную копию
            if os.path.exists(self.data_file):
                backup_file = self.data_file + ".backup"
                with open(self.data_file, 'r', encoding='utf-8') as src, \
                     open(backup_file, 'w', encoding='utf-8') as dst:
                    dst.write(src.read())
            
            # Сохраняем новые данные
            with open(self.data_file, 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
            
            print(f"Данные сохранены в {self.data_file}")
        except Exception as e:
            print(f"Ошибка сохранения данных: {e}")
    
    def update_historical_data(self) -> None:
        """Основной метод для обновления исторических данных"""
        print("Начинаем загрузку исторических данных...")
        print(f"Период: {self.start_date.strftime('%Y-%m-%d')} - {self.end_date.strftime('%Y-%m-%d')}")
        
        # Очищаем старые данные и начинаем заново
        historical_data = {}
        
        # Получаем список дат
        dates = self.get_date_range()
        total_dates = len(dates)
        
        print(f"Всего дат для обработки: {total_dates}")
        
        success_count = 0
        error_count = 0
        
        for i, date in enumerate(dates, 1):
            date_str = date.strftime("%Y-%m-%d")
            
            print(f"[{i}/{total_dates}] Обрабатываем {date_str}...")
            
            # Загружаем курсы для даты
            rates = self.fetch_rates_for_date(date)
            
            if rates:
                # Фильтруем поддерживаемые валюты
                filtered_rates = self.filter_supported_currencies(rates)
                
                if filtered_rates:
                    historical_data[date_str] = filtered_rates
                    success_count += 1
                    print(f"  ✓ Загружено {len(filtered_rates)} валют")
                    
                    # Показываем курс RUB для контроля
                    if "RUB" in filtered_rates:
                        print(f"    RUB: {filtered_rates['RUB']}")
                else:
                    print(f"  ⚠ Нет поддерживаемых валют для {date_str}")
                    error_count += 1
            else:
                print(f"  ✗ Не удалось загрузить данные для {date_str}")
                error_count += 1
            
            # Пауза между запросами
            time.sleep(0.3)
            
            # Сохраняем промежуточные результаты каждые 20 дат
            if i % 20 == 0:
                print(f"Промежуточное сохранение после {i} дат...")
                self.save_data(historical_data)
        
        # Финальное сохранение
        print("\nФинальное сохранение данных...")
        self.save_data(historical_data)
        
        print(f"\n=== РЕЗУЛЬТАТЫ ===")
        print(f"Успешно обработано: {success_count} дат")
        print(f"Ошибок: {error_count} дат")
        print(f"Всего дат в файле: {len(historical_data)}")
        
        # Проверяем конкретные даты RUB
        test_dates = ["2024-07-15", "2024-07-16", "2025-07-14", "2025-07-15"]
        for test_date in test_dates:
            if test_date in historical_data and "RUB" in historical_data[test_date]:
                rub_rate = historical_data[test_date]["RUB"]
                print(f"Курс RUB на {test_date}: {rub_rate}")
        
        print("\nОбновление исторических данных завершено!")

def main():
    updater = HistoricalDataUpdater()
    updater.update_historical_data()

if __name__ == "__main__":
    main()