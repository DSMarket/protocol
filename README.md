# protocol

Decentralized Storage Market Protocol

# Use Cases Sequence Diagrams

## Publish Content

```mermaid
sequenceDiagram
    actor P as Publisher
    participant IPFS
    participant R as Registry
    participant T as DSMarket ERC20
    participant M as Market ERC404
    participant MV as Market Vault ERC4626
    participant H as Host


    P ->>+ IPFS: Publish content in a IPFS node
    IPFS ->>- P: return CID
    P ->> T: Approve allowance to Market
    P ->>+ M: Create New Storage Foward Contract (SFC NFT) with CID, N_Nodes, Total_Incentive and TTL
    M ->> T: send tx to transfer tokens to Market Vault
    T ->> MV: transfer tokens
    M ->>- P: Mint Storage Foward Contract NTF to Publisher

    H ->>+ M: Ask for new SFC
    H ->> M: Take Position of new SFC NFT as Taker or Hoster
    M -> R: Ask Registry if Taker is registered
    M ->>- H: Mint Hoster NFT
    IPFS ->> H: Retrive CID and Host Content in their node
```

## Register as Taker or Hoster

```mermaid
sequenceDiagram
    Actor H as Host
    participant T as DSMarket ERC20
    participant R as Hoster Registry
    participant RV as Registry Vault ERC4626


    H ->> T: Approve allowance to Registry

    H ->>+ R: Ask to register Node Host with IPFS ID
    R ->> T: send msg to transfer token to Registry Vault
    T ->> RV: Transfer tokens
    R ->>- H: Mint Host NFT
```

## Register as Validator

```mermaid
sequenceDiagram
    Actor V as Validator
    participant T as DSMarket ERC20
    participant R as Validator Registry
    participant RV as Registry Vault ERC4626


    V ->> T: Approve allowance to Registry

    V ->>+ R: Ask to register Node Validator with IPFS ID
    R ->> T: Transfer token to Registry Vault
    T ->> RV: Transfer tokens
    R ->>- V: Mint Validator NFT
```
