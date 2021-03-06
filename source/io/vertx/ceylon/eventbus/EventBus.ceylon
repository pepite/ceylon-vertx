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

import org.vertx.java.core.eventbus { EventBus_=EventBus, Message_=Message }
import org.vertx.java.core { Handler_=Handler }
import org.vertx.java.core.json { JsonObject_=JsonObject }
import ceylon.promises { Promise, Deferred }
import java.lang { String_=String, Void_=Void }
import io.vertx.ceylon.interop { EventBusAdapter { registerHandler_=registerHandler, unregisterHandler_=unregisterHandler } }
import io.vertx.ceylon { Registration }
import io.vertx.ceylon.util { HandlerPromise, fromObject, toObject }
import ceylon.json { JSonObject=Object, JSonArray=Array }

"A distributed lightweight event bus which can encompass multiple vert.x instances.
 The event bus implements publish / subscribe, point to point messaging and request-response messaging.
 
 Messages sent over the event bus are represented by instances of the [[Message]] class.
 
 For publish / subscribe, messages can be published to an address using one of the `publish` methods. An
 address is a simple `String` instance.
 
 Handlers are registered against an address. There can be multiple handlers registered against each address, and a particular handler can
 be registered against multiple addresses. The event bus will route a sent message to all handlers which are
 registered against that address.
 
 For point to point messaging, messages can be sent to an address using one of the `send` methods.
 The messages will be delivered to a single handler, if one is registered on that address. If more than one
 handler is registered on the same address, Vert.x will choose one and deliver the message to that. Vert.x will
 aim to fairly distribute messages in a round-robin way, but does not guarantee strict round-robin under all
 circumstances.
 
 All messages sent over the bus are transient. On event of failure of all or part of the event bus messages
 may be lost. Applications should be coded to cope with lost messages, e.g. by resending them, and making application
 services idempotent.
 
 The order of messages received by any specific handler from a specific sender should match the order of messages
 sent from that sender.
 
 When sending a message, a reply handler can be provided. If so, it will be called when the reply from the receiver
 has been received. Reply messages can also be replied to, etc, ad infinitum
 
 Different event bus instances can be clustered together over a network, to give a single logical event bus.<p>
 Instances of EventBus are thread-safe.
 
 If handlers are registered from an event loop, they will be executed using that same event loop. If they are
 registered from outside an event loop (i.e. when using Vert.x embedded) then Vert.x will assign an event loop
 to the handler and use it to deliver messages to that handler."
by("Julien Viet")
shared class EventBus(EventBus_ delegate) {

	class RegistrableMessageAdapter<M>(String address, Anything(Message<M>) handler)
			satisfies Registration & Handler_<Message_<Object>> {
	
    	value resultHandler = HandlerPromise<Null, Void_>((Void_ s) => null);
    	shared actual Promise<Null> completed = resultHandler.promise;
    	
    	shared actual Promise<Null> cancel() {
    		value resultHandler = HandlerPromise<Null, Void_>((Void_ s) => null);
    		unregisterHandler_(delegate, address, this, resultHandler);
    		return resultHandler.promise;
    	}
    	
    	shared void register() {
    		registerHandler_(delegate, address, this, resultHandler);
    	}

    	shared actual void handle(Message_<Object> eventDelegate) {
    		String? replyAddress = eventDelegate.replyAddress();
    		Object body = eventDelegate.body();
    		void doReply(Payload body) {
    			switch(body)
    			case (is String) { eventDelegate.reply(body); }
    			case (is JSonObject) { eventDelegate.reply(fromObject(body)); }
    			else { }
    		}
    		if (is String_ body) {
    			if (is Anything(Message<String>) handler) {
    				handler(Message<String>(body.string, replyAddress, doReply)); 
    			}
    		} else if (is JsonObject_ body) {
    			if (is Anything(Message<JSonObject>) handler) {
    				handler(Message<JSonObject>(toObject(body), replyAddress, doReply)); 
    			}
    		}
    	}
	}
	
	class MessageAdapter<M>() satisfies Handler_<Message_<Object>> {
		shared Deferred<Message<M>> deferred = Deferred<Message<M>>();
		shared actual void handle(Message_<Object> eventDelegate) {
			String? replyAddress = eventDelegate.replyAddress();
			Object body = eventDelegate.body();
			void doReply(Payload body) {
				switch(body)
				case (is String) { eventDelegate.reply(body); }
				case (is JSonObject) { eventDelegate.reply(fromObject(body)); }
				else {}
			}
			if (is String_ body) {
				if (is Deferred<Message<String>> deferred) {
					Deferred<Message<String>> cast = deferred;
					cast.resolve(Message<String>(body.string, replyAddress, doReply));
				} else {
					deferred.reject(Exception("Wrong promise type for reply ``body``"));
				}
			} else if (is JsonObject_ body) {
				if (is Deferred<Message<JSonObject>> deferred) {
					Deferred<Message<JSonObject>> cast = deferred;
					cast.resolve(Message<JSonObject>(toObject(body), replyAddress, doReply));
				} else {
					deferred.reject(Exception("Wrong promise type for reply ``body``"));
				}
			} else {
				deferred.reject(Exception("Unsupported reply type ``body``"));
			}
		} 
	}

    // A promise of nothing
    object promiseOfNothing extends Promise<Nothing>() {
        shared actual Promise<Result> then__<Result>(
            <Promise<Result>(Nothing)> onFulfilled,
            <Promise<Result>(Exception)> onRejected) {
            try {
                return onRejected(Exception("No result expected"));
            } catch(Exception e) {
                return promiseOfNothing;
            }
        }
    }

	"Send a message via the event bus. The returned promise allows to receive any reply message from the recipient."
	shared Promise<Message<M>> send<M = Nothing>(
    		"The address to send it to"
    		String address,
    		"The message"
    		Payload message) {

        //
        if (`M` == `Nothing`) {
            switch (message)
            case (is String) { delegate.send(address, message); }
            case (is JSonObject) { delegate.send(address, fromObject(message)); }
            case (is JSonArray) { throw Exception(); }
            return promiseOfNothing;
        } else {
            MessageAdapter<M> adapter = MessageAdapter<M>();
            Handler_<Message_<Object>> handler = adapter;
            switch (message)
            case (is String) { delegate.send(address, message, handler); }
            case (is JSonObject) { delegate.send(address, fromObject(message), handler); }
            case (is JSonArray) { throw Exception(); }
            return adapter.deferred.promise;
        }
	}
	
	"Publish a message"
	shared void publish<M>(
    		"The address to send it to"
    		String address,
    		"The message"
    		Payload message,
    		"Reply handler will be called when any reply from the recipient is received"
    		Anything(Message<M>)? replyHandler = null) {

		switch (message)
		case (is String) { delegate.publish(address, message); }
		case (is JSonObject) { delegate.publish(address, fromObject(message)); }
		case (is JSonArray) { throw Exception(); }
	}

    "Registers a handler against the specified address. The method returns a registration whose:
     * the `completed` promise is resolved when the register has been propagated to all nodes of the event bus
     * the `cancel()` method can be called to cancel the registration"
    shared Registration registerHandler<M>(
            "The address to register it at"
            String address,
            "The handler"
            Anything(Message<M>) handler) given M satisfies Object {

        RegistrableMessageAdapter<M> handlerAdapter = RegistrableMessageAdapter<M>(address, handler);
        handlerAdapter.register();
        return handlerAdapter;
    }
}