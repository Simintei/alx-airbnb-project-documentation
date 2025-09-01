### Backend API Specification

#### Goals

  * Secure sign-up/sign-in for guests/hosts/admins.
  * Short-lived access token (**JWT**) + long-lived refresh token.
  * Optional **OAuth (Google)** via OpenID Connect.

#### Endpoints

  * `POST /api/v1/auth/register`

      * Creates a user (role: **guest** or **host**).
      * **Request (JSON)**
        ```json
        {
          "first_name": "Mary",
          "last_name": "Karanja",
          "email": "mary@example.com",
          "password": "P@ssw0rd!123",
          "phone_number": "+254700000001",
          "role": "guest"
        }
        ```
      * **Validation**
          * `first_name`, `last_name`: 1–100 chars, letters/hyphen/apostrophe only.
          * `email`: RFC 5322; must be unique.
          * `password`: ≥8 chars; ≥1 upper, ≥1 lower, ≥1 digit, ≥1 symbol.
          * `role`: in `{guest, host}`. (admin created via admin tools only.)
          * `phone_number`: E.164 or null.
      * **Responses**
          * `201 Created`
            ```json
            {
              "user_id": "uuid",
              "email": "mary@example.com",
              "role": "guest",
              "created_at": "2025-09-01T09:00:00Z"
            }
            ```
          * `409 Conflict` (email exists)
          * `422 Unprocessable Entity` (validation errors)
      * **Security/Notes**
          * Hash password with **Argon2id** (preferred) or **bcrypt(12+)**.
          * Audit: write “user\_created” event.

  * `POST /api/v1/auth/login`

      * Exchanges email+password for tokens.
      * **Request**
        ```json
        { "email": "mary@example.com", "password": "P@ssw0rd!123" }
        ```
      * **Responses**
          * `200 OK`
            ```json
            {
              "access_token": "jwt",
              "refresh_token": "jwt",
              "token_type": "Bearer",
              "expires_in": 900
            }
            ```
          * `401 Unauthorized` (invalid credentials) with generic message.
      * **Rate limiting**: 5/min/IP; exponential backoff.
      * **Account lock**: optional temporary lock after N failures (e.g., 5/15min).

  * `POST /api/v1/auth/refresh`

      * Rotates tokens.
      * **Request (cookie or body)**
        ```json
        { "refresh_token": "jwt" }
        ```
      * **Responses**
          * `200 OK` (new pair)
          * `401 Unauthorized` (expired/invalid/used)
      * **Security**: store refresh token family (revocation list). Rotate on each use.

  * `POST /api/v1/auth/logout`

      * Revokes refresh token (server-side).
      * **Request**
        ```json
        { "refresh_token": "jwt" }
        ```
      * **Response**: `204 No Content`

  * `GET /api/v1/auth/me`  (auth required)

      * Returns current user.
      * **Response**
        ```json
        { "user_id": "uuid", "email": "mary@example.com", "role": "guest", "first_name": "Mary", "last_name": "Karanja", "phone_number": "+254700000001" }
        ```

  * `GET /api/v1/auth/oauth/google/url`

      * Returns Google auth URL.

  * `GET /api/v1/auth/oauth/google/callback`

      * Exchanges code→tokens→user; creates/links account.
      * **Validation/Threats**
          * CSRF on OAuth callback: `state` param required.
          * Use **PKCE**.

  * **Performance/SLO**

      * **P50/P95**: 60ms/200ms (login not counting external OAuth).
      * 99.9% availability.
      * **DB**: index on `users.email`; unique constraint.

-----

### 2\) Property Management

#### Goals

  * Hosts manage listings.
  * Guests can search/filter.
  * Admin may moderate.

#### Endpoints

  * `POST /api/v1/properties`  (role: **host|admin**)

      * Create listing.
      * **Request**
        ```json
        {
          "name": "Beach House",
          "description": "Lovely beachside house.",
          "location": "Mombasa, Kenya",
          "price_per_night": 120.00,
          "amenities": ["wifi","pool","kitchen"],
          "max_guests": 6,
          "photos": ["https://.../1.jpg","https://.../2.jpg"],
          "availability": [{ "start":"2025-10-01", "end":"2025-12-31" }]
        }
        ```
      * **Validation**
          * `name`: 1–150; `description`: 1–5000.
          * `location`: 1–255; consider structured fields later (city,country,lat,lng).
          * `price_per_night`: ≥ 0.00 with 2 decimals.
          * `amenities`: whitelist strings; ≤50 items.
          * `max_guests`: 1–32.
          * `photos`: valid HTTPS URLs ≤10.
          * `availability`: non-overlapping ranges; `start`≤`end`.
      * **Responses**
          * `201 Created`
            ```json
            { "property_id": "uuid" }
            ```
          * `422 Validation errors`
      * **Side-effects**
          * Store photos in object storage; keep signed URLs.
          * Emit “property\_created”.

  * `GET /api/v1/properties/{property_id}`

      * Public details.
      * **Response**
        ```json
        {
          "property_id":"uuid",
          "host_id":"uuid",
          "name":"Beach House",
          "description":"Lovely beachside house.",
          "location":"Mombasa, Kenya",
          "price_per_night":120.00,
          "amenities":["wifi","pool","kitchen"],
          "max_guests":6,
          "rating":4.6,
          "photos":["..."],
          "created_at":"...",
          "updated_at":"..."
        }
        ```

  * `PATCH /api/v1/properties/{property_id}`  (owner host or admin)

      * Partial update; same validation as create.
      * **Response**: `200 OK` with updated resource.
      * **Authorization**
          * Host can only manage own properties.
          * Admin can manage all.

  * `DELETE /api/v1/properties/{property_id}`  (owner host or admin)

      * Deletes property; cascades bookings per FK policy (or soft-delete; recommended).
      * **Response**: `204 No Content`

  * `GET /api/v1/properties`

      * Search & filter (public).
      * **Query params**
          * `q` (text search in name/description/location)
          * `location`, `min_price`, `max_price`
          * `guests` (`≥ max_guests`)
          * `amenities=wifi,pool,pets`
          * `sort=price_asc|price_desc|rating_desc|created_desc`
          * `page` (default 1), `page_size` (default 20, max 100)
      * **Response**
        ```json
        {
          "items":[ { "property_id":"uuid", "name":"...", "location":"...", "price_per_night":120.00, "rating":4.6, "photos":["..."] } ],
          "page":1,
          "page_size":20,
          "total":134
        }
        ```
      * **Performance**
          * **P95** \< 300ms for filtered list with indexes.
          * **Cache** hot queries (e.g., Redis) for 60–120s.

