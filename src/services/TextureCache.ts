class TextureCache {
  private static instance: TextureCache;
  private cache: Map<string, HTMLImageElement> = new Map();
  private loadingPromises: Map<string, Promise<HTMLImageElement>> = new Map();
  private textureWorker: Worker | null = null;
  private isInitialized: boolean = false;
  private preloadStarted: boolean = false;
  private offscreenCanvas: OffscreenCanvas | null = null;

  private priorityTextures: Set<string> = new Set([
    'modern_keyboard_bg_texture',
    'classic_keyboard_bg_texture',
    'modern_currency_bg_texture',
    'classic_currency_bg_texture'
  ]);

  private constructor() {
    this.initWorker();
    this.initOffscreenCanvas();
  }

  private initOffscreenCanvas() {
    if (typeof OffscreenCanvas !== 'undefined') {
      this.offscreenCanvas = new OffscreenCanvas(1, 1);
    }
  }

  private initWorker() {
    const workerCode = `
      let offscreenCanvas = null;
      let ctx = null;

      function initCanvas(width, height) {
        if (typeof OffscreenCanvas !== 'undefined') {
          offscreenCanvas = new OffscreenCanvas(width, height);
          ctx = offscreenCanvas.getContext('2d');
        }
      }

      self.onmessage = async function(e) {
        const { textureName, textureUrl, width, height } = e.data;
        
        try {
          const response = await fetch(textureUrl);
          const blob = await response.blob();
          
          // Если поддерживается OffscreenCanvas, оптимизируем текстуру
          if (typeof createImageBitmap !== 'undefined') {
            const img = await createImageBitmap(blob);
            
            if (!offscreenCanvas) {
              initCanvas(img.width, img.height);
            }
            
            if (ctx && offscreenCanvas) {
              offscreenCanvas.width = img.width;
              offscreenCanvas.height = img.height;
              
              // Оптимизация текстуры
              ctx.drawImage(img, 0, 0);
              const optimizedBlob = await offscreenCanvas.convertToBlob({
                type: 'image/webp',
                quality: 0.9
              });
              
              self.postMessage({ 
                type: 'success', 
                textureName, 
                blob: optimizedBlob,
                width: img.width,
                height: img.height
              });
            } else {
              self.postMessage({ type: 'success', textureName, blob });
            }
          } else {
            self.postMessage({ type: 'success', textureName, blob });
          }
        } catch (error) {
          self.postMessage({ type: 'error', textureName, error: error.message });
        }
      };
    `;

    const blob = new Blob([workerCode], { type: 'application/javascript' });
    this.textureWorker = new Worker(URL.createObjectURL(blob));
    
    this.textureWorker.onmessage = (e) => {
      const { type, textureName, blob, width, height, error } = e.data;
      if (type === 'success') {
        const img = new Image();
        img.decoding = 'async';
        img.loading = 'eager';
        
        if (width && height) {
          img.width = width;
          img.height = height;
        }
        
        img.src = URL.createObjectURL(blob);
        this.cache.set(textureName, img);
        this.loadingPromises.delete(textureName);
        
        if (this.priorityTextures.has(textureName)) {
          console.log(`✅ Текстура ${textureName} предзагружена в кэш`);
        }
      } else {
        console.error(`❌ Ошибка загрузки текстуры ${textureName}:`, error);
        this.loadingPromises.delete(textureName);
      }
    };
  }

  static getInstance(): TextureCache {
    if (!TextureCache.instance) {
      TextureCache.instance = new TextureCache();
    }
    return TextureCache.instance;
  }

  async initialize(): Promise<void> {
    if (this.isInitialized) return;
    
    // Загружаем приоритетные текстуры в фоне при первой инициализации
    if (!this.preloadStarted) {
      this.preloadStarted = true;
      
      if ('requestIdleCallback' in window) {
        requestIdleCallback(() => {
          this.preloadPriorityTextures();
        }, { timeout: 1000 });
      } else {
        setTimeout(() => {
          this.preloadPriorityTextures();
        }, 100);
      }
    }

    this.isInitialized = true;
  }

  async preloadPriorityTextures(): Promise<void> {
    if (this.priorityTextures.size === 0) return;
    
    console.log('TextureCache: начинаем предзагрузку всех текстур');
    
    const loadPromises = Array.from(this.priorityTextures).map(textureName => 
      this.loadTexture(textureName, true)
    );
    
    try {
      await Promise.all(loadPromises);
      console.log('TextureCache: предзагрузка текстур завершена');
    } catch (error) {
      console.error('TextureCache: ошибка при предзагрузке текстур:', error);
    }
  }

  private loadTexture(textureName: string, isPriority: boolean = false): Promise<HTMLImageElement> {
    if (this.cache.has(textureName)) {
      return Promise.resolve(this.cache.get(textureName)!);
    }

    if (this.loadingPromises.has(textureName)) {
      return this.loadingPromises.get(textureName)!;
    }

    const loadPromise = new Promise<HTMLImageElement>((resolve, reject) => {
      if (!this.textureWorker) {
        reject(new Error('Texture worker not initialized'));
        return;
      }

      const textureUrl = `/assets/textures/${textureName}.png`;
      this.textureWorker.postMessage({ 
        textureName, 
        textureUrl,
        width: window.innerWidth,
        height: window.innerHeight
      });

      let checkInterval: number;
      const maxAttempts = 100; // 5 секунд максимум
      let attempts = 0;

      const checkCache = () => {
        const texture = this.cache.get(textureName);
        if (texture) {
          clearInterval(checkInterval);
          resolve(texture);
        } else if (attempts >= maxAttempts) {
          clearInterval(checkInterval);
          reject(new Error(`Texture load timeout: ${textureName}`));
        }
        attempts++;
      };

      checkInterval = window.setInterval(checkCache, 50);
    });

    this.loadingPromises.set(textureName, loadPromise);
    return loadPromise;
  }

  async getTexture(textureName: string): Promise<HTMLImageElement> {
    await this.initialize();
    return this.loadTexture(textureName);
  }

  clearCache(): void {
    this.cache.clear();
    this.loadingPromises.clear();
    if (this.textureWorker) {
      this.textureWorker.terminate();
      this.initWorker();
    }
    if (this.offscreenCanvas) {
      this.offscreenCanvas = null;
      this.initOffscreenCanvas();
    }
    console.log('🗑️ Кэш текстур очищен');
  }
}

export default TextureCache.getInstance(); 