//
//  StubGenerator.swift
//  CucumberSwift
//
//  Created by Tyler Thompson on 8/4/18.
//  Copyright © 2018 Tyler Thompson. All rights reserved.
//

import Foundation
enum StubGenerator {
    private static func regexForTokens(_ tokens: [Lexer.Token]) -> String {
        var regex = ""
        for token in tokens {
            if case Lexer.Token.match(_, let m) = token {
                regex += NSRegularExpression
                    .escapedPattern(for: m)
                    .replacingOccurrences(of: "\\", with: "\\\\", options: [], range: nil)
                    .replacingOccurrences(of: "\"", with: "\\\"", options: [], range: nil)
            } else if case Lexer.Token.string = token {
                regex += "\\\"(.*?)\\\""
            } else if case Lexer.Token.integer = token {
                regex += "(\\\\d+)"
            }
        }
        return regex.trimmingCharacters(in: .whitespaces)
    }

    static func getStubs(for features: [Feature]) -> [(step: Step, generatedSwift: String)] {
        var lookup = [String: Method]()
        let executableSteps = features
            .taggedElements(askImplementor: false)
            .flatMap { $0.scenarios }
            .taggedElements(askImplementor: true)
            .flatMap { $0.steps }
            .sorted { $0.keyword.rawValue < $1.keyword.rawValue }

        let implementedSteps = executableSteps.filter { $0.canExecute }

        let methods = executableSteps
            .filter { !$0.canExecute }
            .reduce(into: [(step: Step, method: Method)]()) {
                let regex = regexForTokens($1.tokens)
                let stringCount = $1.tokens.filter { $0.isString() }.count
                let integerCount = $1.tokens.filter { $0.isInteger() }.count
                let matchesParameter = (stringCount > 0 || integerCount > 0) ? "matches" : "_"
                let variables = [
                    (type: "string", count: stringCount),
                    (type: "integer", count: integerCount),
                    (type: "dataTable", count: $1.dataTable != nil ? 1 : 0),
                    (type: "docString", count: $1.docString != nil ? 1 : 0)
                ]

                if let m = lookup[regex],
                   !m.keyword.contains($1.keyword) {
                    m.insertKeyword($1.keyword)
                } else {
                    let method = Method(keyword: $1.keyword, regex: regex, matchesParameter: matchesParameter, variables: variables)
                    $0.append(($1, method))
                    lookup[regex] = method
                }
            }

        return methods.map { step, method in
            let canMatchAll = implementedSteps.allSatisfy { $0.match.matches(for: method.regex).isEmpty }
            let overwrittenSteps = implementedSteps.filter { method.keyword.contains($0.keyword) && !$0.match.matches(for: method.regex).isEmpty }
            if !overwrittenSteps.isEmpty {
                method.comment = "//FIXME: WARNING: This will overwite your implementation for the step(s):\n"
                method.comment += overwrittenSteps.map { "//                \($0.keyword.toString()) \($0.match)" }.joined(separator: "\n")
                method.comment += "\n"
            }
            return (step, method.generateSwift(matchAllAllowed: canMatchAll))
        }
    }
}
