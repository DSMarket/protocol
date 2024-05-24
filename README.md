# protocol

Decentralized Storage Market Protocol

# Use Cases Sequence Diagrams

## Create SFA

```mermaid
sequenceDiagram
    actor P as Publisher
    participant IPFS
    participant T as ERC20
    participant M as Market ERC721
    participant H as Host


    P ->>+ IPFS: Publish content in a IPFS node
    IPFS ->>- P: return CID
    P ->> T: Approve allowance to Market ERC721
    P ->>+ M: Create New Storage Forward Agreement (SFA NFT) with CID, Vesting, startTime and TTL
    M ->> T: call to transfer tokens to Market
    T ->> M: transfer tokens
    M ->>- P: Mint SFA NTF to Publisher

    H ->>+ M: Ask for new SFC
    H ->> M: Take Position of new SFC NFT as Taker or Hoster
    M -> R: Ask Registry if Taker is registered
    M ->>- H: Mint Hoster NFT
    IPFS ->> H: Retrive CID and Host Content in their node
```

## Take position in SFA (only hosts)

```mermaid
sequenceDiagram
    actor H as Host
    participant T as ERC20
    participant M as Market ERC721
    participant IPFS

    H ->> T: Approve allowance to Market
    H --> M: watch Market for INACTIVE SFA

    H ->>+ M: claim Host in INACTIVE SFA
    M ->> T: call to transfer token to Market
    T ->> M: transfer tokens for collateral
    M ->> M: assign host and ACTIVE SFA
    IPFS ->> H: Retrive CID and Host Content
```

## Claim Vesting in SFA

call for available vesting in SFA NFT is open to public in base of incentives to caller, so in this way we can incentive market to automate and keep token rolling.
caller get a ratio participation of vesting amount tranfered

```mermaid
sequenceDiagram
    actor C as Caller
    participant M as Market ERC721
    actor H as Host

    C ->>+ M: claim Vesting in ACTIVE SFA
    M ->> M: reduce vesting amount available in SFA NFT
    M ->> C: transfer vesting incentives tokens
    M ->> H: transfer vesting amount minus vesting incentives tokens
```

## Register as Host

```mermaid
sequenceDiagram
    Actor H as Host
    participant M as Market ERC721

    H ->> M: Register as Host sending tx with ipfsID ipfsPubKey
```

## Register as Sentinel

```mermaid
sequenceDiagram
    Actor S as Sentinel
    participant T as Token ERC20
    participant M as Market ERC721

    S ->> T: Approve allowance to Market
    S ->>+ M: Send TX to register Address as Sentinel
    M ->> T: call to Transfer token to Market
    T ->> M: Deposit tokens as collateral
    M ->>- M: Active Sentinel
```
