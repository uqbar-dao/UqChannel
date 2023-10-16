// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { ECDSA } from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

uint256 constant CHALLENGE_PERIOD = 5 minutes;

contract UqChannel {
    event ChannelCreated(
        uint256 indexed id,
        address indexed ali,
        address indexed bob,
        address aliChannelKey,
        address bobChannelKey,
        uint256 aliBalance,
        uint256 bobBalance,
        address token
    );

    event ChannelUpdated(
        uint256 indexed id,
        uint256 messageId,
        bytes32 stateHash,
        uint256 aliBalance,
        uint256 bobBalance,
        uint256 challengePeriod
    );

    // other info should be indexed already, no reason to re-emit
    event ChannelClosed(
        uint256 indexed id,
        uint256 messageId,
        bytes32 stateHash,
        uint256 aliBalance,
        uint256 bobBalance
    );

    struct Channel {
        // alice data
        address ali;
        address aliChannelKey;
        uint256 aliBalance;
        // bob data
        address bob;
        address bobChannelKey;
        uint256 bobBalance;
        // shared data
        IERC20 token;
        uint256 messageId;
        bytes32 stateHash;
        uint256 challengePeriod;
    }

    mapping(uint256 => Channel) public channels;

    function makeChannel(
        address ali,
        address aliChannelKey,
        uint256 aliBalance,
        address bob,
        address bobChannelKey,
        uint256 bobBalance,
        IERC20 token
    ) external returns (uint256) {
        /// TODO transferFrom tokens from ali and bob
        require(token.transferFrom(ali, address(this), aliBalance), "ali transfer failed");
        require(token.transferFrom(bob, address(this), bobBalance), "bob transfer failed");

        // NOTE this is unique so long as you use new channel keys each new channel (you should)
        uint256 id = uint256(keccak256(abi.encodePacked(ali, bob, aliChannelKey, bobChannelKey)));

        channels[id] = Channel({
            ali: ali,
            aliChannelKey: aliChannelKey,
            aliBalance: aliBalance,
            bob: bob,
            bobChannelKey: bobChannelKey,
            bobBalance: bobBalance,
            token: token,
            messageId: 0,
            stateHash: bytes32(0),
            // if no new messages are posted after the challenge period, both parties can withdraw
            challengePeriod: block.timestamp + CHALLENGE_PERIOD
        });

        emit ChannelCreated(id, ali, bob, aliChannelKey, bobChannelKey, aliBalance, bobBalance, address(token));
        return id;
    }

    /// Every update of the channel is an attempt to close. We don't have a distinction between cooperative/uncooperative closes.
    /// Anytime the channel is updated, you can withdrawToken after the timelock. If a malicious party tries to close the channel
    /// with an old state, the other party can challenge the close by providing the state and signatures of the latest state.
    /// @param id of the channel
    /// @param messageId id of the message (should increase by one every message)
    /// @param newAliBalance alice's new balance
    /// @param newBobBalance bob's new balance
    /// @param newState hash of the state agreed upon
    /// @param aliSig ali's signature of ...
    /// @param bobSig bob's signature of ...
    function updateChannel(
        uint256 id,
        uint256 messageId,
        uint256 newAliBalance,
        uint256 newBobBalance,
        bytes32 newState,
        bytes calldata aliSig,
        bytes calldata bobSig
    ) external {
        Channel storage channel = channels[id];
        require(newAliBalance + newBobBalance == channel.aliBalance + channel.bobBalance, "UqChannel: balances must add up");
        require(channel.messageId < messageId, "UqChannel: must advance the state");

        bytes memory message = abi.encodePacked(id, messageId, newAliBalance, newBobBalance, newState);
        require(ECDSA.recover(keccak256(message), aliSig) == channel.aliChannelKey, "UqChannel: invalid ali signature");
        require(ECDSA.recover(keccak256(message), bobSig) == channel.bobChannelKey, "UqChannel: invalid bob signature");

        channel.aliBalance = newAliBalance;
        channel.bobBalance = newBobBalance;
        channel.messageId = messageId;
        channel.stateHash = newState;
        channel.challengePeriod = block.timestamp + CHALLENGE_PERIOD;

        emit ChannelUpdated(id, messageId, newState, newAliBalance, newBobBalance, channel.challengePeriod);
    }

    function withdrawTokens(uint256 id) external {
        Channel storage channel = channels[id];
        require(channel.challengePeriod < block.timestamp, "UqChannel: challenge period not over yet");
        
        require(channel.token.transfer(channel.ali, channel.aliBalance), "UqChannel: ali transfer failed");
        require(channel.token.transfer(channel.bob, channel.bobBalance), "UqChannel: bob transfer failed");

        emit ChannelClosed(id, channel.messageId, channel.stateHash, channel.aliBalance, channel.bobBalance);
    }
}
