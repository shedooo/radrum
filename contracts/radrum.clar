;; A sophisticated yield-bearing vault with dynamic strategy allocation,
;; risk-adjusted optimization, gamification, and advanced governance features

;; ========== CONSTANTS & ERRORS ==========
(define-constant ERR-NO-FUNDS u100)
(define-constant ERR-NO-SHARES u101)
(define-constant ERR-INVALID-STRATEGY u102)
(define-constant ERR-UNAUTHORIZED u103)
(define-constant ERR-VAULT-PAUSED u104)
(define-constant ERR-INSUFFICIENT-BALANCE u105)
(define-constant ERR-INVALID-AMOUNT u106)
(define-constant ERR-STRATEGY-NOT-FOUND u107)
(define-constant ERR-COOLDOWN-ACTIVE u108)
(define-constant ERR-SLIPPAGE-TOO-HIGH u109)
(define-constant ERR-INVALID-FEE u110)
(define-constant ERR-INVALID-ALLOCATION u111)
(define-constant ERR-REBALANCE-NOT-NEEDED u112)
(define-constant ERR-INVALID-REFERRAL u113)

;; Fee constants (basis points: 10000 = 100%)
(define-constant MAX-MANAGEMENT-FEE u200)  ;; 2% max
(define-constant MAX-PERFORMANCE-FEE u2000) ;; 20% max
(define-constant PRECISION u10000)
(define-constant SECONDS-PER-YEAR u31536000)

;; Gamification constants
(define-constant POINTS-PER-STX u100)
(define-constant LOYALTY-BONUS-THRESHOLD u1000000) ;; 1M STX for bonus
(define-constant REFERRAL-BONUS u500) ;; 5% bonus

;; Risk management constants
(define-constant MAX-STRATEGY-ALLOCATION u5000) ;; 50% max per strategy
(define-constant REBALANCE-THRESHOLD u500) ;; 5% deviation triggers rebalance

;; Input validation constants
(define-constant MAX-DEPOSIT-AMOUNT u1000000000000) ;; 1M STX max deposit
(define-constant MAX-APY u10000) ;; 100% max APY
(define-constant MAX-VOLATILITY u10000) ;; 100% max volatility
(define-constant MAX-DRAWDOWN u10000) ;; 100% max drawdown
(define-constant MAX-THRESHOLD u2000) ;; 20% max threshold
(define-constant MAX-SHARES u1000000000000) ;; Maximum shares that can be requested

;; ========== GLOBAL STATE ==========
(define-data-var total-assets uint u0)
(define-data-var total-shares uint u0)
(define-data-var vault-paused bool false)
(define-data-var emergency-shutdown-flag bool false)
(define-data-var initialized bool false)

;; Governance & Admin
(define-data-var contract-owner principal tx-sender)
(define-data-var pending-owner principal tx-sender)
(define-data-var governance-delay uint u86400) ;; 24 hours

;; Fee Structure
(define-data-var management-fee uint u100)    ;; 1% annually
(define-data-var performance-fee uint u1000)  ;; 10% on profits
(define-data-var treasury principal tx-sender)
(define-data-var last-fee-collection uint u0)

;; Dynamic allocation state
(define-data-var rebalance-threshold uint u500) ;; 5% deviation
(define-data-var last-rebalance uint u0)
(define-data-var auto-rebalance-enabled bool true)

;; Performance tracking
(define-data-var total-fees-collected uint u0)
(define-data-var high-water-mark uint u10000) ;; Start at 1.0 share price
(define-data-var last-harvest uint u0)

;; Gamification state
(define-fungible-token radrum-points)
(define-data-var total-points-issued uint u0)
(define-data-var loyalty-program-active bool true)

;; ========== DATA MAPS ==========

;; User data with enhanced tracking
(define-map shares 
  {user: principal} 
  {balance: uint, last-deposit: uint, total-deposited: uint, deposit-count: uint})

(define-map withdrawal-requests 
  {user: principal} 
  {amount: uint, timestamp: uint})

;; Enhanced strategy data with risk metrics
(define-map strategies 
  {id: uint} 
  {
    name: (string-ascii 32), 
    balance: uint, 
    yield: uint, 
    active: bool, 
    risk-level: uint,
    apy: uint,
    volatility: uint,
    max-drawdown: uint,
    sharpe-ratio: uint
  })

;; Dynamic strategy allocation
(define-map strategy-allocations 
  {id: uint} 
  {target-weight: uint, current-weight: uint, max-allocation: uint})

;; Risk management
(define-map strategy-risk-limits 
  {id: uint} 
  {max-allocation: uint, stop-loss: uint, risk-budget: uint})

;; Gamification maps
(define-map user-achievements 
  {user: principal} 
  {
    points: uint, 
    level: uint, 
    total-earned: uint,
    referrals: uint,
    loyalty-multiplier: uint,
    last-activity: uint
  })

(define-map user-referrals 
  {referrer: principal} 
  {total-referred: uint, total-bonus: uint})

