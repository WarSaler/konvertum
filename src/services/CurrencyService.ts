import { useCallback, useRef } from 'react';

const CACHE_DURATION = 5 * 60 * 1000; // 5 minutes
const BATCH_DELAY = 50; // 50ms for batching requests

interface CacheEntry {
  data: any;
  timestamp: number;
}

class CurrencyService {
  private static cache: Map<string, CacheEntry> = new Map();
  private static pendingRequests: Map<string, Promise<any>> = new Map();
  private static batchTimeout: NodeJS.Timeout | null = null;
  private static batchedRequests: Set<string> = new Set();

  private static async processBatchedRequests() {
    const requests = Array.from(this.batchedRequests);
    this.batchedRequests.clear();
    
    if (requests.length === 0) return;

    try {
      const responses = await Promise.all(
        requests.map(currency =>
          fetch(`https://latest.currency-api.pages.dev/v1/currencies/${currency}.json`)
            .then(response => response.json())
            .then(data => ({ currency, data }))
        )
      );

      responses.forEach(({ currency, data }) => {
        this.cache.set(`rate_${currency}`, {
          data,
          timestamp: Date.now()
        });
      });

      return responses;
    } catch (error) {
      console.error('❌ Ошибка при получении курсов валют:', error);
      throw error;
    }
  }

  static async fetchExchangeRate(currency: string): Promise<any> {
    const cacheKey = `rate_${currency}`;
    
    // Check cache first
    const cachedData = this.cache.get(cacheKey);
    if (cachedData && (Date.now() - cachedData.timestamp) < CACHE_DURATION) {
      return cachedData.data;
    }

    // Check pending requests
    const pendingRequest = this.pendingRequests.get(cacheKey);
    if (pendingRequest) {
      return pendingRequest;
    }

    // Add to batch
    this.batchedRequests.add(currency);

    // Create new request promise
    const request = new Promise((resolve, reject) => {
      if (this.batchTimeout) {
        clearTimeout(this.batchTimeout);
      }

      this.batchTimeout = setTimeout(async () => {
        try {
          const responses = await this.processBatchedRequests();
          const response = responses?.find(r => r.currency === currency);
          if (response) {
            resolve(response.data);
          } else {
            reject(new Error('Currency data not found in batch response'));
          }
        } catch (error) {
          reject(error);
        } finally {
          this.pendingRequests.delete(cacheKey);
        }
      }, BATCH_DELAY);
    });

    this.pendingRequests.set(cacheKey, request);
    return request;
  }

  static async fetchHistoricalRates(currency: string): Promise<any> {
    const cacheKey = `history_${currency}`;
    const cachedData = this.cache.get(cacheKey);
    
    if (cachedData && (Date.now() - cachedData.timestamp) < CACHE_DURATION) {
      return cachedData.data;
    }

    const pendingRequest = this.pendingRequests.get(cacheKey);
    if (pendingRequest) {
      return pendingRequest;
    }

    const request = (async () => {
      await this.rateLimit();

      try {
        const response = await fetch(`https://api.example.com/historical/${currency}`);
        const data = await response.json();
        
        this.cache.set(cacheKey, {
          data,
          timestamp: Date.now()
        });
        
        this.pendingRequests.delete(cacheKey);
        return data;
      } catch (error) {
        this.pendingRequests.delete(cacheKey);
        console.error('❌ Ошибка при получении исторических данных:', error);
        throw error;
      }
    })();

    this.pendingRequests.set(cacheKey, request);
    return request;
  }

  static clearCache() {
    this.cache.clear();
    this.pendingRequests.clear();
    this.batchedRequests.clear();
    if (this.batchTimeout) {
      clearTimeout(this.batchTimeout);
      this.batchTimeout = null;
    }
  }
}

export const useCurrencyService = () => {
  const serviceRef = useRef<typeof CurrencyService>(CurrencyService);

  const getExchangeRate = useCallback(async (currency: string) => {
    return serviceRef.current.fetchExchangeRate(currency);
  }, []);

  const getHistoricalRates = useCallback(async (currency: string) => {
    return CurrencyService.fetchHistoricalRates(currency);
  }, []);

  const clearCache = useCallback(() => {
    serviceRef.current.clearCache();
  }, []);

  return {
    getExchangeRate,
    getHistoricalRates,
    clearCache
  };
};

export default CurrencyService; 