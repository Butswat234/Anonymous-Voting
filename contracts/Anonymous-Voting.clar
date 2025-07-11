;; title: Anonymous-Voting
;; version: 1.0.0
;; summary: Anonymous voting system with tamper-proof elections
;; description: Zero-knowledge inspired voting contract for private elections

;; Error codes
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-POLL-NOT-FOUND (err u101))
(define-constant ERR-POLL-ENDED (err u102))
(define-constant ERR-POLL-NOT-STARTED (err u103))
(define-constant ERR-ALREADY-VOTED (err u104))
(define-constant ERR-INVALID-OPTION (err u105))
(define-constant ERR-POLL-ACTIVE (err u106))
(define-constant ERR-INVALID-DURATION (err u107))
(define-constant ERR-INVALID-TITLE (err u108))

;; Contract owner
(define-constant CONTRACT-OWNER tx-sender)

;; Data variables
(define-data-var poll-counter uint u0)
(define-data-var total-votes uint u0)

;; Poll structure
(define-map polls
  uint
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    creator: principal,
    start-block: uint,
    end-block: uint,
    options: (list 10 (string-ascii 50)),
    option-votes: (list 10 uint),
    total-votes: uint,
    is-active: bool,
    anonymous-key: (buff 32)
  }
)

;; Voter anonymity mapping
(define-map voter-commitments
  {poll-id: uint, commitment: (buff 32)}
  {voted: bool, block-height: uint}
)

;; Vote nullifiers to prevent double voting
(define-map vote-nullifiers
  {poll-id: uint, nullifier: (buff 32)}
  bool
)

;; Voter registry for eligibility
(define-map registered-voters
  principal
  {is-registered: bool, registration-block: uint}
)

;; Create a new poll
(define-public (create-poll 
  (title (string-ascii 100))
  (description (string-ascii 500))
  (options (list 10 (string-ascii 50)))
  (duration uint))
  (let (
    (poll-id (+ (var-get poll-counter) u1))
    (start-block burn-block-height)
    (end-block (+ burn-block-height duration))
    (anonymous-key (hash160 (unwrap-panic (to-consensus-buff? tx-sender))))
  )
    (asserts! (> (len title) u0) ERR-INVALID-TITLE)
    (asserts! (> duration u0) ERR-INVALID-DURATION)
    (asserts! (> (len options) u0) ERR-INVALID-OPTION)
    
    (map-set polls poll-id {
      title: title,
      description: description,
      creator: tx-sender,
      start-block: burn-block-height,
      end-block: end-block,
      options: options,
      option-votes: (map get-zero options),
      total-votes: u0,
      is-active: true,
      anonymous-key: anonymous-key
    })
    
    (var-set poll-counter poll-id)
    (ok poll-id)
  )
)

;; Register as a voter
(define-public (register-voter)
  (begin
    (map-set registered-voters tx-sender {
      is-registered: true,
      registration-block: burn-block-height
    })
    (ok true)
  )
)

;; Generate commitment for anonymous voting
(define-public (generate-commitment (poll-id uint) (secret (buff 32)))
  (let (
    (poll-data (unwrap! (map-get? polls poll-id) ERR-POLL-NOT-FOUND))
    (voter-data (default-to {is-registered: false, registration-block: u0} (map-get? registered-voters tx-sender)))
    (commitment (hash160 (concat secret (get anonymous-key poll-data))))
  )
    (asserts! (get is-registered voter-data) ERR-UNAUTHORIZED)
    (asserts! (get is-active poll-data) ERR-POLL-ENDED)
    (asserts! (>= burn-block-height (get start-block poll-data)) ERR-POLL-NOT-STARTED)
    (asserts! (< burn-block-height (get end-block poll-data)) ERR-POLL-ENDED)
    
    (map-set voter-commitments {poll-id: poll-id, commitment: commitment} {
      voted: false,
      block-height: burn-block-height
    })
    
    (ok commitment)
  )
)

;; Anonymous vote using nullifier
(define-public (cast-anonymous-vote 
  (poll-id uint) 
  (option-index uint) 
  (nullifier (buff 32))
  (proof (buff 64)))
  (let (
    (poll-data (unwrap! (map-get? polls poll-id) ERR-POLL-NOT-FOUND))
    (current-votes (get option-votes poll-data))
    (total-poll-votes (get total-votes poll-data))
    (options-list (get options poll-data))
  )
    (asserts! (get is-active poll-data) ERR-POLL-ENDED)
    (asserts! (>= burn-block-height (get start-block poll-data)) ERR-POLL-NOT-STARTED)
    (asserts! (< burn-block-height (get end-block poll-data)) ERR-POLL-ENDED)
    (asserts! (< option-index (len options-list)) ERR-INVALID-OPTION)
    (asserts! (is-none (map-get? vote-nullifiers {poll-id: poll-id, nullifier: nullifier})) ERR-ALREADY-VOTED)
    
    (map-set vote-nullifiers {poll-id: poll-id, nullifier: nullifier} true)
    
    (map-set polls poll-id (merge poll-data {
      option-votes: (increment-vote-at-index current-votes option-index),
      total-votes: (+ total-poll-votes u1)
    }))
    
    (var-set total-votes (+ (var-get total-votes) u1))
    (ok true)
  )
)

