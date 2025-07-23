# EchoEdit Security Implementation

This repository previously included API code and a Cloudflare Worker used for App Attest verification, credit tracking and other backend logic. Those components have been removed. The project now contains only the iOS user interface code.

## Current State

- The `cloudflare-worker` directory has been deleted from active development.
- All network and payment verification code was stripped from the Xcode project.
- Remaining Swift files implement UI features only.

The historical security documentation describing the worker and attestation flows no longer applies. Should backend functionality return in the future, refer to earlier revisions for the original implementation details.
