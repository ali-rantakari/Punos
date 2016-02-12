
Punos
=====

A Swift localhost mock HTTP server for writing automated tests against.

This is what it might look like to __use in a test case:__

```swift
func testLogin_HandlingOfServerErrorStatus() {

	// Tell the server to respond a certain way when it receives
	// an incoming request:
	//
    server.mockResponse(endpoint: "POST /login", status: 500)

	// Exercise the system under test — tell your networking code
	// (perhaps a “backend API consumer” object) to perform a
	// request, and assert that the behavior is as expected:
	//
    waitForResponse(apiConsumer.login(username: "foo")) { response in
        XCTAssertTrue(response.isFailure)
        XCTAssertEqual(response.error.description,
            "The server is down again")
    }
}
```

Here's how you would __set it up for a test case:__

```swift
import XCTest
import Punos

private let sharedServer = Punos.MockHTTPServer()

/// Base class for test cases that use a mock HTTP server.
class MockHTTPServerTestCase: XCTestCase {
	
	var server: Punos.MockHTTPServer { return sharedServer }
	
	override class func setUp() {
		super.setUp()
        do {
            try sharedServer.start()
        } catch let error {
            fatalError("Could not start mock server: \(error)")
        }
	}
	
    override func tearDown() {
        super.tearDown()
        server.clearAllMockingState()
    }
}
```
