/*
 * Copyright 2013 Julien Viet
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import io.vertx.ceylon { Vertx }
import io.vertx.ceylon.http { HttpServer, HttpServerRequest, HttpServerResponse, textBody }
import ceylon.net.http { Header }
import ceylon.net.uri { Query, Parameter }
import ceylon.net.http.client { Response, Parser }
import ceylon.test { ... }
import ceylon.promises { Promise, Deferred }
import ceylon.collection { HashMap }
import ceylon.io { newSocketConnector, SocketAddress }
import ceylon.io.charset { ascii }
import test.io.vertx.ceylon { assertRequest, assertResolve }

void run(Anything(HttpServer) test) {
	value vertx = Vertx();
	try {
		value server = vertx.createHttpServer();
		test(server);
		Promise<Null> promise = server.close();
		assertResolve(promise);
	} finally {
		vertx.stop();
	}
}

shared test void testPath() => run(path);
shared test void testRequestHeader() => run(requestHeaders);
shared test void testQuery() => run(query);
shared test void testForm() => run(form);
shared test void testOk() => run(ok);
shared test void testParseBody() => run(parseBody);

void path(HttpServer server) {
    variable String? path = null;
    void f(HttpServerRequest req) {
        path = req.path;
        HttpServerResponse resp = req.response;
        resp.status(200);
        resp.contentType("text/html");
        resp.end("HELLO");
    }
    value a = server.requestHandler(f).listen(8080);
    assertResolve(a);
    assertRequest("http://localhost:8080/foo%20?bar");
    assertEquals("/foo%20", path);
}

void requestHeaders(HttpServer server) {
    variable String? path = null;
    value headers = Deferred<Map<String, {String+}>>();
    void f(HttpServerRequest req) {
        path = req.path;
        headers.resolve(req.headers);
        HttpServerResponse resp = req.response;
        resp.status(200);
        resp.contentType("text/html");
        resp.end("HELLO");
    }
    assertResolve(server.requestHandler(f).listen(8080));
	/*
	assertRequest {
		uri = "http://localhost:8080/";
		headers = { "foo" -> {"foo_value"} };
	};
	*/
	
	// Do it by hand as the Ceylon client does not yet support POST
	value request = "GET / HTTP/1.1\r\nfoo: foo_value1\r\nfoo: foo_value2\r\n\r\n";
	value connector = newSocketConnector(SocketAddress("localhost", 8080));
	value socket = connector.connect();
	value buffer = ascii.encode(request);
	socket.writeFully(buffer);
	Parser(socket).parseResponse();
	socket.close();
	
	Map<String, {String+}> a = assertResolve(headers);
	assertEquals(HashMap({"foo"->{"foo_value1","foo_value2"}}), a);
}

void query(HttpServer server) {
    variable Query? query = null;
    variable Map<String, {String+}>? parameters = null;
    void f(HttpServerRequest req) {
        query = req.query;
        parameters = req.queryParameters;
        HttpServerResponse resp = req.response;
        resp.status(200);
        resp.contentType("text/html");
        resp.end("HELLO");
    }
    assertResolve(server.requestHandler(f).listen(8080));
    assertRequest("http://localhost:8080/?foo=foo_value&bar=bar_value1&bar=bar_value2");
    assertEquals(Query(Parameter("foo", "foo_value"),  Parameter("bar", "bar_value1"), Parameter("bar", "bar_value2")), query);
    assertEquals(HashMap({"foo"->{"foo_value"},"bar"->{"bar_value1","bar_value2"}}), parameters);
}

void form(HttpServer server) {
    value parameters = Deferred<Map<String, {String+}>>();
    Promise<Map<String, {String+}>> p = parameters.promise;
    void f(HttpServerRequest req) {
        value form = req.formParameters;
        if (exists form) {
            parameters.resolve(form);
        } else {
            parameters.reject(Exception("No parameters"));
        }
        HttpServerResponse resp = req.response;
        resp.status(200);
        resp.contentType("text/html");
        resp.end("HELLO");
    }
    assertResolve(server.requestHandler(f).listen(8080));
    
    // Do it by hand as the Ceylon client does not yet support POST
    value request = "POST / HTTP/1.1\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: 43\r\n\r\nfoo=foo_value&bar=bar_value1&bar=bar_value2";
    value connector = newSocketConnector(SocketAddress("localhost", 8080));
    value socket = connector.connect();
    value buffer = ascii.encode(request);
    socket.writeFully(buffer);
    Parser(socket).parseResponse();
    socket.close();
    value o = assertResolve(p);
    assertEquals(HashMap({"foo"->{"foo_value"},"bar"->{"bar_value1","bar_value2"}}), o);
}

void ok(HttpServer server) {
    void f(HttpServerRequest req) {
        HttpServerResponse resp = req.response;
        resp.status(200);
        resp.headers("foo"->"foo_value","bar"->"bar_value");
        resp.contentType("text/html");
        resp.end("HELLO");
    }
    assertResolve(server.requestHandler(f).listen(8080));
    Response resp = assertRequest("http://localhost:8080");
    assertEquals(200, resp.status);
    assertEquals("text/html", resp.contentType);
    assertEquals("UTF-8", resp.charset);
    assertEquals("HELLO", resp.contents);
    Header? foo = resp.headersByName["foo"];
    if (exists foo) {
        assertEquals({"foo_value"}, foo.values);
    } else {
        fail("Was expecting the foo header");
    }
    Header? bar = resp.headersByName["bar"];
    if (exists bar) {
        assertEquals({"bar_value"}, bar.values);
    } else {
        fail("Was expecting the bar header");
    }
}

void parseBody(HttpServer server) {
    value parameters = Deferred<String>();
    Promise<String> p = parameters.promise;
    void f(HttpServerRequest req) {
        value form = req.formParameters;
        if (exists form) {
            parameters.reject(Exception("Was not expecting parameters"));
        } else {
            value text = req.parseBody(textBody);
            parameters.resolve(text);
        }
        HttpServerResponse resp = req.response;
        resp.status(200);
        resp.contentType("text/html");
        resp.end("HELLO");
    }
    assertResolve(server.requestHandler(f).listen(8080));
    
    // Do it by hand as the Ceylon client does not yet support POST
    value request = "POST / HTTP/1.1\r\nContent-Type: text/plain\r\nContent-Length: 9\r\n\r\nsome_text";
    value connector = newSocketConnector(SocketAddress("localhost", 8080));
    value socket = connector.connect();
    value buffer = ascii.encode(request);
    socket.writeFully(buffer);
    Parser(socket).parseResponse();
    socket.close();
    value o = assertResolve(p);
    assertEquals("some_text", o);
}
