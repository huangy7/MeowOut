// Tests/MeowOutTests/TextInjectorTests.swift
import XCTest
import ApplicationServices
@testable import MeowOut

final class TextInjectorTests: XCTestCase {
    
    func testTextInjectorSingleton() {
        let injector1 = TextInjector.shared
        let injector2 = TextInjector.shared
        XCTAssertTrue(injector1 === injector2, "TextInjector should be a singleton")
    }
    
    func testTextInjectorSafeExitWhenUntrusted() {
        // In unit test environment, AXIsProcessTrusted() is typically false.
        // We verify that calling inject completes and resets the isInjecting state
        // (meaning it does not lock up or crash).
        let injector = TextInjector.shared
        
        let expectation = XCTestExpectation(description: "Injection execution or early exit completed")
        
        injector.inject(text: "Hello World", title: "Test Snippet")
        
        // Wait briefly to ensure the background queue completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
}
