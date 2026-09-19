import XCTest
import SwiftUI
@testable import MeowOut

final class SparklineTests: XCTestCase {
    func testPointsCalculation() {
        let values: [Double] = [0.0, 50.0, 100.0]
        let size = CGSize(width: 200, height: 40)
        let points = Sparkline.calculatePoints(values: values, size: size, baselineY: 39.5, maxValue: 100.0)
        
        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points[0].x, 0.0)
        XCTAssertEqual(points[0].y, 39.5) // value 0 -> baseline
        XCTAssertEqual(points[1].x, 100.0)
        XCTAssertEqual(points[2].x, 200.0)
        XCTAssertEqual(points[2].y, 0.5, accuracy: 0.1) // peak 100 -> topY
    }

    func testPointsCalculationWithEmptyOrSingleValue() {
        let size = CGSize(width: 200, height: 40)
        XCTAssertTrue(Sparkline.calculatePoints(values: [], size: size, baselineY: 39.5, maxValue: 100.0).isEmpty)
        XCTAssertTrue(Sparkline.calculatePoints(values: [10.0], size: size, baselineY: 39.5, maxValue: 100.0).isEmpty)
    }

    func testPointsCalculationAutoPeak() {
        let values: [Double] = [0.0, 20.0]
        let size = CGSize(width: 100, height: 50)
        let points = Sparkline.calculatePoints(values: values, size: size, baselineY: 49.5, maxValue: nil)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[1].y, 0.5, accuracy: 0.1) // 20 is peak
    }

    func testPointsCalculationWithZeroOrNegativeSize() {
        let values = [10.0, 20.0, 30.0]
        XCTAssertTrue(Sparkline.calculatePoints(values: values, size: .zero).isEmpty)
        XCTAssertTrue(Sparkline.calculatePoints(values: values, size: CGSize(width: 0, height: 50)).isEmpty)
        XCTAssertTrue(Sparkline.calculatePoints(values: values, size: CGSize(width: 50, height: 0)).isEmpty)
        XCTAssertTrue(Sparkline.calculatePoints(values: values, size: CGSize(width: -10, height: 50)).isEmpty)
    }

    func testPointsCalculationWithNegativeAndNaNValues() {
        let values = [-20.0, Double.nan, 50.0, Double.infinity]
        let size = CGSize(width: 300, height: 60)
        let points = Sparkline.calculatePoints(values: values, size: size, baselineY: 59.5, maxValue: 100.0)
        
        XCTAssertEqual(points.count, 4)
        // Negative and NaN become 0.0, which maps to baseline
        XCTAssertEqual(points[0].y, 59.5)
        XCTAssertEqual(points[1].y, 59.5)
        // 50.0 is half of peak (100) -> middle
        let expectedMidY = 59.5 - (59.5 - 0.5) * 0.5
        XCTAssertEqual(points[2].y, expectedMidY, accuracy: 0.1)
        // Infinity becomes 0.0 -> baseline
        XCTAssertEqual(points[3].y, 59.5)
    }

    func testPointsCalculationAllZeroWithNilMaxValue() {
        let values = [0.0, 0.0, 0.0]
        let size = CGSize(width: 100, height: 40)
        let points = Sparkline.calculatePoints(values: values, size: size, baselineY: 39.5, maxValue: nil)
        
        XCTAssertEqual(points.count, 3)
        // All points should stay at baseline without crashing or generating NaN
        for pt in points {
            XCTAssertEqual(pt.y, 39.5)
            XCTAssertFalse(pt.y.isNaN)
            XCTAssertFalse(pt.x.isNaN)
        }
    }

    func testPointsCalculationDefaultBaselineAndLineWidth() {
        let values = [0.0, 100.0]
        let size = CGSize(width: 100, height: 50)
        let points = Sparkline.calculatePoints(values: values, size: size, maxValue: 100.0, lineWidth: 2.0)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].y, 49.0) // 50 - lineWidth/2 = 49.0
        XCTAssertEqual(points[1].y, 1.0)  // lineWidth/2 = 1.0
    }
}
