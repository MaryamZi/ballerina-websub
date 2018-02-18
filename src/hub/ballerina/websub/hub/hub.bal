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

package ballerina.websub.hub;

import ballerina.data.sql;
import ballerina.log;
import ballerina.mime;
import ballerina.net.http;
import ballerina.security.crypto;
import ballerina.util;

const string CONTENT_TYPE = "Content-Type";
const string MODE_SUBSCRIBE = "subscribe";
const string MODE_UNSUBSCRIBE = "unsubscribe";
const string MODE_PUBLISH = "publish";
const string MODE_REGISTER = "register";
const string MODE_RETRIEVE_UPDATES = "retrieve";
const string X_HUB_SIGNATURE = "X-Hub-Signature";
const string X_HUB_UUID = "X-Hub-Uuid";
const string X_HUB_TOPIC = "X-Hub-Topic";

const int DEFAULT_LEASE_SECONDS_VALUE = 86400000;
const string SIGNATURE_METHOD = "SHA256";

map pendingSubscriptionRequests = {};
map pendingUnsubscriptionRequests = {};
map topicResourceMap = {};

@http:configuration {
    basePath:"/hub",
    port:9092
}
service<http> hub {

    @http:resourceConfig {
        methods:["POST"],
        path:"/changeSubscription"
    }
    resource subscribe (http:Connection connection, http:InRequest request) {
        map params = request.getFormParams();
        boolean validSubscriptionRequest = validateSubscriptionRequest(params);

        http:OutResponse response = {};
        var mode, _ = (string) params["hub.mode"];
        var topic, _ = (string) params["hub.topic"];
        if (!validSubscriptionRequest && topic != null && mode != null) {
            if (mode == MODE_PUBLISH && topicResourceMap[topic] != null) {
                response.statusCode = 202;
                _ = connection.respond(response);
                any payload = retrieveUpdates(topic);
                println(payload);
                if (payload != null) {
                    distributeContent(topic, payload);
                }
            } else if (mode == MODE_REGISTER && params["resource.url"] != null) {
                response.statusCode = 202;
                _ = connection.respond(response);
                var resourceUrl, _ = (string) params["resource.url"];
                topicResourceMap[topic] = resourceUrl;
            } else {
                response.statusCode = 400;
                _ = connection.respond(response);
            }
        } else {
            response.statusCode = 202;
            _ = connection.respond(response);
        }
        if (validSubscriptionRequest) {
            var callbackUrl, _ = (string) params["hub.callback"];
            verifySubscription(callbackUrl, params);
        }
    }


}

function validateSubscriptionRequest(map params) (boolean) {
    var mode, _ = (string) params["hub.mode"];
    var topic, _ = (string) params["hub.topic"];
    var callbackUrl, _ = (string) params["hub.callback"];

    if (mode == MODE_SUBSCRIBE || mode == MODE_UNSUBSCRIBE) {
        if (topic != null && callbackUrl != null) {
            PendingSubscription pendingSubscription = { topic : topic, callback : callbackUrl };
            if (mode == MODE_SUBSCRIBE) {
                pendingSubscriptionRequests[topic + callbackUrl] = pendingSubscription;
            } else {
                pendingUnsubscriptionRequests[topic + callbackUrl] = pendingSubscription;
            }
            return true;
        }
    }
    return false;
}

function verifySubscription(string  callbackUrl, map params) {
    endpoint<http:HttpClient> callbackEP {
        create http:HttpClient(callbackUrl, {});
    }
    endpoint<sql:ClientConnector> subscriptionDB {
        create sql:ClientConnector(
        sql:DB.MYSQL, "localhost", 3306, "subscriptiondb", "wso2", "wso2", {maximumPoolSize:5});
    }

    var mode, _ = (string) params["hub.mode"];
    var topic, _ = (string) params["hub.topic"];
    var secret, _ = (string) params["hub.secret"];
    var leaseSeconds, _ = (int) params["hub.lease_seconds"];

    //measured from the time the verification request was made from the hub to the subscriber from the recommendation
    int createdAt = currentTime().time;

    if (!(leaseSeconds > 0)) {
        leaseSeconds = DEFAULT_LEASE_SECONDS_VALUE;
    }
    string challenge = util:uuid();

    http:OutRequest request = {};
    http:InResponse response = {};
    string queryParams = "hub.mode=" + mode
                  + "&hub.topic=" + topic
                  + "&hub.challenge=" + challenge
                  + "&hub.lease_seconds=" + leaseSeconds;

    response, _ = callbackEP.get("?" + queryParams, request);

    string payload = response.getStringPayload();
    string key = topic + callbackUrl;
    if (payload != challenge) {
        log:printInfo("Intent verification failed for mode: [" + mode + "], for callback URL: [" + callbackUrl
                      + "]");
    } else {
        sql:Parameter[] sqlParams = [];
        sql:Parameter para1 = {sqlType:sql:Type.VARCHAR, value:topic};
        sql:Parameter para2 = {sqlType:sql:Type.VARCHAR, value:callbackUrl};
        sql:Parameter para3 = {sqlType:sql:Type.VARCHAR, value:secret};
        sql:Parameter para4 = {sqlType:sql:Type.BIGINT, value:leaseSeconds};
        sql:Parameter para5 = {sqlType:sql:Type.BIGINT, value:createdAt};

        int ret; //TODO: take action based on ret value
        if (mode == MODE_SUBSCRIBE) {
            sqlParams = [para1, para2, para3, para4, para5, para3, para4, para5];
            ret = subscriptionDB.update("INSERT INTO subscriptions (topic,callback,secret,lease_seconds,created_at) "
                                        + "VALUES (?,?,?,?,?) ON DUPLICATE KEY UPDATE secret=?, lease_seconds=?,"
                                          + "created_at=?", sqlParams);
        } else {
            sqlParams = [para1, para2];
            ret = subscriptionDB.update("DELETE FROM subscriptions WHERE topic=? AND callback=?", sqlParams);
        }
        log:printInfo("Intent verification successful for mode: [" + mode + "], for callback URL: ["
                      + callbackUrl + "]");
    }
    if (mode == MODE_SUBSCRIBE) {
        pendingSubscriptionRequests.remove(key);
    } else {
        pendingUnsubscriptionRequests.remove(key);
    }

}

