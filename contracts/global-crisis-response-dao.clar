(define-constant ERR-NOT-MEMBER u100)
(define-constant ERR-ALREADY-VOTED u101)
(define-constant ERR-PROPOSAL-NOT-FOUND u102)
(define-constant ERR-NOT-ACTIVE u103)
(define-constant ERR-NOT-PROPOSER u104)
(define-constant ERR-VOTING-OPEN u105)
(define-constant ERR-VOTING-CLOSED u106)
(define-constant ERR-EXECUTED u107)
(define-constant ERR-CANCELED u108)
(define-constant ERR-INSUFFICIENT-TREASURY u109)
(define-constant ERR-DUPLICATE-MEMBER u112)
(define-constant ERR-ZERO-AMOUNT u113)
(define-constant ERR-INVALID u114)

(define-constant VOTING-PERIOD u144)
(define-constant QUORUM-PCT u20)

(define-data-var next-proposal-id uint u1)
(define-data-var total-weight uint u0)

(define-map members { addr: principal } { joined-at: uint, weight: uint, active: bool })
(define-map proposals
  { id: uint }
  { proposer: principal,
    recipient: principal,
    amount: uint,
    start-height: uint,
    end-height: uint,
    yes: uint,
    no: uint,
    executed: bool,
    canceled: bool,
    memo: (buff 64) })
(define-map votes { id: uint, voter: principal } { choice: bool, weight: uint })

(define-read-only (is-active-member (who principal))
  (match (map-get? members { addr: who })
    m (and (get active m) (> (get weight m) u0))
    false))

(define-read-only (get-member (who principal))
  (map-get? members { addr: who }))

(define-read-only (get-proposal (id uint))
  (map-get? proposals { id: id }))

(define-read-only (get-vote (id uint) (who principal))
  (map-get? votes { id: id, voter: who }))

(define-read-only (get-total-weight)
  (var-get total-weight))

(define-read-only (get-current-height)
  stacks-block-height)

(define-read-only (get-treasury)
  (as-contract (stx-get-balance tx-sender)))

(define-read-only (get-header-hash (h uint))
  (get-stacks-block-info? header-hash h))

(define-public (join)
  (let ((m (map-get? members { addr: tx-sender })))
    (if (is-some m)
        (let ((m1 (unwrap-panic m)))
          (if (get active m1)
              (err ERR-DUPLICATE-MEMBER)
              (begin
                (map-set members { addr: tx-sender }
                  { joined-at: stacks-block-height,
                    weight: (get weight m1),
                    active: true })
                (var-set total-weight (+ (var-get total-weight) (get weight m1)))
                (ok true))))
        (begin
          (map-set members { addr: tx-sender }
            { joined-at: stacks-block-height, weight: u1, active: true })
          (var-set total-weight (+ (var-get total-weight) u1))
          (ok true)))))

(define-public (leave)
  (match (map-get? members { addr: tx-sender })
    m (if (and (get active m) (> (get weight m) u0))
           (begin
             (map-set members { addr: tx-sender }
               { joined-at: (get joined-at m), weight: (get weight m), active: false })
             (var-set total-weight (- (var-get total-weight) (get weight m)))
             (ok true))
           (err ERR-NOT-ACTIVE))
    (err ERR-NOT-MEMBER)))

(define-private (can-propose (who principal))
  (is-active-member who))

(define-private (ensure-proposal-open (p { proposer: principal, recipient: principal, amount: uint, start-height: uint, end-height: uint, yes: uint, no: uint, executed: bool, canceled: bool, memo: (buff 64) }))
  (and (not (get executed p)) (not (get canceled p)) (<= stacks-block-height (get end-height p))))

(define-private (ensure-proposal-closed (p { proposer: principal, recipient: principal, amount: uint, start-height: uint, end-height: uint, yes: uint, no: uint, executed: bool, canceled: bool, memo: (buff 64) }))
  (and (not (get executed p)) (not (get canceled p)) (> stacks-block-height (get end-height p))))

(define-public (propose (recipient principal) (amount uint) (memo (buff 64)))
  (if (not (can-propose tx-sender))
      (err ERR-NOT-MEMBER)
      (if (is-eq amount u0)
          (err ERR-ZERO-AMOUNT)
          (let (
                (treasury (as-contract (stx-get-balance tx-sender)))
                (id (var-get next-proposal-id))
                (end (+ stacks-block-height VOTING-PERIOD)))
            (if (< treasury amount)
                (err ERR-INSUFFICIENT-TREASURY)
                (begin
                  (map-set proposals { id: id }
                    { proposer: tx-sender,
                      recipient: recipient,
                      amount: amount,
                      start-height: stacks-block-height,
                      end-height: end,
                      yes: u0,
                      no: u0,
                      executed: false,
                      canceled: false,
                      memo: memo })
                  (var-set next-proposal-id (+ id u1))
                  (ok id)))))))

