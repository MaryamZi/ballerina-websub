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

package ballerina.websub.publisher;

import ballerina.net.http;
import ballerina.log;

const string MODE_PUBLISH = "publish";
const string MODE_REGISTER = "register";
const string MODE_RETRIEVE_UPDATES = "retrieve";

@http:configuration {
    basePath:"/registration",
    port:9090
}
service<http> registrationService {

    @http:resourceConfig {
        methods:["GET", "HEAD", "POST"],
        path:"/register"
    }
    resource register (http:Connection connection, http:InRequest request) {
        http:OutResponse response = {};
        //TODO: Read from annotations
        string[] hubs = ["http://0.0.0.0:9093/hub/changeSubscription", "http://0.0.0.0:9092/hub/changeSubscription"];
        string topic = "testtopic.com";
        //TODO: TO BE MOVED
        if(request.method == "GET" || request.method == "HEAD") {
            map params = request.getQueryParams();
            var mode, _ = (string) params["hub.mode"];
            println(mode);
            if (mode == MODE_RETRIEVE_UPDATES) {
                //TODO: Return updates as appropriate
                json dummyPayload = {dummy:"value"};
                response.setJsonPayload(dummyPayload);
                response.setHeader("Content-Type", "application/json");
                println("Retrieve Mode");
            } else {
                response = addWebSubLinkHeaders(hubs, topic);
            }
            _ = connection.respond(response);
        } else {
            json payload = request.getJsonPayload();
            println(payload.toString());

            //TODO: TO BE MOVED
            boolean status = notifyHubs(hubs, topic);
            println(status);
            response.statusCode = 202;
            _ = connection.respond(response);
        }
    }
}

function addWebSubLinkHeaders (string[] hubs, string topic) (http:OutResponse) {
    http:OutResponse response = {};
    string hubLinkHeader = "";
    foreach hub in hubs {
        hubLinkHeader = hubLinkHeader + "<" + hub + "> ; rel=\"hub\", ";
    }
    response.setHeader("Link", hubLinkHeader + "<" + topic + "> ; rel=\"self\"");
    return response;
}

function notifyHubs (string[] hubs, string topic) (boolean) {
    endpoint<http:HttpClient> hubEP {
        create http:HttpClient("http://localhost:9090/", {});
    }

    http:InResponse response;
    http:HttpConnectorError err;
    foreach hub in hubs {
        println(hub);
        http:OutRequest request = {};
        http:HttpClient httpConn;
        httpConn = create http:HttpClient(hub, {});
        bind httpConn with hubEP;
        string body = "hub.mode=" + MODE_PUBLISH
                      + "&hub.topic=" + topic;
        request.setStringPayload(body);
        request.setHeader("Content-Type", "application/x-www-form-urlencoded");
        response, err = hubEP.post("", request);
        if (err != null) {
            log:printError("Notification failed for hub[" + hub +"]");
        } else {
            println(response.statusCode);
        }
    }
    return true;
}