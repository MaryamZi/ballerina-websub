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

public function main (string[] args) {

    //TODO: This needs to be done when a service is declared as a WebSub publisher/resource as one that is publishing
    endpoint<http:HttpClient> hubEP {
        create http:HttpClient("http://localhost:9090/", {});
    }
    string[] hubs = ["http://0.0.0.0:9093/hub/changeSubscription", "http://0.0.0.0:9092/hub/changeSubscription"];
    string topic = "testtopic.com";
    foreach hub in hubs {
        http:HttpClient httpConn;
        httpConn = create http:HttpClient(hub, {});
        bind httpConn with hubEP;
        http:OutRequest request = {};
        http:InResponse response = {};
        http:HttpConnectorError err = {};
        string body = "hub.mode=" + MODE_REGISTER
                      + "&hub.topic=" + topic
                      + "&resource.url=http://localhost:9090/registration/register";
        request.setStringPayload(body);
        request.setHeader("Content-Type", "application/x-www-form-urlencoded");
        response, err = hubEP.post("/", request);
        if (err == null) {
            println(response.statusCode);
        } else {
            println(err);
        }
    }

}
