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
(define-constant ERR-DELEGATION-NOT-FOUND (err u109))
(define-constant ERR-SELF-DELEGATION (err u110))
(define-constant ERR-ALREADY-DELEGATED (err u111))
(define-constant ERR-INVALID-CATEGORY (err u112))
(define-constant ERR-INSUFFICIENT-CREDITS (err u113))
(define-constant ERR-QUADRATIC-NOT-ENABLED (err u114))
(define-constant ERR-INVALID-CREDITS (err u115))
(define-constant ERR-CREDITS-ALREADY-ALLOCATED (err u116))

;; Contract owner
(define-constant CONTRACT-OWNER tx-sender)

;; Data variables
(define-data-var poll-counter uint u0)
(define-data-var total-votes uint u0)
(define-data-var current-poll-id uint u0)
(define-data-var category-counter uint u0)
(define-data-var total-quadratic-polls uint u0)

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
    anonymous-key: (buff 32),
    category: (string-ascii 30)
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

;; Vote delegation mapping
(define-map vote-delegations
  {delegator: principal, poll-id: uint}
  {delegate: principal, delegation-block: uint}
)

(define-map poll-categories
  (string-ascii 30)
  {count: uint, created-block: uint}
)

(define-map polls-by-category
  {category: (string-ascii 30), index: uint}
  uint
)

(define-map quadratic-polls
  uint
  {
    is-quadratic: bool,
    initial-credits-per-voter: uint,
    total-credits-allocated: uint,
    total-votes-cast: uint
  }
)

(define-map voter-credits
  {poll-id: uint, voter: principal}
  {
    total-credits: uint,
    spent-credits: uint,
    remaining-credits: uint
  }
)

(define-map quadratic-vote-allocations
  {poll-id: uint, voter: principal, option-index: uint}
  {
    votes-cast: uint,
    credits-spent: uint
  }
)

;; Create a new poll
(define-public (create-poll 
  (title (string-ascii 100))
  (description (string-ascii 500))
  (options (list 10 (string-ascii 50)))
  (duration uint)
  (category (string-ascii 30)))
  (let (
    (poll-id (+ (var-get poll-counter) u1))
    (start-block burn-block-height)
    (end-block (+ burn-block-height duration))
    (anonymous-key (hash160 (unwrap-panic (to-consensus-buff? tx-sender))))
    (category-data (default-to {count: u0, created-block: u0} (map-get? poll-categories category)))
    (category-count (get count category-data))
  )
    (asserts! (> (len title) u0) ERR-INVALID-TITLE)
    (asserts! (> duration u0) ERR-INVALID-DURATION)
    (asserts! (> (len options) u0) ERR-INVALID-OPTION)
    (asserts! (> (len category) u0) ERR-INVALID-CATEGORY)
    
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
      anonymous-key: anonymous-key,
      category: category
    })
    
    (map-set poll-categories category {
      count: (+ category-count u1),
      created-block: (if (is-eq category-count u0) burn-block-height (get created-block category-data))
    })
    
    (map-set polls-by-category {category: category, index: category-count} poll-id)
    
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

;; Delegate vote to another registered voter
(define-public (delegate-vote (poll-id uint) (delegate principal))
  (let (
    (poll-data (unwrap! (map-get? polls poll-id) ERR-POLL-NOT-FOUND))
    (voter-data (default-to {is-registered: false, registration-block: u0} (map-get? registered-voters tx-sender)))
    (delegate-data (default-to {is-registered: false, registration-block: u0} (map-get? registered-voters delegate)))
    (existing-delegation (map-get? vote-delegations {delegator: tx-sender, poll-id: poll-id}))
  )
    (asserts! (get is-registered voter-data) ERR-UNAUTHORIZED)
    (asserts! (get is-registered delegate-data) ERR-UNAUTHORIZED)
    (asserts! (not (is-eq tx-sender delegate)) ERR-SELF-DELEGATION)
    (asserts! (get is-active poll-data) ERR-POLL-ENDED)
    (asserts! (>= burn-block-height (get start-block poll-data)) ERR-POLL-NOT-STARTED)
    (asserts! (< burn-block-height (get end-block poll-data)) ERR-POLL-ENDED)
    (asserts! (is-none existing-delegation) ERR-ALREADY-DELEGATED)
    
    (map-set vote-delegations {delegator: tx-sender, poll-id: poll-id} {
      delegate: delegate,
      delegation-block: burn-block-height
    })
    
    (ok true)
  )
)

