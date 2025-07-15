# EchoEdit Secure API Worker

This Cloudflare Worker provides secure API access for the EchoEdit iOS app using App Attest for device authentication and proper receipt validation for payment verification.

## Security Features

- **App Attest Integration**: Every API request is authenticated using Apple's App Attest framework
- **Receipt Validation**: App Store receipts are validated against Apple's servers
- **Per-Device Rate Limiting**: Rate limiting by device keyID instead of IP address
- **Credit Tracking**: Proper credit management with transaction deduplication
- **Abuse Logging**: Comprehensive logging of all generation requests

## Setup Instructions

### 1. Create KV Namespaces

Create the required KV namespaces in your Cloudflare dashboard:

```bash
# Create KV namespaces
wrangler kv:namespace create "DEVICE_KEYS"
wrangler kv:namespace create "CREDITS" 
wrangler kv:namespace create "USED_TRANSACTIONS"
wrangler kv:namespace create "GENERATION_LOGS"
wrangler kv:namespace create "RATE_LIMIT"
```

### 2. Update wrangler.toml

Replace the placeholder namespace IDs in `wrangler.toml` with the actual IDs from step 1.

### 3. Set Environment Secrets

```bash
# Set your Flux API key
wrangler secret put FLUX_API_KEY

# Set your App Store shared secret
wrangler secret put APPLE_SHARED_SECRET
```

### 4. Configure Variables

Update the variables in `wrangler.toml`:
- Set `APPLE_SANDBOX` to `false` for production
- Verify `BUNDLE_ID` matches your app's bundle ID

### 5. Deploy

```bash
wrangler deploy
```

## API Endpoints

### App Attest Flow

#### GET /attest/nonce
Returns a nonce for App Attest attestation.

#### POST /attest/verify
Verifies App Attest attestation and stores device key.

**Body:**
```json
{
  "keyID": "device-key-id",
  "attestation": "base64-attestation-data",
  "clientDataHash": "base64-client-data-hash"
}
```

### Credits Management

#### GET /credits
Returns current credit balance for the device.

**Headers:**
- `X-Key-ID`: Device key ID
- `X-Assertion`: App Attest assertion
- `X-Client-Data-Hash`: Client data hash
- `X-Receipt-Data`: Base64 App Store receipt

### Image Generation

#### POST /generate-pro
Generate image using Flux Kontext Pro (2 credits).

#### POST /generate-max
Generate image using Flux Kontext Max (5 credits).

**Headers:**
- `X-Key-ID`: Device key ID
- `X-Assertion`: App Attest assertion
- `X-Client-Data-Hash`: Client data hash
- `X-Receipt-Data`: Base64 App Store receipt (optional)

**Body:**
```json
{
  "prompt": "image description",
  "inputImage": "base64-image-data", // optional
  "seed": 12345, // optional
  "aspectRatio": "16:9" // optional
}
```

#### GET /poll/{polling-url}
Poll for generation results.

## Security Model

### Device Authentication
1. iOS app generates App Attest key on first launch
2. App performs attestation with nonce from `/attest/nonce`
3. Worker verifies attestation with Apple's App Attest API
4. Verified keyID is stored for future requests

### Request Authentication
1. Every API request includes keyID, assertion, and clientDataHash
2. Worker verifies assertion against stored device key
3. Only verified devices can access protected endpoints

### Payment Verification
1. App Store receipts are validated against Apple's servers
2. Credits are calculated based on verified purchases
3. Transaction IDs are tracked to prevent reuse
4. Credits are deducted per generation request

### Rate Limiting
- 20 requests per minute per device keyID
- More secure than IP-based rate limiting
- Prevents abuse from compromised devices

## Monitoring

The worker logs all security events and generation requests:
- Failed attestations and assertions
- Invalid receipts
- Rate limit violations
- Credit transactions
- Generation requests

Logs are stored in the `GENERATION_LOGS` KV namespace for 30 days.

## Production Considerations

1. **Apple Credentials**: Configure proper Apple App Attest credentials for production
2. **Receipt Validation**: Ensure `APPLE_SANDBOX` is set to `false` for production
3. **Monitoring**: Set up alerts for security violations and abuse
4. **Backup**: Consider backing up critical KV data
5. **Scaling**: Monitor KV usage and consider Durable Objects for high-volume scenarios

## Troubleshooting

### Common Issues

1. **"Unverified device" errors**: Device needs to complete attestation flow first
2. **"Invalid receipt" errors**: Check App Store shared secret and sandbox settings
3. **"Insufficient credits" errors**: User needs to purchase credits or subscription
4. **Rate limit errors**: Device is making too many requests

### Debug Mode

Set `WORKER_ENV = "development"` in wrangler.toml for additional logging.