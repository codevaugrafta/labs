import NaturalLanguage

class LanguageDetector {
    private let recognizer = NLLanguageRecognizer()

    /// Returns the BCP-47 language code for the dominant language in `text`.
    /// Defaults to "en" when detection is inconclusive.
    func detect(_ text: String) -> String {
        recognizer.reset()
        recognizer.processString(text)

        guard let language = recognizer.dominantLanguage else {
            return "en"
        }

        return language.rawValue
    }

    /// Returns the top-N language hypotheses ordered by descending confidence.
    func detectWithConfidence(_ text: String, maxResults: Int = 3) -> [(language: String, confidence: Double)] {
        recognizer.reset()
        recognizer.processString(text)

        return recognizer
            .languageHypotheses(withMaximum: maxResults)
            .map { ($0.key.rawValue, $0.value) }
            .sorted { $0.1 > $1.1 }
    }
}
