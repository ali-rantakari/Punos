
Punos
=====

A Swift localhost mock HTTP server for writing automated tests against.

This is what it might look like to __use in a test case:__

```swift
func testLogin_HandlingOfServerErrorStatus() {

	// Tell the server to respond a certain way when it receives
	// an incoming request:
	//
    server.mockResponse(endpoint: "POST /auth/step-one", status: 200)
    server.mockJSONResponse(endpoint: "POST /auth/step-two", status: 500,
        json: "{\"error\": \"Down for good\"}")

	// Exercise the system under test — tell your networking code
	// (perhaps a “backend API consumer” object) to talk to the server,
	// and assert that the behavior is as expected:
	//
    waitForResponse(apiConsumer.login(username: "foo")) { response in
        XCTAssertFalse(response.success)
        XCTAssertEqual(response.error.description, "Down for good")

        // Assert that our API consumer performed two HTTP requests:
        XCTAssertEqual(self.server.latestRequests.count, 2)
        XCTAssertEqual(self.server.latestRequestEndpoints,
            ["POST /auth/step-one", "POST /auth/step-two"])
        XCTAssertEqual(self.server.lastRequest!.query, ["username":"foo"])
    }
}
```

Here's how you would __set it up for a test case:__

```swift
import XCTest
import Punos
@testable import MyAppModule

private let sharedServer = Punos.MockHTTPServer()

/// Base class for test cases that use a mock HTTP server.
class MockHTTPServerTestCase: XCTestCase {
	
	var server: Punos.MockHTTPServer { return sharedServer }
    let apiConsumer = MyAppModule.BackendAPIConsumer()
	
	override class func setUp() {
		super.setUp()
        if !sharedServer.isRunning {
            do {
                try sharedServer.start()
            } catch let error {
                fatalError("Could not start mock server: \(error)")
            }
        }
	}

    override func setUp() {
        super.setUp()
        apiConsumer.baseURL = "http://localhost:\(server.port)"
    }
	
    override func tearDown() {
        super.tearDown()
        server.clearAllMockingState()
    }
}
```


Current Limitations
-------------------

- HTTP keep-alive is not supported (the server responds `Connection: close` every time)
- `100 Continue` responses are never sent
- IPv6 is not supported