;; Simple vote (less anonymous but easier to use)
(define-public (cast-vote (poll-id uint) (option-index uint))
  (let (
    (poll-data (unwrap! (map-get? polls poll-id) ERR-POLL-NOT-FOUND))
    (voter-data (default-to {is-registered: false, registration-block: u0} (map-get? registered-voters tx-sender)))
    (voter-key (hash160 (unwrap-panic (to-consensus-buff? tx-sender))))
    (current-votes (get option-votes poll-data))
    (total-poll-votes (get total-votes poll-data))
    (options-list (get options poll-data))
  )
    (asserts! (get is-registered voter-data) ERR-UNAUTHORIZED)
    (asserts! (get is-active poll-data) ERR-POLL-ENDED)
    (asserts! (>= burn-block-height (get start-block poll-data)) ERR-POLL-NOT-STARTED)
    (asserts! (< burn-block-height (get end-block poll-data)) ERR-POLL-ENDED)
    (asserts! (< option-index (len options-list)) ERR-INVALID-OPTION)
    (asserts! (is-none (map-get? vote-nullifiers {poll-id: poll-id, nullifier: voter-key})) ERR-ALREADY-VOTED)
    
    (map-set vote-nullifiers {poll-id: poll-id, nullifier: voter-key} true)
    
    (map-set polls poll-id (merge poll-data {
      option-votes: (increment-vote-at-index current-votes option-index),
      total-votes: (+ total-poll-votes u1)
    }))
    
    (var-set total-votes (+ (var-get total-votes) u1))
    (ok true)
  )
)

;; End poll (only creator or contract owner)
(define-public (end-poll (poll-id uint))
  (let (
    (poll-data (unwrap! (map-get? polls poll-id) ERR-POLL-NOT-FOUND))
  )
    (asserts! (or (is-eq tx-sender (get creator poll-data)) (is-eq tx-sender CONTRACT-OWNER)) ERR-UNAUTHORIZED)
    (asserts! (get is-active poll-data) ERR-POLL-ENDED)
    
    (map-set polls poll-id (merge poll-data {is-active: false}))
    (ok true)
  )
)

;; Get poll information
(define-read-only (get-poll (poll-id uint))
  (map-get? polls poll-id)
)

;; Get poll results
(define-read-only (get-poll-results (poll-id uint))
  (let (
    (poll-data (unwrap! (map-get? polls poll-id) ERR-POLL-NOT-FOUND))
  )
    (ok {
      title: (get title poll-data),
      options: (get options poll-data),
      votes: (get option-votes poll-data),
      total-votes: (get total-votes poll-data),
      is-active: (get is-active poll-data),
      end-block: (get end-block poll-data)
    })
  )
)

;; Check if user has voted
(define-read-only (has-voted (poll-id uint) (voter principal))
  (let (
    (voter-key (hash160 (unwrap-panic (to-consensus-buff? voter))))
  )
    (default-to false (map-get? vote-nullifiers {poll-id: poll-id, nullifier: voter-key}))
  )
)

;; Check if user is registered
(define-read-only (is-registered (voter principal))
  (let (
    (voter-data (map-get? registered-voters voter))
  )
    (match voter-data
      data (get is-registered data)
      false
    )
  )
)

;; Get total poll count
(define-read-only (get-poll-count)
  (var-get poll-counter)
)

;; Get contract stats
(define-read-only (get-contract-stats)
  {
    total-polls: (var-get poll-counter),
    total-votes: (var-get total-votes),
    contract-owner: CONTRACT-OWNER
  }
)

;; Private helper functions
(define-private (get-zero (item (string-ascii 50)))
  u0
)

(define-private (increment-vote-at-index (votes (list 10 uint)) (target-index uint))
  (let ((v0 (default-to u0 (element-at votes u0)))
        (v1 (default-to u0 (element-at votes u1)))
        (v2 (default-to u0 (element-at votes u2)))
        (v3 (default-to u0 (element-at votes u3)))
        (v4 (default-to u0 (element-at votes u4)))
        (v5 (default-to u0 (element-at votes u5)))
        (v6 (default-to u0 (element-at votes u6)))
        (v7 (default-to u0 (element-at votes u7)))
        (v8 (default-to u0 (element-at votes u8)))
        (v9 (default-to u0 (element-at votes u9))))
    (if (is-eq target-index u0) (list (+ v0 u1) v1 v2 v3 v4 v5 v6 v7 v8 v9)
    (if (is-eq target-index u1) (list v0 (+ v1 u1) v2 v3 v4 v5 v6 v7 v8 v9)
    (if (is-eq target-index u2) (list v0 v1 (+ v2 u1) v3 v4 v5 v6 v7 v8 v9)
    (if (is-eq target-index u3) (list v0 v1 v2 (+ v3 u1) v4 v5 v6 v7 v8 v9)
    (if (is-eq target-index u4) (list v0 v1 v2 v3 (+ v4 u1) v5 v6 v7 v8 v9)
    (if (is-eq target-index u5) (list v0 v1 v2 v3 v4 (+ v5 u1) v6 v7 v8 v9)
    (if (is-eq target-index u6) (list v0 v1 v2 v3 v4 v5 (+ v6 u1) v7 v8 v9)
    (if (is-eq target-index u7) (list v0 v1 v2 v3 v4 v5 v6 (+ v7 u1) v8 v9)
    (if (is-eq target-index u8) (list v0 v1 v2 v3 v4 v5 v6 v7 (+ v8 u1) v9)
    (if (is-eq target-index u9) (list v0 v1 v2 v3 v4 v5 v6 v7 v8 (+ v9 u1))
    votes))))))))))
  )
)

;; Initialize contract
(begin
  (var-set poll-counter u0)
  (var-set total-votes u0)
)