(define-map referral-codes 
  {code: (string-ascii 20)} 
  {owner: principal, uses: uint, active: bool})

;; Performance history tracking
(define-map performance-history 
  {period: uint} 
  {apy: uint, sharpe: uint, max-drawdown: uint, total-return: uint})

;; ========== INPUT VALIDATION HELPERS ==========

(define-private (validate-amount (amount uint))
  (and (> amount u0) (<= amount MAX-DEPOSIT-AMOUNT)))

(define-private (validate-shares (share-amount uint))
  (and (> share-amount u0) (<= share-amount MAX-SHARES)))

(define-private (validate-strategy-id (strategy-id uint))
  (and (>= strategy-id u1) (<= strategy-id u3)))

(define-private (validate-apy (apy uint))
  (<= apy MAX-APY))

(define-private (validate-volatility (volatility uint))
  (<= volatility MAX-VOLATILITY))

(define-private (validate-drawdown (drawdown uint))
  (<= drawdown MAX-DRAWDOWN))

(define-private (validate-threshold (threshold uint))
  (<= threshold MAX-THRESHOLD))

(define-private (validate-allocation (allocation uint))
  (<= allocation PRECISION))

;; ========== HELPER FUNCTIONS ==========

(define-read-only (get-user-shares (user principal))
  (default-to {balance: u0, last-deposit: u0, total-deposited: u0, deposit-count: u0} 
              (map-get? shares {user: user})))

(define-read-only (get-user-achievements (user principal))
  (default-to {points: u0, level: u0, total-earned: u0, referrals: u0, loyalty-multiplier: u10000, last-activity: u0}
              (map-get? user-achievements {user: user})))

(define-read-only (get-share-price)
  (let ((total-shares-supply (var-get total-shares)))
    (if (is-eq total-shares-supply u0)
        PRECISION
        (/ (* (var-get total-assets) PRECISION) total-shares-supply))))

(define-read-only (get-strategy-info (id uint))
  (map-get? strategies {id: id}))

(define-read-only (get-strategy-allocation (id uint))
  (map-get? strategy-allocations {id: id}))

(define-read-only (get-vault-info)
  {
    total-assets: (var-get total-assets),
    total-shares: (var-get total-shares),
    share-price: (get-share-price),
    paused: (var-get vault-paused),
    emergency: (var-get emergency-shutdown-flag),
    initialized: (var-get initialized),
    auto-rebalance: (var-get auto-rebalance-enabled),
    last-rebalance: (var-get last-rebalance)
  })

;; Calculate user level based on points
(define-read-only (calculate-user-level (points uint))
  (if (>= points u100000) u5
  (if (>= points u50000) u4
  (if (>= points u20000) u3
  (if (>= points u5000) u2
  (if (>= points u1000) u1
      u0))))))

;; Calculate loyalty multiplier based on holding duration and amount
(define-read-only (calculate-loyalty-multiplier (user principal))
  (let (
    (user-data (get-user-shares user))
    (holding-duration (- stacks-block-height (get last-deposit user-data)))
    (balance (get balance user-data))
  )
    (if (and (> holding-duration u52560) (> balance LOYALTY-BONUS-THRESHOLD)) ;; 1 year + 1M STX
        u11000 ;; 10% bonus
    (if (> holding-duration u26280) ;; 6 months
        u10500 ;; 5% bonus
    (if (> holding-duration u8760) ;; 2 months
        u10250 ;; 2.5% bonus
        u10000))))) ;; No bonus

;; ========== INITIALIZATION ==========

(define-public (initialize)
  (begin
    (asserts! (not (var-get initialized)) (err ERR-UNAUTHORIZED))
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR-UNAUTHORIZED))
    
    ;; Initialize enhanced strategies with risk metrics
    (map-set strategies {id: u1} 
      {name: "LendingProtocolA", balance: u0, yield: u0, active: true, risk-level: u3,
       apy: u800, volatility: u200, max-drawdown: u500, sharpe-ratio: u150})
    (map-set strategies {id: u2} 
      {name: "LendingProtocolB", balance: u0, yield: u0, active: true, risk-level: u5,
       apy: u1200, volatility: u400, max-drawdown: u800, sharpe-ratio: u120})
    (map-set strategies {id: u3} 
      {name: "LiquidityPool", balance: u0, yield: u0, active: true, risk-level: u7,
       apy: u1500, volatility: u600, max-drawdown: u1200, sharpe-ratio: u100})
    
    ;; Initialize dynamic allocations (equal weight initially)
    (map-set strategy-allocations {id: u1} 
      {target-weight: u3333, current-weight: u0, max-allocation: u4000})
    (map-set strategy-allocations {id: u2} 
      {target-weight: u3333, current-weight: u0, max-allocation: u4000})
    (map-set strategy-allocations {id: u3} 
      {target-weight: u3334, current-weight: u0, max-allocation: u4000})
    
    ;; Initialize risk limits
    (map-set strategy-risk-limits {id: u1} 
      {max-allocation: u4000, stop-loss: u1000, risk-budget: u2000})
    (map-set strategy-risk-limits {id: u2} 
      {max-allocation: u4000, stop-loss: u1500, risk-budget: u3000})
    (map-set strategy-risk-limits {id: u3} 
      {max-allocation: u4000, stop-loss: u2000, risk-budget: u4000})
    
    (var-set last-fee-collection stacks-block-height)
    (var-set last-rebalance stacks-block-height)
    (var-set initialized true)
    
    (print {event: "vault-initialized", owner: tx-sender})
    (ok true)
  )
)

