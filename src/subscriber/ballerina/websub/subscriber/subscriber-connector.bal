// Copyright (c) 2018 WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
//
// WSO2 Inc. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

package ballerina.websub.subscriber;

import ballerina.log;
import ballerina.net.http;

const string MODE_SUBSCRIBE = "subscribe";
const string MODE_UNSUBSCRIBE = "unsubscribe";


@Description{ value : "WebSub Subscriber Client Connector allowing subscription/unsubscription to notifications."}
public connector SubscriberConnector () {

    action subscribe (string resourceUrl, SubscriptionChangeRequest subscriptionRequest)
            returns (SubscriptionChangeResponse, WebSubError) {
        return changeSubscription(MODE_SUBSCRIBE, resourceUrl, subscriptionRequest);
    }

    action unsubscribe (string resourceUrl, SubscriptionChangeRequest unsubscriptionRequest)
            returns (SubscriptionChangeResponse, WebSubError) {
        return changeSubscription(MODE_UNSUBSCRIBE, resourceUrl, unsubscriptionRequest);
    }

    action retrieveHubsAndTopic (string resourceUrl) returns (ResourceHubsAndTopic, WebSubError) {
        return retrieveHubsAndTopic(resourceUrl);
    }

    action subscribeAtHubs (HubSubscriptionChangeRequest hubSubscriptionRequest)
    returns (SubscriptionChangeResponse, WebSubError) {

        ResourceHubsAndTopic resourceHubsAndTopic = {hubs:hubSubscriptionRequest.hubs,
                                                              topic:hubSubscriptionRequest.topic};
        SubscriptionChangeRequest subscriptionRequest = {callback:hubSubscriptionRequest.callback,
                                                      leaseSeconds:hubSubscriptionRequest.leaseSeconds,
                                                      secret:hubSubscriptionRequest.secret,
                                                      subscribeAtAllHubs:true};

        return changeSubscriptionAtHubs(MODE_SUBSCRIBE, resourceHubsAndTopic, subscriptionRequest);

    }

    action unsubscribeAtHubs (HubSubscriptionChangeRequest hubUnsubscriptionRequest)
    returns (SubscriptionChangeResponse, WebSubError) {

        ResourceHubsAndTopic resourceHubsAndTopic = {hubs:hubUnsubscriptionRequest.hubs,
                                                              topic:hubUnsubscriptionRequest.topic};
        SubscriptionChangeRequest subscriptionRequest = {callback:hubUnsubscriptionRequest.callback};
        return changeSubscriptionAtHubs(MODE_UNSUBSCRIBE, resourceHubsAndTopic, subscriptionRequest);

    }

}

function changeSubscription(string mode, string resourceUrl, SubscriptionChangeRequest subscriptionChangeRequest)
            (SubscriptionChangeResponse, WebSubError) {

    SubscriptionChangeResponse subscriptionChangeResponse;
    ResourceHubsAndTopic resourceHubsAndTopic;
    WebSubError webSubError;

    resourceHubsAndTopic, webSubError = retrieveHubsAndTopic(resourceUrl);
    if (webSubError == null) {
        subscriptionChangeResponse, webSubError = changeSubscriptionAtHubs(mode, resourceHubsAndTopic,
                                                                           subscriptionChangeRequest);
    }

    return subscriptionChangeResponse, webSubError;
}

function retrieveHubsAndTopic(string resourceUrl) (ResourceHubsAndTopic, WebSubError) {
    //endpoint<http:HttpClient> resourceEP {
    //    create http:HttpClient(config:getGlobalValue("resource.url"), {});
    //}

    endpoint<http:HttpClient> resourceEP {
        create http:HttpClient(resourceUrl, {});
    }
    http:OutRequest request = {};
    http:InResponse response;
    http:HttpConnectorError err;
    response, err = resourceEP.get("", request);

    ResourceHubsAndTopic resourceHubsAndTopic;
    WebSubError webSubError;
    string linkHeader = response.getHeader("Link");
    if (linkHeader == null) {
        webSubError = {errorMessage:"No Link Header available for Resource URL[" + resourceUrl +"]"};
    } else {
        int hubIndex = 0;
        string[] hubs = [];
        string topic;
        string[] linkHeaders = linkHeader.split(",");
        foreach linkHeaderConstituent in linkHeaders {
            string[] linkHeaderConstituents = linkHeaderConstituent.split(";");
            if (linkHeaderConstituents[1] != null) {
                string url = linkHeaderConstituents[0].trim();
                url = url.replace("<", "");
                url = url.replace(">", "");
                if (linkHeaderConstituents[1].contains("rel=\"hub\"")) {
                    hubs[hubIndex] = url;
                    hubIndex = hubIndex + 1;
                } else if (linkHeaderConstituents[1].contains("rel=\"self\"")) {
                    if (topic != null) {
                        log:printError("Link Header contains >1 self URLs.");
                    } else {
                        topic = url;
                    }
                }
            } else {
                log:printError("Ignoring Link Header [" + linkHeaderConstituent + "] since type not available");
            }
        }
        if (lengthof hubs >= 1 && topic != null) {
            resourceHubsAndTopic = {hubs:hubs, topic:topic};
        } else {
            webSubError = {errorMessage:"Hub URL(s) and/or Self URL unavailable for Resource URL[" + resourceUrl + "]"};
        }
    }
    return resourceHubsAndTopic, webSubError;
}

