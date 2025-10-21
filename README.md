# Global-Crisis-Response-DAO 🌍🚑

A minimal DAO on Stacks to coordinate crisis-response funding. Members join, propose disbursements, vote, and execute approved STX transfers from the treasury.

## Features
- Open membership with equal voting weight
- Proposals with recipient, amount, and memo
- Voting window in blocks, quorum, and simple majority
- Execute transfers from contract to recipient on success

## Files
- contracts/global-crisis-response-dao.clar
- Clarinet.toml

## Quickstart ⚡
1) Create project and contract
```
clarinet new global-crisis-response-dao
cd global-crisis-response-dao
clarinet contract new global-crisis-response-dao
```

2) Replace files with the contents here, then normalize line endings (Windows) ⏎
```
pwsh
(Get-Content "contracts/global-crisis-response-dao.clar" -Raw).Replace("`r`n", "`n") | Set-Content "contracts/global-crisis-response-dao.clar" -NoNewline
(Get-Content "Clarinet.toml" -Raw).Replace("`r`n", "`n") | Set-Content "Clarinet.toml" -NoNewline
```

3) Check compilation ✅
```
clarinet check
```

## Interact 🧪
```
clarinet console
(contract-call? .global-crisis-response-dao join)
(contract-call? .global-crisis-response-dao propose 'SP2C2M4EXAMPLEADDRESS000000000000000000 u100000 "Earthquake Aid")
(contract-call? .global-crisis-response-dao vote u1 true)
(contract-call? .global-crisis-response-dao execute u1)
```

## Read-only
- get-member(principal)
- get-proposal(uint)
- list-proposal-stats(uint)
- get-total-weight
- get-current-height
- get-treasury