;; ========== MODIFIERS ==========

(define-private (is-owner)
  (is-eq tx-sender (var-get contract-owner)))

(define-private (not-paused)
  (not (var-get vault-paused)))

(define-private (not-emergency)
  (not (var-get emergency-shutdown-flag)))

(define-private (is-initialized)
  (var-get initialized))

;; ========== GAMIFICATION FUNCTIONS ==========

(define-public (create-referral-code (code (string-ascii 20)))
  (begin
    (asserts! (is-initialized) (err ERR-UNAUTHORIZED))
    (asserts! (is-none (map-get? referral-codes {code: code})) (err ERR-INVALID-REFERRAL))
    
    (map-set referral-codes {code: code} 
      {owner: tx-sender, uses: u0, active: true})
    
    (print {event: "referral-code-created", user: tx-sender, code: code})
    (ok true)
  )
)

(define-private (award-points (user principal) (input-amount uint))
  (begin
    ;; Validate amount before using
    (asserts! (validate-amount input-amount) (err ERR-INVALID-AMOUNT))
    
    (let (
      (current-achievements (get-user-achievements user))
      (validated-amount input-amount) ;; Use validated amount consistently
      (points-to-award (* validated-amount POINTS-PER-STX))
      (new-points (+ (get points current-achievements) points-to-award))
      (new-level (calculate-user-level new-points))
    )
      (begin
        ;; Mint points tokens
        (unwrap! (ft-mint? radrum-points points-to-award user) (err ERR-INVALID-AMOUNT))
        
        ;; Update achievements
        (map-set user-achievements {user: user}
          (merge current-achievements {
            points: new-points,
            level: new-level,
            total-earned: (+ (get total-earned current-achievements) points-to-award),
            last-activity: stacks-block-height
          }))
        
        (var-set total-points-issued (+ (var-get total-points-issued) points-to-award))
        (ok points-to-award)
      )
    )
  )
)

;; Simplified referral processing that tracks referrals 
(define-private (process-referral (referral-code (optional (string-ascii 20))))
  (match referral-code
    code (let (
      (referral-info (map-get? referral-codes {code: code}))
    )
      (match referral-info
        info (let (
          (referrer (get owner info))
          (current-referrals (default-to {total-referred: u0, total-bonus: u0} 
                                        (map-get? user-referrals {referrer: referrer})))
        )
          (if (not (is-eq referrer tx-sender))
              (begin
                ;; Update referral stats
                (map-set user-referrals {referrer: referrer}
                  {total-referred: (+ (get total-referred current-referrals) u1),
                   total-bonus: (get total-bonus current-referrals)})
                
                ;; Update referral code usage
                (map-set referral-codes {code: code}
                  (merge info {uses: (+ (get uses info) u1)}))
                
                (ok referrer)
              )
              (ok tx-sender)
          )
        )
        (ok tx-sender)
      )
    )
    (ok tx-sender)
  )
)

;; ========== DYNAMIC ALLOCATION FUNCTIONS ==========

(define-read-only (calculate-allocation-drift)
  (let (
    (total-deployed (fold + (list 
      (get balance (default-to {balance: u0, yield: u0, active: false, name: "", risk-level: u0, apy: u0, volatility: u0, max-drawdown: u0, sharpe-ratio: u0} (map-get? strategies {id: u1})))
      (get balance (default-to {balance: u0, yield: u0, active: false, name: "", risk-level: u0, apy: u0, volatility: u0, max-drawdown: u0, sharpe-ratio: u0} (map-get? strategies {id: u2})))
      (get balance (default-to {balance: u0, yield: u0, active: false, name: "", risk-level: u0, apy: u0, volatility: u0, max-drawdown: u0, sharpe-ratio: u0} (map-get? strategies {id: u3})))
    ) u0))
  )
    (if (is-eq total-deployed u0)
        u0
        (let (
          (strategy1-current (/ (* (get balance (default-to {balance: u0, yield: u0, active: false, name: "", risk-level: u0, apy: u0, volatility: u0, max-drawdown: u0, sharpe-ratio: u0} (map-get? strategies {id: u1}))) PRECISION) total-deployed))
          (strategy1-target (get target-weight (default-to {target-weight: u0, current-weight: u0, max-allocation: u0} (map-get? strategy-allocations {id: u1}))))
          (drift1 (if (> strategy1-current strategy1-target) 
                     (- strategy1-current strategy1-target) 
                     (- strategy1-target strategy1-current)))
        )
          drift1
        )
    )
  )
)

(define-read-only (needs-rebalancing)
  (> (calculate-allocation-drift) (var-get rebalance-threshold)))