-----

### 3\) Booking System

#### Goals

  * Guests create/cancel/view bookings.
  * Prevent double bookings.
  * Track status: `pending`, `confirmed`, `canceled`, `completed`.
  * **Concurrency & Consistency**: Implement with `SERIALIZABLE` transaction or explicit advisory locks.

#### Endpoints

  * `POST /api/v1/bookings`  (role: **guest**)

      * Creates a booking request.
      * **Request**
        ```json
        {
          "property_id": "uuid",
          "start_date": "2025-10-10",
          "end_date": "2025-10-15",
          "guests": 2,
          "payment_method": "stripe",
          "idempotency_key": "a-unique-client-generated-string"
        }
        ```
      * **Validation**
          * `start_date` \< `end_date`; both future.
          * `stay_length` ≤ 30 nights.
          * `guests` ≤ `property.max_guests`.
          * `property` exists and is active.
          * `idempotency_key`: required; prevents duplicates within 24h.
      * **Process (transaction)**
          * Lock property availability.
          * Verify no overlap.
          * Create booking with status “pending”.
          * (Optional) create payment intent; store client secret.
      * **Responses**
          * `201 Created`
            ```json
            {
              "booking_id":"uuid",
              "status":"pending",
              "total_estimate": 600.00,
              "payment": { "provider":"stripe", "client_secret":"..." }
            }
            ```
          * `409 Conflict` (overlap)
          * `422 Validation errors`

  * `GET /api/v1/bookings/{booking_id}`  (owner guest, host of property, or admin)

      * Returns booking details.
      * **Response**
        ```json
        {
          "booking_id":"uuid",
          "property_id":"uuid",
          "user_id":"uuid",
          "start_date":"2025-10-10",
          "end_date":"2025-10-15",
          "status":"confirmed",
          "created_at":"...",
          "payments":[{"payment_id":"uuid","amount":600.00,"payment_method":"stripe","payment_date":"..."}]
        }
        ```

  * `POST /api/v1/bookings/{booking_id}/confirm`  (system webhook or host/admin)

      * Marks booking confirmed after successful payment.
      * **Response**: `200 OK` `{ "status":"confirmed" }`

  * `POST /api/v1/bookings/{booking_id}/cancel`  (guest who booked, host, or admin)

      * **Business rules**
          * Guest can cancel until policy window.
          * Host/admin can cancel anytime.
      * **Response**: `200 OK` `{ "status":"canceled" }`

  * `GET /api/v1/bookings`  (auth)

      * List bookings.
      * **Query params**: `status`, `date_from`, `date_to`, `property_id`, `page`, `page_size`.
      * **Response**: paginated list.

-----

### Common Concerns

#### Security

  * All endpoints (except public auth) require `Authorization: Bearer <jwt>`.
  * **RBAC** by role: `guest`/`host`/`admin`.
  * Input sanitized; output uses JSON with safe encoding.
  * **HTTPS only**; HSTS; secure cookies for refresh tokens.

#### Errors (standard shape)

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "end_date must be after start_date",
    "details": {
      "end_date": "..."
    }
  }
}
```

  * **Common codes**: `VALIDATION_ERROR`, `AUTH_REQUIRED`, `FORBIDDEN`, `NOT_FOUND`, `CONFLICT`, `RATE_LIMITED`.

#### Observability

  * **Correlation-ID** per request.
  * Structured logs, metrics, traces.
  * **Audit events**: `user_created`, `user_login`, `property_created`, etc.

#### Rate Limits

  * **Auth/login**: 5/min/IP.
  * **Search**: 60/min/IP.
  * **Booking create**: 10/min/user.

#### Pagination

  * Offset/limit or cursor.

#### Idempotency

  * For `POST /bookings` and payment actions using `Idempotency-Key` header.
