# Friend Circle: API Design Standards (God-Level)

All development must strictly adhere to these standards. **NO EXCEPTIONS.**

## 1. Resource-Oriented Design (Google/Microsoft)
- **URLs**: Must follow `{collection}/{id}/{sub-collection}`.
- **Naming**: Use kebab-case for URLs, camelCase for JSON fields.
- **Methods**:
  - `GET`: Retrieve resource (Idempotent, Safe)
  - `POST`: Create resource or execute custom method (Non-idempotent without key)
  - `PATCH`: Partial update (Idempotent)
  - `DELETE`: Remove resource (Idempotent)

## 2. Reliability & Idempotency (Stripe/PayPal)
- **Idempotency-Key**: Every mutation (`POST`) must support an `Idempotency-Key` header.
- **Response Caching**: If the same key is sent within 24 hours, return the *exact same* cached response without re-executing logic.
- **Transaction Sagas**: Distributed transactions (Gifting/Payments) must use the Saga pattern with compensating transactions.

## 3. Error Modeling (Google rpc.Status)
- Errors must return a consistent structure:
  ```json
  {
    "error": {
      "code": "INSUFFICIENT_FUNDS",
      "message": "User balance is too low for this gift.",
      "status": "FAILED_PRECONDITION",
      "requestId": "uuid-v4-trace-id",
      "details": []
    }
  }
  ```

## 4. Security (OWASP API Top 10)
- **BOLA (API1)**: Every request must verify ownership of the resource ID via middleware.
- **Rate Limiting (API4)**: Enforced via Redis `fixed-window` or `token-bucket`.
- **JWT Rotation**: Access tokens expire in 15m; Refresh tokens support rotation and revocation.

## 5. Performance (Netflix/Discord)
- **Pagination**: Mandatory cursor-based pagination for all collections (`limit`, `nextPageToken`).
- **Expansion**: Support `?expand=user,room` to reduce N+1 roundtrips.
- **Compression**: Gzip/Brotli mandatory for responses > 1KB.