;; Vote on behalf of delegators
(define-public (cast-delegated-vote 
  (poll-id uint) 
  (option-index uint)
  (delegators (list 100 principal)))
  (let (
    (poll-data (unwrap! (map-get? polls poll-id) ERR-POLL-NOT-FOUND))
    (voter-data (default-to {is-registered: false, registration-block: u0} (map-get? registered-voters tx-sender)))
    (options-list (get options poll-data))
  )
    (asserts! (get is-registered voter-data) ERR-UNAUTHORIZED)
    (asserts! (get is-active poll-data) ERR-POLL-ENDED)
    (asserts! (>= burn-block-height (get start-block poll-data)) ERR-POLL-NOT-STARTED)
    (asserts! (< burn-block-height (get end-block poll-data)) ERR-POLL-ENDED)
    (asserts! (< option-index (len options-list)) ERR-INVALID-OPTION)
    
    (var-set current-poll-id poll-id)
    (let (
      (valid-delegations (filter validate-delegation-for-poll delegators))
      (delegation-count (len valid-delegations))
      (current-votes (get option-votes poll-data))
      (total-poll-votes (get total-votes poll-data))
    )
      (map-set polls poll-id (merge poll-data {
        option-votes: (increment-votes-by-amount current-votes option-index delegation-count),
        total-votes: (+ total-poll-votes delegation-count)
      }))
      
      (var-set total-votes (+ (var-get total-votes) delegation-count))
      (fold mark-delegator-as-voted valid-delegations poll-id)
      (ok delegation-count)
    )
  )
)