function retrieveUpdates(string topic) (any) {
    endpoint<http:HttpClient> resourceEP {
        create http:HttpClient("http://localhost:9090", {});
    }
    string resourceUrl;
    resourceUrl, _ = (string) topicResourceMap[topic];
    if (resourceUrl == null) {
        log:printError("Resource URL not known for topic: " + topic);
        return null;
    }
    http:HttpClient httpConn;
    httpConn = create http:HttpClient(resourceUrl, {});
    bind httpConn with resourceEP;

    http:OutRequest request = {};
    http:InResponse response = {};
    http:HttpConnectorError err = {};

    string queryParams = "hub.mode=" + MODE_RETRIEVE_UPDATES;
    response, err = resourceEP.get("?" + queryParams, request);
    if (err == null) {
        log:printInfo("Successfully retrieved updates");
    }

    any payload;
    string contentType = response.getHeader(CONTENT_TYPE);
    if (contentType == mime:APPLICATION_XML) {
        payload = response.getXmlPayload();
    } else if (contentType == mime:APPLICATION_JSON) {
        payload = response.getJsonPayload();
    } else {
        payload = response.getStringPayload();
    }

    if (payload == null) {
        log:printError("Error retrieving updates for topic: " + topic);
    }
    return payload;
}

function distributeContent(string topic, any payload) {
    endpoint<http:HttpClient> callbackEP {
        create http:HttpClient("http://localhost:9090/", {});
    }
    endpoint<sql:ClientConnector> subscriptionDB {
        create sql:ClientConnector(
        sql:DB.MYSQL, "localhost", 3306, "subscriptiondb", "wso2", "wso2", {maximumPoolSize:5});
    }
    http:OutRequest request = {};
    http:InResponse response = {};
    http:HttpConnectorError err = {};

    sql:Parameter[] sqlParams = [];
    int time = currentTime().time;
    sql:Parameter para1 = {sqlType:sql:Type.BIGINT, value:time};

    sqlParams = [para1];
    int ret = subscriptionDB.update("DELETE FROM subscriptions WHERE ? - lease_seconds > created_at", sqlParams);

    para1 = {sqlType:sql:Type.VARCHAR, value:topic};
    sqlParams = [para1];
    table dt = subscriptionDB.select("SELECT callback, secret FROM subscriptions WHERE topic=?", sqlParams,
                                     typeof SubscriberDetails );
    while (dt.hasNext()) {
        var subscription, _ = (SubscriberDetails) dt.getNext();
        http:HttpClient httpConn;
        httpConn = create http:HttpClient(subscription.callback, {});
        bind httpConn with callbackEP;

        type payloadType = typeof payload;
        string stringPayload;

        if (payloadType == typeof xml) {
            xml xmlPayload;
            xmlPayload, _ = (xml) payload;
            stringPayload = <string> xmlPayload;
            request.setXmlPayload(xmlPayload);
            request.setHeader(CONTENT_TYPE, mime:APPLICATION_XML);
        } if (payloadType == typeof json) {
            json jsonPayload;
            jsonPayload, _ = (json) payload;
            stringPayload = jsonPayload.toString();
            request.setJsonPayload(jsonPayload);
            request.setHeader(CONTENT_TYPE, mime:APPLICATION_JSON);
        } else {
            stringPayload, _ = (string) payload;
            request.setStringPayload(stringPayload);
            request.setHeader(CONTENT_TYPE, mime:TEXT_PLAIN); //TODO:check
        }

        string xHubSignature = SIGNATURE_METHOD + "=";
        string generatedSignature = null;
        string sha1 = "SHA1";
        string sha256 = "SHA256";
        string md5 = "MD5";
        if (sha1.equalsIgnoreCase(SIGNATURE_METHOD)) { //not recommended
            generatedSignature = crypto:getHmac(stringPayload, subscription.secret, crypto:Algorithm.SHA1);
        } else if (sha256.equalsIgnoreCase(SIGNATURE_METHOD)) {
            generatedSignature = crypto:getHmac(stringPayload, subscription.secret, crypto:Algorithm.SHA256);
        } else if (md5.equalsIgnoreCase(SIGNATURE_METHOD)) {
            generatedSignature = crypto:getHmac(stringPayload, subscription.secret, crypto:Algorithm.MD5);
        }
        xHubSignature = xHubSignature + generatedSignature;
        request.setHeader(X_HUB_SIGNATURE, xHubSignature);

        request.setHeader(X_HUB_UUID, util:uuid());
        request.setHeader(X_HUB_TOPIC, topic);
        response, err = callbackEP.post("", request);
        if (err != null) {
            log:printError("Error delievering content to: " + subscription.callback);
        }
    }

}

struct SubscriberDetails {
    string callback;
    string secret;
}

struct PendingSubscription {
    string topic;
    string callback;
}