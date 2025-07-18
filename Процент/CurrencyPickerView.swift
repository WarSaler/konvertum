import SwiftUI

struct CurrencyPickerView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.presentationMode) private var presentationMode
    let selectedCode: String
    let allCodes: [String]
    let onSelect: (String) -> Void
    
    // Определяет режим: выбор или добавление
    var isAddMode: Bool {
        return selectedCode.isEmpty
    }

    @State private var searchText = ""

    private var codeNamePairs: [(code: String, name: String)] {
        allCodes.compactMap { code in
            // Фильтруем устаревшие валюты, криптовалюты, драгоценные металлы, AR и XDR
            if CurrencyFlag.isDeprecatedCurrency(code) { return nil }
            if code == "XAU" || code == "XAG" || code == "XPT" || code == "XPD" { return nil }
            if code == "XDR" || code == "AR" { return nil }
            // Криптовалюты (можно использовать список из CurrencyFlag или просто исключить все коды, которые были в isCryptoCurrency)
            if ["BTC","ETH","XRP","LTC","BCH","ADA","DOT","LINK","XLM","DOGE","UNI","AAVE","COMP","SOL","VET","THETA","EOS","TRX","XMR","XTZ","ATOM","NEO","FIL","DASH","LUNA","WAVES","XEM","KCS","ZEC","EGLD","FTT","BTCB","BTG","FLOW","USDT","USDC","BUSD","DAI","WEMIX","NEXO","1INCH","AGIX","AKT","ALGO","AMP","APE","APT","ARB","AVAX","AXS","BAKE","BAT","BNB","CAKE","CELO","CFX","CHZ","CRO","CRV","CSPR","CVX","DFI","DYDX","ENJ","ETC","EURC","FEI","FIM","FLOKI","FLR","FRAX","FTM","GALA","GMX","GNO","GRT","GUSD","HBAR","HNT","HOT","ICP","IMX","INJ","JASMY","KAS","KAVA","KDA","KLAY","KNC","LDO","LEO","LRC","LUNC","MANA","MBX","MINA","MKR","MTL","NEAR","NFT","ONE","OP","ORDI","PAXG","PEPE","POL","QNT","QTUM","RPL","RUNE","RVN","SNX","STX","SUI","TON","TWT","USDD","USDP","VAL","VED","WOO","XAUT","XBT","XCH","XEC","BSV","BTT","DCR","KSM","OKB","SAND","SHIB","SHP","SPL","TUSD","XCG","XDC","ZIL","BSW","DSR"].contains(code) { return nil }
            let currencyName = getLocalizedCurrencyName(for: code)
            return (code, currencyName)
        }
    }
    
    private var filteredPairs: [(code: String, name: String)] {
        if searchText.isEmpty {
            return codeNamePairs
        } else {
            return codeNamePairs.filter {
                $0.code.lowercased().contains(searchText.lowercased()) ||
                $0.name.lowercased().contains(searchText.lowercased())
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Поисковая строка
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(themeManager.currentTheme.textColor.opacity(0.6))
                    
                    TextField(localizationManager.localizedString("search"), text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .foregroundColor(themeManager.currentTheme.textColor)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(themeManager.currentTheme.backgroundColor.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                // Список валют без секций
                List {
                    ForEach(filteredPairs, id: \.code) { pair in
                        currencyCell(code: pair.code, name: pair.name)
                    }
                }
                .listStyle(PlainListStyle())
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
            .background(themeManager.currentTheme.backgroundColor)
            .navigationTitle(isAddMode ? localizationManager.localizedString("add_currency") : localizationManager.localizedString("select_currency"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button(localizationManager.localizedString("cancel")) {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
    
    private func currencyCell(code: String, name: String) -> some View {
        Button(action: {
            onSelect(code)
            presentationMode.wrappedValue.dismiss()
        }) {
            HStack {
                CurrencyFlag(currencyCode: code)
                    .frame(width: 32, height: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(code)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(themeManager.currentTheme.textColor)
                    
                    Text(name)
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.currentTheme.textColor.opacity(0.7))
                        .lineLimit(1)
                }
                
                Spacer()
                
                if code == selectedCode {
                    Image(systemName: "checkmark")
                        .foregroundColor(themeManager.currentTheme.textColor)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
    }
    
    // FIX: Unified method to get localized currency name
    private func getLocalizedCurrencyName(for code: String) -> String {
        // Просто возвращаем локализованное имя валюты
        let appLocale = localizationManager.currentLocale()
        if let localizedName = appLocale.localizedString(forCurrencyCode: code),
           !localizedName.isEmpty && localizedName != code {
            return localizedName
        }
        return getAdditionalCurrencyNames(for: code) ?? code
    }
    
    // Получаем название криптовалюты
    private func getCryptoName(for code: String) -> String {
        // Удалены дубликаты ключей, чтобы избежать предупреждений компилятора и ошибок отображения
        let cryptoNames: [String: String] = [
            "BTC": "Bitcoin", "ETH": "Ethereum", "USDT": "Tether", "BNB": "BNB",
            "SOL": "Solana", "USDC": "USD Coin", "XRP": "XRP", "STETH": "Lido Staked Ether",
            "DOGE": "Dogecoin", "ADA": "Cardano", "TRX": "TRON", "AVAX": "Avalanche",
            "WBTC": "Wrapped Bitcoin", "SHIB": "Shiba Inu", "LINK": "Chainlink",
            "DOT": "Polkadot", "BCH": "Bitcoin Cash", "UNI": "Uniswap", "NEAR": "NEAR Protocol",
            "LTC": "Litecoin", "MATIC": "Polygon", "ICP": "Internet Computer", "DAI": "Dai",
            "LEO": "UNUS SED LEO", "ETC": "Ethereum Classic", "APT": "Aptos", "CRO": "Cronos",
            "ATOM": "Cosmos", "MNT": "Mantle", "XMR": "Monero", "OKB": "OKB Token", "HBAR": "Hedera",
            "FIL": "Filecoin", "IMX": "Immutable X", "VET": "VeChain", "ARB": "Arbitrum",
            "OP": "Optimism", "MKR": "Maker", "INJ": "Injective", "GRT": "The Graph",
            "AAVE": "Aave", "STX": "Stacks", "RUNE": "THORChain", "ALGO": "Algorand",
            "QNT": "Quant", "SAND": "The Sandbox", "MANA": "Decentraland", "FTM": "Fantom",
            "THETA": "THETA", "FLOW": "Flow", "XTZ": "Tezos", "AXS": "Axie Infinity",
            "EGLD": "MultiversX", "CHZ": "Chiliz", "EOS": "EOS", "KAVA": "Kava", "KDA": "Kadena", "KLAY": "Klaytn", "KNC": "Kyber Network Crystal",
            "LDO": "Lido DAO", "LRC": "Loopring", "LUNC": "Terra Classic",
            "MBX": "MBX", "MINA": "Mina Protocol",
            "MTL": "Metal", "ONE": "Harmony",
            "ORDI": "Ordinals", "PAXG": "PAX Gold", "PEPE": "Pepe", "POL": "Polygon",
            "QTUM": "Qtum", "RPL": "Rocket Pool",
            "RVN": "Ravencoin", "SNX": "Synthetix", "SUI": "Sui",
            "TON": "Toncoin", "TWT": "Trust Wallet Token", "USDD": "USDD", "USDP": "Pax Dollar",
            "VAL": "Validity", "WOO": "WOO Network", "XAUT": "Tether Gold", "XBT": "Bitcoin",
            "XCH": "Chia", "XDC": "XDC Network", "XEC": "eCash",
            // Добавляем валюты, которые отображались как серые квадраты
            "BSV": "Bitcoin SV", "BTT": "BitTorrent", "DCR": "Decred", 
            "KSM": "Kusama", "SHP": "Sharpay", "SLE": "Sierra Leone Leone", "SPL": "Spell Token", 
            "TUSD": "TrueUSD", "XCG": "Xchange", "ZIL": "Zilliqa", 
            // Добавляем новые криптовалюты
            "BSW": "Biswap", "DSR": "Digital Reserve Currency", "XDR": "Special Drawing Rights"
        ]
        
        return cryptoNames[code] ?? code
    }
    
    // Получаем название драгоценного металла с локализацией
    private func getPreciousMetalName(for code: String) -> String {
        // Используем локализованные названия драгоценных металлов
        switch code {
        case "XAU":
            return localizationManager.localizedString("gold")
        case "XAG":
            return localizationManager.localizedString("silver")
        case "XPD":
            return localizationManager.localizedString("palladium")
        case "XPT":
            return localizationManager.localizedString("platinum")
        default:
            return code
        }
    }
    
    // FIX: Get additional currency names with proper localization
    private func getAdditionalCurrencyNames(for code: String) -> String? {
        // FIX: Create localized names based on app language
        let currentLang = localizationManager.currentLanguage
        
        // Language-specific currency names
        switch currentLang {
        case "ru":
            return getRussianCurrencyName(for: code)
        case "ar":
            return getArabicCurrencyName(for: code)
        case "zh-Hans", "zh-Hant":
            return getChineseCurrencyName(for: code)
        case "ja":
            return getJapaneseCurrencyName(for: code)
        case "fr":
            return getFrenchCurrencyName(for: code)
        case "de":
            return getGermanCurrencyName(for: code)
        case "es":
            return getSpanishCurrencyName(for: code)
        default:
            return getEnglishCurrencyName(for: code)
        }
    }
    
    // English currency names (default)
    private func getEnglishCurrencyName(for code: String) -> String? {
        let names: [String: String] = [
            "CUP": "Cuban Peso",
            "KYD": "Cayman Islands Dollar",
            "MXV": "Mexican Investment Unit",
            "FOK": "Faroe Islands Króna",
            "GGP": "Guernsey Pound",
            "GIP": "Gibraltar Pound",
            "IMP": "Isle of Man Pound",
            "JEP": "Jersey Pound",

            "TVD": "Tuvalu Dollar",
            "SLE": "Sierra Leone Leone",
            "XDR": "Special Drawing Rights",
            "XCD": "East Caribbean Dollar",
            "XPF": "CFP Franc",

            "CNH": "Chinese Yuan (Offshore)",
            "STD": "São Tomé and Príncipe Dobra"
        ]
        return names[code]
    }
    
    // Russian currency names
    private func getRussianCurrencyName(for code: String) -> String? {
        let names: [String: String] = [
            "CUP": "Кубинское песо",
            "KYD": "Доллар Каймановых островов",
            "MXV": "Мексиканская инвестиционная единица",
            "FOK": "Фарерская крона",
            "GGP": "Фунт Гернси",
            "GIP": "Гибралтарский фунт",
            "IMP": "Фунт острова Мэн",
            "JEP": "Фунт Джерси",

            "TVD": "Доллар Тувалу",
            "SLE": "Леоне Сьерра-Леоне",
            "XDR": "Специальные права заимствования",
            "XCD": "Восточно-карибский доллар",
            "XPF": "Франк КФП",

            "CNH": "Китайский юань (офшорный)",
            "STD": "Добра Сан-Томе и Принсипи"
        ]
        return names[code]
    }
    
    // Arabic currency names
    private func getArabicCurrencyName(for code: String) -> String? {
        let names: [String: String] = [
            "CUP": "البيزو الكوبي",
            "KYD": "دولار جزر كايمان",
            "MXV": "وحدة الاستثمار المكسيكية",
            "FOK": "كرونة جزر فارو",
            "GGP": "جنيه غيرنزي",
            "GIP": "جنيه جبل طارق",
            "IMP": "جنيه جزيرة مان",
            "JEP": "جنيه جيرزي",

            "TVD": "دولار توفالو",
            "SLE": "ليون سيراليون",
            "XDR": "حقوق السحب الخاصة",
            "XCD": "دولار شرق الكاريبي",
            "XPF": "فرنك سي إف بي",

            "CNH": "اليوان الصيني (الخارجي)",
            "STD": "دوبرا ساو تومي وبرينسيبي"
        ]
        return names[code]
    }
    
    // Chinese currency names
    private func getChineseCurrencyName(for code: String) -> String? {
        let names: [String: String] = [
            "CUP": "古巴比索",
            "KYD": "开曼群岛元",
            "MXV": "墨西哥投资单位",
            "FOK": "法罗群岛克朗",
            "GGP": "根西岛镑",
            "GIP": "直布罗陀镑",
            "IMP": "马恩岛镑",
            "JEP": "泽西岛镑",

            "TVD": "图瓦卢元",
            "SLE": "塞拉利昂利昂",
            "XDR": "特别提款权",
            "XCD": "东加勒比元",
            "XPF": "太平洋法郎",

            "CNH": "离岸人民币",
            "STD": "圣多美和普林西比多布拉"
        ]
        return names[code]
    }
    
    // Japanese currency names
    private func getJapaneseCurrencyName(for code: String) -> String? {
        let names: [String: String] = [
            "CUP": "キューバ・ペソ",
            "KYD": "ケイマン諸島・ドル",
            "MXV": "メキシコ投資単位",
            "FOK": "フェロー諸島クローナ",
            "GGP": "ガーンジー・ポンド",
            "GIP": "ジブラルタル・ポンド",
            "IMP": "マン島ポンド",
            "JEP": "ジャージー・ポンド",

            "TVD": "ツバル・ドル",
            "SLE": "シエラレオネ・レオン",
            "XDR": "特別引出権",
            "XCD": "東カリブ・ドル",
            "XPF": "CFPフラン",

            "CNH": "オフショア人民元",
            "STD": "サントメ・プリンシペ・ドブラ"
        ]
        return names[code]
    }
    
    // French currency names
    private func getFrenchCurrencyName(for code: String) -> String? {
        let names: [String: String] = [
            "CUP": "Peso cubain",
            "KYD": "Dollar des îles Caïmans",
            "MXV": "Unité d'investissement mexicaine",
            "FOK": "Couronne féroïenne",
            "GGP": "Livre de Guernesey",
            "GIP": "Livre de Gibraltar",
            "IMP": "Livre de l'île de Man",
            "JEP": "Livre de Jersey",

            "TVD": "Dollar de Tuvalu",
            "SLE": "Leone de Sierra Leone",
            "XDR": "Droits de tirage spéciaux",
            "XCD": "Dollar des Caraïbes orientales",
            "XPF": "Franc CFP",

            "CNH": "Yuan chinois (offshore)",
            "STD": "Dobra de São Tomé-et-Príncipe"
        ]
        return names[code]
    }
    
    // German currency names
    private func getGermanCurrencyName(for code: String) -> String? {
        let names: [String: String] = [
            "CUP": "Kubanischer Peso",
            "KYD": "Kaiman-Dollar",
            "MXV": "Mexikanische Investmenteinheit",
            "FOK": "Färöische Krone",
            "GGP": "Guernsey-Pfund",
            "GIP": "Gibraltar-Pfund",
            "IMP": "Isle-of-Man-Pfund",
            "JEP": "Jersey-Pfund",

            "TVD": "Tuvalu-Dollar",
            "SLE": "Leone",
            "XDR": "Sonderziehungsrechte",
            "XCD": "Ostkaribischer Dollar",
            "XPF": "CFP-Franc",

            "CNH": "Chinesischer Yuan (Offshore)",
            "STD": "São-toméischer Dobra"
        ]
        return names[code]
    }
    
    // Spanish currency names
    private func getSpanishCurrencyName(for code: String) -> String? {
        let names: [String: String] = [
            "CUP": "Peso cubano",
            "KYD": "Dólar de las Islas Caimán",
            "MXV": "Unidad de inversión mexicana",
            "FOK": "Corona feroesa",
            "GGP": "Libra de Guernsey",
            "GIP": "Libra gibraltareña",
            "IMP": "Libra de la Isla de Man",
            "JEP": "Libra de Jersey",

            "TVD": "Dólar de Tuvalu",
            "SLE": "Leone de Sierra Leona",
            "XDR": "Derechos especiales de giro",
            "XCD": "Dólar del Caribe Oriental",
            "XPF": "Franco CFP",

            "CNH": "Yuan chino (offshore)",
            "STD": "Dobra de Santo Tomé y Príncipe"
        ]
        return names[code]
    }
}