;; Fixed rebalance-strategies function with simplified response handling
(define-public (rebalance-strategies)
  (begin
    (asserts! (is-initialized) (err ERR-UNAUTHORIZED))
    (asserts! (not-paused) (err ERR-VAULT-PAUSED))
    (asserts! (not-emergency) (err ERR-VAULT-PAUSED))
    (asserts! (needs-rebalancing) (err ERR-REBALANCE-NOT-NEEDED))
    
    ;; Withdraw all from strategies - use unwrap-panic to handle response
    (unwrap-panic (withdraw-all-from-strategies))
    
    ;; Redeploy according to target allocations - use unwrap-panic to handle response
    (unwrap-panic (deploy-to-all-strategies))
    
    (var-set last-rebalance stacks-block-height)
    
    (print {event: "strategies-rebalanced", timestamp: stacks-block-height})
    (ok true)
  )
)

(define-private (withdraw-all-from-strategies)
  (let (
    (strategy1 (default-to {balance: u0, yield: u0, active: false, name: "", risk-level: u0, apy: u0, volatility: u0, max-drawdown: u0, sharpe-ratio: u0} (map-get? strategies {id: u1})))
    (strategy2 (default-to {balance: u0, yield: u0, active: false, name: "", risk-level: u0, apy: u0, volatility: u0, max-drawdown: u0, sharpe-ratio: u0} (map-get? strategies {id: u2})))
    (strategy3 (default-to {balance: u0, yield: u0, active: false, name: "", risk-level: u0, apy: u0, volatility: u0, max-drawdown: u0, sharpe-ratio: u0} (map-get? strategies {id: u3})))
    (total-to-withdraw (+ (+ (get balance strategy1) (get balance strategy2)) (get balance strategy3)))
  )
    (begin
      ;; Reset all strategy balances
      (map-set strategies {id: u1} (merge strategy1 {balance: u0}))
      (map-set strategies {id: u2} (merge strategy2 {balance: u0}))
      (map-set strategies {id: u3} (merge strategy3 {balance: u0}))
      
      ;; Add to vault assets
      (var-set total-assets (+ (var-get total-assets) total-to-withdraw))
      
      (ok total-to-withdraw)
    )
  )
)

(define-private (deploy-to-all-strategies)
  (let (
    (total-assets-to-deploy (var-get total-assets))
    (allocation1 (get target-weight (default-to {target-weight: u0, current-weight: u0, max-allocation: u0} (map-get? strategy-allocations {id: u1}))))
    (allocation2 (get target-weight (default-to {target-weight: u0, current-weight: u0, max-allocation: u0} (map-get? strategy-allocations {id: u2}))))
    (allocation3 (get target-weight (default-to {target-weight: u0, current-weight: u0, max-allocation: u0} (map-get? strategy-allocations {id: u3}))))
  )
    (let (
      (amount1 (/ (* total-assets-to-deploy allocation1) PRECISION))
      (amount2 (/ (* total-assets-to-deploy allocation2) PRECISION))
      (amount3 (/ (* total-assets-to-deploy allocation3) PRECISION))
    )
      (begin
        ;; Deploy to each strategy - use unwrap-panic for consistent error handling
        (unwrap-panic (deploy-to-specific-strategy u1 amount1))
        (unwrap-panic (deploy-to-specific-strategy u2 amount2))
        (unwrap-panic (deploy-to-specific-strategy u3 amount3))
        
        ;; Update vault assets (should be close to 0 after deployment)
        (var-set total-assets (- total-assets-to-deploy (+ (+ amount1 amount2) amount3)))
        
        (ok (+ (+ amount1 amount2) amount3))
      )
    )
  )
)

(define-private (deploy-to-specific-strategy (strategy-id uint) (amount uint))
  (begin
    ;; Validate inputs
    (asserts! (validate-strategy-id strategy-id) (err ERR-INVALID-STRATEGY))
    (asserts! (validate-amount amount) (err ERR-INVALID-AMOUNT))
    
    (let ((strategy (unwrap! (map-get? strategies {id: strategy-id}) (err ERR-STRATEGY-NOT-FOUND))))
      (begin
        (map-set strategies {id: strategy-id}
          (merge strategy {balance: (+ (get balance strategy) amount)}))
        (ok amount)
      )
    )
  )
)

;; ========== RISK MANAGEMENT FUNCTIONS ==========