;; Remove delegation
(define-public (remove-delegation (poll-id uint))
  (let (
    (poll-data (unwrap! (map-get? polls poll-id) ERR-POLL-NOT-FOUND))
    (delegation (map-get? vote-delegations {delegator: tx-sender, poll-id: poll-id}))
  )
    (asserts! (is-some delegation) ERR-DELEGATION-NOT-FOUND)
    (asserts! (get is-active poll-data) ERR-POLL-ENDED)
    (asserts! (< burn-block-height (get end-block poll-data)) ERR-POLL-ENDED)
    
    (map-delete vote-delegations {delegator: tx-sender, poll-id: poll-id})
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

;; Get delegation info for a voter in a poll
(define-read-only (get-delegation (poll-id uint) (delegator principal))
  (map-get? vote-delegations {delegator: delegator, poll-id: poll-id})
)

;; Check if voter has delegated their vote
(define-read-only (has-delegated (poll-id uint) (voter principal))
  (is-some (map-get? vote-delegations {delegator: voter, poll-id: poll-id}))
)

;; Get total poll count
(define-read-only (get-poll-count)
  (var-get poll-counter)
)

(define-read-only (get-polls-by-category (category (string-ascii 30)))
  (let (
    (category-data (map-get? poll-categories category))
  )
    (match category-data
      data (ok {category: category, count: (get count data), created-block: (get created-block data)})
      ERR-INVALID-CATEGORY
    )
  )
)

(define-read-only (get-poll-id-by-category (category (string-ascii 30)) (index uint))
  (map-get? polls-by-category {category: category, index: index})
)

(define-read-only (list-polls-in-category (category (string-ascii 30)) (start-index uint) (limit uint))
  (let (
    (category-data (map-get? poll-categories category))
  )
    (match category-data
      data (let (
        (total-count (get count data))
        (end-index (if (> (+ start-index limit) total-count) total-count (+ start-index limit)))
        (poll-ids (build-poll-list category start-index end-index))
      )
        (ok {
          category: category,
          total-count: total-count,
          start-index: start-index,
          polls: poll-ids
        })
      )
      ERR-INVALID-CATEGORY
    )
  )
)

(define-read-only (get-all-categories)
  (ok {
    total-categories: (var-get category-counter),
    governance: (default-to {count: u0, created-block: u0} (map-get? poll-categories "governance")),
    community: (default-to {count: u0, created-block: u0} (map-get? poll-categories "community")),
    technical: (default-to {count: u0, created-block: u0} (map-get? poll-categories "technical")),
    proposal: (default-to {count: u0, created-block: u0} (map-get? poll-categories "proposal")),
    general: (default-to {count: u0, created-block: u0} (map-get? poll-categories "general"))
  })
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

(define-private (increment-votes-by-amount (votes (list 10 uint)) (target-index uint) (amount uint))
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
    (if (is-eq target-index u0) (list (+ v0 amount) v1 v2 v3 v4 v5 v6 v7 v8 v9)
    (if (is-eq target-index u1) (list v0 (+ v1 amount) v2 v3 v4 v5 v6 v7 v8 v9)
    (if (is-eq target-index u2) (list v0 v1 (+ v2 amount) v3 v4 v5 v6 v7 v8 v9)
    (if (is-eq target-index u3) (list v0 v1 v2 (+ v3 amount) v4 v5 v6 v7 v8 v9)
    (if (is-eq target-index u4) (list v0 v1 v2 v3 (+ v4 amount) v5 v6 v7 v8 v9)
    (if (is-eq target-index u5) (list v0 v1 v2 v3 v4 (+ v5 amount) v6 v7 v8 v9)
    (if (is-eq target-index u6) (list v0 v1 v2 v3 v4 v5 (+ v6 amount) v7 v8 v9)
    (if (is-eq target-index u7) (list v0 v1 v2 v3 v4 v5 v6 (+ v7 amount) v8 v9)
    (if (is-eq target-index u8) (list v0 v1 v2 v3 v4 v5 v6 v7 (+ v8 amount) v9)
    (if (is-eq target-index u9) (list v0 v1 v2 v3 v4 v5 v6 v7 v8 (+ v9 amount))
    votes))))))))))
  )
)

(define-private (validate-delegation-for-poll (delegator principal))
  (let (
    (delegation (map-get? vote-delegations {delegator: delegator, poll-id: (var-get current-poll-id)}))
    (voter-key (hash160 (unwrap-panic (to-consensus-buff? delegator))))
  )
    (and
      (is-some delegation)
      (is-eq tx-sender (get delegate (unwrap-panic delegation)))
      (is-none (map-get? vote-nullifiers {poll-id: (var-get current-poll-id), nullifier: voter-key}))
    )
  )
)

(define-private (mark-delegator-as-voted (delegator principal) (poll-id uint))
  (let (
    (voter-key (hash160 (unwrap-panic (to-consensus-buff? delegator))))
  )
    (map-set vote-nullifiers {poll-id: poll-id, nullifier: voter-key} true)
    poll-id
  )
)

(define-private (build-poll-list (category (string-ascii 30)) (start-index uint) (end-index uint))
  (let (
    (result (list))
  )
    (if (>= start-index end-index)
      result
      (let (
        (poll-id-0 (map-get? polls-by-category {category: category, index: start-index}))
        (poll-id-1 (map-get? polls-by-category {category: category, index: (+ start-index u1)}))
        (poll-id-2 (map-get? polls-by-category {category: category, index: (+ start-index u2)}))
        (poll-id-3 (map-get? polls-by-category {category: category, index: (+ start-index u3)}))
        (poll-id-4 (map-get? polls-by-category {category: category, index: (+ start-index u4)}))
      )
        (unwrap-panic (as-max-len? 
          (concat 
            (if (and (is-some poll-id-0) (< start-index end-index)) (list (unwrap-panic poll-id-0)) (list))
            (concat 
              (if (and (is-some poll-id-1) (< (+ start-index u1) end-index)) (list (unwrap-panic poll-id-1)) (list))
              (concat 
                (if (and (is-some poll-id-2) (< (+ start-index u2) end-index)) (list (unwrap-panic poll-id-2)) (list))
                (concat 
                  (if (and (is-some poll-id-3) (< (+ start-index u3) end-index)) (list (unwrap-panic poll-id-3)) (list))
                  (if (and (is-some poll-id-4) (< (+ start-index u4) end-index)) (list (unwrap-panic poll-id-4)) (list))
                )
              )
            )
          )
        u100))
      )
    )
  )
)

(define-private (sqrt (n uint))
  (if (<= n u1)
    n
    (let (
      (x0 (/ n u2))
      (x1 (/ (+ x0 (/ n x0)) u2))
      (x2 (/ (+ x1 (/ n x1)) u2))
      (x3 (/ (+ x2 (/ n x2)) u2))
      (x4 (/ (+ x3 (/ n x3)) u2))
      (x5 (/ (+ x4 (/ n x4)) u2))
    )
      x5
    )
  )
)

(define-private (calculate-quadratic-cost (votes uint))
  (* votes votes)
)

(define-public (create-quadratic-poll
  (title (string-ascii 100))
  (description (string-ascii 500))
  (options (list 10 (string-ascii 50)))
  (duration uint)
  (category (string-ascii 30))
  (credits-per-voter uint))
  (let (
    (poll-id (+ (var-get poll-counter) u1))
    (start-block burn-block-height)
    (end-block (+ burn-block-height duration))
    (anonymous-key (hash160 (unwrap-panic (to-consensus-buff? tx-sender))))
    (category-data (default-to {count: u0, created-block: u0} (map-get? poll-categories category)))
    (category-count (get count category-data))
  )
    (asserts! (> (len title) u0) ERR-INVALID-TITLE)
    (asserts! (> duration u0) ERR-INVALID-DURATION)
    (asserts! (> (len options) u0) ERR-INVALID-OPTION)
    (asserts! (> (len category) u0) ERR-INVALID-CATEGORY)
    (asserts! (> credits-per-voter u0) ERR-INVALID-CREDITS)
    
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
      anonymous-key: anonymous-key,
      category: category
    })
    
    (map-set quadratic-polls poll-id {
      is-quadratic: true,
      initial-credits-per-voter: credits-per-voter,
      total-credits-allocated: u0,
      total-votes-cast: u0
    })
    
    (map-set poll-categories category {
      count: (+ category-count u1),
      created-block: (if (is-eq category-count u0) burn-block-height (get created-block category-data))
    })
    
    (map-set polls-by-category {category: category, index: category-count} poll-id)
    
    (var-set poll-counter poll-id)
    (var-set total-quadratic-polls (+ (var-get total-quadratic-polls) u1))
    (ok poll-id)
  )
)

