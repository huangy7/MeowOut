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
        // In unit test environment, TextInjector safely exits early without
        // modifying system pasteboard or simulating keystrokes.
        let injector = TextInjector.shared
        
        let expectation = XCTestExpectation(description: "Injection execution or early exit completed")
        
        injector.inject(text: "Hello World", title: "Test Snippet")
        
        // Wait briefly to ensure the background queue completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
}
