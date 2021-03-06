// Copyright 2020 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import <XCTest/XCTest.h>

#import "FirebasePerformance/Sources/Loggers/FPRGDTLogSampler+Private.h"
#import "FirebasePerformance/Sources/Loggers/FPRGDTLogSampler.h"

#import "FirebasePerformance/Sources/Configurations/FPRConfigurations+Private.h"
#import "FirebasePerformance/Sources/FPRProtoUtils.h"
#import "FirebasePerformance/Sources/Instrumentation/FPRNetworkTrace+Private.h"
#import "FirebasePerformance/Sources/Instrumentation/FPRNetworkTrace.h"
#import "FirebasePerformance/Sources/Loggers/FPRGDTEvent.h"
#import "FirebasePerformance/Sources/Public/FIRTrace.h"
#import "FirebasePerformance/Sources/Timer/FIRTrace+Internal.h"
#import "FirebasePerformance/Sources/Timer/FIRTrace+Private.h"
#import "FirebasePerformance/Tests/Unit/FPRTestCase.h"
#import "FirebasePerformance/Tests/Unit/FPRTestUtils.h"
#import "FirebasePerformance/Tests/Unit/Fakes/FPRFakeConfigurations.h"

#import <GoogleDataTransport/GoogleDataTransport.h>

#import <OCMock/OCMock.h>

@interface FPRGDTLogSamplerTest : FPRTestCase

/** The log sampler object. */
@property(nonatomic) FPRGDTLogSampler *logSampler;

/** Transport object which generates initial GDTCOREvent. */
@property(nonatomic) GDTCORTransport *gdtcctTransport;

/** GDTCOREvent which contains trace event for testing. */
@property(nonatomic) GDTCOREvent *transportTraceEvent;

/** GDTCOREvent which contains network trace event  for testing. */
@property(nonatomic) GDTCOREvent *transportNetworkEvent;

/** Fake configurations flags used for overriding configs. */
@property(nonatomic) FPRFakeConfigurations *fakeConfigs;

@end

@implementation FPRGDTLogSamplerTest

- (void)setUp {
  [super setUp];

  self.appFake.fakeIsDataCollectionDefaultEnabled = YES;

  // Mocks log sampling configuration to allow event dispatch.
  self.fakeConfigs =
      [[FPRFakeConfigurations alloc] initWithSources:FPRConfigurationSourceRemoteConfig];
  self.logSampler = [[FPRGDTLogSampler alloc] initWithFlags:self.fakeConfigs
                                          samplingThreshold:0.66];
  [self.fakeConfigs setTraceSamplingRate:1.0];
  [self.fakeConfigs setNetworkSamplingRate:1.0];

  // Defines transport logger for generating log events.
  self.gdtcctTransport = [[GDTCORTransport alloc] initWithMappingID:@"462"
                                                       transformers:nil
                                                             target:kGDTCORTargetCCT];

  // Generates sample trace metric.
  FPRMSGPerfMetric *tracePerfMetric = [FPRTestUtils createRandomPerfMetric:@"Random"];

  self.transportTraceEvent = [self.gdtcctTransport eventForTransport];
  self.transportTraceEvent.qosTier = GDTCOREventQosDefault;
  self.transportTraceEvent.dataObject = [FPRGDTEvent gdtEventForPerfMetric:tracePerfMetric];

  // Generates sample network trace metric.
  NSString *randomAppID = @"RandomID";
  FPRMSGPerfMetric *networkTraceMetric = FPRGetPerfMetricMessage(randomAppID);
  NSURL *URL = [NSURL URLWithString:@"https://abc.xyz"];
  NSURLRequest *URLRequest = [NSURLRequest requestWithURL:URL];
  FPRNetworkTrace *networkTrace = [[FPRNetworkTrace alloc] initWithURLRequest:URLRequest];
  [networkTrace start];
  [networkTrace checkpointState:FPRNetworkTraceCheckpointStateInitiated];
  [networkTrace checkpointState:FPRNetworkTraceCheckpointStateResponseReceived];

  NSDictionary<NSString *, NSString *> *headerFields = @{@"Content-Type" : @"text/json"};
  NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:URL
                                                            statusCode:200
                                                           HTTPVersion:@"HTTP/1.1"
                                                          headerFields:headerFields];
  [networkTrace didReceiveData:[NSData data]];
  [networkTrace didCompleteRequestWithResponse:response error:nil];
  // Make sure there are no sessions as they will not be sampled.
  networkTrace.activeSessions = [NSMutableArray array];
  networkTraceMetric.networkRequestMetric = FPRGetNetworkRequestMetric(networkTrace);

  self.transportNetworkEvent = [self.gdtcctTransport eventForTransport];
  self.transportNetworkEvent.qosTier = GDTCOREventQosDefault;
  self.transportNetworkEvent.dataObject = [FPRGDTEvent gdtEventForPerfMetric:networkTraceMetric];
}