(define-public (update-strategy-risk-metrics (strategy-id uint) (apy uint) (volatility uint) (max-drawdown uint))
  (begin
    (asserts! (is-owner) (err ERR-UNAUTHORIZED))
    (asserts! (is-initialized) (err ERR-UNAUTHORIZED))
    ;; Validate all inputs
    (asserts! (validate-strategy-id strategy-id) (err ERR-INVALID-STRATEGY))
    (asserts! (validate-apy apy) (err ERR-INVALID-AMOUNT))
    (asserts! (validate-volatility volatility) (err ERR-INVALID-AMOUNT))
    (asserts! (validate-drawdown max-drawdown) (err ERR-INVALID-AMOUNT))
    
    (let ((strategy (unwrap! (map-get? strategies {id: strategy-id}) (err ERR-STRATEGY-NOT-FOUND))))
      (let ((sharpe-ratio (if (> volatility u0) (/ (* apy PRECISION) volatility) u0)))
        (map-set strategies {id: strategy-id}
          (merge strategy {
            apy: apy,
            volatility: volatility,
            max-drawdown: max-drawdown,
            sharpe-ratio: sharpe-ratio
          }))
        
        (print {event: "strategy-metrics-updated", strategy: strategy-id, apy: apy, volatility: volatility})
        (ok true)
      )
    )
  )
)

(define-public (optimize-allocation-by-sharpe)
  (begin
    (asserts! (is-owner) (err ERR-UNAUTHORIZED))
    (asserts! (is-initialized) (err ERR-UNAUTHORIZED))
    
    (let (
      (strategy1 (unwrap! (map-get? strategies {id: u1}) (err ERR-STRATEGY-NOT-FOUND)))
      (strategy2 (unwrap! (map-get? strategies {id: u2}) (err ERR-STRATEGY-NOT-FOUND)))
      (strategy3 (unwrap! (map-get? strategies {id: u3}) (err ERR-STRATEGY-NOT-FOUND)))
      (total-sharpe (+ (+ (get sharpe-ratio strategy1) (get sharpe-ratio strategy2)) (get sharpe-ratio strategy3)))
    )
      (if (> total-sharpe u0)
          (let (
            (weight1 (/ (* (get sharpe-ratio strategy1) PRECISION) total-sharpe))
            (weight2 (/ (* (get sharpe-ratio strategy2) PRECISION) total-sharpe))
            (weight3 (/ (* (get sharpe-ratio strategy3) PRECISION) total-sharpe))
          )
            (begin
              ;; Update target allocations based on Sharpe ratios
              (map-set strategy-allocations {id: u1} 
                {target-weight: weight1, current-weight: u0, max-allocation: u4000})
              (map-set strategy-allocations {id: u2} 
                {target-weight: weight2, current-weight: u0, max-allocation: u4000})
              (map-set strategy-allocations {id: u3} 
                {target-weight: weight3, current-weight: u0, max-allocation: u4000})
              
              (print {event: "allocation-optimized", weights: {w1: weight1, w2: weight2, w3: weight3}})
              (ok true)
            )
          )
          (ok false)
      )
    )
  )
)

;; ========== FEE MANAGEMENT ==========

(define-private (collect-management-fees)
  (let (
    (last-collected (var-get last-fee-collection))
    (current-block stacks-block-height)
    (elapsed-blocks (- current-block last-collected))
    (vault-assets (var-get total-assets))
    (management-fee-rate (var-get management-fee))
  )
    (if (or (is-eq elapsed-blocks u0) (is-eq vault-assets u0))
        (ok u0)
        (let (
          (annual-fee (/ (* vault-assets management-fee-rate) PRECISION))
          (fee (/ (* annual-fee elapsed-blocks) SECONDS-PER-YEAR))
        )
          (if (> fee u0)
              (begin
                (var-set total-assets (- vault-assets fee))
                (var-set total-fees-collected (+ (var-get total-fees-collected) fee))
                (var-set last-fee-collection current-block)
                ;; Transfer fee to treasury
                (unwrap! (as-contract (stx-transfer? fee tx-sender (var-get treasury))) (err ERR-INSUFFICIENT-BALANCE))
                (ok fee)
              )
              (ok u0)
          )
        )
    )
  )
)

(define-private (collect-performance-fees (input-profit uint))
  (begin
    ;; Validate profit amount
    (asserts! (validate-amount input-profit) (err ERR-INVALID-AMOUNT))
    
    (let (
      (current-share-price (get-share-price))
      (high-water (var-get high-water-mark))
      (validated-profit input-profit) ;; Use validated profit consistently
    )
      (if (> current-share-price high-water)
          (let (
            (performance-fee-rate (var-get performance-fee))
            (fee-amount (/ (* validated-profit performance-fee-rate) PRECISION))
          )
            (if (> fee-amount u0)
                (begin
                  ;; Update high water mark
                  (var-set high-water-mark current-share-price)
                  
                  ;; Collect fee by minting shares to treasury
                  (let ((fee-shares (/ (* fee-amount (var-get total-shares)) (var-get total-assets))))
                    (var-set total-shares (+ (var-get total-shares) fee-shares))
                    (map-set shares {user: (var-get treasury)} 
                      {balance: (+ (get balance (get-user-shares (var-get treasury))) fee-shares), 
                       last-deposit: stacks-block-height,
                       total-deposited: u0,
                       deposit-count: u0})
                  )
                  
                  (var-set total-fees-collected (+ (var-get total-fees-collected) fee-amount))
                  (ok fee-amount)
                )
                (ok u0)
            )
          )
          (ok u0)
      )
    )
  )
)

