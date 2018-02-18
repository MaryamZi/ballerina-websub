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
import ballerina.security.crypto;
import ballerina.mime;

@http:configuration {
    basePath:"/subscriber",
    port:9094
}
service<http> webhookListener {

    @http:resourceConfig {
        methods:["POST", "GET"],
        path:"/listener"
    }
    resource webhookListener (http:Connection connection, http:InRequest request) {
        http:OutResponse response = {};
        map params = request.getQueryParams();
        var challenge, _ = (string) params["hub.challenge"];

        if (challenge != null) {
            response = verifyIntent(request);
        } else {
            boolean successful;
            ParsedRequest parsedRequest;
            successful, parsedRequest = parseWebhookRequest(request);
            if (successful) {
                response.statusCode = 202;
                any payload = parsedRequest.payload;
                type typeOfPayload = typeof payload;
                string stringPayload;
                if (typeOfPayload == typeof json) {
                    json jsonPayload;
                    jsonPayload, _ = (json) payload;
                    stringPayload = jsonPayload.toString();
                } else if (typeOfPayload == typeof xml) {
                    xml xmlPayload;
                    xmlPayload, _ = (xml) payload;
                    stringPayload = <string> xmlPayload;
                } else {
                    stringPayload, _ = (string) payload;
                }
                log:printInfo("Webhook Listener received payload: " + stringPayload);
            } else {
                //set an error code
                response.statusCode = 400;
                log:printError("Error parsing Webhook request");
            }
        }
        _ = connection.respond(response);
    }
}

function verifyIntent(http:InRequest request) (http:OutResponse) {
    http:OutResponse response = {};
    boolean verified = false;
    map params = request.getQueryParams();
    var challenge, _ = (string) params["hub.challenge"];
    var mode, _ = (string) params["hub.mode"];
    if (mode == null) {
        verified = false;
    } else {
        //TODO: We need to check against pending subscription requests first
        verified = true;
    }

    if (verified) {
        string body = challenge;
        response.setStringPayload(body);
        response.statusCode = 202;
    } else {
        response.statusCode = 404;
    }
    return response;
}

function parseWebhookRequest(http:InRequest request) (boolean, ParsedRequest) {
    ParsedRequest parsedRequest = {};
    string secret = "SKDFNFKGGLw35"; //TODO: load from annotation/config file
    string signature;
    any payload;
    if (secret != null && request.getHeader(X_HUB_SIGNATURE) == null) {
        log:printError(X_HUB_SIGNATURE + " header not present for subscription added specifying hub.secret");
        return false, parsedRequest;
    } else if (secret == null) {
        if (request.getHeader(X_HUB_SIGNATURE) != null) {
            log:printWarn("Ignoring " + X_HUB_SIGNATURE + " value since secret is not specified.");
        }
    } else {
        string xHubSignature = (string) request.getHeader(X_HUB_SIGNATURE);
        string[] splitSignature = xHubSignature.split("=");
        string method;
        method = splitSignature[0];
        signature = xHubSignature.replace(method + "=", "");
        string generatedSignature = null;

        string stringPayload;
        string contentType = request.getHeader("Content-Type");
        if (contentType == mime:APPLICATION_XML) {
            xml xmlPayload = request.getXmlPayload();
            payload = xmlPayload;
            stringPayload = <string> xmlPayload;
        } else if (contentType == mime:APPLICATION_JSON) {
            json jsonPayload = request.getJsonPayload();
            payload = jsonPayload;
            stringPayload = jsonPayload.toString();
        } else {
            stringPayload = request.getStringPayload();
            payload = stringPayload;
        }

        string sha1 = "SHA1";
        string sha256 = "SHA256";
        string md5 = "MD5";
        if (sha1.equalsIgnoreCase(method)) { //not recommended
            generatedSignature = crypto:getHmac(stringPayload, secret, crypto:Algorithm.SHA1);
        } else if (sha256.equalsIgnoreCase(method)) {
            println(stringPayload);
            println(secret);
            generatedSignature = crypto:getHmac(stringPayload, secret, crypto:Algorithm.SHA256);
        } else if (md5.equalsIgnoreCase(method)) {
            generatedSignature = crypto:getHmac(stringPayload, secret, crypto:Algorithm.MD5);
        } else {
            log:printError("Unsupported signature method: " + method);
            return false, parsedRequest;
        }
        if (!signature.equalsIgnoreCase(generatedSignature)) {
            log:printError("Signature verification failed.");
            return false, parsedRequest;
        }
    }
    WebhookHeaders webhookHeaders = {xHubUuid:(string) request.getHeader(X_HUB_UUID),
                                        xHubTopic:request.getHeader(X_HUB_TOPIC), xHubSignature:signature};
    parsedRequest = {webhookHeaders:webhookHeaders, payload:payload};
    return true, parsedRequest;
}

struct ParsedRequest {
    WebhookHeaders webhookHeaders;
    any payload;
}

struct WebhookHeaders {
    string xHubUuid;
    string xHubTopic;
    string xHubSignature;
}