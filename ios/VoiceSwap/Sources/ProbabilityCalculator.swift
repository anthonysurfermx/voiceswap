/**
 * ProbabilityCalculator.swift
 * BetWhisper - Win Probability + Kelly Criterion Sizing
 *
 * Pure math, no API calls. Port of lib/probability.ts.
 * Uses Agent Radar data + Polymarket prices + user bet size.
 */

import Foundation

struct ProbabilityBreakdown {
    let marketImplied: Int      // from Polymarket price
    let agentAdjustment: Double // +/- up to 10%
    let redFlagPenalty: Double  // 0 to -15%
    let marketImpact: Double    // 0 to -20% from size vs volume
}

struct ProbabilityResult {
    let winProbability: Int          // 0-100 composite score
    let recommendedSide: String?     // "Yes", "No", or nil
    let confidence: String           // "high", "medium", "low"
    let edge: Double                 // positive = we have edge
    let kellyFraction: Double        // 0-1
    let smartMoneySize: Int          // in USD
    let betAmount: Double            // user's intended bet in USD
    let breakdown: ProbabilityBreakdown
}

enum ProbabilityCalculator {

    static func calculate(
        analysis: DeepAnalysisResult,
        yesPrice: Double,
        noPrice: Double,
        betAmountUSD: Double,
        marketVolumeUSD: Double
    ) -> ProbabilityResult {

        // 1. Determine which side to evaluate based on smart money
        let evaluatingSide: String
        if analysis.smartMoneyDirection == "Yes" {
            evaluatingSide = "Yes"
        } else if analysis.smartMoneyDirection == "No" {
            evaluatingSide = "No"
        } else {
            evaluatingSide = yesPrice >= noPrice ? "Yes" : "No"
        }

        // 2. Base: Polymarket price IS the implied probability
        let marketImplied = (evaluatingSide == "Yes" ? yesPrice : noPrice) * 100

        // 3. Agent adjustment: smart money conviction, +/- up to 10%
        var agentAdjustment: Double = 0
        if analysis.smartMoneyDirection == evaluatingSide && analysis.smartMoneyPct > 50 {
            agentAdjustment = min(10, Double(analysis.smartMoneyPct - 50) / 50 * 10)
        } else if analysis.smartMoneyDirection != "Divided"
                    && analysis.smartMoneyDirection != "No Signal"
                    && analysis.smartMoneyDirection != evaluatingSide {
            agentAdjustment = -min(10, Double(analysis.smartMoneyPct - 50) / 50 * 10)
        }

        // 4. Red flag penalty
        var redFlagPenalty: Double = 0
        if analysis.agentRate >= 60 { redFlagPenalty = -10 }
        else if analysis.agentRate >= 40 { redFlagPenalty = -5 }
        if analysis.redFlags.count >= 3 { redFlagPenalty -= 5 }
        redFlagPenalty = max(-15, redFlagPenalty)

        // 5. Market impact penalty: bet size relative to market volume
        //    >5% of volume = your entry MOVES the market against you
        var marketImpact: Double = 0
        if marketVolumeUSD > 0 && betAmountUSD > 0 {
            let sizeRatio = betAmountUSD / marketVolumeUSD
            if sizeRatio >= 0.50 {
                marketImpact = -20
            } else if sizeRatio >= 0.25 {
                marketImpact = -10 - ((sizeRatio - 0.25) / 0.25) * 10
            } else if sizeRatio >= 0.05 {
                marketImpact = -2 - ((sizeRatio - 0.05) / 0.20) * 8
            }
            marketImpact = (marketImpact * 10).rounded() / 10
        }

        // 6. Composite win probability (capped 5-95)
        let rawProb = marketImplied + agentAdjustment + redFlagPenalty + marketImpact
        let winProbability = max(5, min(95, Int(rawProb.rounded())))

        // 7. Edge calculation
        let marketPrice = evaluatingSide == "Yes" ? yesPrice : noPrice
        let ourProbability = Double(winProbability) / 100
        let edge = marketPrice > 0 ? (ourProbability - marketPrice) / marketPrice : 0

        // 8. Simplified Kelly Criterion (half-Kelly, capped at 25%)
        let b = marketPrice > 0 ? (1 / marketPrice) - 1 : 0
        let p = ourProbability
        let q = 1 - p
        let kellyRaw = b > 0 ? (b * p - q) / b : 0
        let kellyFraction = max(0, min(0.25, kellyRaw * 0.5))

        // 9. Smart Money Size: Kelly fraction applied to stated amount
        let smartMoneySize: Int
        if betAmountUSD > 0 {
            smartMoneySize = max(1, Int((kellyFraction * betAmountUSD).rounded()))
        } else {
            smartMoneySize = max(1, Int((kellyFraction * 100).rounded()))
        }

        // 10. Confidence level (market impact degrades confidence)
        let confidence: String
        if edge > 0.1 && analysis.redFlags.isEmpty && marketImpact > -5 {
            confidence = "high"
        } else if edge > 0 && marketImpact > -10 {
            confidence = "medium"
        } else {
            confidence = "low"
        }

        return ProbabilityResult(
            winProbability: winProbability,
            recommendedSide: edge > 0 ? evaluatingSide : nil,
            confidence: confidence,
            edge: (edge * 1000).rounded() / 1000,
            kellyFraction: (kellyFraction * 1000).rounded() / 1000,
            smartMoneySize: smartMoneySize,
            betAmount: betAmountUSD,
            breakdown: ProbabilityBreakdown(
                marketImplied: Int(marketImplied.rounded()),
                agentAdjustment: (agentAdjustment * 10).rounded() / 10,
                redFlagPenalty: (redFlagPenalty * 10).rounded() / 10,
                marketImpact: marketImpact
            )
        )
    }
}
