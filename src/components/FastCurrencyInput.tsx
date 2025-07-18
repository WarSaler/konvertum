import React, { memo, useCallback, useRef, useState, useLayoutEffect } from 'react';

interface FastCurrencyInputProps {
  onValueChange: (value: string) => void;
  initialValue?: string;
}

const FastCurrencyInput = memo(({ onValueChange, initialValue = '' }: FastCurrencyInputProps) => {
  const inputRef = useRef<HTMLInputElement>(null);
  const [value, setValue] = useState(initialValue);
  const frameRef = useRef<number>();
  const lastUpdateRef = useRef<number>(0);
  const queuedValueRef = useRef<string | null>(null);

  // Оптимизированная функция обновления значения
  const updateValue = useCallback((newValue: string) => {
    const now = performance.now();
    
    // Если прошло менее 16.67мс (60fps) с последнего обновления
    if (now - lastUpdateRef.current < 16.67) {
      // Откладываем обновление
      queuedValueRef.current = newValue;
      
      if (frameRef.current) {
        cancelAnimationFrame(frameRef.current);
      }
      
      frameRef.current = requestAnimationFrame(() => {
        if (queuedValueRef.current !== null) {
          setValue(queuedValueRef.current);
          onValueChange(queuedValueRef.current);
          queuedValueRef.current = null;
        }
      });
    } else {
      // Обновляем немедленно
      setValue(newValue);
      onValueChange(newValue);
      lastUpdateRef.current = now;
    }
  }, [onValueChange]);

  const handleChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const newValue = e.target.value.replace(/[^0-9.]/g, '');
    if (newValue === value) return;
    
    if (newValue === '' || /^\d*\.?\d*$/.test(newValue)) {
      updateValue(newValue);
    }
  }, [value, updateValue]);

  // Очистка при размонтировании
  useLayoutEffect(() => {
    return () => {
      if (frameRef.current) {
        cancelAnimationFrame(frameRef.current);
      }
    };
  }, []);

  return (
    <input
      ref={inputRef}
      type="text"
      value={value}
      onChange={handleChange}
      placeholder="Enter amount"
      className="currency-input"
      style={{
        WebkitTapHighlightColor: 'transparent',
        touchAction: 'manipulation',
        willChange: 'transform'
      }}
    />
  );
});

FastCurrencyInput.displayName = 'FastCurrencyInput';

export default FastCurrencyInput; 