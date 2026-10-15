// Guesses the hiragana reading of each input line with the macOS Japanese tokenizer.
// Used by build_sights.py only for sights that have no reading in Wikidata or Wikipedia.
import Foundation

func reading(_ text: String) -> String {
    let tokenizer = CFStringTokenizerCreate(
        nil, text as CFString, CFRange(location: 0, length: (text as NSString).length),
        kCFStringTokenizerUnitWordBoundary, Locale(identifier: "ja") as CFLocale
    )
    var result = ""
    while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
        let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription)
        if let latin = latin as? String {
            result += latin.applyingTransform(.latinToHiragana, reverse: false) ?? latin
        }
    }
    return result
}

while let line = readLine() {
    print(reading(line))
}