function changeSubscriptionAtHubs(string mode, ResourceHubsAndTopic resourceHubsAndTopic,
                         SubscriptionChangeRequest subscriptionChangeRequest)
                            (SubscriptionChangeResponse, WebSubError) {
    endpoint<http:HttpClient> hubEP {
        create http:HttpClient("http://localhost:9090/", {});
    }
    string topicUrl = resourceHubsAndTopic.topic;
    string[] subscriptionChangeRequestSuccessfulAtHubs = [];
    int subscriptionChangeRequestSuccessfulHubIndex;

    http:HttpClient httpConn;
    http:OutRequest builtSubscriptionRequest;
    http:InResponse response;
    http:HttpConnectorError connectorError;
    foreach hubEndpointUrl in resourceHubsAndTopic.hubs {
        //For subscription requests, if only subscription is expected to be requested at only one hub, break after
        //sending one subscription request. Not valid for unsubscription.
        if (mode == MODE_SUBSCRIBE && !subscriptionChangeRequest.subscribeAtAllHubs
                                       && subscriptionChangeRequestSuccessfulHubIndex > 0) {
            break;
        }
        httpConn = create http:HttpClient(hubEndpointUrl, {});
        bind httpConn with hubEP;

        builtSubscriptionRequest = buildSubscriptionChangeRequest(mode, topicUrl, subscriptionChangeRequest);

        response, connectorError = hubEP.post("/", builtSubscriptionRequest);

        if (connectorError != null) {
            log:printError("Error occurred for request: Mode[" + mode + "] at Hub[" + hubEndpointUrl +"] - "
                           + connectorError.msg);
        }
        else if (response.statusCode != 202) {
            log:printError("Error in request: Mode[" + mode + "] at Hub[" + hubEndpointUrl +"] - "
                           + response.getStringPayload());
        } else {
            log:printInfo("Request successful for Mode[" + mode + "] at Hub[" + hubEndpointUrl +"]");
            subscriptionChangeRequestSuccessfulAtHubs[subscriptionChangeRequestSuccessfulHubIndex] = hubEndpointUrl;
            subscriptionChangeRequestSuccessfulHubIndex = subscriptionChangeRequestSuccessfulHubIndex + 1;
        }

    }

    SubscriptionChangeResponse subscriptionChangeResponse;
    WebSubError webSubError;
    if (lengthof subscriptionChangeRequestSuccessfulAtHubs > 0) {
        log:printInfo("Subscription Change Requests successful for "
                      + lengthof subscriptionChangeRequestSuccessfulAtHubs + " hubs");
        subscriptionChangeResponse =
        {subscriptionChangeRequestSuccessfulHubs:subscriptionChangeRequestSuccessfulAtHubs,
            subscribedTopic:resourceHubsAndTopic.topic};
    } else {
        webSubError = {errorMessage:"Subscription change request unsuccessful at all hubs"};
    }
    return subscriptionChangeResponse, webSubError;
}

function buildSubscriptionChangeRequest(string mode, string topicUrl,
                                        SubscriptionChangeRequest subscriptionChangeRequest) (http:OutRequest) {
    http:OutRequest request = {};
    string body = "hub.mode=" + mode
                  + "&hub.topic=" + topicUrl
                  + "&hub.callback=" + subscriptionChangeRequest.callback;
    if (mode == MODE_SUBSCRIBE) {
        body = body + "&hub.secret=" + subscriptionChangeRequest.secret + "&hub.lease_seconds="
               + subscriptionChangeRequest.leaseSeconds;
    }
    log:printInfo(body);
    request.setStringPayload(body);
    request.setHeader("Content-Type", "application/x-www-form-urlencoded");
    return request;
}
