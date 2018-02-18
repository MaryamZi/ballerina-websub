A simple WebSub implementation in Ballerina.

Includes implementation of all three parties, namely:
- Subscriber
- Publisher
- Hub 

The Hub is currently based on a relational database.


This implementation supports:
- Discovery
- Subscription, Unsubscription and Re-subscription
- Publishing to/Subscribing at multiple hubs
- Direct subscription at the publisher - subscription request(s) to the hub(s) follow automatically, after discovery, 
without manual intervention
- Honouring lease values for subscriptions (expiry)
- Allowing authenticated content distribution