"""Contract facts for the luxios shared validator: the SDK's request bodies vs the server's spec.

The SDK only SENDS to the server (it reads nothing back but the status code and
Retry-After), so every component here is a REQUEST body. Editing this file IS a
wire-format change, made visible.

The spec URL is not committed: the dev server's hostname is private. luxios reads
OPENAPI_URL from the environment over this file's (`export OPENAPI_URL = …` in the
untracked Makefile.local); with neither, the contract stage fails.
"""

OPENAPI_URL = ""

# The SDK encodes timestamps as ISO 8601 strings and metadata as a string map.
TYPEMAP = {
    "string:date-time": "String",
    "object": "[String: String]",
}

# The wire's EventCreate is the SDK's AnalyticsEvent.
ALIAS = {"EventCreate": "AnalyticsEvent"}

REQUEST = {"EventCreate", "BatchEventRequest"}

EXPECTED = {
    # AnalyticsEvent (Sources/LuxAnalytics/AnalyticsEvent.swift). `id` is always sent:
    # it is the server's idempotency key (LUXANALYTI-68).
    "EventCreate": {
        "id": ("String", False),
        "name": ("String", False),
        "timestamp": ("String", False),
        "user_id": ("String", True),
        "session_id": ("String", True),
        "metadata": ("[String: String]", False),
    },
    # LuxAnalytics.BatchPayload: a batch of two or more events.
    "BatchEventRequest": {
        "events": ("[AnalyticsEvent]", False),
    },
}