(define-private (harvest-strategy (strategy-id uint))
  (begin
    ;; Validate strategy ID
    (asserts! (validate-strategy-id strategy-id) (err ERR-INVALID-STRATEGY))
    
    (let ((strategy (unwrap! (map-get? strategies {id: strategy-id}) (err ERR-STRATEGY-NOT-FOUND))))
      (let ((yield-amount (get yield strategy)))
        (if (> yield-amount u0)
            (begin
              ;; Reset strategy yield
              (map-set strategies {id: strategy-id}
                (merge strategy {yield: u0}))
              
              ;; Add yield to total assets
              (var-set total-assets (+ (var-get total-assets) yield-amount))
              (ok yield-amount)
            )
            (ok u0)
        )
      )
    )
  )
)

;; ========== USER INTERACTIONS ==========

;; Fixed deposit function with proper error handling
(define-public (deposit (input-amount uint) (input-min-shares uint) (referral-code (optional (string-ascii 20))))
  (begin
    ;; Validate inputs first
    (asserts! (validate-amount input-amount) (err ERR-INVALID-AMOUNT))
    (asserts! (validate-shares input-min-shares) (err ERR-INVALID-AMOUNT))
    (asserts! (is-initialized) (err ERR-UNAUTHORIZED))
    (asserts! (not-paused) (err ERR-VAULT-PAUSED))
    (asserts! (not (var-get emergency-shutdown-flag)) (err ERR-VAULT-PAUSED))
    
    (let (
      (assets (var-get total-assets))
      (total-shares-supply (var-get total-shares))
      (share-price (get-share-price))
      (user-data (get-user-shares tx-sender))
      (loyalty-multiplier (calculate-loyalty-multiplier tx-sender))
      (validated-amount input-amount) ;; Use validated amount consistently
      (validated-min-shares input-min-shares) ;; Use validated min-shares consistently
      (mint-shares (if (is-eq total-shares-supply u0)
                       validated-amount
                       (/ (* validated-amount PRECISION) share-price)))
      (bonus-shares (/ (* mint-shares (- loyalty-multiplier PRECISION)) PRECISION))
    )
      (begin
        (asserts! (>= (+ mint-shares bonus-shares) validated-min-shares) (err ERR-SLIPPAGE-TOO-HIGH))
        
        ;; Process referral if provided (tracks referrals without point rewards)
        (unwrap-panic (process-referral referral-code))
        
        ;; Collect management fees before deposit
        (try! (collect-management-fees))
        
        ;; Transfer STX to vault
        (try! (stx-transfer? validated-amount tx-sender (as-contract tx-sender)))
        
        ;; Award gamification points to depositor
        (try! (award-points tx-sender validated-amount))
        
        ;; Update user shares with enhanced tracking
        (map-set shares {user: tx-sender} 
          {balance: (+ (get balance user-data) mint-shares bonus-shares), 
           last-deposit: stacks-block-height,
           total-deposited: (+ (get total-deposited user-data) validated-amount),
           deposit-count: (+ (get deposit-count user-data) u1)})
        
        ;; Update vault state
        (var-set total-assets (+ assets validated-amount))
        (var-set total-shares (+ total-shares-supply mint-shares bonus-shares))
        
        ;; Auto-rebalance if enabled and needed - properly handle the response
        (let ((should-rebalance (and (var-get auto-rebalance-enabled) (needs-rebalancing))))
          (unwrap-panic (if should-rebalance
              (begin 
                  (unwrap! (rebalance-strategies) (err ERR-REBALANCE-NOT-NEEDED))
                  (ok true))
              (begin
                  (unwrap! (deploy-to-all-strategies) (err ERR-STRATEGY-NOT-FOUND))
                  (ok true)))))
        
        (print {event: "deposit", user: tx-sender, amount: validated-amount, shares: (+ mint-shares bonus-shares), bonus: bonus-shares})
        (ok (+ mint-shares bonus-shares))
      )
    )
  )
)

(define-public (request-withdrawal (input-user-shares uint))
  (begin
    ;; Validate input
    (asserts! (validate-shares input-user-shares) (err ERR-INVALID-AMOUNT))
    
    (let ((user-balance (get-user-shares tx-sender))
          (validated-shares input-user-shares)) ;; Use validated shares consistently
      (asserts! (is-initialized) (err ERR-UNAUTHORIZED))
      (asserts! (not-emergency) (err ERR-VAULT-PAUSED))
      (asserts! (<= validated-shares (get balance user-balance)) (err ERR-NO-SHARES))
      
      ;; Set withdrawal request with cooldown
      (map-set withdrawal-requests {user: tx-sender} 
        {amount: validated-shares, timestamp: (+ stacks-block-height u144)}) ;; ~24 hour cooldown
      
      (print {event: "withdrawal-requested", user: tx-sender, shares: validated-shares})
      (ok true)
    )
  )
)