/** Validates if the object creation is successful. */
- (void)testObjectCreation {
  XCTAssertNotNil([[FPRGDTLogSampler alloc] init]);
}

/** Validates if sampling works for valid values of configs. */
- (void)testLogSamplingWithBucketIdentifier {
  [self.fakeConfigs setTraceSamplingRate:0.05];
  [self.fakeConfigs setNetworkSamplingRate:0.05];
  XCTAssertNil([self.logSampler transform:self.transportTraceEvent]);
  XCTAssertNil([self.logSampler transform:self.transportNetworkEvent]);

  [self.fakeConfigs setTraceSamplingRate:0.65];
  [self.fakeConfigs setNetworkSamplingRate:0.65];
  XCTAssertNil([self.logSampler transform:self.transportTraceEvent]);
  XCTAssertNil([self.logSampler transform:self.transportNetworkEvent]);

  [self.fakeConfigs setTraceSamplingRate:0.66];
  [self.fakeConfigs setNetworkSamplingRate:0.66];
  XCTAssertEqual([self.logSampler transform:self.transportTraceEvent], self.transportTraceEvent);
  XCTAssertEqual([self.logSampler transform:self.transportNetworkEvent],
                 self.transportNetworkEvent);

  [self.fakeConfigs setTraceSamplingRate:0.67];
  [self.fakeConfigs setNetworkSamplingRate:0.67];
  XCTAssertEqual([self.logSampler transform:self.transportTraceEvent], self.transportTraceEvent);
  XCTAssertEqual([self.logSampler transform:self.transportNetworkEvent],
                 self.transportNetworkEvent);

  [self.fakeConfigs setTraceSamplingRate:1.0];
  [self.fakeConfigs setNetworkSamplingRate:1.0];
  XCTAssertEqual([self.logSampler transform:self.transportTraceEvent], self.transportTraceEvent);
  XCTAssertEqual([self.logSampler transform:self.transportNetworkEvent],
                 self.transportNetworkEvent);
}

/** Validates if the trace and network trace event honor different sampling rates. */
- (void)testSamplingWhenTracesAndNetworkSamplingRatesAreDifferent {
  [self.fakeConfigs setTraceSamplingRate:0.65];
  [self.fakeConfigs setNetworkSamplingRate:0.67];
  XCTAssertNil([self.logSampler transform:self.transportTraceEvent]);
  XCTAssertEqual([self.logSampler transform:self.transportNetworkEvent],
                 self.transportNetworkEvent);

  [self.fakeConfigs setTraceSamplingRate:0.67];
  [self.fakeConfigs setNetworkSamplingRate:0.65];
  XCTAssertEqual([self.logSampler transform:self.transportTraceEvent], self.transportTraceEvent);
  XCTAssertNil([self.logSampler transform:self.transportNetworkEvent]);
}

/** Validates if sampling works when trace sampling rate is greater than 1. */
- (void)testTraceSamplingWithInvalidNumerator {
  [self.fakeConfigs setTraceSamplingRate:2.0];
  XCTAssertEqual([self.logSampler transform:self.transportTraceEvent], self.transportTraceEvent);
}

/** Validates if sampling works with trace sampling rate of Zero. */
- (void)testTraceSamplingWithZeroNumerator {
  [self.fakeConfigs setTraceSamplingRate:0.0];
  XCTAssertNil([self.logSampler transform:self.transportTraceEvent]);
}

/** Validates if sampling works when network sampling rate is greater than 1. */
- (void)testNetworkSamplingWithInvalidNumerator {
  [self.fakeConfigs setNetworkSamplingRate:2.0];
  XCTAssertEqual([self.logSampler transform:self.transportNetworkEvent],
                 self.transportNetworkEvent);
}

/** Validates if sampling works with network sampling rate of Zero. */
- (void)testNetworkSamplingWithZeroNumerator {
  [self.fakeConfigs setNetworkSamplingRate:0.0];
  XCTAssertNil([self.logSampler transform:self.transportNetworkEvent]);
}

