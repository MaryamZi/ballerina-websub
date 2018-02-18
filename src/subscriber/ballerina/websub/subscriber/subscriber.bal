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

public function main (string[] args) {
    endpoint<SubscriberConnector> subscriberEP {
        create SubscriberConnector();
    }

    //Subscription at publisher, to all available hubs
    SubscriptionChangeRequest screq = {callback:"http://0.0.0.0:9094/subscriber/listener", leaseSeconds:60000,
                                        subscribeAtAllHubs:true, secret:"SKDFNFKGGLw35"};
    SubscriptionChangeResponse scresp;
    WebSubError wse;
    scresp, wse = subscriberEP.subscribe("http://localhost:9090/registration/register", screq);
    if (wse == null) {
        println(scresp.subscriptionChangeRequestSuccessfulHubs);
    } else {
        println(wse.errorMessage);
    }

    //Unsubscription at hubs
    //HubSubscriptionChangeRequest hscreq = {callback:"http://0.0.0.0:9090/subscriber/listener",
    //                                         hubs:["http://0.0.0.0:9092/hub/changeSubscription"],
    //                                      topic:"http://temp.checkTwo"};
    //SubscriptionChangeResponse scresp;
    //WebSubError wse;
    //scresp, wse = subscriberEP.unsubscribeAtHubs(hscreq);
    //if (wse == null) {
    //    println(scresp.subscriptionChangeRequestSuccessfulHubs);
    //}

    //Subscription at hubs
    //HubSubscriptionChangeRequest hscreq = {callback:"http://0.0.0.0:9094/subscriber/listener",
    //                                          hubs:["http://0.0.0.0:9093/hub/changeSubscription",
    //                                                  "http://0.0.0.0:9092/hub/changeSubscription"],
    //                                          topic:"http://temp.checkTwo", leaseSeconds:60000, secret:"DEEF@345h"};
    //SubscriptionChangeResponse scresp;
    //WebSubError wse;
    //scresp, wse = subscriberEP.subscribeAtHubs(hscreq);
    //if (wse == null) {
    //    println(scresp.subscriptionChangeRequestSuccessfulHubs);
    //}
}
