# UqChannel
State channels used in Uqbar for offchain asset management. For example, when playing online poker:
1. players establish a channel by depositing some amount of tokens using `makeChannel`
2. players sign off on every statet change off-chain
3. players close the channel by submitting the last updated state using `updateChannel`
    - NOTE: the contract has no way of knowing whether this is actually the latest state. Someone can easily (maliciously) post an old state and attempt to withdraw early. To mitigate this, all withdraws are subject to a timelock of 5 minutes after the last state was submitted. So if Alice and Bob are playing a game, and they get to state `foo`, but Alice maliciously submits an older state `bar`, Bob has 5 minutes to submit `foo` using `updateChannel`, otherwise Alice will be able to withdraw the tokens according to the older `bar` state. For Alice to pull off this attack, she has to censor Bob's access to the chain for 5 minutes (extremely difficult) or somehow get rid of Bob's knowledge or the more recent `foo` state. Even if Alice DOSsed Bob's node, provided this data is backed up on the Uqbar network, this is prohibitively difficult for Alice to do this given even a short time period of 5 minutes.
4. After the timelock has passed, players can withdraw with `withdrawTokens`

## Deployment
```bash
forge script script/UqChannel.sol --rpc-url https://eth-sepolia.g.alchemy.com/v2/W0nka5SiRCHASxyF6jzJ7HkQaMfnq4Mh -vvvv --via-ir --broadcast
```

## Verification
```bash
forge verify-contract \
    --chain-id 11155111 \
    --num-of-optimizations 200 \
    --watch \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --compiler-version v0.8.21+commit.d9974bed \
    0x84b39324a683C49d85e80F0206088373099Fc8DF \
    src/UqChannel.sol:UqChannel

forge verify-contract \
    --chain-id 11155111 \
    --num-of-optimizations 200 \
    --watch \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --compiler-version v0.8.21+commit.d9974bed \
    0xaF33AB6a25D434d4b5EA6A2B3EB4488Fe64015a3 \
    src/test/TestERC20.sol:TestERC20
```