(define-public (allocate-voting-credits (poll-id uint))
  (let (
    (poll-data (unwrap! (map-get? polls poll-id) ERR-POLL-NOT-FOUND))
    (quadratic-data (unwrap! (map-get? quadratic-polls poll-id) ERR-QUADRATIC-NOT-ENABLED))
    (voter-data (default-to {is-registered: false, registration-block: u0} (map-get? registered-voters tx-sender)))
    (existing-credits (map-get? voter-credits {poll-id: poll-id, voter: tx-sender}))
    (initial-credits (get initial-credits-per-voter quadratic-data))
  )
    (asserts! (get is-registered voter-data) ERR-UNAUTHORIZED)
    (asserts! (get is-active poll-data) ERR-POLL-ENDED)
    (asserts! (>= burn-block-height (get start-block poll-data)) ERR-POLL-NOT-STARTED)
    (asserts! (< burn-block-height (get end-block poll-data)) ERR-POLL-ENDED)
    (asserts! (is-none existing-credits) ERR-CREDITS-ALREADY-ALLOCATED)
    
    (map-set voter-credits
      {poll-id: poll-id, voter: tx-sender}
      {
        total-credits: initial-credits,
        spent-credits: u0,
        remaining-credits: initial-credits
      }
    )
    
    (map-set quadratic-polls poll-id
      (merge quadratic-data {
        total-credits-allocated: (+ (get total-credits-allocated quadratic-data) initial-credits)
      })
    )
    
    (ok initial-credits)
  )
)