(define-public (vote (id uint) (support bool))
  (if (not (is-active-member tx-sender))
      (err ERR-NOT-MEMBER)
      (match (map-get? members { addr: tx-sender })
        m (match (map-get? proposals { id: id })
            p (if (not (ensure-proposal-open p))
                    (err ERR-VOTING-CLOSED)
                    (if (is-some (map-get? votes { id: id, voter: tx-sender }))
                        (err ERR-ALREADY-VOTED)
                        (let ((w (get weight m)))
                          (begin
                            (map-set votes { id: id, voter: tx-sender } { choice: support, weight: w })
                            (if support
                                (map-set proposals { id: id }
                                  { proposer: (get proposer p),
                                    recipient: (get recipient p),
                                    amount: (get amount p),
                                    start-height: (get start-height p),
                                    end-height: (get end-height p),
                                    yes: (+ (get yes p) w),
                                    no: (get no p),
                                    executed: (get executed p),
                                    canceled: (get canceled p),
                                    memo: (get memo p) })
                                (map-set proposals { id: id }
                                  { proposer: (get proposer p),
                                    recipient: (get recipient p),
                                    amount: (get amount p),
                                    start-height: (get start-height p),
                                    end-height: (get end-height p),
                                    yes: (get yes p),
                                    no: (+ (get no p) w),
                                    executed: (get executed p),
                                    canceled: (get canceled p),
                                    memo: (get memo p) }))
                            (ok true)))))
          (err ERR-PROPOSAL-NOT-FOUND))
        (err ERR-NOT-MEMBER))))

(define-private (meets-quorum (yes uint))
  (let ((tw (var-get total-weight)))
    (if (is-eq tw u0)
        false
        (>= (* yes u100) (* tw QUORUM-PCT)))))

(define-public (execute (id uint))
  (match (map-get? proposals { id: id })
    p (if (ensure-proposal-closed p)
           (if (or (get executed p) (get canceled p))
               (err ERR-EXECUTED)
               (if (and (meets-quorum (get yes p)) (> (get yes p) (get no p)))
                   (let ((amt (get amount p)) (rcp (get recipient p)))
                     (let ((res (as-contract (stx-transfer? amt tx-sender rcp))))
                       (match res
                         okv (begin
                               (map-set proposals { id: id }
                                 { proposer: (get proposer p),
                                   recipient: (get recipient p),
                                   amount: (get amount p),
                                   start-height: (get start-height p),
                                   end-height: (get end-height p),
                                   yes: (get yes p),
                                   no: (get no p),
                                   executed: true,
                                   canceled: (get canceled p),
                                   memo: (get memo p) })
                               (ok true))
                         errv (err ERR-INSUFFICIENT-TREASURY))))
                   (err ERR-INVALID)))
           (err ERR-VOTING-OPEN))
    (err ERR-PROPOSAL-NOT-FOUND)))

(define-public (cancel (id uint))
  (match (map-get? proposals { id: id })
    p (if (or (get executed p) (get canceled p))
           (err ERR-EXECUTED)
           (if (is-eq (get proposer p) tx-sender)
               (if (<= stacks-block-height (get end-height p))
                   (begin
                     (map-set proposals { id: id }
                       { proposer: (get proposer p),
                         recipient: (get recipient p),
                         amount: (get amount p),
                         start-height: (get start-height p),
                         end-height: (get end-height p),
                         yes: (get yes p),
                         no: (get no p),
                         executed: (get executed p),
                         canceled: true,
                         memo: (get memo p) })
                     (ok true))
                   (err ERR-VOTING-CLOSED))
               (err ERR-NOT-PROPOSER)))
    (err ERR-PROPOSAL-NOT-FOUND)))

(define-read-only (list-proposal-stats (id uint))
  (match (map-get? proposals { id: id })
    p (ok { yes: (get yes p), no: (get no p), end: (get end-height p), executed: (get executed p), canceled: (get canceled p) })
    (err ERR-PROPOSAL-NOT-FOUND)))