/** Validates if the trace event is not dropped if the session is verbose. */
- (void)testTraceSamplingWhenSessionIsVerbose {
  [self.fakeConfigs setTraceSamplingRate:0.0];

  // Trace is verbose.
  FPRMSGPerfMetric *traceMetric = [FPRTestUtils createVerboseRandomPerfMetric:@"Random"];

  GDTCOREvent *traceEvent = [self.gdtcctTransport eventForTransport];
  traceEvent.qosTier = GDTCOREventQosDefault;
  traceEvent.dataObject = [FPRGDTEvent gdtEventForPerfMetric:traceMetric];

  // Trace event will not be dropped.
  XCTAssertEqual([self.logSampler transform:traceEvent], traceEvent);
}

/** Validates if the trace event is sampled if the session is not verbose. */
- (void)testTraceSamplingWhenSessionIsNotVerbose {
  [self.fakeConfigs setTraceSamplingRate:0.0];

  // Trace is non-verbose.
  FPRMSGPerfMetric *tracePerfMetric = [FPRTestUtils createRandomPerfMetric:@"random"];

  GDTCOREvent *traceEvent = [self.gdtcctTransport eventForTransport];
  traceEvent.qosTier = GDTCOREventQosDefault;
  traceEvent.dataObject = [FPRGDTEvent gdtEventForPerfMetric:tracePerfMetric];

  // Trace event is dropped because of sampling.
  XCTAssertNil([self.logSampler transform:traceEvent]);
}

/** Validates if the network trace event is not sampled if the session is verbose. */
- (void)testNetworkTraceSamplingWhenSessionIsVerbose {
  self.appFake.fakeIsDataCollectionDefaultEnabled = YES;
  [self.fakeConfigs setNetworkSamplingRate:0.0];

  // Network request is verbose.
  FPRMSGPerfMetric *networkMetric = FPRGetPerfMetricMessage(@"RandomID");
  NSURL *URL = [NSURL URLWithString:@"https://abc.com"];
  NSURLRequest *testURLRequest = [NSURLRequest requestWithURL:URL];
  FPRNetworkTrace *networkTrace = [[FPRNetworkTrace alloc] initWithURLRequest:testURLRequest];
  [networkTrace start];
  NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:testURLRequest.URL
                                                            statusCode:200
                                                           HTTPVersion:@"HTTP/1.1"
                                                          headerFields:nil];
  [networkTrace didCompleteRequestWithResponse:response error:nil];
  FPRSessionDetails *details =
      [[FPRSessionDetails alloc] initWithSessionId:@"random" options:FPRSessionOptionsGauges];
  networkTrace.activeSessions = [[NSMutableArray alloc] initWithObjects:details, nil];
  networkMetric.networkRequestMetric = FPRGetNetworkRequestMetric(networkTrace);

  GDTCOREvent *networkEvent = [self.gdtcctTransport eventForTransport];
  networkEvent.qosTier = GDTCOREventQosDefault;
  networkEvent.dataObject = [FPRGDTEvent gdtEventForPerfMetric:networkMetric];

  // Network event will not be dropped.
  XCTAssertEqual([self.logSampler transform:networkEvent], networkEvent);
}

/** Validates if the network trace event is sampled if the session is not verbose. */
- (void)testNetworkTraceSamplingWhenSessionIsNotVerbose {
  [self.fakeConfigs setNetworkSamplingRate:0.0];

  // Network request is not verbose.
  FPRMSGPerfMetric *networkMetric = FPRGetPerfMetricMessage(@"RandomID");
  NSURL *URL = [NSURL URLWithString:@"https://abc.com"];
  NSURLRequest *testURLRequest = [NSURLRequest requestWithURL:URL];
  FPRNetworkTrace *networkTrace = [[FPRNetworkTrace alloc] initWithURLRequest:testURLRequest];
  [networkTrace start];
  NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:testURLRequest.URL
                                                            statusCode:200
                                                           HTTPVersion:@"HTTP/1.1"
                                                          headerFields:nil];
  [networkTrace didCompleteRequestWithResponse:response error:nil];
  // Make sure the session information is empty.
  networkTrace.activeSessions = [NSMutableArray array];
  networkMetric.networkRequestMetric = FPRGetNetworkRequestMetric(networkTrace);

  GDTCOREvent *networkEvent = [self.gdtcctTransport eventForTransport];
  networkEvent.qosTier = GDTCOREventQosDefault;
  networkEvent.dataObject = [FPRGDTEvent gdtEventForPerfMetric:networkMetric];

  // Network event is dropped because of sampling.
  XCTAssertNil([self.logSampler transform:networkEvent]);
}

@end