(define-public (execute-withdrawal)
  (let (
    (request (unwrap! (map-get? withdrawal-requests {user: tx-sender}) (err ERR-NO-SHARES)))
    (user-shares (get amount request))
    (cooldown-end (get timestamp request))
    (user-balance (get-user-shares tx-sender))
    (assets (var-get total-assets))
    (total-shares-supply (var-get total-shares))
  )
    (asserts! (is-initialized) (err ERR-UNAUTHORIZED))
    (asserts! (>= stacks-block-height cooldown-end) (err ERR-COOLDOWN-ACTIVE))
    (asserts! (<= user-shares (get balance user-balance)) (err ERR-NO-SHARES))
    
    ;; Collect fees before withdrawal
    (try! (collect-management-fees))
    
    ;; Calculate withdrawal amount
    (let ((withdrawal-amount (/ (* user-shares assets) total-shares-supply)))
      ;; Validate withdrawal amount
      (asserts! (validate-amount withdrawal-amount) (err ERR-INVALID-AMOUNT))
      
      ;; Ensure vault has enough liquid assets
      (if (> withdrawal-amount assets)
    (unwrap-panic (withdraw-all-from-strategies))
    u0)
      
      ;; Update user balance
      (map-set shares {user: tx-sender} 
        (merge user-balance {balance: (- (get balance user-balance) user-shares)}))
      
      ;; Update vault state
      (var-set total-shares (- total-shares-supply user-shares))
      (var-set total-assets (- (var-get total-assets) withdrawal-amount))
      
      ;; Remove withdrawal request
      (map-delete withdrawal-requests {user: tx-sender})
      
      ;; Transfer STX to user
      (try! (as-contract (stx-transfer? withdrawal-amount tx-sender tx-sender)))
      
      (print {event: "withdrawal", user: tx-sender, amount: withdrawal-amount, shares: user-shares})
      (ok withdrawal-amount)
    )
  )
)

;; ========== YIELD MANAGEMENT ==========

(define-public (simulate-yield (strategy-id uint) (input-amount uint))
  (begin
    (asserts! (is-owner) (err ERR-UNAUTHORIZED))
    (asserts! (is-initialized) (err ERR-UNAUTHORIZED))
    ;; Validate inputs
    (asserts! (validate-strategy-id strategy-id) (err ERR-INVALID-STRATEGY))
    (asserts! (validate-amount input-amount) (err ERR-INVALID-AMOUNT))
    
    (let ((strategy (unwrap! (map-get? strategies {id: strategy-id}) (err ERR-STRATEGY-NOT-FOUND)))
          (validated-amount input-amount)) ;; Use validated amount consistently
      (begin
        (map-set strategies {id: strategy-id}
          (merge strategy {yield: (+ (get yield strategy) validated-amount)}))
        
        (print {event: "yield-simulated", strategy: strategy-id, amount: validated-amount})
        (ok validated-amount)
      )
    )
  )
)

(define-public (harvest-all-strategies)
  (begin
    (asserts! (is-initialized) (err ERR-UNAUTHORIZED))
    (asserts! (not-emergency) (err ERR-VAULT-PAUSED))
    
    (let (
      (yield1 (try! (harvest-strategy u1)))
      (yield2 (try! (harvest-strategy u2)))
      (yield3 (try! (harvest-strategy u3)))
      (total-yield (+ (+ yield1 yield2) yield3))
    )
      (begin
        ;; Collect performance fees on profits
        (unwrap-panic (collect-performance-fees total-yield))
        (var-set last-harvest stacks-block-height)
        
        ;; Auto-rebalance after harvest if enabled - simplified response handling
        (if (and (var-get auto-rebalance-enabled) (needs-rebalancing))
    (begin
        (unwrap-panic (rebalance-strategies))
        u1)  ;; Return 1 for rebalanced
    u0)      ;; Return 0 for not rebalanced
        
        (print {event: "harvest-all", total-yield: total-yield})
        (ok total-yield)
      )
    )
  )
)

;; ========== GOVERNANCE FUNCTIONS ==========

(define-public (set-strategy-allocation (strategy-id uint) (target-weight uint) (max-allocation uint))
  (begin
    (asserts! (is-owner) (err ERR-UNAUTHORIZED))
    (asserts! (is-initialized) (err ERR-UNAUTHORIZED))
    ;; Validate inputs
    (asserts! (validate-strategy-id strategy-id) (err ERR-INVALID-STRATEGY))
    (asserts! (validate-allocation target-weight) (err ERR-INVALID-ALLOCATION))
    (asserts! (<= max-allocation MAX-STRATEGY-ALLOCATION) (err ERR-INVALID-ALLOCATION))
    
    (let ((current-allocation (default-to {target-weight: u0, current-weight: u0, max-allocation: u0} 
                                         (map-get? strategy-allocations {id: strategy-id}))))
      (map-set strategy-allocations {id: strategy-id}
        (merge current-allocation {target-weight: target-weight, max-allocation: max-allocation}))
      
      (print {event: "allocation-updated", strategy: strategy-id, target: target-weight, max: max-allocation})
      (ok true)
    )
  )
)