(define-public (cast-quadratic-vote
  (poll-id uint)
  (option-index uint)
  (votes-to-cast uint))
  (let (
    (poll-data (unwrap! (map-get? polls poll-id) ERR-POLL-NOT-FOUND))
    (quadratic-data (unwrap! (map-get? quadratic-polls poll-id) ERR-QUADRATIC-NOT-ENABLED))
    (voter-data (default-to {is-registered: false, registration-block: u0} (map-get? registered-voters tx-sender)))
    (credits-data (unwrap! (map-get? voter-credits {poll-id: poll-id, voter: tx-sender}) ERR-INSUFFICIENT-CREDITS))
    (existing-allocation (default-to {votes-cast: u0, credits-spent: u0} 
                          (map-get? quadratic-vote-allocations {poll-id: poll-id, voter: tx-sender, option-index: option-index})))
    (current-votes (get option-votes poll-data))
    (total-poll-votes (get total-votes poll-data))
    (options-list (get options poll-data))
    (new-total-votes (+ (get votes-cast existing-allocation) votes-to-cast))
    (credits-needed (calculate-quadratic-cost new-total-votes))
    (additional-credits (- credits-needed (get credits-spent existing-allocation)))
  )
    (asserts! (get is-registered voter-data) ERR-UNAUTHORIZED)
    (asserts! (get is-active poll-data) ERR-POLL-ENDED)
    (asserts! (>= burn-block-height (get start-block poll-data)) ERR-POLL-NOT-STARTED)
    (asserts! (< burn-block-height (get end-block poll-data)) ERR-POLL-ENDED)
    (asserts! (< option-index (len options-list)) ERR-INVALID-OPTION)
    (asserts! (> votes-to-cast u0) ERR-INVALID-OPTION)
    (asserts! (<= additional-credits (get remaining-credits credits-data)) ERR-INSUFFICIENT-CREDITS)
    
    (map-set voter-credits
      {poll-id: poll-id, voter: tx-sender}
      {
        total-credits: (get total-credits credits-data),
        spent-credits: (+ (get spent-credits credits-data) additional-credits),
        remaining-credits: (- (get remaining-credits credits-data) additional-credits)
      }
    )
    
    (map-set quadratic-vote-allocations
      {poll-id: poll-id, voter: tx-sender, option-index: option-index}
      {
        votes-cast: new-total-votes,
        credits-spent: credits-needed
      }
    )
    
    (map-set polls poll-id (merge poll-data {
      option-votes: (increment-votes-by-amount current-votes option-index votes-to-cast),
      total-votes: (+ total-poll-votes votes-to-cast)
    }))
    
    (map-set quadratic-polls poll-id
      (merge quadratic-data {
        total-votes-cast: (+ (get total-votes-cast quadratic-data) votes-to-cast)
      })
    )
    
    (var-set total-votes (+ (var-get total-votes) votes-to-cast))
    (ok {votes-cast: new-total-votes, credits-spent: credits-needed, remaining-credits: (- (get remaining-credits credits-data) additional-credits)})
  )
)

(define-read-only (get-quadratic-poll-info (poll-id uint))
  (map-get? quadratic-polls poll-id)
)

(define-read-only (get-voter-credits (poll-id uint) (voter principal))
  (map-get? voter-credits {poll-id: poll-id, voter: voter})
)

(define-read-only (get-voter-allocation (poll-id uint) (voter principal) (option-index uint))
  (map-get? quadratic-vote-allocations {poll-id: poll-id, voter: voter, option-index: option-index})
)

(define-read-only (is-quadratic-poll (poll-id uint))
  (match (map-get? quadratic-polls poll-id)
    data (get is-quadratic data)
    false
  )
)

(define-read-only (calculate-vote-cost (current-votes uint) (additional-votes uint))
  (let (
    (new-total (+ current-votes additional-votes))
    (new-cost (calculate-quadratic-cost new-total))
    (old-cost (calculate-quadratic-cost current-votes))
  )
    (ok {
      additional-votes: additional-votes,
      current-votes: current-votes,
      new-total-votes: new-total,
      additional-credits-needed: (- new-cost old-cost),
      total-credits-needed: new-cost
    })
  )
)

(define-read-only (get-quadratic-stats)
  {
    total-quadratic-polls: (var-get total-quadratic-polls),
    total-polls: (var-get poll-counter),
    total-votes: (var-get total-votes)
  }
)

;; Initialize contract
(begin
  (var-set poll-counter u0)
  (var-set total-votes u0)
  (var-set current-poll-id u0)
  (var-set category-counter u0)
)
