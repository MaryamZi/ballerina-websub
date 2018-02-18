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

const string X_HUB_UUID = "X-Hub-Uuid";
const string X_HUB_TOPIC = "X-Hub-Topic";
const string X_HUB_SIGNATURE = "X-Hub-Signature";

struct SubscriptionChangeRequest {
    string callback;
    int leaseSeconds;
    string secret;
    boolean subscribeAtAllHubs; //invalid for unsubscription - value ignored
}

struct HubSubscriptionChangeRequest {
    string[] hubs;
    string topic;
    string callback;
    int leaseSeconds;
    string secret;
}

struct SubscriptionChangeResponse {
    string[] subscriptionChangeRequestSuccessfulHubs;
    string subscribedTopic;
}

struct ResourceHubsAndTopic {
    string[] hubs;
    string topic;
}

struct WebSubError {
    string errorMessage;
}