(define-public (toggle-auto-rebalance)
  (begin
    (asserts! (is-owner) (err ERR-UNAUTHORIZED))
    (var-set auto-rebalance-enabled (not (var-get auto-rebalance-enabled)))
    (print {event: "auto-rebalance-toggled", enabled: (var-get auto-rebalance-enabled)})
    (ok (var-get auto-rebalance-enabled))
  )
)

(define-public (set-rebalance-threshold (threshold uint))
  (begin
    (asserts! (is-owner) (err ERR-UNAUTHORIZED))
    ;; Validate threshold input
    (asserts! (validate-threshold threshold) (err ERR-INVALID-AMOUNT))
    (var-set rebalance-threshold threshold)
    (print {event: "rebalance-threshold-updated", threshold: threshold})
    (ok true)
  )
)

(define-public (pause-vault)
  (begin
    (asserts! (is-owner) (err ERR-UNAUTHORIZED))
    (var-set vault-paused true)
    (print {event: "vault-paused", by: tx-sender})
    (ok true)
  )
)

(define-public (unpause-vault)
  (begin
    (asserts! (is-owner) (err ERR-UNAUTHORIZED))
    (var-set vault-paused false)
    (print {event: "vault-unpaused", by: tx-sender})
    (ok true)
  )
)

(define-public (emergency-shutdown)
  (begin
    (asserts! (is-owner) (err ERR-UNAUTHORIZED))
    (var-set emergency-shutdown-flag true)
    (var-set vault-paused true)
    (print {event: "emergency-shutdown", by: tx-sender})
    (ok true)
  )
)

(define-public (set-management-fee (new-fee uint))
  (begin
    (asserts! (is-owner) (err ERR-UNAUTHORIZED))
    (asserts! (<= new-fee MAX-MANAGEMENT-FEE) (err ERR-INVALID-FEE))
    (var-set management-fee new-fee)
    (print {event: "management-fee-updated", new-fee: new-fee})
    (ok true)
  )
)

(define-public (set-performance-fee (new-fee uint))
  (begin
    (asserts! (is-owner) (err ERR-UNAUTHORIZED))
    (asserts! (<= new-fee MAX-PERFORMANCE-FEE) (err ERR-INVALID-FEE))
    (var-set performance-fee new-fee)
    (print {event: "performance-fee-updated", new-fee: new-fee})
    (ok true)
  )
)

(define-public (set-treasury (new-treasury principal))
  (begin
    (asserts! (is-owner) (err ERR-UNAUTHORIZED))
    (var-set treasury new-treasury)
    (print {event: "treasury-updated", new-treasury: new-treasury})
    (ok true)
  )
)

(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-owner) (err ERR-UNAUTHORIZED))
    (var-set pending-owner new-owner)
    (print {event: "ownership-transfer-initiated", new-owner: new-owner})
    (ok true)
  )
)

(define-public (accept-ownership)
  (begin
    (asserts! (is-eq tx-sender (var-get pending-owner)) (err ERR-UNAUTHORIZED))
    (var-set contract-owner tx-sender)
    (print {event: "ownership-transferred", new-owner: tx-sender})
    (ok true)
  )
)

;; ========== GAMIFICATION PUBLIC FUNCTIONS ==========

(define-public (claim-loyalty-bonus)
  (let (
  (user-achievements-data (get-user-achievements tx-sender))
  (user-shares-data (get-user-shares tx-sender))
  (loyalty-multiplier (calculate-loyalty-multiplier tx-sender))
)
  (begin
    (asserts! (is-initialized) (err ERR-UNAUTHORIZED))
    (asserts! (> loyalty-multiplier PRECISION) (err ERR-INVALID-AMOUNT))
    
    ;; Update loyalty multiplier in achievements map
    (map-set user-achievements {user: tx-sender}
      (merge user-achievements-data {loyalty-multiplier: loyalty-multiplier}))
    
    (print {event: "loyalty-bonus-claimed", user: tx-sender, multiplier: loyalty-multiplier})
    (ok loyalty-multiplier)
  )
)
)

(define-read-only (get-user-stats (user principal))
  {
    shares: (get-user-shares user),
    achievements: (get-user-achievements user),
    loyalty-multiplier: (calculate-loyalty-multiplier user),
    referrals: (default-to {total-referred: u0, total-bonus: u0} (map-get? user-referrals {referrer: user}))
  }
)

;; ========== MANUAL REFERRAL POINT AWARDING (OPTIONAL) ==========

;; Owner can manually award referral points if needed
(define-public (manual-award-referral-points (referrer principal) (input-amount uint))
  (begin
    (asserts! (is-owner) (err ERR-UNAUTHORIZED))
    (asserts! (is-initialized) (err ERR-UNAUTHORIZED))
    ;; Validate amount input
    (asserts! (validate-amount input-amount) (err ERR-INVALID-AMOUNT))
    
    (let ((validated-amount input-amount)) ;; Use validated amount consistently
      (try! (award-points referrer validated-amount))
      
      (print {event: "manual-referral-points-awarded", referrer: referrer, amount: validated-amount})
      (ok validated-amount)
    )
  )
)
