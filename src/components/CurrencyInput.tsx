import React, { memo } from 'react';
import FastCurrencyInput from './FastCurrencyInput';

interface CurrencyInputProps {
  onValueChange: (value: string) => void;
  initialValue?: string;
}

const CurrencyInput = memo(({ onValueChange, initialValue }: CurrencyInputProps) => {
  return (
    <FastCurrencyInput
      onValueChange={onValueChange}
      initialValue={initialValue}
    />
  );
});

CurrencyInput.displayName = 'CurrencyInput';

export default CurrencyInput; 