# Configuration

## The DSN

The DSN tells the SDK where to send events and how to authenticate:

```text
https://<public-id>@<host>[:port]/<path>/<project-id>
```

For example `https://pk_123@analytics.example.com/api/v1/events/proj_456`:

- **`public-id`** (the URL's user part) is sent as the HTTP Basic user, with an empty password. It identifies the app to the server; it is not a secret, since it ships inside your app.
- **`project-id`** is the last path component.
- Events are POSTed to the DSN's URL without the user part: `https://analytics.example.com/api/v1/events/proj_456`.

Your server's dashboard gives you the DSN for each app. A DSN without a host, a public id or a project id throws `LuxAnalyticsError.invalidConfiguration`. Use `https`; App Transport Security blocks plain `http` unless your app adds an exception.

## Options

`LuxAnalyticsConfiguration(dsn:...)` takes every option below as a parameter with a default. The defaults are the constants in `LuxAnalyticsDefaults`.

| Option | Default | What it does |
|---|---|---|
| `autoFlushInterval` | `30` s | How often queued events are flushed automatically. |
| `maxQueueSize` | `500` | `track` triggers a flush when the queue holds this many events. A memory warning triggers one above half of it. |
| `batchSize` | `50` | The most events sent in one request. Each flush sends one batch. |
| `debugLogging` | `false` | Log to the unified log (subsystem `com.luxardolabs.LuxAnalytics`), with sensitive values redacted. |
| `requestTimeout` | `60` s | Timeout for each send request. |
| `maxQueueSizeHard` | `10000` | The queue's hard limit. At the limit, `overflowStrategy` applies. |
| `overflowStrategy` | `.dropOldest` | At the hard limit: `.dropOldest` removes the oldest events, `.dropNewest` rejects the new event, `.dropAll` empties the queue first. |
| `eventTTL` | `604800` s (7 days) | Queued events older than this are dropped before the next flush. |
| `maxRetryAttempts` | `5` | How many times a failed event is retried before it's dropped. |
| `compressionEnabled` | `true` | zlib-compress request bodies at or above `compressionThreshold`. |
| `compressionThreshold` | `1024` bytes | The smallest body that gets compressed. |

Values aren't range-checked. A `batchSize` of `0`, for example, means nothing is ever sent.

```swift
func makeConfiguration() throws -> LuxAnalyticsConfiguration {
    try LuxAnalyticsConfiguration(
        dsn: "https://pk_123@analytics.example.com/api/v1/events/proj_456",
        autoFlushInterval: 60,
        batchSize: 100,
        debugLogging: true,
        maxQueueSizeHard: 2_000,
        eventTTL: 3 * 24 * 3600,
        overflowStrategy: .dropNewest
    )
}
```

The configuration also exposes what it parsed from the DSN: `apiURL` (the URL without the project id), `publicId` and `projectId`.

## Info.plist

`LuxAnalytics.initializeFromPlist()` (or `LuxAnalyticsConfiguration(bundle:)`) reads these keys from your app's Info.plist:

| Key | Type | Option |
|---|---|---|
| `LuxAnalyticsDSN` | String (required) | the DSN |
| `LuxAnalyticsAutoFlushInterval` | Number | `autoFlushInterval` |
| `LuxAnalyticsMaxQueueSize` | Number | `maxQueueSize` |
| `LuxAnalyticsBatchSize` | Number | `batchSize` |
| `LuxAnalyticsDebugLogging` | Boolean | `debugLogging` |
| `LuxAnalyticsRequestTimeout` | Number | `requestTimeout` |
| `LuxAnalyticsCompressionEnabled` | Boolean | `compressionEnabled` |

Options not in this list use their defaults when you initialize from Info.plist. A missing `LuxAnalyticsDSN` throws `LuxAnalyticsError.invalidConfiguration`.

```xml
<key>LuxAnalyticsDSN</key>
<string>https://pk_123@analytics.example.com/api/v1/events/proj_456</string>
<key>LuxAnalyticsBatchSize</key>
<integer>100</integer>
```

## Debug and release DSNs

A common setup sends debug builds to a separate project, so test traffic stays out of production numbers:

```swift
func analyticsDSN() -> String {
    #if DEBUG
    return "https://pk_dev@analytics.example.com/api/v1/events/proj_dev"
    #else
    return "https://pk_prod@analytics.example.com/api/v1/events/proj_prod"
    #endif
}
```
