#!/bin/bash

# Список: код валюты = код флага (по CurrencyFlag.map)
declare -A flags=(
  [USD]=us [CAD]=ca [MXN]=mx [BSD]=bs [BMD]=bm [BRL]=br [ARS]=ar [CLP]=cl [COP]=co [VES]=ve
  [PEN]=pe [UYU]=uy [PYG]=py [BOB]=bo [CRC]=cr [JMD]=jm [TTD]=tt [BBD]=bb [BZD]=bz [DOP]=do
  [HTG]=ht [GTQ]=gt [HNL]=hn [NIO]=ni [PAB]=pa [SRD]=sr [AWG]=aw [ANG]=cw [GYD]=gy [MXV]=mx
  [CUP]=cu [KYD]=ky [EUR]=eu [GBP]=gb [CHF]=ch [SEK]=se [NOK]=no [DKK]=dk [CZK]=cz [PLN]=pl
  [RON]=ro [HUF]=hu [BGN]=bg [HRK]=hr [RSD]=rs [BYN]=by [MDL]=md [ISK]=is [MKD]=mk [ALL]=al
  [BAM]=ba [GIP]=gi [JEP]=je [IMP]=im [FOK]=fo [GGP]=gg [FKP]=fk [TRY]=tr [RUB]=ru [UAH]=ua
  [KZT]=kz [AZN]=az [AMD]=am [GEL]=ge [TJS]=tj [KGS]=kg [UZS]=uz [TMT]=tm [KUD]=kw [JPY]=jp
  [CNY]=cn [KRW]=kr [INR]=in [IDR]=id [PHP]=ph [SGD]=sg [THB]=th [MYR]=my [VND]=vn [HKD]=hk
  [TWD]=tw [PKR]=pk [BDT]=bd [LKR]=lk [NPR]=np [MMK]=mm [LAK]=la [KHR]=kh [BND]=bn [MNT]=mn
  [MVR]=mv [BTN]=bt [MOP]=mo [KPW]=kp [AFN]=af [AUD]=au [NZD]=nz [FJD]=fj [PGK]=pg [SBD]=sb
  [TOP]=to [VUV]=vu [WST]=ws [KID]=ki [TVD]=tv [ZAR]=za [EGP]=eg [NGN]=ng [KES]=ke [TZS]=tz
  [UGX]=ug [GHS]=gh [MAD]=ma [DZD]=dz [TND]=tn [XOF]=sn [XAF]=cm [ZMW]=zm [RWF]=rw [ETB]=et
  [GMD]=gm [GNF]=gn [MGA]=mg [MWK]=mw [MUR]=mu [NAD]=na [SCR]=sc [SLL]=sl [SZL]=sz [LSL]=ls
  [CVE]=cv [CDF]=cd [KMF]=km [LRD]=lr [LYD]=ly [SDG]=sd [SSP]=ss [STN]=st [MRU]=mr [MZN]=mz
  [AOA]=ao [BIF]=bi [BWP]=bw [DJF]=dj [ERN]=er [SOS]=so [SLE]=sl [AED]=ae [SAR]=sa [QAR]=qa
  [OMR]=om [KWD]=kw [BHD]=bh [IQD]=iq [ILS]=il [JOD]=jo [LBP]=lb [SYP]=sy [YER]=ye [IRR]=ir
  [CLF]=cl [CNH]=cn [STD]=st [SVC]=sv [XCD]=ag [XPF]=pf
)

mkdir -p "Процент/Flags"

for code in \"${!flags[@]}\"; do
  flag_code=\"${flags[$code]}\"
  url=\"https://flagcdn.com/40x30/${flag_code}.png\"
  out=\"Процент/Flags/${code,,}.png\"
  echo \"Скачиваю $code ($flag_code) -> $out\"
  curl -s -o \"$out\" \"$url\"
done

echo \"Готово! Всего скачано: ${#flags[@]} флагов.\"