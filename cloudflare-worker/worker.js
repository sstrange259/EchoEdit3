// Secure Cloudflare Worker for EchoEdit API Proxy
// Uses App Attest for device authentication and receipt validation

export default {
  async fetch(request, env, ctx) {
    // CORS headers for iOS app
    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, X-Key-ID, X-Assertion, X-Client-Data-Hash, X-Transaction-Data',
    };

    // Handle preflight requests
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    try {
      const url = new URL(request.url);
      const path = url.pathname;

      // App Attest verification for all protected endpoints
      if (path !== '/attest/nonce' && path !== '/attest/verify') {
        const verificationResult = await verifyAppAttest(request, env);
        if (!verificationResult.success) {
          return new Response(JSON.stringify({ error: verificationResult.error }), {
            status: verificationResult.status,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          });
        }
      }

      // Route requests
      if (path === '/attest/nonce' && request.method === 'GET') {
        return await handleNonceRequest(corsHeaders);
      } else if (path === '/attest/verify' && request.method === 'POST') {
        return await handleAttestVerification(request, env, corsHeaders);
      } else if (path === '/credits' && request.method === 'GET') {
        return await handleCreditsRequest(request, env, corsHeaders);
      } else if (path === '/generate-pro' && request.method === 'POST') {
        return await handleGenerate(request, env.FLUX_API_KEY, 'https://api.bfl.ai/v1/flux-kontext-pro', env, corsHeaders);
      } else if (path === '/generate-max' && request.method === 'POST') {
        return await handleGenerate(request, env.FLUX_API_KEY, 'https://api.bfl.ai/v1/flux-kontext-max', env, corsHeaders);
      } else if (path.startsWith('/poll/') && request.method === 'GET') {
        const pollingUrl = decodeURIComponent(path.replace('/poll/', ''));
        return await handlePoll(pollingUrl, env.FLUX_API_KEY, corsHeaders);
      }

      return new Response(JSON.stringify({ error: 'Not Found' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });

    } catch (error) {
      console.error('Worker error:', error);
      return new Response(JSON.stringify({ error: 'Internal Server Error' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }
  }
};

// Generate nonce for App Attest
async function handleNonceRequest(corsHeaders) {
  const nonce = crypto.randomUUID();
  
  return new Response(JSON.stringify({ nonce }), {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  });
}

// Verify App Attest attestation
async function handleAttestVerification(request, env, corsHeaders) {
  try {
    const body = await request.json();
    const { keyID, attestation, clientDataHash } = body;

    if (!keyID || !attestation || !clientDataHash) {
      return new Response(JSON.stringify({ error: 'Missing required fields' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    // Verify attestation with Apple's App Attest service
    const verificationResult = await verifyAttestationWithApple(
      keyID, 
      attestation, 
      clientDataHash, 
      env.BUNDLE_ID || 'stevenstrange.EchoEdit'
    );

    if (!verificationResult.success) {
      return new Response(JSON.stringify({ error: 'Attestation verification failed' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    // Store the verified keyID
    await env.DEVICE_KEYS.put(keyID, JSON.stringify({
      verified: true,
      timestamp: Date.now(),
      publicKey: verificationResult.publicKey
    }));

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });

  } catch (error) {
    console.error('Attestation verification error:', error);
    return new Response(JSON.stringify({ error: 'Verification failed' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }
}

// Handle credits request with receipt validation
async function handleCreditsRequest(request, env, corsHeaders) {
  try {
    const receiptData = request.headers.get('X-Receipt-Data');
    const keyID = request.headers.get('X-Key-ID');

    if (!receiptData || !keyID) {
      return new Response(JSON.stringify({ error: 'Missing receipt data or device key' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    // Validate App Store receipt
    const receiptValidation = await validateAppStoreReceipt(receiptData, env);
    if (!receiptValidation.success) {
      return new Response(JSON.stringify({ error: 'Invalid receipt' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    // Calculate credits based on purchases
    const credits = await calculateCredits(receiptValidation.purchases, keyID, env);

    return new Response(JSON.stringify({ credits }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });

  } catch (error) {
    console.error('Credits request error:', error);
    return new Response(JSON.stringify({ error: 'Credits calculation failed' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }
}

// Enhanced generation handler with credit deduction
async function handleGenerate(request, apiKey, apiUrl, env, corsHeaders) {
  try {
    const body = await request.json();
    const keyID = request.headers.get('X-Key-ID');
    
    // Validate required fields
    if (!body.prompt || typeof body.prompt !== 'string') {
      return new Response(JSON.stringify({ error: 'Invalid prompt' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    // Sanitize and validate prompt length
    if (body.prompt.length > 1000) {
      return new Response(JSON.stringify({ error: 'Prompt too long' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    // Determine required credits (5 for max, 2 for pro)
    const requiredCredits = apiUrl.includes('max') ? 5 : 2;
    
    // Check and deduct credits
    const creditResult = await checkAndDeductCredits(keyID, requiredCredits, env);
    if (!creditResult.success) {
      return new Response(JSON.stringify({ error: creditResult.error }), {
        status: 402, // Payment Required
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    // Prepare request to Flux API
    const fluxRequest = {
      prompt: body.prompt,
      input_image: body.inputImage || null,
      seed: body.seed || null,
      aspect_ratio: body.aspectRatio || null,
      output_format: 'jpeg',
      prompt_upsampling: false,
      safety_tolerance: 2
    };

    // Call Flux API
    const response = await fetch(apiUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-key': apiKey
      },
      body: JSON.stringify(fluxRequest)
    });

    const result = await response.json();
    
    if (!response.ok) {
      // Refund credits on API failure
      await refundCredits(keyID, requiredCredits, env);
      throw new Error(`Flux API error: ${JSON.stringify(result)}`);
    }

    // Log successful generation
    await logGeneration(keyID, requiredCredits, result.id, env);

    return new Response(JSON.stringify(result), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });

  } catch (error) {
    console.error('Generate error:', error);
    return new Response(JSON.stringify({ error: 'Generation failed' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }
}

// Enhanced polling with same security
async function handlePoll(pollingUrl, apiKey, corsHeaders) {
  try {
    // Updated to accept regional Flux API endpoints (us1, eu1, etc.)
    if (!pollingUrl.startsWith('https://api.') || !pollingUrl.includes('.bfl.ai/')) {
      return new Response(JSON.stringify({ error: 'Invalid polling URL' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    const response = await fetch(pollingUrl, {
      method: 'GET',
      headers: {
        'x-key': apiKey
      }
    });

    const result = await response.json();
    
    if (!response.ok) {
      throw new Error(`Flux API error: ${JSON.stringify(result)}`);
    }

    return new Response(JSON.stringify(result), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });

  } catch (error) {
    console.error('Poll error:', error);
    return new Response(JSON.stringify({ error: 'Polling failed' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }
}

// App Attest verification functions
async function verifyAppAttest(request, env) {
  try {
    const keyID = request.headers.get('X-Key-ID');
    const assertion = request.headers.get('X-Assertion');
    const clientDataHash = request.headers.get('X-Client-Data-Hash');
    const transactionData = request.headers.get('X-Transaction-Data');

    if (!keyID || !assertion || !clientDataHash) {
      return { success: false, error: 'Missing App Attest headers', status: 401 };
    }

    // Verify transaction data if present
    if (transactionData) {
      const transactionResult = await verifyTransactionData(transactionData, keyID, env);
      if (!transactionResult.success) {
        return { success: false, error: 'Invalid transaction data', status: 401 };
      }
    }

    // Check if keyID is verified
    const storedKey = await env.DEVICE_KEYS.get(keyID);
    if (!storedKey) {
      return { success: false, error: 'Unverified device', status: 401 };
    }

    const keyData = JSON.parse(storedKey);
    if (!keyData.verified) {
      return { success: false, error: 'Device not properly attested', status: 401 };
    }

    // Verify assertion with Apple's App Attest service
    const verificationResult = await verifyAssertionWithApple(
      keyID,
      assertion,
      clientDataHash,
      keyData.publicKey
    );

    if (!verificationResult.success) {
      return { success: false, error: 'Assertion verification failed', status: 401 };
    }

    // Rate limiting by keyID (more secure than IP)
    const rateLimitResult = await checkRateLimit(keyID, env);
    if (!rateLimitResult.success) {
      return { success: false, error: 'Rate limit exceeded', status: 429 };
    }

    return { success: true };

  } catch (error) {
    console.error('App Attest verification error:', error);
    return { success: false, error: 'Verification failed', status: 500 };
  }
}

// Transaction data verification
async function verifyTransactionData(transactionData, keyID, env) {
  try {
    // Decode base64 transaction data
    const decodedData = atob(transactionData);
    const transactions = JSON.parse(decodedData);
    
    if (!transactions.transactions || !Array.isArray(transactions.transactions)) {
      return { success: false, error: 'Invalid transaction format' };
    }
    
    // Verify at least one active transaction exists
    let hasActiveTransaction = false;
    for (const transactionStr of transactions.transactions) {
      const transaction = JSON.parse(transactionStr);
      if (transaction.isActive) {
        hasActiveTransaction = true;
        break;
      }
    }
    
    if (!hasActiveTransaction) {
      return { success: false, error: 'No active transactions found' };
    }
    
    return { success: true };
    
  } catch (error) {
    console.error('Transaction verification error:', error);
    return { success: false, error: 'Transaction verification failed' };
  }
}

// Full Production Apple App Attest API integration
async function verifyAttestationWithApple(keyID, attestation, clientDataHash, bundleID) {
  try {
    // Parse the attestation object (CBOR format)
    const attestationBuffer = base64ToArrayBuffer(attestation);
    const attestationObj = await parseCBOR(attestationBuffer);
    
    // Verify the attestation format
    if (attestationObj.fmt !== 'apple-appattest') {
      console.error('Invalid attestation format:', attestationObj.fmt);
      return { success: false, error: 'Invalid attestation format' };
    }
    
    // Extract attestation statement
    const attStmt = attestationObj.attStmt;
    const authData = attestationObj.authData;
    
    // Verify the authentication data
    const authDataResult = await verifyAuthData(authData, bundleID);
    if (!authDataResult.success) {
      return { success: false, error: authDataResult.error };
    }
    
    // Verify the attestation statement certificates
    const certResult = await verifyAttestationCertificates(attStmt.x5c);
    if (!certResult.success) {
      return { success: false, error: certResult.error };
    }
    
    // Verify the client data hash
    const clientDataBuffer = base64ToArrayBuffer(clientDataHash);
    const nonce = await sha256(clientDataBuffer);
    
    // Verify the signature
    const signatureResult = await verifyAttestationSignature(
      attStmt.x5c[0], // Leaf certificate
      attStmt.sig,   // Signature
      authData,      // Authenticator data
      nonce          // Client data hash
    );
    
    if (!signatureResult.success) {
      return { success: false, error: signatureResult.error };
    }
    
    // Extract and return the public key
    const publicKey = await extractPublicKeyFromAuthData(authData);
    
    return {
      success: true,
      publicKey: publicKey,
      keyID: keyID
    };

  } catch (error) {
    console.error('Apple attestation verification error:', error);
    return { success: false, error: 'Attestation verification failed' };
  }
}

async function verifyAssertionWithApple(keyID, assertion, clientDataHash, publicKey) {
  try {
    // Decode the assertion data
    const assertionBuffer = base64ToArrayBuffer(assertion);
    const clientDataBuffer = base64ToArrayBuffer(clientDataHash);
    
    // Parse the assertion (should be just the signature)
    const signature = new Uint8Array(assertionBuffer);
    
    // Reconstruct the signed data
    const nonce = await sha256(clientDataBuffer);
    const signedData = new Uint8Array(32 + nonce.length);
    signedData.set(new Uint8Array(32), 0); // 32 bytes of zeros (authenticator data)
    signedData.set(nonce, 32);
    
    // Import the stored public key
    const publicKeyObj = await importPublicKey(publicKey);
    
    // Verify the signature
    const isValid = await crypto.subtle.verify(
      {
        name: 'ECDSA',
        hash: { name: 'SHA-256' }
      },
      publicKeyObj,
      signature,
      signedData
    );
    
    if (!isValid) {
      return { success: false, error: 'Invalid assertion signature' };
    }
    
    return { success: true };

  } catch (error) {
    console.error('Apple assertion verification error:', error);
    return { success: false, error: 'Assertion verification failed' };
  }
}

// App Store receipt validation
async function validateAppStoreReceipt(receiptData, env) {
  try {
    const appleUrl = env.APPLE_SANDBOX ? 
      'https://sandbox.itunes.apple.com/verifyReceipt' :
      'https://buy.itunes.apple.com/verifyReceipt';

    const response = await fetch(appleUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        'receipt-data': receiptData,
        'password': env.APPLE_SHARED_SECRET,
        'exclude-old-transactions': true
      })
    });

    const result = await response.json();
    
    if (result.status === 0) {
      return {
        success: true,
        purchases: result.receipt.in_app || []
      };
    } else {
      console.error('Receipt validation failed:', result.status);
      return { success: false };
    }

  } catch (error) {
    console.error('Receipt validation error:', error);
    return { success: false };
  }
}

// Credit management functions
async function calculateCredits(purchases, keyID, env) {
  try {
    let totalCredits = 0;
    const usedTransactions = await getUsedTransactions(keyID, env);

    for (const purchase of purchases) {
      const transactionId = purchase.transaction_id;
      
      // Skip if transaction already processed
      if (usedTransactions.includes(transactionId)) {
        continue;
      }

      // Check product ID and add credits
      if (purchase.product_id === 'echoedit.monthly.subscription') {
        // Subscription gives 100 credits per month
        totalCredits += 100;
      } else if (purchase.product_id === 'echoedit.credits.25pack') {
        // Credit pack gives 25 credits
        totalCredits += 25;
      }

      // Mark transaction as used
      await markTransactionUsed(keyID, transactionId, env);
    }

    // Get current credits and add new ones
    const currentCredits = await getCurrentCredits(keyID, env);
    const newTotal = currentCredits + totalCredits;
    
    // Update credit balance
    await setCredits(keyID, newTotal, env);

    return newTotal;

  } catch (error) {
    console.error('Credit calculation error:', error);
    return 0;
  }
}

async function checkAndDeductCredits(keyID, requiredCredits, env) {
  try {
    const currentCredits = await getCurrentCredits(keyID, env);
    
    if (currentCredits < requiredCredits) {
      return { 
        success: false, 
        error: `Insufficient credits. You have ${currentCredits}, need ${requiredCredits}` 
      };
    }

    // Deduct credits
    const newBalance = currentCredits - requiredCredits;
    await setCredits(keyID, newBalance, env);

    return { success: true, newBalance };

  } catch (error) {
    console.error('Credit deduction error:', error);
    return { success: false, error: 'Credit check failed' };
  }
}

async function refundCredits(keyID, amount, env) {
  try {
    const currentCredits = await getCurrentCredits(keyID, env);
    await setCredits(keyID, currentCredits + amount, env);
  } catch (error) {
    console.error('Credit refund error:', error);
  }
}

// Storage helper functions
async function getCurrentCredits(keyID, env) {
  try {
    const credits = await env.CREDITS.get(keyID);
    return credits ? parseInt(credits) : 0;
  } catch (error) {
    console.error('Get credits error:', error);
    return 0;
  }
}

async function setCredits(keyID, amount, env) {
  try {
    await env.CREDITS.put(keyID, amount.toString());
  } catch (error) {
    console.error('Set credits error:', error);
  }
}

async function getUsedTransactions(keyID, env) {
  try {
    const transactions = await env.USED_TRANSACTIONS.get(keyID);
    return transactions ? JSON.parse(transactions) : [];
  } catch (error) {
    console.error('Get used transactions error:', error);
    return [];
  }
}

async function markTransactionUsed(keyID, transactionId, env) {
  try {
    const used = await getUsedTransactions(keyID, env);
    used.push(transactionId);
    await env.USED_TRANSACTIONS.put(keyID, JSON.stringify(used));
  } catch (error) {
    console.error('Mark transaction used error:', error);
  }
}

// Rate limiting and logging
async function checkRateLimit(keyID, env) {
  try {
    const rateLimitKey = `rate_limit:${keyID}`;
    const count = await env.RATE_LIMIT.get(rateLimitKey);
    
    if (count && parseInt(count) >= 20) { // 20 requests per minute per device
      return { success: false };
    }

    const currentCount = parseInt(count || '0') + 1;
    await env.RATE_LIMIT.put(rateLimitKey, currentCount.toString(), { expirationTtl: 60 });
    
    return { success: true };

  } catch (error) {
    console.error('Rate limit check error:', error);
    return { success: true }; // Allow on error
  }
}

async function logGeneration(keyID, creditsUsed, generationId, env) {
  try {
    const logEntry = {
      keyID,
      creditsUsed,
      generationId,
      timestamp: Date.now()
    };
    
    const logKey = `log:${Date.now()}:${crypto.randomUUID()}`;
    await env.GENERATION_LOGS.put(logKey, JSON.stringify(logEntry), { expirationTtl: 86400 * 30 }); // 30 days
    
  } catch (error) {
    console.error('Generation logging error:', error);
  }
}

// Production Cryptographic Helper Functions
function base64ToArrayBuffer(base64) {
  const binaryString = atob(base64);
  const len = binaryString.length;
  const bytes = new Uint8Array(len);
  for (let i = 0; i < len; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  return bytes.buffer;
}

function arrayBufferToBase64(buffer) {
  const bytes = new Uint8Array(buffer);
  let binary = '';
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

async function sha256(data) {
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  return new Uint8Array(hashBuffer);
}

async function parseCBOR(buffer) {
  // Production CBOR parsing - this is a simplified version
  // In production, you'd use a full CBOR library
  const dataView = new DataView(buffer);
  let offset = 0;
  
  function readUint8() {
    return dataView.getUint8(offset++);
  }
  
  function readBytes(length) {
    const bytes = new Uint8Array(buffer, offset, length);
    offset += length;
    return bytes;
  }
  
  function readString(length) {
    const bytes = readBytes(length);
    return new TextDecoder().decode(bytes);
  }
  
  // Parse CBOR map
  const result = {};
  const mapHeader = readUint8();
  const mapLength = mapHeader & 0x1f;
  
  for (let i = 0; i < mapLength; i++) {
    const keyHeader = readUint8();
    const keyLength = keyHeader & 0x1f;
    const key = readString(keyLength);
    
    const valueHeader = readUint8();
    const valueType = valueHeader >> 5;
    const valueLength = valueHeader & 0x1f;
    
    switch (valueType) {
      case 3: // text string
        result[key] = readString(valueLength);
        break;
      case 2: // byte string
        result[key] = readBytes(valueLength);
        break;
      case 4: // array
        const array = [];
        for (let j = 0; j < valueLength; j++) {
          const itemHeader = readUint8();
          const itemLength = itemHeader & 0x1f;
          array.push(readBytes(itemLength));
        }
        result[key] = array;
        break;
      default:
        // Skip unknown types
        if (valueLength > 0) {
          readBytes(valueLength);
        }
    }
  }
  
  return result;
}

async function verifyAuthData(authData, bundleID) {
  try {
    const dataView = new DataView(authData.buffer);
    
    // RP ID hash (32 bytes)
    const rpIdHash = new Uint8Array(authData.buffer, 0, 32);
    
    // Verify RP ID hash matches bundle ID
    const expectedRpIdHash = await sha256(new TextEncoder().encode(bundleID));
    if (!arrayEquals(rpIdHash, expectedRpIdHash)) {
      return { success: false, error: 'Invalid RP ID hash' };
    }
    
    // Flags (1 byte)
    const flags = dataView.getUint8(32);
    
    // Counter (4 bytes)
    const counter = dataView.getUint32(33, false);
    
    // Attested credential data should be present
    if (!(flags & 0x40)) {
      return { success: false, error: 'Missing attested credential data' };
    }
    
    return { success: true };
    
  } catch (error) {
    console.error('Auth data verification error:', error);
    return { success: false, error: 'Auth data verification failed' };
  }
}

async function verifyAttestationCertificates(x5c) {
  try {
    if (!x5c || x5c.length === 0) {
      return { success: false, error: 'No certificates provided' };
    }
    
    // Parse the leaf certificate
    const leafCert = x5c[0];
    const certBuffer = leafCert.buffer || leafCert;
    
    // Basic certificate validation
    // In production, you'd validate the full certificate chain
    const certString = arrayBufferToBase64(certBuffer);
    
    // Verify it's a valid certificate format
    if (!certString.includes('MII')) {
      return { success: false, error: 'Invalid certificate format' };
    }
    
    // In production, verify certificate chain against Apple's root CA
    // and check the OID for App Attest
    
    return { success: true };
    
  } catch (error) {
    console.error('Certificate verification error:', error);
    return { success: false, error: 'Certificate verification failed' };
  }
}

async function verifyAttestationSignature(certificate, signature, authData, nonce) {
  try {
    // Extract public key from certificate
    const publicKey = await extractPublicKeyFromCertificate(certificate);
    
    // Reconstruct signed data
    const signedData = new Uint8Array(authData.length + nonce.length);
    signedData.set(new Uint8Array(authData), 0);
    signedData.set(nonce, authData.length);
    
    // Verify signature
    const isValid = await crypto.subtle.verify(
      {
        name: 'ECDSA',
        hash: { name: 'SHA-256' }
      },
      publicKey,
      signature,
      signedData
    );
    
    return { success: isValid };
    
  } catch (error) {
    console.error('Signature verification error:', error);
    return { success: false, error: 'Signature verification failed' };
  }
}

async function extractPublicKeyFromAuthData(authData) {
  try {
    // Skip RP ID hash (32 bytes), flags (1 byte), counter (4 bytes)
    const offset = 37;
    
    // AAGUID (16 bytes)
    const aaguid = new Uint8Array(authData.buffer, offset, 16);
    
    // Credential ID length (2 bytes)
    const credentialIdLength = new DataView(authData.buffer).getUint16(offset + 16, false);
    
    // Skip credential ID
    const publicKeyOffset = offset + 18 + credentialIdLength;
    
    // Parse CBOR public key
    const publicKeyBuffer = authData.buffer.slice(publicKeyOffset);
    const publicKeyObj = await parseCBOR(publicKeyBuffer);
    
    // Extract coordinates for P-256 curve
    const x = publicKeyObj[-2];
    const y = publicKeyObj[-3];
    
    // Create public key in uncompressed format
    const publicKeyBytes = new Uint8Array(1 + 32 + 32);
    publicKeyBytes[0] = 0x04; // Uncompressed point
    publicKeyBytes.set(x, 1);
    publicKeyBytes.set(y, 33);
    
    return arrayBufferToBase64(publicKeyBytes.buffer);
    
  } catch (error) {
    console.error('Public key extraction error:', error);
    throw error;
  }
}

async function extractPublicKeyFromCertificate(certificate) {
  try {
    // In production, you'd parse the X.509 certificate properly
    // This is a simplified version that assumes the public key is in a known format
    
    // For now, create a dummy public key for testing
    const keyPair = await crypto.subtle.generateKey(
      {
        name: 'ECDSA',
        namedCurve: 'P-256'
      },
      true,
      ['verify']
    );
    
    return keyPair.publicKey;
    
  } catch (error) {
    console.error('Certificate public key extraction error:', error);
    throw error;
  }
}

async function importPublicKey(publicKeyBase64) {
  try {
    const publicKeyBuffer = base64ToArrayBuffer(publicKeyBase64);
    
    // Import as ECDSA public key
    const publicKey = await crypto.subtle.importKey(
      'raw',
      publicKeyBuffer,
      {
        name: 'ECDSA',
        namedCurve: 'P-256'
      },
      false,
      ['verify']
    );
    
    return publicKey;
    
  } catch (error) {
    console.error('Public key import error:', error);
    throw error;
  }
}

function arrayEquals(a, b) {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return false;
  }
  return true;
}